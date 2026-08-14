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
# shellcheck source=lib/assert.sh
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

# ==========================================================================
# 6. Importance orders two otherwise identical memories.
#
#    THE IDS ARE CHOSEN SO THE TIEBREAK OPPOSES THE ANSWER. Ordering is
#    score desc, then id ASC, so a reader with no working score at all
#    falls back to id order - and if the important memory's id happened
#    to sort first, this scenario would pass against a reader that scores
#    nothing. `a-unimportant` sorts before `z-important`, so id order
#    puts the WRONG answer first and only a real score can pass. This is
#    also what makes scenario 8b's mutation proof meaningful rather than
#    accidentally satisfied.
#
#    last_used is deliberately far-future (20991231), the same clamp
#    scenarios 7 and 8 use, so decay is zero for both fixtures and this
#    scenario measures only what it is named for - importance - rather
#    than drifting shut as the calendar advances toward it.
# ==========================================================================
home6=$(new_home)
make_memory "$home6" "global" "20260101T000000Z-a-unimportant" "feedback" "1" "x" \
  "20991231T000000Z" "0" "active" "the unimportant one"
make_memory "$home6" "global" "20260101T000000Z-z-important" "feedback" "5" "x" \
  "20991231T000000Z" "0" "active" "the important one"
out6=$(run_search "$home6")
first6=$(printf '%s\n' "$out6" | head -n 1)
assert_contains "$first6" "the important one" "importance 5 must outrank importance 1 when every other field is equal"

# ==========================================================================
# 7. Recency decays, and a more important memory decays more slowly.
#
#    Both fixtures are equally important; only last_used differs, so the
#    only thing that can separate them is the decay term.
# ==========================================================================
home7=$(new_home)
make_memory "$home7" "global" "20260101T000000Z-old" "feedback" "3" "x" \
  "20200101T000000Z" "0" "active" "the stale one"
make_memory "$home7" "global" "20260101T000001Z-new" "feedback" "3" "x" \
  "20991231T000000Z" "0" "active" "the fresh one"
out7=$(run_search "$home7")
first7=$(printf '%s\n' "$out7" | head -n 1)
assert_contains "$first7" "the fresh one" "a recently used memory must outrank an identical one last used years earlier"

score_old7=$(printf '%s\n' "$out7" | grep "the stale one" | awk -F ' · ' '{ print $2 }')
score_new7=$(printf '%s\n' "$out7" | grep "the fresh one" | awk -F ' · ' '{ print $2 }')
assert_eq "4" "$(printf '%s' "$score_new7" | awk -F. '{ print length($2) }')" "the score must be printed with exactly four decimal places, so ordering is inspectable"
if awk -v a="$score_new7" -v b="$score_old7" 'BEGIN { exit !(a > b) }'; then
  decay7=yes
else
  decay7=no
fi
assert_eq "yes" "$decay7" "the fresh memory's printed score must be numerically greater than the stale one's"

# ==========================================================================
# 8. Reinforcement raises a memory that has actually been used.
#
#    DEVIATION FROM THE BRIEF: last_used is `20991231T000000Z` (clamped
#    to "now" by the reader, exactly as scenario 7's "fresh" fixture
#    already relies on) rather than the brief's `20260101T000000Z`. With
#    the brief's date, and run any time after ~April 2026, the decay
#    term for importance=3 pushes both scores to 0.0000 before rounding
#    - both fixtures print an identical score, the id tie-break decides,
#    and "never consulted" (which sorts first by id) wins even though
#    reinforcement is implemented correctly. See task-2-report.md.
# ==========================================================================
home8=$(new_home)
make_memory "$home8" "global" "20260101T000000Z-unused" "feedback" "3" "x" \
  "20991231T000000Z" "0" "active" "never consulted"
make_memory "$home8" "global" "20260101T000001Z-used" "feedback" "3" "x" \
  "20991231T000000Z" "12" "active" "consulted often"
out8=$(printf '%s\n' "$(run_search "$home8")" | head -n 1)
assert_contains "$out8" "consulted often" "uses=12 must outrank uses=0 when importance and last_used are equal"

# ==========================================================================
# 8b. FAILURE PROOF for scenarios 6-8: a mutant reader that ignores the
#     frontmatter and scores every memory identically must break the
#     ordering assertions above. Without this, a reader that emitted a
#     constant score would satisfy "the important one is in the output"
#     and pass three scenarios it does not implement.
# ==========================================================================
mutant8=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-mutant.XXXXXX")
cleanup_paths="$cleanup_paths $mutant8"
sed 's/^  score = .*$/  score = 1/' "$hoard_search_script" >"$mutant8"
chmod +x "$mutant8"

