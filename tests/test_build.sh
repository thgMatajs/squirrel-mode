#!/bin/sh
# Coverage for S3: scripts/build.sh and the four BASE-RULES-DERIVED generated
# artifacts it produces (output-styles/squirrel-mode.md, skills/rules/SKILL.md,
# targets/codex/AGENTS.md, targets/cursor/squirrel-mode.mdc) -- four of the thirteen
# total artifacts build.sh generates. The other nine (the ported Codex
# skills, Cursor commands, Cursor Agent Skills, and Cursor hooks.json) are a separate source
# (skills/{digest,plan,init,tune}/SKILL.md, not rules/base-rules.md) and are
# covered by tests/test_targets.sh instead, not duplicated here.
#
# This is where S3 is actually verified: idempotence, drift-from-source,
# per-target rule completeness/exclusion, frontmatter validity, the
# no-interpolation and GENERATED-marker contracts, that no rule text has
# leaked into build.sh itself, and that malformed input fails the build
# loudly instead of silently emitting a half-empty artifact.
#
# Malformed-input scenarios (12) NEVER touch the real
# rules/base-rules.md: every mutation happens on a throwaway scratch
# copy of scripts/build.sh + rules/base-rules.md, built by
# make_build_scratch (build.sh resolves its own repo root from its own
# location, so running the scratch copy's build.sh reads and writes
# entirely inside the scratch directory).
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion: every assert_* helper always returns 0, and
# only assert_report (called once, at the end) turns a failure into a
# non-zero exit code.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line. Unset
# unconditionally, before that `cd` runs.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# shellcheck source=lib/assert.sh
. "$script_dir/lib/assert.sh"

build_script="$repo_root/scripts/build.sh"
base_rules_file="$repo_root/rules/base-rules.md"

output_style_file="$repo_root/output-styles/squirrel-mode.md"
skill_file="$repo_root/skills/rules/SKILL.md"
codex_file="$repo_root/targets/codex/AGENTS.md"
cursor_file="$repo_root/targets/cursor/squirrel-mode.mdc"

