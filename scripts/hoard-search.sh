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

awk -v want_all="$want_all" '
function emit() {
  if (m_title == "") return
  if (want_all != 1 && m_status != "active") return
  printf "%s\t%s\t%s\n", m_type, m_title, m_id
}
function reset() {
  in_fm = 0; fm_done = 0
  m_type = ""; m_title = ""; m_status = "active"; m_id = ""
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
  if (key == "type")   m_type = val
  if (key == "title")  m_title = val
  if (key == "status" && val != "") m_status = val
  next
}
END { emit() }
' "$@" | while IFS="$(printf '\t')" read -r r_type r_title r_id; do
  printf '%s · %s · %s · %s\n' "$r_id" "0.0000" "$r_type" "$r_title"
done | head -n "$topk"

exit 0