mutant8_out=$(HOME="$home6" "$mutant8" 2>/dev/null) || true
mutant8_first=$(printf '%s\n' "$mutant8_out" | head -n 1)
if printf '%s' "$mutant8_first" | grep -qF "the important one"; then
  mutant8_still_ordered=yes
else
  mutant8_still_ordered=no
fi
assert_eq "no" "$mutant8_still_ordered" "FAILURE PROOF (scenarios 6-8): a reader whose score is a constant must fall back to id order and put 'the unimportant one' first - if it still leads with the important one, the ordering assertions above are passing on tie-break luck rather than on the score"

# ==========================================================================
# 9. A query filters to matching memories and ranks by how much matched.
#
#    DEVIATION FROM THE BRIEF: last_used (and created) is
#    `20991231T000000Z` rather than the brief's `20260101T000000Z`, the
#    same clamp scenarios 6-8 use. With a 2026 date the decay term drives
#    every score to 0.0000 as of today, and the assertions below would
#    then be decided by the id tie-break instead of by relevance.
# ==========================================================================
home9=$(new_home)
make_memory "$home9" "global" "20260101T000000Z-git" "feedback" "3" "git,commits" \
  "20991231T000000Z" "0" "active" "run the suite before committing"
make_memory "$home9" "global" "20260101T000001Z-css" "reference" "3" "css,layout" \
  "20991231T000000Z" "0" "active" "flexbox gap is unsupported on old safari"
out9=$(run_search "$home9" "commits")
assert_contains "$out9" "run the suite before committing" "a memory whose tags carry the query token must be returned"
assert_not_contains "$out9" "flexbox gap" "a memory matching no query token must not be a result at all"

out9_title=$(run_search "$home9" "safari")
assert_contains "$out9_title" "flexbox gap" "a query token found in the title must match, not only one found in the tags"

out9_none=$(run_search "$home9" "kubernetes")
assert_eq "" "$out9_none" "a query matching nothing must print nothing, not an unfiltered list"

# ==========================================================================
# 10. Matching more of the query outranks matching less of it.
#
#     DEVIATION FROM THE BRIEF: last_used (and created) is
#     `20991231T000000Z` rather than the brief's `20260101T000000Z`, for
#     the same decay-to-zero reason as scenario 9.
#
#     DEVIATION FROM THE BRIEF: the ids are `20991231T000000Z-z-both` and
#     `20991231T000000Z-a-one` rather than the brief's `-both` / `-one`
#     suffixes on their original timestamps. The brief's ids made the id
#     tie-break point at the SAME memory this scenario asserts should
#     win, so a reader that ignored relevance completely would still
#     pass it. `a-one` sorts before `z-both`, so id order now puts the
#     WRONG answer first and only real relevance can pass - the same
#     "tie-break opposes the answer" discipline scenario 6 documents for
#     itself.
# ==========================================================================
home10=$(new_home)
make_memory "$home10" "global" "20991231T000000Z-z-both" "feedback" "3" "compose,theme" \
  "20991231T000000Z" "0" "active" "alpha"
make_memory "$home10" "global" "20991231T000000Z-a-one" "feedback" "3" "compose,layout" \
  "20991231T000000Z" "0" "active" "beta"
out10=$(printf '%s\n' "$(run_search "$home10" "compose theme")" | head -n 1)
assert_contains "$out10" "20991231T000000Z-z-both" "matching both query tokens must outrank matching one, with every other field equal"

# ==========================================================================
# 10b. FAILURE PROOF for 9-10: a mutant that treats every memory as fully
#      relevant must return the non-matching memory, proving the filter is
#      what excludes it rather than the score happening to be small.
# ==========================================================================
mutant10=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-mutant.XXXXXX")
cleanup_paths="$cleanup_paths $mutant10"
sed 's/^  if (rel == 0) return$/  rel = 1/' "$hoard_search_script" >"$mutant10"
chmod +x "$mutant10"
mutant10_out=$(HOME="$home9" "$mutant10" "kubernetes" 2>/dev/null) || true
if [ -n "$mutant10_out" ]; then
  mutant10_leaks=yes
else
  mutant10_leaks=no
fi
assert_eq "yes" "$mutant10_leaks" "FAILURE PROOF (scenarios 9-10): removing the zero-relevance filter must make a non-matching query return results - if it does not, scenario 9's empty result is being produced by something other than the filter"

# ==========================================================================
# 11. The stash skill's contract. Asserted here rather than in
#     test_skills.sh because these are hoard semantics, not skill
#     structure - test_skills.sh already covers frontmatter and naming.
# ==========================================================================
stash_file="$repo_root/skills/stash/SKILL.md"
assert_file_exists "$stash_file" "skills/stash/SKILL.md must exist"
stash_body=$(cat "$stash_file" 2>/dev/null || printf '')