# --- Freeze a snapshot of "the committed artifacts" right now, before
# ANY scenario below (in particular scenario 2's own idempotence run,
# which legitimately invokes build.sh against the real repo) has a
# chance to regenerate them. Without this, scenario 3's "diff against
# the committed artifacts" would be diffing a fresh regeneration against
# a file that a scenario running earlier IN THIS SAME test process had
# already silently rewritten back to canonical form moments before --
# masking exactly the kind of drift (a hand-edit never run through
# build.sh) this scenario exists to catch. Captured with plain `cat`
# (not `cp`, and tolerating a missing file as empty) so a first-ever run
# before any artifact exists yet still produces a well-defined snapshot
# rather than aborting under `set -eu`.
committed_snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-committed-snapshot.XXXXXX")
# All EXIT-trap-cleaned scratch directories accumulate here rather than
# each being handed its own `trap ... EXIT` call: `trap` REPLACES the
# previous EXIT handler rather than adding to it, so a second `trap
# ... EXIT` later in this file would silently cancel this one's cleanup.
cleanup_dirs="$committed_snapshot_dir"
trap 'rm -rf $cleanup_dirs' EXIT
for pair in "output-style.md:$output_style_file" "skill.md:$skill_file" "codex.md:$codex_file" "cursor.mdc:$cursor_file"; do
  snap_name=${pair%%:*}
  src_path=${pair#*:}
  if [ -f "$src_path" ]; then
    cat "$src_path" >"$committed_snapshot_dir/$snap_name"
  else
    printf '' >"$committed_snapshot_dir/$snap_name"
  fi
done

# The 11 Defaults field names, derived the same way tests/test_base_rules.sh
# derives them (from PLAN.md's profile example), so a rename in PLAN.md
# that is not mirrored here is caught rather than silently tolerated by a
# second hardcoded copy.
plan_file="$repo_root/PLAN.md"
defaults_field_names=$(awk '
  /^### The profile/ { in_section=1 }
  in_section && /^```markdown/ && !in_fence { in_fence=1; next }
  in_fence && /^```$/ { in_fence=0; in_section=0; next }
  in_fence {
    if (match($0, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
      print substr($0, 1, RLENGTH - 1)
    }
  }
' "$plan_file")

# --- Distinctive rule-body sentences used throughout this file ----------
#
# Copied verbatim from rules/base-rules.md (read, never written, by this
# file). Kept as named variables so every assertion that needs one of
# them stays byte-identical to the canonical source rather than each
# call site retyping (and risking a silent divergence from) the string.
RULE1_ANSWER_SENTENCE="the opening sentence of the response is the answer or the immediate next action"
RULE5_STEP_BY_STEP_SENTENCE="When \`code_style\` is step-by-step: state the numbered steps first, then show the code block, and keep the total explanation within \`explanation_budget\` lines."
RULE13_CLARITY_SENTENCE="Clarity beats compression whenever safety is at stake."
RULE14_NOT_INVISIBILITY_SENTENCE="Tool calls are always visible in the transcript; this rule promises no prose about the write in the response, not invisibility."
RULE16_WARM_OPENER_SENTENCE="A warm opener that stands alone before the answer is preamble, and rule 2 forbids it regardless of \`tone\`."

# S9, X1: rule 10's amended full body, as three sentences (trigger,
# carve-out, no-branch) -- the same pattern rule 5's/14's/16's pins above
# use. Pinned in full because the S9 defect was a MISSING carve-out
# sentence: a pin on the trigger sentence alone would still pass on the
# pre-amendment text (the trigger clause is new too, but a pin that
# checked only "ask before switching" would have passed both the old and
# the new wording), so the carve-out sentence specifically -- the one
# clause whose absence IS the bug probe 8 found -- gets its own constant
# and its own assertion below, not folded into a substring of the other
# two.
RULE10_TRIGGER_SENTENCE="ask a single yes/no question before switching topics only when the assistant itself is the one introducing the different topic, or when the switch would abandon a task that is still open and unfinished."
RULE10_CARVEOUT_SENTENCE="Do not ask when the user has already named the new topic themselves, even when that switch abandons open work: an explicit request to switch is the answer to that question, and asking it back is exactly the preamble rule 2 forbids."
RULE10_NO_BRANCH_SENTENCE="When \`confirm_topic_switch\` is no, switch without asking, in every case."

read_file() {
  # read_file <path> - prints file content, or empty string if missing.
  # Never fails the whole test file on a missing artifact; the missing
  # file itself is caught by the assert_file_exists calls below.
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf ''
  fi
}

# make_build_scratch: creates a throwaway directory containing
# scripts/build.sh, rules/base-rules.md, AND the four real
# skills/{digest,plan,init,tune}/SKILL.md sources (build.sh resolves
# its own repo root as the parent of its own script_dir, so a copy
# running from scratch/scripts/build.sh reads scratch/rules/base-rules.md
# and scratch/skills/*/SKILL.md, and writes into scratch/output-styles,
# scratch/skills/rules, scratch/targets/* -- never touching the real
# repo). Prints the scratch dir path.
#
# The four skills/*/SKILL.md copies are NOT optional (S7's B1 fix):
# build.sh used to tolerate a missing skills/<name>/SKILL.md as a
# silent per-artifact skip, specifically so this fixture could omit
# skills/ entirely and still build the four rules-derived artifacts.
# That tolerance is exactly what let a deleted skills/plan/SKILL.md
# ship targets/cursor/commands/plan.md stale, with build.sh exiting 0
# and the CI drift check structurally unable to see it (regenerating
# from the same missing source reproduces the same stale artifact). The
# tolerance is gone from build.sh now - a missing source is a loud,
# whole-build failure - so this fixture supplies real sources instead
# of relying on build.sh to cope with their absence.
#
# Defined HERE, before the first scenario that needs it, because every
# scenario in this file that runs build.sh at all now runs it through
# this fixture -- see the "no scenario in this file may invoke the real
# repo's build.sh" note just below.
make_build_scratch() {
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-build-scratch.XXXXXX")
  mkdir -p "$scratch/scripts" "$scratch/rules" "$scratch/skills"
  cp "$build_script" "$scratch/scripts/build.sh"
  chmod +x "$scratch/scripts/build.sh"
  cp "$base_rules_file" "$scratch/rules/base-rules.md"
  for cmd_name in digest plan init tune; do
    mkdir -p "$scratch/skills/$cmd_name"
    cp "$repo_root/skills/$cmd_name/SKILL.md" "$scratch/skills/$cmd_name/SKILL.md"
  done
  printf '%s\n' "$scratch"
}

# --- NO SCENARIO IN THIS FILE MAY INVOKE THE REAL REPO'S build.sh -------
#
# build.sh derives its own repo_root from its own location, so running
# "$build_script" (the repo's own copy) WRITES all thirteen generated
# artifacts into the working tree under test. Scenarios 2, 13 and 13b
# used to do exactly that, and the consequence was not theoretical: a
# real drift -- e.g. a hand-edited `alwaysApply: false` in the committed
# targets/cursor/squirrel-mode.mdc -- was reported by scenario 3 exactly
# ONCE, because the very same run had already silently rewritten the
# file back to canonical. `git status --porcelain` came back empty after
# the failing run, and every later run passed: a test run REPAIRED the
# defect it exists to report, destroying the evidence and making the
# failure unreproducible.
#
# Every build.sh invocation below therefore goes through
# make_build_scratch above and runs "$scratch/scripts/build.sh". The
# repository working tree is READ ONLY for the whole of this file, and
# the repo_generated_* tripwire at the bottom asserts that outright.
repo_generated_rel_paths="output-styles/squirrel-mode.md skills/rules/SKILL.md targets/codex/AGENTS.md targets/cursor/squirrel-mode.mdc targets/codex/skills/digest/SKILL.md targets/codex/skills/plan/SKILL.md targets/codex/skills/init/SKILL.md targets/codex/skills/tune/SKILL.md targets/cursor/commands/digest.md targets/cursor/commands/plan.md targets/cursor/skills/squirrel-digest/SKILL.md targets/cursor/skills/squirrel-plan/SKILL.md targets/cursor/hooks/hooks.json"
repo_generated_snapshot() {
  # Prints one cksum line per generated artifact, with the volatile
  # absolute path stripped, so the result compares equal across two
  # calls iff every one of those files is byte-identical.
  for rel in $repo_generated_rel_paths; do
    if [ -f "$repo_root/$rel" ]; then
      printf '%s %s\n' "$rel" "$(cksum <"$repo_root/$rel")"
    else
      printf '%s MISSING\n' "$rel"
    fi
  done
}
repo_generated_before=$(repo_generated_snapshot)

# ==========================================================================
# 1. scripts/build.sh exists and is executable.
# ==========================================================================
assert_file_exists "$build_script" "scripts/build.sh must exist"
if [ -x "$build_script" ]; then
  build_script_executable=yes
else
  build_script_executable=no
fi
assert_eq "yes" "$build_script_executable" "scripts/build.sh must be executable"

# ==========================================================================
# 2. Idempotence: build twice IN A SCRATCH DIRECTORY, snapshot all four
#    rules-derived artifacts between the two runs, assert byte-identical.
#
#    Deliberately run against a make_build_scratch copy, never against
#    "$build_script" itself: see the "NO SCENARIO IN THIS FILE MAY
#    INVOKE THE REAL REPO'S build.sh" note above. Idempotence is a
#    property of build.sh, not of the repository working tree, so a
#    scratch copy fed the real rules/base-rules.md and the real
#    skills/*/SKILL.md proves exactly the same thing without writing a
#    single byte into the repo.
# ==========================================================================
idempotence_scratch=$(make_build_scratch)
cleanup_dirs="$cleanup_dirs $idempotence_scratch"
snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-idempotence.XXXXXX")
cleanup_dirs="$cleanup_dirs $snapshot_dir"

if idempotence_run1_output=$("$idempotence_scratch/scripts/build.sh" 2>&1); then
  idempotence_run1_exit=0
else
  idempotence_run1_exit=$?
fi
assert_eq "0" "$idempotence_run1_exit" "scripts/build.sh (first run) must exit 0 -- output: $idempotence_run1_output"

cp "$idempotence_scratch/output-styles/squirrel-mode.md" "$snapshot_dir/output-style.md" 2>/dev/null || true
cp "$idempotence_scratch/skills/rules/SKILL.md" "$snapshot_dir/skill.md" 2>/dev/null || true
cp "$idempotence_scratch/targets/codex/AGENTS.md" "$snapshot_dir/codex.md" 2>/dev/null || true
cp "$idempotence_scratch/targets/cursor/squirrel-mode.mdc" "$snapshot_dir/cursor.mdc" 2>/dev/null || true

if idempotence_run2_output=$("$idempotence_scratch/scripts/build.sh" 2>&1); then
  idempotence_run2_exit=0
else
  idempotence_run2_exit=$?
fi
assert_eq "0" "$idempotence_run2_exit" "scripts/build.sh (second run) must exit 0 -- output: $idempotence_run2_output"

for pair in "output-style.md:output-styles/squirrel-mode.md" "skill.md:skills/rules/SKILL.md" "codex.md:targets/codex/AGENTS.md" "cursor.mdc:targets/cursor/squirrel-mode.mdc"; do
  snap_name=${pair%%:*}
  rel_path=${pair#*:}
  if diff_output=$(diff -u "$snapshot_dir/$snap_name" "$idempotence_scratch/$rel_path" 2>&1); then
    idempotent_status=identical
  else
    idempotent_status="DIFFERS: $diff_output"
  fi
  assert_eq "identical" "$idempotent_status" "$rel_path must be byte-identical across two consecutive build.sh runs (idempotence)"
done
rm -rf "$idempotence_scratch"

# ==========================================================================
# 3. Drift: regenerate into a temporary directory and diff against the
#    committed artifacts. This is the check CI relies on to keep
#    "generated files are committed" safe.
# ==========================================================================
drift_scratch=$(make_build_scratch)
if drift_build_output=$("$drift_scratch/scripts/build.sh" 2>&1); then
  drift_build_exit=0
else
  drift_build_exit=$?
fi
assert_eq "0" "$drift_build_exit" "regenerating into a scratch directory must succeed -- output: $drift_build_output"

# Compared against the FROZEN committed_snapshot_dir captured at the top
# of this file rather than against "$repo_root/$rel" directly. Scenario
# 2 no longer builds into the real repo at all (it runs a
# make_build_scratch copy), so a live-file comparison here would be
# correct today -- but the freeze is kept deliberately as a second line
# of defence: it is what makes this drift check independent of anything
# a scenario running earlier in this same process might do to the
# working tree, which is exactly the property that failed before.
for pair in "output-styles/squirrel-mode.md:output-style.md" "skills/rules/SKILL.md:skill.md" "targets/codex/AGENTS.md:codex.md" "targets/cursor/squirrel-mode.mdc:cursor.mdc"; do
  rel=${pair%%:*}
  snap_name=${pair#*:}
  if drift_diff=$(diff -u "$committed_snapshot_dir/$snap_name" "$drift_scratch/$rel" 2>&1); then
    drift_status=identical
  else
    drift_status="DRIFT DETECTED: $drift_diff"
  fi
  assert_eq "identical" "$drift_status" "committed $rel must match a fresh regeneration from rules/base-rules.md (no drift)"
done
rm -rf "$drift_scratch"

# ==========================================================================
# 4. Rule completeness per target: assert full BODIES survived, not just
#    headings. Specifically pins rule 5's step-by-step branch and rule
#    14's "not invisibility" sentence in the Claude Code artifacts (the
#    exact truncation the blank-line-parser warning describes). Rule 5 is
#    targets:all, so it is also checked in the Codex/Cursor artifacts.
# ==========================================================================
output_style_content=$(read_file "$output_style_file")
skill_content=$(read_file "$skill_file")
codex_content=$(read_file "$codex_file")
cursor_content=$(read_file "$cursor_file")

assert_contains "$output_style_content" "$RULE5_STEP_BY_STEP_SENTENCE" "output style must carry rule 5's full step-by-step branch (not truncated at the first blank line)"
assert_contains "$skill_content" "$RULE5_STEP_BY_STEP_SENTENCE" "skill must carry rule 5's full step-by-step branch (not truncated at the first blank line)"
assert_contains "$output_style_content" "$RULE14_NOT_INVISIBILITY_SENTENCE" "output style must carry rule 14's full 'not invisibility' sentence (not truncated at the first blank line)"
assert_contains "$skill_content" "$RULE14_NOT_INVISIBILITY_SENTENCE" "skill must carry rule 14's full 'not invisibility' sentence (not truncated at the first blank line)"

# Bonus: rule 5 is targets:all, so it must also survive in Codex/Cursor.
assert_contains "$codex_content" "$RULE5_STEP_BY_STEP_SENTENCE" "Codex AGENTS.md must carry rule 5's full step-by-step branch (rule 5 is targets:all)"
assert_contains "$cursor_content" "$RULE5_STEP_BY_STEP_SENTENCE" "Cursor .mdc must carry rule 5's full step-by-step branch (rule 5 is targets:all)"

# S9, X1: rule 10's amended body, full text, in all four artifacts (rule
# 10 is targets:all, same as rule 5 above). The carve-out sentence is the
# one that matters most here -- it is what a live probe (probe 8) found
# missing from the ORIGINAL rule, and it is the clause most likely to be
# silently dropped by a future edit that "simplifies" rule 10 back toward
# its pre-amendment shape. All three sentences are pinned, not just the
# carve-out, per X1's "full body text" instruction.
for target_label_content in "output style:$output_style_content" "skill:$skill_content" "Codex AGENTS.md:$codex_content" "Cursor .mdc:$cursor_content"; do
  target_label=${target_label_content%%:*}
  target_content=${target_label_content#*:}
  assert_contains "$target_content" "$RULE10_TRIGGER_SENTENCE" "$target_label must carry rule 10's full trigger sentence (rule 10 is targets:all)"
  assert_contains "$target_content" "$RULE10_CARVEOUT_SENTENCE" "$target_label must carry rule 10's carve-out sentence for a user-named topic switch (rule 10 is targets:all) -- this is the exact clause probe 8 found missing"
  assert_contains "$target_content" "$RULE10_NO_BRANCH_SENTENCE" "$target_label must carry rule 10's confirm_topic_switch:no branch, unchanged (rule 10 is targets:all)"
done

# ==========================================================================
# 5. Rule exclusion per target: rule 14 must be absent from Codex/Cursor,
#    checked by its distinctive BODY text, not merely its heading.
# ==========================================================================
assert_not_contains "$codex_content" "$RULE14_NOT_INVISIBILITY_SENTENCE" "Codex AGENTS.md must NOT contain rule 14's body text (rule 14 is targets:claude-code)"
assert_not_contains "$cursor_content" "$RULE14_NOT_INVISIBILITY_SENTENCE" "Cursor .mdc must NOT contain rule 14's body text (rule 14 is targets:claude-code)"
assert_not_contains "$codex_content" "### 14. Checkpoint maintenance" "Codex AGENTS.md must NOT contain rule 14's heading either"
assert_not_contains "$cursor_content" "### 14. Checkpoint maintenance" "Cursor .mdc must NOT contain rule 14's heading either"

# ==========================================================================
# 5b (AD3, S10 review cycle 3 final gate). AC2's fix stopped rules 2 and 7
#    (both targets:all, so both ship verbatim into Codex/Cursor) from
#    naming rule 14 BY NUMBER, but left the checkpoint-failure-report
#    CONCEPT described in their prose - so a Codex/Cursor user still read
#    a definitive ordering statement for an event those targets
#    structurally cannot produce (README's parity table: "Auto
#    checkpoints: no"; docs/OTHER-TOOLS.md: nothing writes to a
#    checkpoints directory on either target). Fixed by making rules 2 and
#    7's ordering GENERIC and moving the report's own concept into rule
#    14 alone (targets:claude-code, absent from both artifacts). Checked
#    here on the GENERATED artifacts directly, not merely on rule 14's
#    own absence (already covered above) - this is what actually proves
#    the CONCEPT is gone, not just the rule NUMBER. Scoped to the specific
#    retired phrases, not a blanket "checkpoint" ban: rule 15 (also
#    targets:all) legitimately says "This rule does not assume a
#    checkpoint... exists on any target", and that correct, cross-target
#    disclaimer must keep shipping into both artifacts unaffected.
# ==========================================================================
for target_label_content in "Codex AGENTS.md:$codex_content" "Cursor .mdc:$cursor_content"; do
  target_label=${target_label_content%%:*}
  target_content=${target_label_content#*:}
  assert_not_contains "$target_content" "checkpoint update failed" "$target_label must not mention a 'checkpoint update failed' report (AD3) - that concept only exists on Claude Code (rule 14), and neither Codex nor Cursor has a checkpoint feature at all"
  assert_not_contains "$target_content" "checkpoint-failure" "$target_label must not mention a checkpoint-failure report or its ordering (AD3) - same reason"
  assert_not_contains "$target_content" "checkpoint-update-failure" "$target_label must not mention a checkpoint-update-failure report (AD3, the exact retired AB2-era phrasing) - same reason"
  # The legitimate, cross-target-correct disclaimer (rule 15) must still
  # be present and unaffected by the negative pins above - proving they
  # are scoped to the retired phrases, not a blanket word ban that would
  # also (wrongly) forbid this sentence.
  assert_contains "$target_content" "does not assume a checkpoint" "$target_label must still carry rule 15's legitimate, unrelated 'does not assume a checkpoint... exists on any target' disclaimer - proving the negative pins above are scoped, not a blanket ban on the word 'checkpoint'"
done

# ==========================================================================
# 6. Rule count per artifact: 16 for the two Claude Code artifacts, 15
#    for Codex and Cursor.
# ==========================================================================
count_rule_headings() {
  grep -c '^### [0-9][0-9]*\. ' "$1" 2>/dev/null || true
}
assert_eq "16" "$(count_rule_headings "$output_style_file")" "output-styles/squirrel-mode.md must contain exactly 16 rule headings"
assert_eq "16" "$(count_rule_headings "$skill_file")" "skills/rules/SKILL.md must contain exactly 16 rule headings"
assert_eq "15" "$(count_rule_headings "$codex_file")" "targets/codex/AGENTS.md must contain exactly 15 rule headings"
assert_eq "15" "$(count_rule_headings "$cursor_file")" "targets/cursor/squirrel-mode.mdc must contain exactly 15 rule headings"

# ==========================================================================
# 7. Frontmatter validity: the output style's and the .mdc's frontmatter
#    parse as YAML, description survives as a single string containing
#    the colon, keep-coding-instructions/force-for-plugin are true in the
#    output style, alwaysApply is true in the .mdc. Always additionally
#    checked via sed/awk (belt-and-suspenders per the S3 instructions),
#    regardless of whether a YAML parser happens to be available.
# ==========================================================================
extract_frontmatter_line() {
  # extract_frontmatter_line <file> <key> - prints the raw line for <key>
  # inside the frontmatter block (between the first two "---" lines).
  awk -v key="$2" '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && $0 ~ ("^" key ":") { print; exit }
  ' "$1"
}

os_description_line=$(extract_frontmatter_line "$output_style_file" "description")
assert_eq 'description: "ADHD-friendly responses: answer first, zero fluff. 🐿️"' "$os_description_line" "output style description line must be exactly the quoted string from the spec"

case "$os_description_line" in
  'description: "'*'"')
    os_description_quoted=yes
    ;;
  *)
    os_description_quoted=no
    ;;
esac
assert_eq "yes" "$os_description_quoted" "output style description line must be double-quoted (required because it contains a colon)"

os_keep_coding_line=$(extract_frontmatter_line "$output_style_file" "keep-coding-instructions")
os_force_plugin_line=$(extract_frontmatter_line "$output_style_file" "force-for-plugin")
assert_eq "keep-coding-instructions: true" "$os_keep_coding_line" "output style must set keep-coding-instructions: true"
assert_eq "force-for-plugin: true" "$os_force_plugin_line" "output style must set force-for-plugin: true"

cursor_always_apply_line=$(extract_frontmatter_line "$cursor_file" "alwaysApply")
assert_eq "alwaysApply: true" "$cursor_always_apply_line" "cursor .mdc must set alwaysApply: true"

cursor_globs_line=$(extract_frontmatter_line "$cursor_file" "globs")
assert_eq "" "$cursor_globs_line" "cursor .mdc must NOT emit a globs field (this is a global rule, not file-scoped)"

skill_description_line=$(extract_frontmatter_line "$skill_file" "description")
skill_disable_invocation_line=$(extract_frontmatter_line "$skill_file" "disable-model-invocation")
if [ -n "$skill_description_line" ]; then
  skill_description_present=yes
else
  skill_description_present=no
fi
assert_eq "yes" "$skill_description_present" "skills/rules/SKILL.md must have a description field"
assert_eq "disable-model-invocation: true" "$skill_disable_invocation_line" "skills/rules/SKILL.md must set disable-model-invocation: true"

# Structural YAML validity, using python3+PyYAML. This is additive to
# the sed/awk checks above, never a replacement for them.
#
# The detection below is kept, but its result is now ASSERTED rather
# than used as a silent skip condition. Before, a machine without
# PyYAML ran none of the nine assertions guarded by have_yaml_parser and
# this file still printed "SUMMARY pass=N fail=0" - a green that told
# you nothing about whether the frontmatter actually parses. tests/run.sh
# now gates python3+PyYAML as a hard prerequisite, alongside the other
# two the harness already required, and .github/workflows/ci.yml
# installs it; the assertion here covers the other way in, running this
# file directly, where run.sh's gate never executes.
have_yaml_parser=no
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" >/dev/null 2>&1; then
    have_yaml_parser=yes
  fi
fi
assert_eq "yes" "$have_yaml_parser" "python3 with PyYAML must be importable: the nine structural YAML assertions below are skipped without it, and a skipped assertion is indistinguishable from a passing one in this file's SUMMARY line. Install it (e.g. 'pip3 install pyyaml' or 'apt-get install python3-yaml'), or run the suite through tests/run.sh, which gates it as a hard prerequisite"

yaml_check_file() {
  # yaml_check_file <path> - prints "PARSES=<yes|no>" then one
  # "<key>=<PASS|FAIL>" line per field this test cares about for that
  # file. Only called when have_yaml_parser=yes.
  python3 - "$1" <<'PYEOF'
import sys, re, yaml

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    print("PARSES=no")
    sys.exit(0)
try:
    data = yaml.safe_load(m.group(1))
except Exception:
    print("PARSES=no")
    sys.exit(0)
if not isinstance(data, dict):
    print("PARSES=no")
    sys.exit(0)
print("PARSES=yes")
desc = data.get("description")
print("description_str_with_colon=%s" % ("PASS" if isinstance(desc, str) and ":" in desc else "FAIL"))
print("keep_coding_true=%s" % ("PASS" if data.get("keep-coding-instructions") is True else "FAIL"))
print("force_plugin_true=%s" % ("PASS" if data.get("force-for-plugin") is True else "FAIL"))
print("always_apply_true=%s" % ("PASS" if data.get("alwaysApply") is True else "FAIL"))
print("no_globs_key=%s" % ("PASS" if "globs" not in data else "FAIL"))
print("disable_invocation_true=%s" % ("PASS" if data.get("disable-model-invocation") is True else "FAIL"))
PYEOF
}

if [ "$have_yaml_parser" = "yes" ]; then
  os_yaml=$(yaml_check_file "$output_style_file")
  assert_eq "PARSES=yes" "$(printf '%s\n' "$os_yaml" | grep '^PARSES=')" "output style frontmatter must parse as valid YAML"
  assert_eq "description_str_with_colon=PASS" "$(printf '%s\n' "$os_yaml" | grep '^description_str_with_colon=')" "output style YAML description must be a string containing a colon"
  assert_eq "keep_coding_true=PASS" "$(printf '%s\n' "$os_yaml" | grep '^keep_coding_true=')" "output style YAML keep-coding-instructions must be boolean true"
  assert_eq "force_plugin_true=PASS" "$(printf '%s\n' "$os_yaml" | grep '^force_plugin_true=')" "output style YAML force-for-plugin must be boolean true"

  cursor_yaml=$(yaml_check_file "$cursor_file")
  assert_eq "PARSES=yes" "$(printf '%s\n' "$cursor_yaml" | grep '^PARSES=')" "cursor .mdc frontmatter must parse as valid YAML"
  assert_eq "always_apply_true=PASS" "$(printf '%s\n' "$cursor_yaml" | grep '^always_apply_true=')" "cursor .mdc YAML alwaysApply must be boolean true"
  assert_eq "no_globs_key=PASS" "$(printf '%s\n' "$cursor_yaml" | grep '^no_globs_key=')" "cursor .mdc YAML must not have a globs key"

  skill_yaml=$(yaml_check_file "$skill_file")
  assert_eq "PARSES=yes" "$(printf '%s\n' "$skill_yaml" | grep '^PARSES=')" "skill frontmatter must parse as valid YAML"
  assert_eq "disable_invocation_true=PASS" "$(printf '%s\n' "$skill_yaml" | grep '^disable_invocation_true=')" "skill YAML disable-model-invocation must be boolean true"
fi

# ==========================================================================
# 8. No interpolation syntax: no "${" appears in any generated artifact.
# ==========================================================================
dollar_brace="\${"
assert_not_contains "$output_style_content" "$dollar_brace" "output style must contain no \${...} placeholder syntax (ADR-0001: output styles do not interpolate)"
assert_not_contains "$skill_content" "$dollar_brace" "skill must contain no \${...} placeholder syntax"
assert_not_contains "$codex_content" "$dollar_brace" "Codex AGENTS.md must contain no \${...} placeholder syntax"
assert_not_contains "$cursor_content" "$dollar_brace" "Cursor .mdc must contain no \${...} placeholder syntax"

# ==========================================================================
# 9. GENERATED marker: every artifact carries it, names its source
#    (rules/base-rules.md) and its generator (scripts/build.sh); in the
#    frontmatter-bearing files it sits after the closing "---".
# ==========================================================================
for label_path in "output style:$output_style_file" "skill:$skill_file" "Codex AGENTS.md:$codex_file" "Cursor .mdc:$cursor_file"; do
  label=${label_path%%:*}
  path=${label_path#*:}
  content=$(read_file "$path")
  assert_contains "$content" "GENERATED" "$label must carry a GENERATED marker"
  assert_contains "$content" "rules/base-rules.md" "$label's GENERATED marker must name rules/base-rules.md as the source"
  assert_contains "$content" "scripts/build.sh" "$label's GENERATED marker must name scripts/build.sh as the generator"
done

marker_line_number() {
  grep -n -m1 'GENERATED FILE' "$1" 2>/dev/null | cut -d: -f1
}
second_frontmatter_delim_line() {
  awk '/^---$/ { c++; if (c == 2) { print NR; exit } }' "$1"
}

for path in "$output_style_file" "$skill_file" "$cursor_file"; do
  close_line=$(second_frontmatter_delim_line "$path")
  gen_line=$(marker_line_number "$path")
  if [ -n "$close_line" ] && [ -n "$gen_line" ] && [ "$gen_line" -gt "$close_line" ]; then
    marker_after_frontmatter=yes
  else
    marker_after_frontmatter=no
  fi
  assert_eq "yes" "$marker_after_frontmatter" "$path: GENERATED marker (line $gen_line) must come after the closing frontmatter '---' (line $close_line)"
done

# ==========================================================================
# 10. No rule text in build.sh: distinctive sentences from several
#     different rule bodies must not appear in scripts/build.sh.
# ==========================================================================
build_script_content=$(read_file "$build_script")
assert_not_contains "$build_script_content" "$RULE1_ANSWER_SENTENCE" "scripts/build.sh must not contain rule 1's body text verbatim"
assert_not_contains "$build_script_content" "$RULE5_STEP_BY_STEP_SENTENCE" "scripts/build.sh must not contain rule 5's body text verbatim"
assert_not_contains "$build_script_content" "$RULE13_CLARITY_SENTENCE" "scripts/build.sh must not contain rule 13's body text verbatim"
assert_not_contains "$build_script_content" "$RULE14_NOT_INVISIBILITY_SENTENCE" "scripts/build.sh must not contain rule 14's body text verbatim"
assert_not_contains "$build_script_content" "$RULE16_WARM_OPENER_SENTENCE" "scripts/build.sh must not contain rule 16's body text verbatim"
assert_not_contains "$build_script_content" "$RULE10_CARVEOUT_SENTENCE" "scripts/build.sh must not contain rule 10's carve-out sentence verbatim"

# ==========================================================================
# 11. Defaults table present in all four artifacts, with all 11 field
#     names.
# ==========================================================================
for label_path in "output style:$output_style_file" "skill:$skill_file" "Codex AGENTS.md:$codex_file" "Cursor .mdc:$cursor_file"; do
  label=${label_path%%:*}
  path=${label_path#*:}
  content=$(read_file "$path")
  assert_contains "$content" "## Defaults" "$label must contain a '## Defaults' section"
  for field in $defaults_field_names; do
    assert_contains "$content" "| $field |" "$label's Defaults table must list the '$field' field"
  done
done

# ==========================================================================
# 12. Build fails loudly on malformed input. Fourteen sub-cases (a-n),
#     each on its own scratch copy so the real rules/base-rules.md is
#     never touched: a missing marker, an unknown target, a removed
#     rule, four comma-syntax defects in a targets value (trailing,
#     leading, doubled comma, empty value), "all" combined with a
#     specific target, a duplicated target, CRLF line endings, a
#     marker-shaped line stray mid-body, that same stray line indented
#     with spaces (l) and with a tab (m), and a real marker indented
#     directly after its heading (n).
# ==========================================================================
line_of_heading() {
  awk -v want="$1" '$0 ~ ("^### " want "\\. ") { print NR; exit }' "$2"
}
line_of_marker_for_rule() {
  awk -v want="$1" '
    $0 ~ ("^### " want "\\. ") { f = 1; next }
    f && /^<!-- targets:/ { print NR; exit }
    f && /^### [0-9]+\. / { exit }
  ' "$2"
}
delete_line() {
  # delete_line <file> <line_number>
  awk -v n="$2" 'NR != n' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
replace_line() {
  # replace_line <file> <line_number> <new_text>
  awk -v n="$2" -v t="$3" 'NR == n { print t; next } { print }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
delete_range() {
  # delete_range <file> <start_line> <end_line_inclusive>
  awk -v s="$2" -v e="$3" '(NR < s) || (NR > e)' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
insert_line_after() {
  # insert_line_after <file> <line_number> <text> - inserts <text> as a
  # new line immediately after line <line_number>.
  awk -v n="$2" -v t="$3" 'NR == n { print; print t; next } { print }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
line_of_first_body_line_for_rule() {
  # line_of_first_body_line_for_rule <n> <file> - prints the line number
  # of rule <n>'s first REAL content line: the same "marker zone" (blank
  # lines and marker lines skipped, ending at the first line that is
  # neither) build.sh's own heading-record parser and stray-marker check
  # use. Used to place an injected line strictly *after* the zone has
  # closed - i.e. genuinely mid-body, not merely adjacent to the heading
  # or the real marker.
  awk -v want="$1" '
    $0 ~ ("^### " want "\\. ") { pending = 1; in_zone = 1; next }
    pending && in_zone {
      if ($0 ~ /^[ \t]*$/) { next }
      if ($0 ~ /^<!-- targets:/) { next }
      print NR
      exit
    }
  ' "$2"
}

# --- 12a: delete a <!-- targets: ... --> marker (rule 5's) --------------
scratch_a=$(make_build_scratch)
rule5_marker_line=$(line_of_marker_for_rule 5 "$scratch_a/rules/base-rules.md")
delete_line "$scratch_a/rules/base-rules.md" "$rule5_marker_line"
if malformed_a_output=$("$scratch_a/scripts/build.sh" 2>&1); then
  malformed_a_exit=0
else
  malformed_a_exit=$?
fi
assert_eq "1" "$malformed_a_exit" "build.sh must exit non-zero when a rule's <!-- targets: ... --> marker is deleted -- got exit $malformed_a_exit, output: $malformed_a_output"
rm -rf "$scratch_a"

# --- 12b: set a marker to an unknown target (rule 6's) ------------------
scratch_b=$(make_build_scratch)
rule6_marker_line=$(line_of_marker_for_rule 6 "$scratch_b/rules/base-rules.md")
replace_line "$scratch_b/rules/base-rules.md" "$rule6_marker_line" "<!-- targets: bogus-target -->"
if malformed_b_output=$("$scratch_b/scripts/build.sh" 2>&1); then
  malformed_b_exit=0
else
  malformed_b_exit=$?
fi
assert_eq "1" "$malformed_b_exit" "build.sh must exit non-zero when a targets marker names an unknown target -- got exit $malformed_b_exit, output: $malformed_b_output"
rm -rf "$scratch_b"

# --- 12c: remove a whole rule so the count is 15 -------------------------
scratch_c=$(make_build_scratch)
rule9_start=$(line_of_heading 9 "$scratch_c/rules/base-rules.md")
rule10_start=$(line_of_heading 10 "$scratch_c/rules/base-rules.md")
rule9_end=$((rule10_start - 1))
delete_range "$scratch_c/rules/base-rules.md" "$rule9_start" "$rule9_end"
if malformed_c_output=$("$scratch_c/scripts/build.sh" 2>&1); then
  malformed_c_exit=0
else
  malformed_c_exit=$?
fi
assert_eq "1" "$malformed_c_exit" "build.sh must exit non-zero when a whole rule is removed (count != 16) -- got exit $malformed_c_exit, output: $malformed_c_output"
rm -rf "$scratch_c"

# --- 12d: trailing comma in a targets value ("claude-code,") ------------
scratch_d=$(make_build_scratch)
rule6_marker_line_d=$(line_of_marker_for_rule 6 "$scratch_d/rules/base-rules.md")
replace_line "$scratch_d/rules/base-rules.md" "$rule6_marker_line_d" "<!-- targets: claude-code, -->"
if malformed_d_output=$("$scratch_d/scripts/build.sh" 2>&1); then
  malformed_d_exit=0
else
  malformed_d_exit=$?
fi
assert_eq "1" "$malformed_d_exit" "build.sh must exit non-zero on a trailing comma in a targets value ('claude-code,') -- got exit $malformed_d_exit, output: $malformed_d_output"
rm -rf "$scratch_d"

# --- 12e: leading comma (",claude-code") ---------------------------------
scratch_e=$(make_build_scratch)
rule6_marker_line_e=$(line_of_marker_for_rule 6 "$scratch_e/rules/base-rules.md")
replace_line "$scratch_e/rules/base-rules.md" "$rule6_marker_line_e" "<!-- targets: ,claude-code -->"
if malformed_e_output=$("$scratch_e/scripts/build.sh" 2>&1); then
  malformed_e_exit=0
else
  malformed_e_exit=$?
fi
assert_eq "1" "$malformed_e_exit" "build.sh must exit non-zero on a leading comma in a targets value (',claude-code') -- got exit $malformed_e_exit, output: $malformed_e_output"
rm -rf "$scratch_e"

# --- 12f: doubled comma ("claude-code,,codex") ---------------------------
scratch_f=$(make_build_scratch)
rule6_marker_line_f=$(line_of_marker_for_rule 6 "$scratch_f/rules/base-rules.md")
replace_line "$scratch_f/rules/base-rules.md" "$rule6_marker_line_f" "<!-- targets: claude-code,,codex -->"
if malformed_f_output=$("$scratch_f/scripts/build.sh" 2>&1); then
  malformed_f_exit=0
else
  malformed_f_exit=$?
fi
assert_eq "1" "$malformed_f_exit" "build.sh must exit non-zero on a doubled comma in a targets value ('claude-code,,codex') -- got exit $malformed_f_exit, output: $malformed_f_output"
rm -rf "$scratch_f"

# --- 12g: empty value ("<!-- targets: -->") -------------------------------
scratch_g=$(make_build_scratch)
rule6_marker_line_g=$(line_of_marker_for_rule 6 "$scratch_g/rules/base-rules.md")
replace_line "$scratch_g/rules/base-rules.md" "$rule6_marker_line_g" "<!-- targets: -->"
if malformed_g_output=$("$scratch_g/scripts/build.sh" 2>&1); then
  malformed_g_exit=0
else
  malformed_g_exit=$?
fi
assert_eq "1" "$malformed_g_exit" "build.sh must exit non-zero on an empty targets value ('<!-- targets: -->') -- got exit $malformed_g_exit, output: $malformed_g_output"
rm -rf "$scratch_g"

# --- 12h: "all" combined with a specific target ("all,claude-code") ------
#
# "all" already means every target; combining it with a named target is
# contradictory. See the reasoning next to the per-token allowlist in
# validate_targets_value() in build.sh for why this is rejected rather
# than normalised.
scratch_h=$(make_build_scratch)
rule6_marker_line_h=$(line_of_marker_for_rule 6 "$scratch_h/rules/base-rules.md")
replace_line "$scratch_h/rules/base-rules.md" "$rule6_marker_line_h" "<!-- targets: all,claude-code -->"
if malformed_h_output=$("$scratch_h/scripts/build.sh" 2>&1); then
  malformed_h_exit=0
else
  malformed_h_exit=$?
fi
assert_eq "1" "$malformed_h_exit" "build.sh must exit non-zero when 'all' is combined with a specific target ('all,claude-code' is contradictory) -- got exit $malformed_h_exit, output: $malformed_h_output"
rm -rf "$scratch_h"

# --- 12i: duplicated target ("claude-code,claude-code") -------------------
scratch_i=$(make_build_scratch)
rule6_marker_line_i=$(line_of_marker_for_rule 6 "$scratch_i/rules/base-rules.md")
replace_line "$scratch_i/rules/base-rules.md" "$rule6_marker_line_i" "<!-- targets: claude-code,claude-code -->"
if malformed_i_output=$("$scratch_i/scripts/build.sh" 2>&1); then
  malformed_i_exit=0
else
  malformed_i_exit=$?
fi
assert_eq "1" "$malformed_i_exit" "build.sh must exit non-zero on a duplicated target ('claude-code,claude-code') -- got exit $malformed_i_exit, output: $malformed_i_output"
rm -rf "$scratch_i"

# --- 12j: CRLF line endings -----------------------------------------------
#
# Must fail (it already did, before this fix) AND the message must name
# line endings as the cause, not the misattributed "marker not found".
scratch_j=$(make_build_scratch)
awk '{ printf "%s\r\n", $0 }' "$scratch_j/rules/base-rules.md" >"$scratch_j/rules/base-rules.md.crlf"
mv "$scratch_j/rules/base-rules.md.crlf" "$scratch_j/rules/base-rules.md"
if malformed_j_output=$("$scratch_j/scripts/build.sh" 2>&1); then
  malformed_j_exit=0
else
  malformed_j_exit=$?
fi
assert_eq "1" "$malformed_j_exit" "build.sh must exit non-zero on a CRLF copy of rules/base-rules.md -- got exit $malformed_j_exit, output: $malformed_j_output"
assert_contains "$malformed_j_output" "line ending" "the CRLF failure message must name line endings as the cause, not just report a marker as missing"
rm -rf "$scratch_j"

# --- 12k: a marker-shaped line stray in the MIDDLE of rule 5's body ------
#
# Reproduces the reviewer's exact failure: a second, mid-body
# "<!-- targets: codex -->"-shaped line, well after real content has
# already started, must not be silently stripped (the old bug - it
# vanished from every artifact with no trace and no assertion noticed).
# This suite's chosen fix is to fail the build loudly, naming the rule
# (see the reasoning above the stray-marker check in build.sh for why
# "fail loudly" was chosen over "pass through verbatim").
scratch_k=$(make_build_scratch)
rule5_first_body_line_k=$(line_of_first_body_line_for_rule 5 "$scratch_k/rules/base-rules.md")
insert_line_after "$scratch_k/rules/base-rules.md" "$rule5_first_body_line_k" "<!-- targets: codex -->"
if malformed_k_output=$("$scratch_k/scripts/build.sh" 2>&1); then
  malformed_k_exit=0
else
  malformed_k_exit=$?
fi
assert_eq "1" "$malformed_k_exit" "build.sh must exit non-zero when a '<!-- targets: ... -->'-shaped line appears mid-body (rule 5) -- got exit $malformed_k_exit, output: $malformed_k_output"
assert_contains "$malformed_k_output" "rule 5" "the mid-body marker error must name rule 5"
rm -rf "$scratch_k"

# --- 12l: the SAME mid-body stray marker as 12k, but indented with THREE
# LEADING SPACES ("   <!-- targets: codex -->") -----------------------
#
# This is MAJOR #2 from the cycle-3 review: the stray-marker check used
# to anchor on "^<!-- targets:" with no whitespace tolerance, so this
# exact indented line sailed straight past it, exited 0, and shipped
# the raw HTML comment verbatim into every artifact carrying rule 5 -
# the cycle-2 safety net (12k) covered the unindented case only. Must
# fail exactly like 12k, naming rule 5.
scratch_l=$(make_build_scratch)
rule5_first_body_line_l=$(line_of_first_body_line_for_rule 5 "$scratch_l/rules/base-rules.md")
insert_line_after "$scratch_l/rules/base-rules.md" "$rule5_first_body_line_l" "   <!-- targets: codex -->"
if malformed_l_output=$("$scratch_l/scripts/build.sh" 2>&1); then
  malformed_l_exit=0
else
  malformed_l_exit=$?
fi
assert_eq "1" "$malformed_l_exit" "build.sh must exit non-zero when a SPACE-INDENTED '<!-- targets: ... -->'-shaped line appears mid-body (rule 5) -- got exit $malformed_l_exit, output: $malformed_l_output"
assert_contains "$malformed_l_output" "rule 5" "the space-indented mid-body marker error must name rule 5"
rm -rf "$scratch_l"

# --- 12m: the same stray marker again, indented with a single TAB -------
#
# Same defect as 12l, different whitespace character - the fixed regex
# ("^[ \t]*<!-- targets:") must tolerate both, matching the blank-line
# check's own "^[ \t]*$" tolerance it was inconsistent with before this
# fix.
scratch_m=$(make_build_scratch)
rule5_first_body_line_m=$(line_of_first_body_line_for_rule 5 "$scratch_m/rules/base-rules.md")
tab_char=$(printf '\t')
insert_line_after "$scratch_m/rules/base-rules.md" "$rule5_first_body_line_m" "${tab_char}<!-- targets: codex -->"
if malformed_m_output=$("$scratch_m/scripts/build.sh" 2>&1); then
  malformed_m_exit=0
else
  malformed_m_exit=$?
fi
assert_eq "1" "$malformed_m_exit" "build.sh must exit non-zero when a TAB-INDENTED '<!-- targets: ... -->'-shaped line appears mid-body (rule 5) -- got exit $malformed_m_exit, output: $malformed_m_output"
assert_contains "$malformed_m_output" "rule 5" "the tab-indented mid-body marker error must name rule 5"
rm -rf "$scratch_m"

# --- 12n: the REAL marker, directly after its heading, indented --------
#
# Chosen behaviour (see build.sh's validation-loop comment, right above
# the `first_indented` check, for the full justification): an indented
# real marker is REJECTED, not silently accepted as a second valid
# spelling - "<!-- targets: ... -->" has exactly one valid shape,
# flush-left. What this sub-case pins is the QUALITY of the failure:
# before this fix, an indented real marker made the count-check regex
# miss it entirely, so the error said "found 0" - true in a narrow,
# technical sense, but misleading, since a marker is plainly sitting
# right there. The fixed message must name indentation/leading
# whitespace as the cause instead, and must still name the right rule.
scratch_n=$(make_build_scratch)
rule6_marker_line_n=$(line_of_marker_for_rule 6 "$scratch_n/rules/base-rules.md")
replace_line "$scratch_n/rules/base-rules.md" "$rule6_marker_line_n" "   <!-- targets: all -->"
if malformed_n_output=$("$scratch_n/scripts/build.sh" 2>&1); then
  malformed_n_exit=0
else
  malformed_n_exit=$?
fi
assert_eq "1" "$malformed_n_exit" "build.sh must exit non-zero when the real marker right after a heading is indented (rule 6) -- got exit $malformed_n_exit, output: $malformed_n_output"
assert_contains "$malformed_n_output" "rule 6" "the indented-real-marker error must name rule 6"
assert_contains "$malformed_n_output" "leading whitespace" "the indented-real-marker error must name leading whitespace/indentation as the cause, not just report a misleading marker count"
assert_not_contains "$malformed_n_output" "found 0" "the indented-real-marker error must NOT say 'found 0' -- a marker IS there, just indented, and the fixed message must not deny that"
rm -rf "$scratch_n"

# Sanity: the real rules/base-rules.md was never touched by any of the
# above (each sub-case mutated only its own throwaway scratch copy).
real_rule_count=$(count_rule_headings "$base_rules_file")
assert_eq "16" "$real_rule_count" "sanity: the real rules/base-rules.md must still contain exactly 16 rule headings after scenario 12 (it must never be mutated)"

# ==========================================================================
# 13. build.sh works from a different cwd.
#
#     The property under test is that build.sh resolves its own repo
#     root from its own LOCATION and never from $PWD, so the artifacts
#     land next to the script no matter where it was invoked from. That
#     is proven just as well - and without writing into the repository
#     working tree, see the note at the top of this file - by invoking a
#     make_build_scratch copy from an unrelated cwd and asserting the
#     artifacts landed inside the SCRATCH root.
# ==========================================================================
cwd_scratch=$(make_build_scratch)
cleanup_dirs="$cleanup_dirs $cwd_scratch"
if cwd_run_output=$(cd / && "$cwd_scratch/scripts/build.sh" 2>&1); then
  cwd_run_exit=0
else
  cwd_run_exit=$?
fi
assert_eq "0" "$cwd_run_exit" "scripts/build.sh must succeed when invoked from a different cwd (/) -- output: $cwd_run_output"
assert_file_exists "$cwd_scratch/output-styles/squirrel-mode.md" "output-styles/squirrel-mode.md must still land at the script's own repo-root-relative path after a run from a different cwd"
assert_file_exists "$cwd_scratch/skills/rules/SKILL.md" "skills/rules/SKILL.md must still land at the script's own repo-root-relative path after a run from a different cwd"
assert_file_exists "$cwd_scratch/targets/codex/AGENTS.md" "targets/codex/AGENTS.md must still land at the script's own repo-root-relative path after a run from a different cwd"
assert_file_exists "$cwd_scratch/targets/cursor/squirrel-mode.mdc" "targets/cursor/squirrel-mode.mdc must still land at the script's own repo-root-relative path after a run from a different cwd"
assert_eq "16" "$(count_rule_headings "$cwd_scratch/output-styles/squirrel-mode.md")" "output style must still have 16 rules after a run from a different cwd"
assert_eq "15" "$(count_rule_headings "$cwd_scratch/targets/codex/AGENTS.md")" "Codex AGENTS.md must still have 15 rules after a run from a different cwd"

if cwd_run2_output=$(cd "$script_dir" && "$cwd_scratch/scripts/build.sh" 2>&1); then
  cwd_run2_exit=0
else
  cwd_run2_exit=$?
fi
assert_eq "0" "$cwd_run2_exit" "scripts/build.sh must succeed when invoked from tests/ -- output: $cwd_run2_output"
assert_file_exists "$cwd_scratch/targets/cursor/squirrel-mode.mdc" "targets/cursor/squirrel-mode.mdc must still land at the script's own repo-root-relative path after a run from tests/"
rm -rf "$cwd_scratch"

# 13b (A10, S7 review). CDPATH hardening: a CDPATH entry containing "."
# must not break build.sh. Invoked via a RELATIVE path from the scratch
# root (not the script's own absolute path) - CDPATH only affects `cd`
# when its operand does not already start with "/" or ".", so an
# absolute invocation (as scenario 13 above uses) would never exercise
# the bug this guards against.
cdpath_scratch=$(make_build_scratch)
cleanup_dirs="$cleanup_dirs $cdpath_scratch"
if cdpath_run_output=$(cd "$cdpath_scratch" && CDPATH=. sh scripts/build.sh 2>&1); then
  cdpath_run_exit=0
else
  cdpath_run_exit=$?
fi
assert_eq "0" "$cdpath_run_exit" "scripts/build.sh must succeed with CDPATH=. set, invoked via a relative path (A10) -- output: $cdpath_run_output"
rm -rf "$cdpath_scratch"

# ==========================================================================
# 14. Atomicity: a write failure on one target must not leave the tree
#     half-regenerated. The input here is perfectly valid (unlike
#     scenario 12) - the failure is purely environmental.
#
#     chmod 444 on the FILE alone does NOT reproduce a write failure
#     under the fixed implementation: rename(2) (what `mv` uses to move
#     a temp file into place) checks write permission on the ENCLOSING
#     DIRECTORY, not on the file being replaced, so `mv newfile
#     readonlyfile` succeeds even when readonlyfile is 444 (verified
#     empirically while building this fix, on this same platform). What
#     DOES fail, under the temp-file-then-mv design, is creating the new
#     temp file in the first place - which requires write permission on
#     the directory. So this test removes write permission from one
#     target's DIRECTORY, not from the file, to reproduce a genuine
#     write failure against the fixed script.
# ==========================================================================
atomic_scratch=$(make_build_scratch)
if atomic_build1_output=$("$atomic_scratch/scripts/build.sh" 2>&1); then
  atomic_build1_exit=0
else
  atomic_build1_exit=$?
fi
assert_eq "0" "$atomic_build1_exit" "atomicity fixture: the first (baseline) build in the scratch copy must succeed -- output: $atomic_build1_output"

atomic_output_style="$atomic_scratch/output-styles/squirrel-mode.md"
atomic_skill="$atomic_scratch/skills/rules/SKILL.md"
atomic_codex="$atomic_scratch/targets/codex/AGENTS.md"
atomic_cursor="$atomic_scratch/targets/cursor/squirrel-mode.mdc"

atomic_snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-atomic-snapshot.XXXXXX")
cleanup_dirs="$cleanup_dirs $atomic_snapshot_dir"
cp "$atomic_output_style" "$atomic_snapshot_dir/output-style.md"
cp "$atomic_skill" "$atomic_snapshot_dir/skill.md"
cp "$atomic_codex" "$atomic_snapshot_dir/codex.md"
cp "$atomic_cursor" "$atomic_snapshot_dir/cursor.mdc"
# B2 (S7 review): snapshot the eight ported artifacts too, so the
# "unchanged after a failed build" assertion below covers all thirteen, not
# just the original four.
cp "$atomic_scratch/targets/codex/skills/digest/SKILL.md" "$atomic_snapshot_dir/codex-skill-digest.md"
cp "$atomic_scratch/targets/codex/skills/plan/SKILL.md" "$atomic_snapshot_dir/codex-skill-plan.md"
cp "$atomic_scratch/targets/codex/skills/init/SKILL.md" "$atomic_snapshot_dir/codex-skill-init.md"
cp "$atomic_scratch/targets/codex/skills/tune/SKILL.md" "$atomic_snapshot_dir/codex-skill-tune.md"
cp "$atomic_scratch/targets/cursor/commands/digest.md" "$atomic_snapshot_dir/cursor-command-digest.md"
cp "$atomic_scratch/targets/cursor/commands/plan.md" "$atomic_snapshot_dir/cursor-command-plan.md"
cp "$atomic_scratch/targets/cursor/skills/squirrel-digest/SKILL.md" "$atomic_snapshot_dir/cursor-skill-digest.md"
cp "$atomic_scratch/targets/cursor/skills/squirrel-plan/SKILL.md" "$atomic_snapshot_dir/cursor-skill-plan.md"
assert_file_exists "$atomic_scratch/targets/cursor/hooks/hooks.json" "atomicity fixture: the first (baseline) build must produce targets/cursor/hooks/hooks.json"
if [ -f "$atomic_scratch/targets/cursor/hooks/hooks.json" ]; then
  cp "$atomic_scratch/targets/cursor/hooks/hooks.json" "$atomic_snapshot_dir/cursor-hooks.json"
fi

# Change rules/base-rules.md (rule 1's body gets an extra sentence) so a
# successful rebuild WOULD change all four artifacts, then make
# targets/codex/'s directory read-only so the rebuild cannot even create
# its temp file there.
rule1_first_body_line=$(line_of_first_body_line_for_rule 1 "$atomic_scratch/rules/base-rules.md")
insert_line_after "$atomic_scratch/rules/base-rules.md" "$rule1_first_body_line" "This sentence was added only to force a content change for the atomicity test."
chmod 555 "$atomic_scratch/targets/codex"

if atomic_build2_output=$("$atomic_scratch/scripts/build.sh" 2>&1); then
  atomic_build2_exit=0
else
  atomic_build2_exit=$?
fi
chmod 755 "$atomic_scratch/targets/codex"
# NON-ZERO, not a specific number. The requirement build.sh has to meet is
# "refuse to ship a half-written artifact", and the only observable it owes
# a caller for that is a failing exit status - which number it is belongs to
# the shell, not to this repo. `sh scripts/build.sh` dies on the failed
# redirection that creates the temp file, and the status a shell reports for
# a redirection failure is dialect-specific: bash reports 1, dash reports 2
# (verified directly: `dash -c 'echo x > /nonexistent-dir/f'` exits 2, the
# same line under bash exits 1). Pinning "1" therefore passed on macOS and
# failed on CI's ubuntu /bin/sh (dash) with "got exit 2" - a green/red split
# decided by the runner's shell rather than by build.sh's behaviour, which
# was correct on both. Widened to the requirement the message already
# stated; the observed status stays in the message so a regression that
# changes WHICH failure occurs is still legible in the output.
if [ "$atomic_build2_exit" -ne 0 ]; then
  atomic_build2_failed=yes
else
  atomic_build2_failed=no
fi
assert_eq "yes" "$atomic_build2_failed" "build.sh must exit non-zero when it cannot write one target artifact (read-only targets/codex/ directory) -- got exit $atomic_build2_exit, output: $atomic_build2_output"

for pair in "output-style.md:$atomic_output_style" "skill.md:$atomic_skill" "cursor.mdc:$atomic_cursor" "codex-skill-digest.md:$atomic_scratch/targets/codex/skills/digest/SKILL.md" "codex-skill-plan.md:$atomic_scratch/targets/codex/skills/plan/SKILL.md" "codex-skill-init.md:$atomic_scratch/targets/codex/skills/init/SKILL.md" "codex-skill-tune.md:$atomic_scratch/targets/codex/skills/tune/SKILL.md" "cursor-command-digest.md:$atomic_scratch/targets/cursor/commands/digest.md" "cursor-command-plan.md:$atomic_scratch/targets/cursor/commands/plan.md" "cursor-skill-digest.md:$atomic_scratch/targets/cursor/skills/squirrel-digest/SKILL.md" "cursor-skill-plan.md:$atomic_scratch/targets/cursor/skills/squirrel-plan/SKILL.md" "cursor-hooks.json:$atomic_scratch/targets/cursor/hooks/hooks.json"; do
  snap_name=${pair%%:*}
  live_path=${pair#*:}
  if [ ! -f "$atomic_snapshot_dir/$snap_name" ]; then
    assert_eq "unchanged" "CHANGED: snapshot missing $snap_name" "$live_path must be UNCHANGED after a failed build caused by one unwritable target (atomicity: no partial regeneration) - B2, all thirteen artifacts"
    continue
  fi
  if atomic_diff=$(diff -u "$atomic_snapshot_dir/$snap_name" "$live_path" 2>&1); then
    atomic_status=unchanged
  else
    atomic_status="CHANGED: $atomic_diff"
  fi
  assert_eq "unchanged" "$atomic_status" "$live_path must be UNCHANGED after a failed build caused by one unwritable target (atomicity: no partial regeneration) - B2, all thirteen artifacts"
done

# The failing target itself must also be unchanged (still the baseline
# content, not corrupted mid-write) - it could not have been touched at
# all, since its own directory was the one made read-only, even for
# creating a temp file.
if atomic_codex_diff=$(diff -u "$atomic_snapshot_dir/codex.md" "$atomic_codex" 2>&1); then
  atomic_codex_status=unchanged
else
  atomic_codex_status="CHANGED: $atomic_codex_diff"
fi
assert_eq "unchanged" "$atomic_codex_status" "$atomic_codex must also be unchanged (its own directory was the one made read-only; it could not have been written at all)"

# No leftover temp files anywhere in the scratch tree after the failed
# build - the EXIT trap in build.sh must clean them up even on failure.
leftover_tmp=$(find "$atomic_scratch" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover_tmp" "no .tmp temp files must be left behind in the scratch tree after a failed build"

rm -rf "$atomic_scratch"

# ==========================================================================
# 15. Non-false-positive confirmation: backtick-quoted prose that merely
#     shows the marker syntax as an example, and an unrelated HTML
#     comment (one that does not contain the literal text "targets:"),
#     must NOT trip the (now whitespace-tolerant) stray-marker check
#     from scenario 12's l/m sub-cases, and must ship byte-verbatim into
#     every artifact carrying that rule. This is the reviewer's
#     non-false-positive finding from the S3 review; the whitespace fix
#     above must not regress it.
# ==========================================================================
nonfp_scratch=$(make_build_scratch)
rule5_first_body_line_nonfp=$(line_of_first_body_line_for_rule 5 "$nonfp_scratch/rules/base-rules.md")
# shellcheck disable=SC2016 # single-quoted deliberately: the backticks
# are literal text to insert, not command substitution to evaluate.
backtick_prose_line='See the `<!-- targets: all -->` marker syntax for how targeting works.'
unrelated_comment_line='<!-- this is an unrelated note, not a targets marker -->'
insert_line_after "$nonfp_scratch/rules/base-rules.md" "$rule5_first_body_line_nonfp" "$unrelated_comment_line"
insert_line_after "$nonfp_scratch/rules/base-rules.md" "$rule5_first_body_line_nonfp" "$backtick_prose_line"

if nonfp_build_output=$("$nonfp_scratch/scripts/build.sh" 2>&1); then
  nonfp_build_exit=0
else
  nonfp_build_exit=$?
fi
assert_eq "0" "$nonfp_build_exit" "build.sh must exit 0 when a rule body contains backtick-quoted marker prose and an unrelated HTML comment (neither is a stray marker) -- output: $nonfp_build_output"

for rel in "output-styles/squirrel-mode.md" "skills/rules/SKILL.md" "targets/codex/AGENTS.md" "targets/cursor/squirrel-mode.mdc"; do
  nonfp_content=$(read_file "$nonfp_scratch/$rel")
  assert_contains "$nonfp_content" "$backtick_prose_line" "$rel must carry the backtick-quoted marker-syntax prose byte-verbatim (rule 5 is targets:all)"
  assert_contains "$nonfp_content" "$unrelated_comment_line" "$rel must carry the unrelated HTML comment byte-verbatim (rule 5 is targets:all)"
done
rm -rf "$nonfp_scratch"

# ==========================================================================
# 16. Signal handling: a terminating signal must stop the build promptly
#     (not merely clean up and then resume on the next statement - the
#     first MAJOR from the S3 review), and the four-mv sequence itself
#     must be uninterruptible by those same signals (fix part (b)),
#     closing the exact corruption the reviewer reproduced: one artifact
#     freshly regenerated, the other three stale, after a SIGTERM landed
#     between the first and second `mv`.
#
#     Made deterministic without leaning on a fixed sleep race against
#     the test's own polling: the injected copy of build.sh creates a
#     marker file the instant it reaches the point under test, then
#     sleeps for $signal_test_pause seconds before continuing. This test
#     polls (bounded, so a bug that prevents the marker from ever
#     appearing fails loudly instead of hanging the suite) and only
#     sends the signal once the marker is observed - the pause only has
#     to outlast "polling interval + signal delivery", never a fixed
#     wall-clock guess about two independently-scheduled processes.
#     Chosen over the static "just assert the trap definitions exist in
#     the source" fallback because this environment supports ordinary
#     job control (&, $!, kill, wait) and a bounded poll loop keeps it
#     deterministic - see the report for why this was judged achievable
#     here rather than falling back to the shape-only assertion.
# ==========================================================================
inject_marker_and_sleep_after() {
  # inject_marker_and_sleep_after <build.sh copy> <line_number> <marker_path> <seconds>
  # Inserts, immediately after <line_number>, a line that creates
  # <marker_path> and then a line that sleeps <seconds> - in that order,
  # so the marker's existence reliably means "execution has reached
  # exactly this point and is now paused there", not merely "is about
  # to reach it". insert_line_after rewrites the file via a plain
  # "awk ... >tmp && mv tmp file", which does not preserve the
  # executable bit (the new tmp file gets umask-default permissions,
  # not build.sh's original mode) - re-set it explicitly afterwards, or
  # the injected copy fails to execute at all with a misleading
  # "Permission denied" instead of ever reaching the point under test.
  file=$1
  line=$2
  marker=$3
  seconds=$4
  insert_line_after "$file" "$line" "sleep $seconds"
  insert_line_after "$file" "$line" "touch '$marker'"
  chmod +x "$file"
}

wait_for_marker() {
  # wait_for_marker <marker_path> - polls once a second, up to 10 times
  # (10s ceiling), returning as soon as the marker exists. Prints "seen"
  # or "TIMEOUT" so the caller asserts on it explicitly instead of
  # silently sending a signal that may arrive before the injected pause
  # is even reached.
  marker=$1
  tries=0
  while [ ! -f "$marker" ] && [ "$tries" -lt 10 ]; do
    sleep 1
    tries=$((tries + 1))
  done
  if [ -f "$marker" ]; then
    printf 'seen\n'
  else
    printf 'TIMEOUT\n'
  fi
}

signal_test_pause=3

# --- 16a: SIGTERM during the WRITE phase (well before any mv) must stop
# the build promptly (exit 143) and leave the working tree untouched --
sig_scratch_a=$(make_build_scratch)
if sig_baseline_a_output=$("$sig_scratch_a/scripts/build.sh" 2>&1); then
  sig_baseline_a_exit=0
else
  sig_baseline_a_exit=$?
fi
assert_eq "0" "$sig_baseline_a_exit" "signal-test fixture 16a: baseline build must succeed -- output: $sig_baseline_a_output"

sig_a_snapshot=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-signal-a-snapshot.XXXXXX")
cleanup_dirs="$cleanup_dirs $sig_a_snapshot"
cp "$sig_scratch_a/output-styles/squirrel-mode.md" "$sig_a_snapshot/output-style.md"
cp "$sig_scratch_a/skills/rules/SKILL.md" "$sig_a_snapshot/skill.md"
cp "$sig_scratch_a/targets/codex/AGENTS.md" "$sig_a_snapshot/codex.md"
cp "$sig_scratch_a/targets/cursor/squirrel-mode.mdc" "$sig_a_snapshot/cursor.mdc"
# B2 (S7 review): the fixture now carries skills/, so build.sh also
# regenerates the eight ported command artifacts - snapshotted here too,
# so the "unchanged after a SIGTERM during the write phase" assertion
# below covers all THIRTEEN artifacts, not just the original four.
cp "$sig_scratch_a/targets/codex/skills/digest/SKILL.md" "$sig_a_snapshot/codex-skill-digest.md"
cp "$sig_scratch_a/targets/codex/skills/plan/SKILL.md" "$sig_a_snapshot/codex-skill-plan.md"
cp "$sig_scratch_a/targets/codex/skills/init/SKILL.md" "$sig_a_snapshot/codex-skill-init.md"
cp "$sig_scratch_a/targets/codex/skills/tune/SKILL.md" "$sig_a_snapshot/codex-skill-tune.md"
cp "$sig_scratch_a/targets/cursor/commands/digest.md" "$sig_a_snapshot/cursor-command-digest.md"
cp "$sig_scratch_a/targets/cursor/commands/plan.md" "$sig_a_snapshot/cursor-command-plan.md"
cp "$sig_scratch_a/targets/cursor/skills/squirrel-digest/SKILL.md" "$sig_a_snapshot/cursor-skill-digest.md"
cp "$sig_scratch_a/targets/cursor/skills/squirrel-plan/SKILL.md" "$sig_a_snapshot/cursor-skill-plan.md"
assert_file_exists "$sig_scratch_a/targets/cursor/hooks/hooks.json" "signal-test fixture 16a: baseline build must produce targets/cursor/hooks/hooks.json"
if [ -f "$sig_scratch_a/targets/cursor/hooks/hooks.json" ]; then
  cp "$sig_scratch_a/targets/cursor/hooks/hooks.json" "$sig_a_snapshot/cursor-hooks.json"
fi

# Change the source so a completed rebuild WOULD change all four
# rules-derived artifacts - this is what makes "unchanged" below
# actually mean "the interruption worked", rather than "there was
# nothing to change anyway" (same reasoning as scenario 14's atomicity
# fixture). The SIGTERM here lands well before ANY mv (see
# line_of_first_write below - it is injected right after the very
# FIRST write, long before the mv phase even begins), so all THIRTEEN
# artifacts, including the nine ported/generated-non-rules ones, must be unchanged - there
# is no mv left to reach any of them.
rule1_first_body_line_sig_a=$(line_of_first_body_line_for_rule 1 "$sig_scratch_a/rules/base-rules.md")
insert_line_after "$sig_scratch_a/rules/base-rules.md" "$rule1_first_body_line_sig_a" "This sentence was added only to force a content change for the signal-handling test."

sig_marker_a="$sig_scratch_a/write-phase-marker"
# shellcheck disable=SC2016 # single-quoted deliberately: this is the
# literal source text to grep for in the scratch build.sh copy, not an
# expression to expand in THIS shell.
line_of_first_write=$(grep -n -F 'write_output_style >"$tmp_output_style"' "$sig_scratch_a/scripts/build.sh" | head -n 1 | cut -d: -f1)
inject_marker_and_sleep_after "$sig_scratch_a/scripts/build.sh" "$line_of_first_write" "$sig_marker_a" "$signal_test_pause"

"$sig_scratch_a/scripts/build.sh" >"$sig_scratch_a/build.out" 2>&1 &
sig_pid_a=$!

sig_a_marker_status=$(wait_for_marker "$sig_marker_a")
assert_eq "seen" "$sig_a_marker_status" "signal test 16a: the write-phase marker must appear before the poll timeout (a fixture problem if not, not a build.sh problem)"

kill -TERM "$sig_pid_a" 2>/dev/null || true
if wait "$sig_pid_a"; then
  sig_a_exit=0
else
  sig_a_exit=$?
fi
assert_eq "143" "$sig_a_exit" "SIGTERM during the write phase must make build.sh exit 143 (128+SIGTERM) promptly, not clean up and resume -- build.sh output: $(read_file "$sig_scratch_a/build.out")"

sig_a_leftover_tmp=$(find "$sig_scratch_a" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$sig_a_leftover_tmp" "no .tmp temp files must remain after a SIGTERM during the write phase"

for pair in "output-style.md:$sig_scratch_a/output-styles/squirrel-mode.md" "skill.md:$sig_scratch_a/skills/rules/SKILL.md" "codex.md:$sig_scratch_a/targets/codex/AGENTS.md" "cursor.mdc:$sig_scratch_a/targets/cursor/squirrel-mode.mdc" "codex-skill-digest.md:$sig_scratch_a/targets/codex/skills/digest/SKILL.md" "codex-skill-plan.md:$sig_scratch_a/targets/codex/skills/plan/SKILL.md" "codex-skill-init.md:$sig_scratch_a/targets/codex/skills/init/SKILL.md" "codex-skill-tune.md:$sig_scratch_a/targets/codex/skills/tune/SKILL.md" "cursor-command-digest.md:$sig_scratch_a/targets/cursor/commands/digest.md" "cursor-command-plan.md:$sig_scratch_a/targets/cursor/commands/plan.md" "cursor-skill-digest.md:$sig_scratch_a/targets/cursor/skills/squirrel-digest/SKILL.md" "cursor-skill-plan.md:$sig_scratch_a/targets/cursor/skills/squirrel-plan/SKILL.md" "cursor-hooks.json:$sig_scratch_a/targets/cursor/hooks/hooks.json"; do
  snap_name=${pair%%:*}
  live_path=${pair#*:}
  if [ ! -f "$sig_a_snapshot/$snap_name" ]; then
    assert_eq "unchanged" "CHANGED: snapshot missing $snap_name" "$live_path must be UNCHANGED after a SIGTERM during the write phase (the mv phase was never reached) - B2, all thirteen artifacts, not just the original four"
    continue
  fi
  if sig_a_diff=$(diff -u "$sig_a_snapshot/$snap_name" "$live_path" 2>&1); then
    sig_a_status=unchanged
  else
    sig_a_status="CHANGED: $sig_a_diff"
  fi
  assert_eq "unchanged" "$sig_a_status" "$live_path must be UNCHANGED after a SIGTERM during the write phase (the mv phase was never reached) - B2, all thirteen artifacts, not just the original four"
done
rm -rf "$sig_scratch_a"

# --- 16b: SIGTERM landing between mv 1 and mv 2 (the reviewer's exact --
# repro) must be IGNORED, not honoured: the thirteen mv's are the one
# window a partial state could reach the working tree, and fix part (b)
# makes that window uninterruptible by HUP/INT/TERM. The build must run
# to completion with all thirteen artifacts consistently updated, not stop
# partway through.
sig_scratch_b=$(make_build_scratch)
if sig_baseline_b_output=$("$sig_scratch_b/scripts/build.sh" 2>&1); then
  sig_baseline_b_exit=0
else
  sig_baseline_b_exit=$?
fi
assert_eq "0" "$sig_baseline_b_exit" "signal-test fixture 16b: baseline build must succeed -- output: $sig_baseline_b_output"

rule1_first_body_line_sig_b=$(line_of_first_body_line_for_rule 1 "$sig_scratch_b/rules/base-rules.md")
sig_b_new_sentence="This sentence was added only to force a content change for the signal-handling test."
insert_line_after "$sig_scratch_b/rules/base-rules.md" "$rule1_first_body_line_sig_b" "$sig_b_new_sentence"

sig_marker_b="$sig_scratch_b/mv-phase-marker"
# shellcheck disable=SC2016 # single-quoted deliberately: this is the
# literal source text to grep for in the scratch build.sh copy, not an
# expression to expand in THIS shell.
line_of_mv1=$(grep -n -F 'mv "$tmp_output_style" "$final_output_style"' "$sig_scratch_b/scripts/build.sh" | head -n 1 | cut -d: -f1)
inject_marker_and_sleep_after "$sig_scratch_b/scripts/build.sh" "$line_of_mv1" "$sig_marker_b" "$signal_test_pause"

"$sig_scratch_b/scripts/build.sh" >"$sig_scratch_b/build.out" 2>&1 &
sig_pid_b=$!

sig_b_marker_status=$(wait_for_marker "$sig_marker_b")
assert_eq "seen" "$sig_b_marker_status" "signal test 16b: the mv-phase marker must appear before the poll timeout (a fixture problem if not, not a build.sh problem)"

kill -TERM "$sig_pid_b" 2>/dev/null || true
if wait "$sig_pid_b"; then
  sig_b_exit=0
else
  sig_b_exit=$?
fi
assert_eq "0" "$sig_b_exit" "a SIGTERM landing between mv 1 and mv 2 must be IGNORED (fix part b) so the build still exits 0, not interrupted mid-sequence -- build.sh output: $(read_file "$sig_scratch_b/build.out")"

sig_b_leftover_tmp=$(find "$sig_scratch_b" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$sig_b_leftover_tmp" "no .tmp temp files must remain after a build that ignored a SIGTERM mid-mv and ran to completion"

for rel in "output-styles/squirrel-mode.md" "skills/rules/SKILL.md" "targets/codex/AGENTS.md" "targets/cursor/squirrel-mode.mdc"; do
  sig_b_content=$(read_file "$sig_scratch_b/$rel")
  assert_contains "$sig_b_content" "$sig_b_new_sentence" "$rel must carry the fresh content after a SIGTERM ignored mid-mv - this is exactly the corruption the reviewer reproduced (one artifact fresh, three stale) under the OLD trap that cleaned up but never called exit"
done

# B2 (S7 review): the eight ported artifacts do not derive from
# rules/base-rules.md, so they carry no equivalent "fresh sentence"
# signal - instead, assert each one's mv ALSO ran to completion despite
# the ignored SIGTERM, by comparing it byte-for-byte against a
# completely separate, uninterrupted reference build from the exact
# same sources. Before B1 removed build.sh's have_<name> guards, a bug
# that silently skipped one of these eight mv's specifically during the
# ignored-signal window would have shown up as a stale (or missing)
# artifact here; this closes that gap.
sig_b_reference=$(make_build_scratch)
if sig_b_reference_output=$("$sig_b_reference/scripts/build.sh" 2>&1); then
  sig_b_reference_exit=0
else
  sig_b_reference_exit=$?
fi
assert_eq "0" "$sig_b_reference_exit" "signal test 16b reference build (uninterrupted, same default sources) must succeed -- output: $sig_b_reference_output"
for rel in "targets/codex/skills/digest/SKILL.md" "targets/codex/skills/plan/SKILL.md" "targets/codex/skills/init/SKILL.md" "targets/codex/skills/tune/SKILL.md" "targets/cursor/commands/digest.md" "targets/cursor/commands/plan.md" "targets/cursor/skills/squirrel-digest/SKILL.md" "targets/cursor/skills/squirrel-plan/SKILL.md" "targets/cursor/hooks/hooks.json"; do
  if [ ! -f "$sig_b_reference/$rel" ] || [ ! -f "$sig_scratch_b/$rel" ]; then
    sig_b_ported_status="DIFFERS: missing $rel in reference or interrupted build"
  elif sig_b_ported_diff=$(diff -u "$sig_b_reference/$rel" "$sig_scratch_b/$rel" 2>&1); then
    sig_b_ported_status=identical
  else
    sig_b_ported_status="DIFFERS: $sig_b_ported_diff"
  fi
  assert_eq "identical" "$sig_b_ported_status" "$rel's mv must have run to completion despite the ignored SIGTERM mid-sequence (B2) - byte-identical to an uninterrupted reference build from the same sources"
done
rm -rf "$sig_b_reference"

rm -rf "$sig_scratch_b"

# ==========================================================================
# Bonus (not one of the 14 numbered scenarios, but stated as a hard
# requirement in the S3 guardrails): generated artifacts must contain no
# non-ASCII byte other than the squirrel emoji (chipmunk + variation
# selector-16) already present in the canonical rules and the frontmatter
# descriptions. Same technique tests/test_base_rules.sh uses for
# rules/base-rules.md itself: strip every occurrence of the exact emoji
# byte sequence, then scan what remains for any byte outside printable
# ASCII (0x20-0x7E).
# ==========================================================================
squirrel_emoji='🐿️'
for label_path in "output style:$output_style_file" "skill:$skill_file" "Codex AGENTS.md:$codex_file" "Cursor .mdc:$cursor_file"; do
  label=${label_path%%:*}
  path=${label_path#*:}
  if [ -f "$path" ]; then
    after_emoji_strip=$(sed "s/$squirrel_emoji//g" "$path")
    non_ascii_lines=$(printf '%s\n' "$after_emoji_strip" | LC_ALL=C grep -n '[^ -~]' || true)
  else
    non_ascii_lines="<file missing: $path>"
  fi
  if [ -n "$non_ascii_lines" ]; then
    non_ascii_status="found non-ASCII outside the permitted squirrel emoji: $non_ascii_lines"
  else
    non_ascii_status="clean"
  fi
  assert_eq "clean" "$non_ascii_status" "$label must contain no non-ASCII byte other than the permitted squirrel emoji"
done

# ==========================================================================
# 17 (F2, S7 review cycle 2 headline finding). check_no_claude_only_syntax's
#     "Claude" vs "Claude Code"/"Claude-Code" guard, exercised through the
#     REAL build.sh code path (the function is a private shell helper with
#     no standalone entry point, so this drives it via a scratch source
#     skill rather than reimplementing its logic here). The full
#     eight-string matrix the review specified, plus "Claudette" as a
#     bonus non-firing case (a word merely STARTING WITH "Claude" followed
#     by a word character must never fire at all):
#       PASS (exit 0): "Claude Code", "Claude Code's", "Claude Code.",
#                       "Claude-Code", "Claudette" (bonus)
#       FAIL (exit 1): "Claude Codex", "Claude", "Claude.", "Claude will"
#     The old bare `sed 's/Claude Code/PLACEHOLDER/'` (no word boundary)
#     let "Claude Codex" ship straight through (the sed's own literal
#     match is a PREFIX of "Claude Codex", so the placeholder swap
#     consumed it before the bare-"Claude" grep ever ran) and wrongly
#     failed "Claude-Code" (the sed never matches a hyphen). Both
#     reproduced against the pre-fix code before this fix landed.
# ==========================================================================
run_f2_matrix_case() {
  # run_f2_matrix_case <string> <expected_exit>: appends a plain content
  # line embedding <string> to the very end of a scratch
  # skills/digest/SKILL.md (past its closing frontmatter "---", so it
  # becomes part of the body) - a line that survives every one of
  # ported_skill_body's literal_replace/delete_exact_line substitutions
  # completely untouched (none of them match this text), so it reaches
  # check_no_claude_only_syntax's scan verbatim, on the REAL,
  # committed source of that check. Runs the scratch build.sh and
  # asserts its exit code against <expected_exit>.
  string=$1
  expected_exit=$2
  scratch=$(make_build_scratch)
  printf 'F2-MATRIX-TEST-LINE: %s\n' "$string" >>"$scratch/skills/digest/SKILL.md"
  if f2_output=$("$scratch/scripts/build.sh" 2>&1); then
    f2_exit=0
  else
    f2_exit=$?
  fi
  assert_eq "$expected_exit" "$f2_exit" "F2 matrix: '$string' embedded in a source skill's body must make build.sh exit $expected_exit -- got $f2_exit, output: $f2_output"
  if [ "$expected_exit" = "1" ]; then
    assert_contains "$f2_output" "$string" "F2 matrix: the failure for '$string' must quote the offending line verbatim (F2's own requirement), not just report a mismatch somewhere"
  fi
  rm -rf "$scratch"
}

run_f2_matrix_case "Claude Code" "0"
run_f2_matrix_case "Claude Code's" "0"
run_f2_matrix_case "Claude Code." "0"
run_f2_matrix_case "Claude-Code" "0"
run_f2_matrix_case "Claudette" "0"
run_f2_matrix_case "Claude Codex" "1"
run_f2_matrix_case "Claude" "1"
run_f2_matrix_case "Claude." "1"
run_f2_matrix_case "Claude will" "1"

# ==========================================================================
# 18 (G4, S7 review cycle 3, mutation discriminator). "Claude Code"
#     wrapped across an ordinary line break must be recognised exactly
#     like the unwrapped phrase - a line-based scan (the pre-G4 code)
#     sees "Claude" alone at the end of one line, matching neither
#     " Code" nor "-Code" because there is no character left on THAT
#     line to check, and wrongly reports a bare-"Claude" leak even
#     though the next line plainly continues "Code...". Two lines are
#     appended to a scratch skills/digest/SKILL.md's body - the first
#     ending in "Claude", the second starting with <second_word> - the
#     same shape an ordinary soft-wrapped paragraph would produce.
# ==========================================================================
run_f2_wrap_matrix_case() {
  # run_f2_wrap_matrix_case <second_word> <expected_exit>: appends
  # "...ends with Claude\n<second_word> continues on the next line.\n"
  # to a scratch skills/digest/SKILL.md, past its closing frontmatter
  # "---" (so it becomes part of the body, surviving every one of
  # ported_skill_body's substitutions untouched, same as
  # run_f2_matrix_case above). Runs the scratch build.sh and asserts
  # its exit code against <expected_exit>.
  second_word=$1
  expected_exit=$2
  scratch=$(make_build_scratch)
  printf 'F2-WRAP-TEST-LINE: ends with Claude\n%s continues on the next line.\n' "$second_word" >>"$scratch/skills/digest/SKILL.md"
  if f2wrap_output=$("$scratch/scripts/build.sh" 2>&1); then
    f2wrap_exit=0
  else
    f2wrap_exit=$?
  fi
  assert_eq "$expected_exit" "$f2wrap_exit" "G4: 'Claude' wrapped across a line break, followed by '$second_word' on the next line, must make build.sh exit $expected_exit -- got $f2wrap_exit, output: $f2wrap_output"
  rm -rf "$scratch"
}

run_f2_wrap_matrix_case "Code" "0"
run_f2_wrap_matrix_case "Codex" "1"

# ==========================================================================
# 19 (G5, S7 review cycle 3). check_no_claude_only_syntax must now also
#    scan the two base-rules-derived target artifacts,
#    targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc - it
#    never reached either one before this fix, so a future
#    rules/base-rules.md edit mentioning "Claude" would have shipped
#    unchecked into both non-Claude-Code hosts. A bare "Claude" appended
#    to the very end of a scratch rules/base-rules.md (landing in rule
#    16's body, targets: all, so it reaches every artifact including
#    the two under test) must fail the scratch build, naming one of
#    those two artifacts as the offender.
# ==========================================================================
g5_scratch=$(make_build_scratch)
printf '\nThis sentence mentions Claude directly and must never reach a non-Claude-Code artifact unscanned.\n' >>"$g5_scratch/rules/base-rules.md"
if g5_output=$("$g5_scratch/scripts/build.sh" 2>&1); then
  g5_exit=0
else
  g5_exit=$?
fi
assert_eq "1" "$g5_exit" "G5: a bare 'Claude' mention added to rules/base-rules.md must fail a scratch build now that the check reaches the base-rules-derived Codex/Cursor artifacts -- output: $g5_output"
case "$g5_output" in
  *"targets/codex/AGENTS.md"* | *"targets/cursor/squirrel-mode.mdc"*)
    g5_named_artifact=yes
    ;;
  *)
    g5_named_artifact=no
    ;;
esac
assert_eq "yes" "$g5_named_artifact" "G5: the failure must name targets/codex/AGENTS.md or targets/cursor/squirrel-mode.mdc as the offending artifact -- output: $g5_output"
rm -rf "$g5_scratch"

# ==========================================================================
# 20 (AC2, S10 review cycle 2). A 'targets: all' rule that names a
#    non-'all' rule BY NUMBER must fail the build - the structural guard
#    that replaces one-off patching. Rules 2 and 7 (both 'targets: all')
#    used to name rule 14 ('targets: claude-code') by number; that
#    specific defect is fixed by rewording those two rules (they now
#    describe the checkpoint-failure report instead of naming rule 14),
#    but this scenario proves the CLASS is closed for any FUTURE rule
#    too. Appended to the very end of a scratch rules/base-rules.md,
#    landing in rule 16's body ('targets: all', the last rule, so there
#    is no next heading to stop the append from landing inside it) - rule
#    16 citing rule 14 ('targets: claude-code') by number must fail,
#    naming both rule numbers and rule 14's actual targets value.
# ==========================================================================
ac2_scratch=$(make_build_scratch)
printf '\nThis sentence deliberately cites rule 14 by number, which is claude-code only, to prove the cross-target-reference guard fires (AC2 test fixture).\n' >>"$ac2_scratch/rules/base-rules.md"
if ac2_output=$("$ac2_scratch/scripts/build.sh" 2>&1); then
  ac2_exit=0
else
  ac2_exit=$?
fi
assert_eq "1" "$ac2_exit" "AC2: a 'targets: all' rule (16) citing rule 14 ('targets: claude-code') by number must fail the build -- output: $ac2_output"
assert_contains "$ac2_output" "rule 16" "AC2: the failure must name the citing rule (16) -- output: $ac2_output"
assert_contains "$ac2_output" "rule 14" "AC2: the failure must name the cited rule (14) -- output: $ac2_output"
assert_contains "$ac2_output" "claude-code" "AC2: the failure must name the cited rule's actual targets value (claude-code), not just say it isn't 'all' -- output: $ac2_output"
rm -rf "$ac2_scratch"

# Sanity companion: the REAL, unmodified rules/base-rules.md (rules 2 and
# 7 no longer name rule 14 by number, per this cycle's own fix) must NOT
# trip this guard - a fresh, unmutated scratch build must still succeed.
ac2_sanity_scratch=$(make_build_scratch)
if ac2_sanity_output=$("$ac2_sanity_scratch/scripts/build.sh" 2>&1); then
  ac2_sanity_exit=0
else
  ac2_sanity_exit=$?
fi
assert_eq "0" "$ac2_sanity_exit" "AC2 sanity: the real, unmodified rules/base-rules.md must build cleanly under the new cross-target-reference guard -- output: $ac2_sanity_output"
rm -rf "$ac2_sanity_scratch"

# Companion: a 'targets: all' rule citing another 'targets: all' rule by
# number (the normal, common case throughout rules/base-rules.md - e.g.
# rule 15 citing rule 2, rule 7 citing rule 15) must NOT fail - proving
# this guard is scoped to the all-cites-non-all case specifically, not
# to numbered rule references in general.
ac2_allall_scratch=$(make_build_scratch)
printf '\nThis sentence cites rule 15 by number, which is also targets: all, and must never fail the build (AC2 sanity fixture).\n' >>"$ac2_allall_scratch/rules/base-rules.md"
if ac2_allall_output=$("$ac2_allall_scratch/scripts/build.sh" 2>&1); then
  ac2_allall_exit=0
else
  ac2_allall_exit=$?
fi
assert_eq "0" "$ac2_allall_exit" "AC2 sanity: a 'targets: all' rule citing ANOTHER 'targets: all' rule by number must not fail the build -- output: $ac2_allall_output"
rm -rf "$ac2_allall_scratch"

# ==========================================================================
# 20b (AD2, S10 review cycle 3 final gate). The cross-target-reference
#    guard above (check_no_all_rule_cites_non_all_rule) used to extract
#    every literal digit token inside a matched "rule(s) ..." span and
#    stop there - which finds the two ENDPOINTS of a range expression
#    ("rules 1 through 12") but never the numbers strictly between them,
#    because "1 through 12" contains exactly two digit tokens ("1" and
#    "12") no matter how many rules the range spans. Proven before this
#    fix: rule 13's real, shipped "This rule takes precedence over rules
#    1 through 12 and rule 16" was checked only for 1, 12, and 16 -
#    flipping any of rules 2-11 to a non-'all' target left a scratch
#    build green. Fixed by additionally expanding "A through B" / "A-B" /
#    "A to B" range pairs within a matched span to every intermediate
#    integer. flip_rule_target below mutates ONE rule's own targets
#    marker line in a scratch copy, by heading number, leaving every
#    other line (including rule 13's citing text) untouched.
# ==========================================================================
flip_rule_target() {
  # flip_rule_target <scratch-rules-file> <rule-num> <new-target-value> -
  # rewrites the FIRST "<!-- targets: ... -->" line following the given
  # rule's own "### <n>. " heading to <new-target-value>, leaving every
  # other line - including any OTHER rule's citation text - byte-for-byte
  # unchanged.
  target_file=$1
  rule_num=$2
  new_value=$3
  awk -v want="$rule_num" -v newval="$new_value" '
    $0 ~ ("^### " want "\\. ") { flip = 1 }
    flip && /^<!-- targets: / { print "<!-- targets: " newval " -->"; flip = 0; next }
    { print }
  ' "$target_file" >"$target_file.flip.tmp"
  mv "$target_file.flip.tmp" "$target_file"
}

# 20b-1: flipping rule 5 - reachable ONLY via rule 13's "1 through 12"
# range, never named directly by any rule - must now fail the build,
# naming both rule 13 (the citing rule) and rule 5 (the cited one),
# without the fail() message claiming rule 5 is spelled out as a literal
# digit (it is not; AD2's fix message distinguishes this case).
ad2_r5_scratch=$(make_build_scratch)
flip_rule_target "$ad2_r5_scratch/rules/base-rules.md" 5 claude-code
if ad2_r5_output=$("$ad2_r5_scratch/scripts/build.sh" 2>&1); then
  ad2_r5_exit=0
else
  ad2_r5_exit=$?
fi
assert_eq "1" "$ad2_r5_exit" "AD2: flipping rule 5 (reachable only via rule 13's 'rules 1 through 12' range) to a non-'all' target must fail the build -- output: $ad2_r5_output"
assert_contains "$ad2_r5_output" "rule 13" "AD2: the failure must name the citing rule (13) -- output: $ad2_r5_output"
assert_contains "$ad2_r5_output" "rule 5" "AD2: the failure must name the cited rule (5) -- output: $ad2_r5_output"
assert_contains "$ad2_r5_output" "range expression includes rule 5" "AD2: the failure message must say rule 5 was reached via the range expression, not claim it is spelled out as a literal digit (it is not) -- output: $ad2_r5_output"
rm -rf "$ad2_r5_scratch"

# 20b-2: a second rule in 2-11, also reachable only via the same range
# (rule 11 - "Use concrete time estimates" - is never named directly by
# any other rule either), independently proves this is not a fix
# narrowly targeted at rule 5's own position in the range.
ad2_r11_scratch=$(make_build_scratch)
flip_rule_target "$ad2_r11_scratch/rules/base-rules.md" 11 claude-code
if ad2_r11_output=$("$ad2_r11_scratch/scripts/build.sh" 2>&1); then
  ad2_r11_exit=0
else
  ad2_r11_exit=$?
fi
assert_eq "1" "$ad2_r11_exit" "AD2: flipping rule 11 (also reachable only via rule 13's range) to a non-'all' target must fail the build -- output: $ad2_r11_output"
assert_contains "$ad2_r11_output" "rule 13" "AD2: the failure must name the citing rule (13) -- output: $ad2_r11_output"
assert_contains "$ad2_r11_output" "rule 11" "AD2: the failure must name the cited rule (11) -- output: $ad2_r11_output"
rm -rf "$ad2_r11_scratch"

# 20b-3: sanity - the real, unmodified rules/base-rules.md must still
# build cleanly under the range-expanding guard (rules 2-11 are all
# legitimately 'targets: all' today, so expanding rule 13's range must
# find nothing wrong).
ad2_sanity_scratch=$(make_build_scratch)
if ad2_sanity_output=$("$ad2_sanity_scratch/scripts/build.sh" 2>&1); then
  ad2_sanity_exit=0
else
  ad2_sanity_exit=$?
fi
assert_eq "0" "$ad2_sanity_exit" "AD2 sanity: the real, unmodified rules/base-rules.md must build cleanly under the range-expanding guard -- output: $ad2_sanity_output"
rm -rf "$ad2_sanity_scratch"

# 20b-4: the "N-M" hyphen form, synthetic (no rule body uses this form
# today) - appended to rule 16's body (the last rule, so there is no
# next heading to stop the append from landing inside it), citing rule
# 14 ('targets: claude-code') via "rules 13-15" rather than by name. 13
# and 15 are both 'targets: all' (both already legitimate, unaffected);
# only the INTERMEDIATE rule 14 is not, so this can only be caught by the
# range expansion, never by the pre-existing plain digit extraction.
ad2_hyphen_scratch=$(make_build_scratch)
printf '\nThis clause also applies to rules 13-15 for completeness (AD2 hyphen-range test fixture).\n' >>"$ad2_hyphen_scratch/rules/base-rules.md"
if ad2_hyphen_output=$("$ad2_hyphen_scratch/scripts/build.sh" 2>&1); then
  ad2_hyphen_exit=0
else
  ad2_hyphen_exit=$?
fi
assert_eq "1" "$ad2_hyphen_exit" "AD2: a synthetic 'rules 13-15' hyphen range whose intermediate rule (14) is not 'targets: all' must fail the build -- output: $ad2_hyphen_output"
assert_contains "$ad2_hyphen_output" "rule 16" "AD2 (hyphen form): the failure must name the citing rule (16) -- output: $ad2_hyphen_output"
assert_contains "$ad2_hyphen_output" "rule 14" "AD2 (hyphen form): the failure must name the cited rule (14) -- output: $ad2_hyphen_output"
rm -rf "$ad2_hyphen_scratch"

# 20b-5: the "N to M" form, synthetic (no rule body uses this form
# today either) - identical shape to 20b-4, proving the range regex's
# "to" alternative works independently of the hyphen one.
ad2_to_scratch=$(make_build_scratch)
printf '\nThis clause also applies to rules 13 to 15 for completeness (AD2 to-range test fixture).\n' >>"$ad2_to_scratch/rules/base-rules.md"
if ad2_to_output=$("$ad2_to_scratch/scripts/build.sh" 2>&1); then
  ad2_to_exit=0
else
  ad2_to_exit=$?
fi
assert_eq "1" "$ad2_to_exit" "AD2: a synthetic 'rules 13 to 15' range whose intermediate rule (14) is not 'targets: all' must fail the build -- output: $ad2_to_output"
assert_contains "$ad2_to_output" "rule 16" "AD2 ('to' form): the failure must name the citing rule (16) -- output: $ad2_to_output"
assert_contains "$ad2_to_output" "rule 14" "AD2 ('to' form): the failure must name the cited rule (14) -- output: $ad2_to_output"
rm -rf "$ad2_to_scratch"

# ==========================================================================
# 21. Tripwire: running this test file must not have written a single
#     byte into the repository working tree.
#
#     This is the counted, always-on form of the "NO SCENARIO IN THIS
#     FILE MAY INVOKE THE REAL REPO'S build.sh" note at the top. It
#     compares the thirteen generated artifacts' cksums against the snapshot
#     taken before scenario 1 ran. Against an already-clean tree it can
#     only pass (build.sh is idempotent, so even the old repo-targeted
#     runs left the bytes unchanged); against a DRIFTED tree it is the
#     assertion that turns "the test run silently repaired the drift" -
#     which is how a real hand-edit stayed reportable exactly once and
#     never again - into a loud, permanent failure.
# ==========================================================================
repo_generated_after=$(repo_generated_snapshot)
assert_eq "$repo_generated_before" "$repo_generated_after" "running tests/test_build.sh must leave every generated artifact in the repository working tree byte-identical (no scenario may build into the real repo)"

assert_report
