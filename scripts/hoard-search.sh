#!/bin/sh
# hoard-search.sh - the hoard's only reader.
#
# Enumerates every memory file in the global layer and (when --slug is
# given) one project layer, parses each file's frontmatter, and prints
# the ranked result as `<id> · <score> · <type> · <title>`.
#
# THERE IS NO INDEX, DELIBERATELY. Every read is a single awk pass over
# the frontmatter of every file - see docs/specs/2026-08-13-hoard-design.md
# §5.1 for the scale ceiling that buys and why it was chosen over a
# derived index (no rebuild, no staleness, no schema migration, no
# divergence between a file and its index).
#
# NEVER WRITES. Reinforcement (`uses`, `last_used`) is the caller's job,
# through the Write tool, so this script stays a pure function of $HOME,
# its arguments, and the filesystem - which is also what makes every
# test a plain stdout comparison.
#
# Never exits non-zero for an empty, missing, or malformed store: a
# reader that fails loudly on a first-ever run would put an error in
# front of a user who has done nothing wrong. Silence is the answer for
# "nothing to show".
set -eu
unset CDPATH

topk=5
slug=""
want_all=0
query=""

while [ $# -gt 0 ]; do
  case "$1" in
    -k)
      shift
      [ $# -gt 0 ] || break
      topk=$1
      ;;
    --slug)
      shift
      [ $# -gt 0 ] || break
      slug=$1
      ;;
    --all)
      want_all=1
      ;;
    --)
      shift
      break
      ;;
    -*)
      # An unknown flag is not fatal: this script is invoked by a model
      # following a skill, and refusing the whole search over one
      # unrecognised token would turn a typo into a dead end.
      ;;
    *)
      if [ -z "$query" ]; then
        query=$1
      else
        query="$query $1"
      fi
      ;;
  esac
  shift
done

while [ $# -gt 0 ]; do
  if [ -z "$query" ]; then
    query=$1
  else
    query="$query $1"
  fi
  shift
done

case "$topk" in
  '' | *[!0-9]*) topk=5 ;;
esac

home_dir="${HOME:-}"
[ -n "$home_dir" ] || exit 0

hoard_dir="$home_dir/.squirrel/hoard"
[ -d "$hoard_dir" ] || exit 0

