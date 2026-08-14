#!/bin/sh
# tests/test_hoard.sh - scripts/hoard-search.sh, the hoard's only reader.
#
# Every scenario builds a scratch HOME with a hand-written hoard under
# it, runs the script against that HOME, and asserts on stdout. The
# script never writes, so no scenario needs to undo anything.
set -eu
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
. "$script_dir/lib/assert.sh"

hoard_search_script="$repo_root/scripts/hoard-search.sh"

# One EXIT trap for every scratch path (a second `trap ... EXIT` would
# REPLACE this one, not add to it - the same rule tests/test_hooks.sh
# states for itself).
cleanup_paths=""
trap 'rm -rf $cleanup_paths' EXIT

new_home() {
  h=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-hoard-home.XXXXXX")
  cleanup_paths="$cleanup_paths $h"
  printf '%s' "$h"
}

make_memory() {
  # make_memory <home> <layer-dir> <id> <type> <importance> <tags>
  #             <last_used> <uses> <status> <title>
  #
  # <layer-dir> is "global" or "projects/<slug>". <last_used> is a
  # compact UTC stamp, e.g. 20260813T142530Z. Bodies are irrelevant to
  # the reader (it never reads past the frontmatter), so every fixture
  # gets the same one-line body.
  mm_home=$1
  mm_layer=$2
  mm_id=$3
  mm_type=$4
  mm_imp=$5
  mm_tags=$6
  mm_last=$7
  mm_uses=$8
  mm_status=$9
  shift 9
  mm_title=$1
  mkdir -p "$mm_home/.squirrel/hoard/$mm_layer"
  {
    printf -- '---\n'
    printf 'type: %s\n' "$mm_type"
    printf 'importance: %s\n' "$mm_imp"
    printf 'tags: %s\n' "$mm_tags"
    printf 'created: %s\n' "$mm_last"
    printf 'last_used: %s\n' "$mm_last"
    printf 'uses: %s\n' "$mm_uses"
    printf 'status: %s\n' "$mm_status"
    printf 'superseded_by:\n'
    printf 'title: %s\n' "$mm_title"
    printf -- '---\n'
    printf '\n'
    printf 'body text\n'
  } >"$mm_home/.squirrel/hoard/$mm_layer/$mm_id.md"
}

run_search() {
  # run_search <home> [args...] - stdout only; a non-zero exit never
  # aborts this helper, and stdout is asserted on regardless.
  rs_home=$1
  shift
  rs_out=$(HOME="$rs_home" "$hoard_search_script" "$@" 2>/dev/null) || true
  printf '%s' "$rs_out"
}

# ==========================================================================
# 1. A missing hoard is silence, not an error.
# ==========================================================================
home1=$(new_home)
out1=$(run_search "$home1")
assert_eq "" "$out1" "a HOME with no ~/.squirrel/hoard at all must print nothing"
assert_exit_code 0 env HOME="$home1" "$hoard_search_script"

# ==========================================================================
# 2. One global memory is found, and its four fields are printed in the
#    documented order: id, score, type, title.
# ==========================================================================
home2=$(new_home)
make_memory "$home2" "global" "20260101T000000Z-alpha" "feedback" "3" "git,tests" \
  "20260101T000000Z" "0" "active" "run the suite before committing"
out2=$(run_search "$home2")
assert_contains "$out2" "20260101T000000Z-alpha" "the memory's id must appear in the output"
assert_contains "$out2" "feedback" "the memory's type must appear in the output"
assert_contains "$out2" "run the suite before committing" "the memory's title must appear in the output"

field_count2=$(printf '%s' "$out2" | awk -F ' · ' '{ print NF; exit }')
assert_eq "4" "$field_count2" "each output line must carry exactly four ' · '-separated fields: id, score, type, title"

# ==========================================================================
# 3. A superseded memory is excluded by default and returned by --all.
# ==========================================================================
home3=$(new_home)
make_memory "$home3" "global" "20260101T000000Z-live" "feedback" "3" "git" \
  "20260101T000000Z" "0" "active" "the live one"
make_memory "$home3" "global" "20260101T000001Z-dead" "feedback" "3" "git" \
  "20260101T000000Z" "0" "superseded" "the superseded one"
out3=$(run_search "$home3")
assert_contains "$out3" "the live one" "an active memory must be returned by default"
assert_not_contains "$out3" "the superseded one" "a superseded memory must be excluded by default"

out3_all=$(run_search "$home3" --all)
assert_contains "$out3_all" "the superseded one" "--all must return superseded memories too"