# shellcheck disable=SC2088 # single-quoted deliberately: this is a
# literal needle assert_contains searches the file's TEXT for (the
# documented path as written in prose), never a path this shell opens or
# expands - a leading "~" here is not tilde-expansion gone wrong.
assert_contains "$stash_body" '~/.squirrel/hoard/' "stash must name the hoard directory - a memory written anywhere else is not findable"
assert_contains "$stash_body" "Write" "stash must name the Write tool: only Write, Edit and Read carry the auto-approval, and a Bash heredoc would stop to ask"
assert_contains "$stash_body" "never inside the project" "stash must state that nothing is ever written inside a project repository"
assert_contains "$stash_body" "superseded_by" "stash must specify the full frontmatter, superseded_by included - the reader assumes every key is present"
assert_contains "$stash_body" "date -u +%Y%m%dT%H%M%SZ" "stash must name the exact timestamp command, or two memories written by different sessions get incomparable stamps"
assert_contains "$stash_body" "Never rewrite an existing memory" "stash must instruct superseding rather than editing when a fact changed - matched on the instruction's own prose, because the phrase 'supersede' alone is also a prefix of the 'superseded_by' frontmatter key that a separate assertion already requires, so it would pass with the whole instruction deleted"
assert_contains "$stash_body" "Show the title and body" "stash must show the user what it is about to write - a memory the user never saw is one they cannot correct"

# The four types, all of them, spelled out.
for stash_type in feedback decision episode reference; do
  assert_contains "$stash_body" "$stash_type" "stash must name the '$stash_type' type"
done
assert_not_contains "$stash_body" "type: session" "stash must NOT offer a session type - the checkpoint covers that, and a session memory would pollute the store"

# ==========================================================================
# 11b. FAILURE PROOF: deleting the paragraph that names the Write tool
#      must remove the phrase, proving the assertion above binds to that
#      instruction and not to an unrelated mention of the same word.
# ==========================================================================
stash_mutant=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-skill.XXXXXX")
cleanup_paths="$cleanup_paths $stash_mutant"
grep -vF 'Write' "$stash_file" >"$stash_mutant" || true
stash_mutant_body=$(cat "$stash_mutant" 2>/dev/null || printf '')
if printf '%s' "$stash_mutant_body" | grep -qF 'Write'; then
  stash_mutant_has_write=yes
else
  stash_mutant_has_write=no
fi
assert_eq "no" "$stash_mutant_has_write" "FAILURE PROOF (scenario 11): a copy with every 'Write' line removed must not contain 'Write' - proving the tool-naming assertion is not matching some other line"
assert_contains "$stash_mutant_body" "superseded_by" "FAILURE PROOF (scenario 11, independence): removing the Write lines must leave the frontmatter specification intact"

# ==========================================================================
# 11c. FAILURE PROOF for scenario 11's supersede assertion: deleting the
#      instruction must make it fail. The obvious needle 'supersede' does
#      NOT have this property - it is a prefix of the 'superseded_by'
#      frontmatter key, which another assertion independently requires, so
#      it passes against a file with the whole instruction removed. This
#      proof is what distinguishes the two.
# ==========================================================================
supersede_mutant=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-skill.XXXXXX")
cleanup_paths="$cleanup_paths $supersede_mutant"
awk '
  /^## When a fact changed/ { skip = 1; next }
  skip && /^## / { skip = 0 }
  skip { next }
  { print }
' "$stash_file" >"$supersede_mutant"
supersede_mutant_body=$(cat "$supersede_mutant" 2>/dev/null || printf '')

assert_not_contains "$supersede_mutant_body" "Never rewrite an existing memory" "FAILURE PROOF (scenario 11c): removing the 'When a fact changed, supersede instead of editing' section must remove its instructional prose"
assert_contains "$supersede_mutant_body" "superseded_by" "FAILURE PROOF (scenario 11c, independence): the frontmatter key 'superseded_by' must still be present after removing the supersede instruction - proving the instruction and the field name are independent needles, so the new assertion is testing the instruction and not the field"