# Build the file list. An unmatched glob stays literal in POSIX sh, so
# every candidate is tested with `[ -f ]` before it is kept. inbox/ is
# never enumerated: a candidate is not a memory.
set --
for f in "$hoard_dir"/global/*.md; do
  [ -f "$f" ] && set -- "$@" "$f"
done
if [ -n "$slug" ]; then
  # A slug carrying a "/" or a ".." COMPONENT would reach outside the
  # project layer. Nothing legitimate produces one: project_slug() in
  # load-profile.sh emits `basename-hash`, where basename has been run
  # through `tr -c 'A-Za-z0-9._-'`.
  #
  # It is the COMPONENT that is rejected, never the two characters - the
  # same distinction allow-checkpoint.sh's Layer 0 draws, and for the
  # same reason. `tr` keeps dots, so a repository named `my..repo`
  # produces the perfectly legitimate slug `my..repo-abc123`; a bare
  # `*..*` test would silently drop that project's whole layer and
  # return only global memories, with nothing reported. Wrapping both
  # ends in "/" is what makes one pattern cover a bare "..", a leading
  # "../x", a trailing "x/.." and an interior "/../" without touching a
  # name that merely contains two dots.
  case "$slug" in
    */*) slug="" ;;
  esac
  case "/$slug/" in
    */../*) slug="" ;;
  esac
fi
if [ -n "$slug" ]; then
  for f in "$hoard_dir/projects/$slug"/*.md; do
    [ -f "$f" ] && set -- "$@" "$f"
  done
fi

[ $# -gt 0 ] || exit 0

now_ymd=$(date -u +%Y%m%d 2>/dev/null) || now_ymd="19700101"
tab=$(printf '\t')

# LC_ALL=C: `printf "%.4f"` below writes the locale's decimal separator,
# not always ".": under pt_BR.UTF-8 it writes "0,0000". That breaks both
# the `sort -k1,1nr` numeric comparison downstream and the "exactly four
# decimal places after a '.'" contract callers rely on to parse the
# score. Same discipline as the `LC_ALL=C sort` a few lines down, and as
# load-profile.sh's json_escape - see its "WHY THE BODY RUNS UNDER
# LC_ALL=C" comment.
LC_ALL=C awk -v want_all="$want_all" -v now_ymd="$now_ymd" '
# days_from_civil: Howard Hinnant days-from-civil, the standard
# proleptic-Gregorian day count. Chosen over `date` arithmetic because
# no portable `date` computes a difference: GNU `date -d` and BSD
# `date -v` disagree in syntax, and this project ships to both. Bucketed
# tiers ("used in the last 30 days") were rejected in the spec: not less
# code, and two memories a day apart would rank identically for a month.
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y = y - 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function stamp_days(s,   y, m, d) {
  # s is a compact UTC stamp: YYYYMMDDTHHMMSSZ. Only the date half is
  # read; a malformed or empty stamp yields day 0, which makes the
  # memory maximally stale rather than crashing the whole search.
  if (length(s) < 8) return 0
  y = substr(s, 1, 4) + 0
  m = substr(s, 5, 2) + 0
  d = substr(s, 7, 2) + 0
  if (y == 0 || m == 0 || d == 0) return 0
  return days_from_civil(y, m, d)
}
function emit(   imp, lambda, days, score) {
  if (m_title == "") return
  if (want_all != 1 && m_status != "active") return

  imp = m_importance + 0
  if (imp < 1) imp = 1
  if (imp > 5) imp = 5

  # Important memories decay more slowly. These weights are a design
  # decision, not a finding: they are specified in
  # docs/specs/2026-08-13-hoard-design.md §5, and are registered in
  # docs/RESEARCH.md as a design decision with no finding behind it by
  # Task 8 of this phase.
  lambda = 0.16 * (1 - imp * 0.8 / 5)
  days = now_days - stamp_days(m_last_used)
  if (days < 0) days = 0

  score = (imp / 5) * exp(-lambda * days) * (1 + 0.2 * log(1 + (m_uses + 0)))
  printf "%.4f\t%s\t%s\t%s\n", score, m_id, m_type, m_title
}
function reset() {
  in_fm = 0; fm_done = 0
  m_type = ""; m_title = ""; m_status = "active"; m_id = ""
  m_importance = 3; m_uses = 0; m_last_used = ""
}
BEGIN {
  now_days = days_from_civil(substr(now_ymd, 1, 4) + 0, substr(now_ymd, 5, 2) + 0, substr(now_ymd, 7, 2) + 0)
}
FNR == 1 {
  emit()
  reset()
  n = split(FILENAME, parts, "/")
  base = parts[n]
  sub(/\.md$/, "", base)
  m_id = base
}
fm_done { next }
/^---[ \t]*$/ {
  if (in_fm == 0) { in_fm = 1; next }
  fm_done = 1
  next
}
in_fm == 1 {
  key = $0
  sub(/:.*$/, "", key)
  val = $0
  sub(/^[^:]*:[ \t]*/, "", val)
  if (key == "type")       m_type = val
  if (key == "title")      m_title = val
  if (key == "importance") m_importance = val
  if (key == "uses")       m_uses = val
  if (key == "last_used")  m_last_used = val
  if (key == "status" && val != "") m_status = val
  next
}
END { emit() }
' "$@" |
  # Deterministic order: score desc, then id asc. The id tie-break is
  # what makes two equally-scored memories come back in the same order
  # on every machine and every run - which is only true with LC_ALL=C.
  # Without it, `sort` collates by the caller's locale, and this project
  # already ships tests that run under pt_BR precisely because a
  # locale-dependent answer is one that is right on the author's machine
  # and wrong somewhere else.
  LC_ALL=C sort -t"$tab" -k1,1nr -k2,2 |
  head -n "$topk" |
  while IFS="$tab" read -r r_score r_id r_type r_title; do
    printf '%s · %s · %s · %s\n' "$r_id" "$r_score" "$r_type" "$r_title"
  done

exit 0