# ==========================================================================
# 4. The project layer is read only for the requested slug.
# ==========================================================================
home4=$(new_home)
make_memory "$home4" "global" "20260101T000000Z-g" "reference" "3" "x" \
  "20260101T000000Z" "0" "active" "a global fact"
make_memory "$home4" "projects/myrepo-abc123" "20260101T000000Z-p" "decision" "3" "x" \
  "20260101T000000Z" "0" "active" "a decision in myrepo"
make_memory "$home4" "projects/otherrepo-def456" "20260101T000000Z-o" "decision" "3" "x" \
  "20260101T000000Z" "0" "active" "a decision in otherrepo"

out4=$(run_search "$home4" --slug "myrepo-abc123")
assert_contains "$out4" "a global fact" "the global layer is always read"
assert_contains "$out4" "a decision in myrepo" "the named project's layer must be read"
assert_not_contains "$out4" "a decision in otherrepo" "another project's layer must never be read"

out4_noslug=$(run_search "$home4")
assert_contains "$out4_noslug" "a global fact" "with no --slug, the global layer is still read"
assert_not_contains "$out4_noslug" "a decision in myrepo" "with no --slug, no project layer is read at all"

# ==========================================================================
# 5. The inbox is never a search result. It is a triage queue, and a
#    candidate is not a memory.
# ==========================================================================
home5=$(new_home)
make_memory "$home5" "inbox" "20260101T000000Z-cand" "feedback" "3" "x" \
  "20260101T000000Z" "0" "active" "an untriaged candidate"
out5=$(run_search "$home5")
assert_not_contains "$out5" "an untriaged candidate" "inbox/ must never appear in search results"

# ==========================================================================
# 5b. The --slug guard rejects every traversal shape and accepts a
#     legitimate name that merely contains two dots.
#
#     Both halves are load-bearing. The broad `*..*` form this guard
#     replaced rejected `my..repo-abc123` too, silently returning only
#     global memories for that project - a guard that barred correct
#     work. A test for the rejecting half alone would pass against that
#     broad form and let it come back.
# ==========================================================================
home5b=$(new_home)
make_memory "$home5b" "global" "20260101T000000Z-g5b" "reference" "3" "x" \
  "20260101T000000Z" "0" "active" "a global fact"
make_memory "$home5b" "projects/my..repo-abc123" "20260101T000000Z-d5b" "decision" "3" "x" \
  "20260101T000000Z" "0" "active" "a dotted-name project decision"

# Half one: a legitimate slug containing two dots still reaches its layer.
out5b_ok=$(run_search "$home5b" --slug "my..repo-abc123")
assert_contains "$out5b_ok" "a dotted-name project decision" "a slug containing '..' as part of a NAME must still reach its project layer - the narrowed guard rejects the component, never the two characters"

# Half two: every traversal shape is refused, and refusing means falling
# back to global only - never reading somewhere else, never erroring.
for slug5b in ".." "../x" "x/.." "a/../b" "../../etc"; do
  out5b_bad=$(run_search "$home5b" --slug "$slug5b")
  assert_contains "$out5b_bad" "a global fact" "a rejected slug must still return the global layer, not fail the whole search"
  assert_not_contains "$out5b_bad" "a dotted-name project decision" "the slug '$slug5b' must not reach any project layer"
done

# ==========================================================================
# 5c. FAILURE PROOF: a copy carrying the BROAD `*..*` guard the narrowed
#     one replaced must fail half one - proving 5b's accepting half is
#     what distinguishes the two forms, and that a revert is caught.
# ==========================================================================
mutant5c=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-mutant.XXXXXX")
cleanup_paths="$cleanup_paths $mutant5c"
python3 -c "
with open('$hoard_search_script', 'r') as f:
  content = f.read()
modified = content.replace('*/../*)', '*..*)')
with open('$mutant5c', 'w') as f:
  f.write(modified)
"
chmod +x "$mutant5c"
mutant5c_out=$(HOME="$home5b" "$mutant5c" --slug "my..repo-abc123" 2>/dev/null) || true
if printf '%s' "$mutant5c_out" | grep -qF "a dotted-name project decision"; then
  mutant5c_reaches=yes
else
  mutant5c_reaches=no
fi
assert_eq "no" "$mutant5c_reaches" "FAILURE PROOF (scenario 5b): a copy carrying the BROAD '*..*' guard must NOT reach the dotted-name project layer - if it still does, 5b's accepting half is not actually testing which form of the guard is present"

assert_report
