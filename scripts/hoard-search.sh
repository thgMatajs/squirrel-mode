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

# Build the file list: ONE `set --` per LAYER, never one per file.
#
# THE PER-FILE FORM IS QUADRATIC. Appending one file at a time - the
# loop this replaced - rebuilds the entire positional list on every
# call, and macOS's /bin/sh (bash 3.2) rebuilds it by copying, so
# appending n files costs O(n^2). (The forbidden form is deliberately
# not spelled here: tests/test_hoard.sh scenario 14 greps this file for
# it, and a guard that its own subject's comment satisfies is a guard
# that cannot fail.)
# Measured on the author's machine at 2000 memories: 12.05 s in that loop
# against 110 ms for the whole awk pass it was feeding. Assigning each
# layer's expansion in a single `set --` makes that one copy per layer
# instead of one per file. tests/test_hoard.sh scenario 14 pins the
# shape so the per-file form cannot come back unnoticed.
#
# An unmatched glob stays literal in POSIX sh, and the literal names no
# file, so it is dropped by testing "$1" and shifting it off. The test
# is exact rather than a sample: an unmatched glob expands to exactly
# one word - the pattern itself - and that word is the FIRST of the
# layer just assigned. Keeping each test immediately after its own
# `set --` is what makes "$1" both the right word to test and a defined
# one under `set -u`.
#
# THOSE TWO SHIFTS ALSO GUARD A PERFORMANCE CLIFF, not just correctness.
# The prescan below treats any non-regular entry as a reason to rebuild,
# and an unmatched glob's literal is non-regular. A fresh project with a
# populated global layer - the commonest state there is - would therefore
# rebuild on every single search if the literal were still in the list.
# Dropping it here, in O(1), is what keeps the rebuild for genuinely
# irregular entries.
#
# inbox/ is never enumerated: a candidate is not a memory.
set -- "$hoard_dir"/global/*.md
[ -f "$1" ] || shift
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
  # PREPENDED, not appended, so the layer under test is once again the
  # front of the list and the same one-word check applies unchanged.
  # Appending would put the candidate literal LAST, where reaching it
  # costs either an `eval` on ${$#} or a walk of the whole list - the
  # per-file cost this rewrite exists to remove. Which layer comes first
  # never reaches the caller: the pipeline below sorts by score and then
  # by id, so awk's argument order decides nothing.
  set -- "$hoard_dir/projects/$slug"/*.md "$@"
  [ -f "$1" ] || shift
fi

# HAND awk NOTHING IT CANNOT SAFELY OPEN. A `*.md` entry that is not a
# regular file is not a memory, and awk does not merely ignore one:
#
#   - a FIFO makes awk BLOCK FOREVER on open, waiting for a writer that
#     never comes. The search never returns and prints nothing, which is
#     the one failure a user cannot diagnose - there is nothing to read.
#   - a broken symlink, or a directory under mawk, makes awk exit fatally
#     mid-list. Because emit() defers each record until the NEXT file's
#     FNR == 1, the memory parsed just before the fatal is DROPPED - a
#     complete-looking answer, silently missing an entry, exit status 0.
#     Measured: 3 memories in, 2 out, on all three awks this project
#     meets. Silent loss from the store's only reader is the worst
#     outcome in this file, worse than being slow and worse than failing.
#
# So the list is prescanned, and rebuilt only if the prescan finds
# something. The prescan is O(n) with NO `set --` at all, so the common
# case - every entry a regular file - pays one stat per file and nothing
# else: 19 ms at 2000 memories, against 8.1 s for filtering per file.
# The rebuild pays that 8.1 s, but only when a hoard actually contains an
# irregular entry, and it is the price of a correct answer over a fast
# wrong one. It is also exactly what this script cost before the one-shot
# construction landed, so no state is slower than it used to be.
#
# The rebuild reassigns "$@" while iterating it, which is safe because a
# `for` loop expands its word list ONCE, before the body runs - verified
# on bash 3.2, dash and zsh, not assumed from the wording. Those three
# are what was actually run; no bash 5 was available to run it on, and
# naming one that was never used would make this comment the kind of
# claim the rest of this repository exists to stop shipping.
irregular=0
for f in "$@"; do
  [ -f "$f" ] || { irregular=1; break; }
done
if [ "$irregular" = 1 ]; then
  kept=0
  for f in "$@"; do
    if [ "$kept" = 0 ]; then set --; kept=1; fi
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
LC_ALL=C awk -v want_all="$want_all" -v now_ymd="$now_ymd" -v query="$query" '
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
function relevance(   hay, i, hits) {
  if (q_n == 0) return 1
  hay = tolower(m_title " " m_tags)
  gsub(/[^a-z0-9]+/, " ", hay)
  hay = " " hay " "
  hits = 0
  for (i = 1; i <= q_n; i++) {
    if (index(hay, " " q_tok[i] " ") > 0) hits++
  }
  return hits / q_n
}
function emit(   imp, lambda, days, score, rel) {
  if (m_title == "") return
  if (want_all != 1 && m_status != "active") return

  rel = relevance()
  if (rel == 0) return

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

  score = rel * (imp / 5) * exp(-lambda * days) * (1 + 0.2 * log(1 + (m_uses + 0)))
  printf "%.4f\t%s\t%s\t%s\n", score, m_id, m_type, m_title
}
function reset() {
  in_fm = 0; fm_done = 0
  m_type = ""; m_title = ""; m_status = "active"; m_id = ""
  m_importance = 3; m_uses = 0; m_last_used = ""; m_tags = ""
}
BEGIN {
  now_days = days_from_civil(substr(now_ymd, 1, 4) + 0, substr(now_ymd, 5, 2) + 0, substr(now_ymd, 7, 2) + 0)

  # Query tokens: lowercased, split on anything that is not a letter or
  # digit, with one-character tokens and a small stopword set dropped.
  # The stopword list is deliberately tiny - it exists to stop "the" and
  # "a" from making every memory look half-relevant, not to be a
  # linguistics project.
  q_n = 0
  if (query != "") {
    tmp = tolower(query)
    gsub(/[^a-z0-9]+/, " ", tmp)
    c = split(tmp, qparts, " ")
    for (i = 1; i <= c; i++) {
      t = qparts[i]
      if (length(t) < 2) continue
      if (t == "the" || t == "and" || t == "for" || t == "que" || t == "com" || t == "para") continue
      q_n++
      q_tok[q_n] = t
    }
  }
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
  if (key == "tags")       m_tags = val
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