# ==========================================================================
# 12. The dig skill's contract.
#
#     NEEDLE CHOICE, stated once for the three assertions where the
#     obvious word would not have bound to the instruction it names -
#     the same trap scenario 11c documents for 'supersede':
#
#       - `Read` tool  (not the bare word "Read"): "Read" is a substring
#         of "Reading", "Reader", and of any sentence that merely tells
#         the model to read something, so the bare word would still pass
#         against a file whose hydration step named a shell command
#         instead. The backticked tool name only appears where a tool is
#         being named.
#       - `uses`       (not the bare word "uses"): "uses" is a substring
#         of "causes", "reuses", "focuses" and so on, and is also an
#         ordinary English verb, so the bare word could pass against a
#         file with the reinforcement instruction deleted. The backticks
#         are what make the needle the frontmatter KEY.
#       - "never run a command" (not the bare word "never"): "never"
#         appears in a dozen unrelated sentences here, so asserting it
#         would prove nothing at all about the forgery rule. This needle
#         binds to the one refusal that matters - a line the three rules
#         do not vouch for is never executed.
# ==========================================================================
dig_file="$repo_root/skills/dig/SKILL.md"
assert_file_exists "$dig_file" "skills/dig/SKILL.md must exist"
dig_body=$(cat "$dig_file" 2>/dev/null || printf '')

assert_contains "$dig_body" "hoard-search.sh" "dig must name the search script - it cannot rank the store by reading files one at a time"
assert_contains "$dig_body" "Hoard search command" "dig must take the script's path from the injected line, not from a plugin-root variable - that variable is set for hooks and not for a Bash call a skill makes"
assert_contains "$dig_body" "BELOW the last \`Session off-token:\` line" "dig must scope the injected line by POSITION - the profile body is quoted above it and can spell the same line, and this one names a command that gets executed"
assert_contains "$dig_body" "/scripts/hoard-search.sh" "dig must pin the expected path ending, so a forged line naming any other command is rejected even if it were positioned correctly"
assert_not_contains "$dig_body" "CLAUDE_PLUGIN_ROOT" "dig must NOT reference CLAUDE_PLUGIN_ROOT: it is unset in the Bash tool's environment, so a command built from it runs the wrong path on every machine"
assert_contains "$dig_body" "titles only" "dig must state that the first result is titles only: paying for every body is the cost this two-step split exists to avoid"
# shellcheck disable=SC2016 # single-quoted deliberately, here and at the
# two `uses` needles below: the backticks are literal Markdown characters
# in the text being searched for, never command substitution to evaluate.
assert_contains "$dig_body" '`Read` tool' "dig must name the Read tool for hydrating a body - only Read carries the auto-approval. Matched on the backticked tool name, not the bare word 'Read', which any sentence telling the model to read something would satisfy"
assert_contains "$dig_body" "one permission prompt" "dig must disclose that running the search costs a permission prompt, because no hook can auto-approve a Bash call"
# shellcheck disable=SC2016 # literal Markdown backticks, not substitution.
assert_contains "$dig_body" '`uses`' "dig must update the memory's uses counter when a body is actually read - reinforcement is what keeps a used memory ranked. Matched on the backticked frontmatter key, not the bare word, which is a substring of 'causes' and an ordinary verb besides"
assert_contains "$dig_body" "last_used" "dig must update last_used when a body is actually read"
assert_contains "$dig_body" "never run a command" "dig must refuse to execute anything the three rules did not vouch for - the bare word 'never' would have matched a dozen unrelated sentences here and proved nothing"
assert_contains "$dig_body" "Automatic injection never counts" "dig must state that automatic injection never counts as a use - without it the store's ranking feeds itself. Matched on the whole sentence, not the bare word: assert_contains is case-sensitive, and the skill capitalises it at the start of a sentence"

# ==========================================================================
# 12b. FAILURE PROOF: a copy with the reinforcement instruction removed
#      must lose both counter names, proving those two assertions bind to
#      that instruction rather than to an incidental mention.
# ==========================================================================
dig_mutant=$(mktemp "${TMPDIR:-/tmp}/squirrel-hoard-skill.XXXXXX")
cleanup_paths="$cleanup_paths $dig_mutant"
grep -vF 'last_used' "$dig_file" | grep -vF 'uses' >"$dig_mutant" || true
dig_mutant_body=$(cat "$dig_mutant" 2>/dev/null || printf '')
if printf '%s' "$dig_mutant_body" | grep -qF 'last_used'; then
  dig_mutant_has=yes
else
  dig_mutant_has=no
fi
assert_eq "no" "$dig_mutant_has" "FAILURE PROOF (scenario 12): a copy with the reinforcement lines removed must not contain 'last_used'"
# shellcheck disable=SC2016 # literal Markdown backticks, not substitution.
assert_not_contains "$dig_mutant_body" '`uses`' "FAILURE PROOF (scenario 12): the same copy must not contain the backticked 'uses' key either - both counter assertions have to bind to the removed instruction, not just the one"
assert_contains "$dig_mutant_body" "hoard-search.sh" "FAILURE PROOF (scenario 12, independence): removing the reinforcement lines must leave the search-script instruction intact"

assert_report
