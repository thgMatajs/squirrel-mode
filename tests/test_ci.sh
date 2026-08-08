#!/bin/sh
# Coverage for S8: .github/workflows/ci.yml, the CI workflow.
#
# This harness's own hard prerequisites are fixed at jq + shellcheck (see
# .build-checkpoint.md's "Harness capabilities" section) - no YAML parser
# (yq, python-yaml, ...) is guaranteed to be on PATH, and this file must not
# make its own assertion count depend on whether one happens to be
# installed on a given machine. So "valid YAML" here means the mechanically
# checkable structural signals available with plain POSIX sh/grep/awk: the
# file exists, is non-empty, contains no tab character (illegal in YAML
# indentation - a real syntax-validity signal, not a style preference), and
# carries the specific keys/lines a workflow file must have to do what
# PLAN.md Section 5 requires. Full grammar-level YAML parsing is left to
# GitHub's own parser when the workflow actually runs.
#
# What this file checks:
#   1. The workflow file exists, is non-empty, executable-bit NOT required
#      (it is not a .sh - test_repo_invariants.sh's executable-bit sweep
#      only applies to tracked *.sh files).
#   2. No tab character anywhere in the file (YAML indentation must be
#      spaces; a stray tab is a real syntax error, not a style nit).
#   3. Triggers on both push and pull_request.
#   4. runs-on is pinned to a specific, versioned Ubuntu image (not the
#      floating "ubuntu-latest" alias).
#   5. actions/checkout is pinned to a specific major version tag (v4), and
#      no OTHER third-party "uses:" action appears anywhere in the file.
#   6. The workflow actually invokes `sh tests/run.sh`.
#   7. The workflow actually invokes all THREE lines of the drift check:
#      re-running `sh scripts/build.sh`, then `git diff --exit-code`, then
#      `git status --porcelain` (PLAN.md Section 5: "CI fails if generated
#      files drift from rules/base-rules.md"). The third line is the ONLY
#      one of the three that catches a brand-new, previously untracked
#      generated artifact: `git diff --exit-code` alone is silent about a
#      file `git` has never seen before (nothing to diff against), so
#      dropping the porcelain check leaves that specific regression
#      invisible to CI (S8-6 MAJOR: this was reproduced - deleting just
#      that one line left the suite at pass=15 fail=0).
#   8. The workflow installs its two hard prerequisites: jq, and the
#      linter this very check runs (see .build-checkpoint.md's "Harness
#      capabilities" section - these are this test harness's own hard
#      prerequisites, so CI must actually provide them).
#   9. The workflow declares a minimal `permissions:` block pinning
#      `contents: read` (least-privilege default; PLAN.md names no
#      broader permission this workflow needs).
#
# [NEW, T2 MAJOR fix, S8 review cycle 2] Scenarios 1-9 above are TEXT-only: `assert_contains`
# proves a required string exists SOMEWHERE in the file, never WHERE. Reproduced, line by line, in
# a scratch copy: deleting ci.yml's line 43 ("- name: Drift check...") merges the drift-check step
# into the "Run test suite" step via YAML last-key-wins, so `sh tests/run.sh` never executes in
# CI - yet every scenario 1-9 assertion still passes, because the literal text of every required
# command survives somewhere in the file regardless of which step (or no step) it lands in.
# Scenarios 10-15 parse the workflow's STRUCTURE with `awk` instead (still no new dependency):
#  10. Top-level skeleton, parsed positionally: `jobs:` at 0 indent, the job id at 2-space indent,
#      `runs-on:` (pinned) at 4-space indent, `steps:` at 4-space indent.
#  11. The steps list contains EXACTLY the four expected steps, each identified by its own
#      "- uses:"/"- name:" marker, in order - not just that four strings exist somewhere.
#  12. `sh tests/run.sh` appears INSIDE the "Run test suite" step's own run: content, located by
#      that step's name rather than by a fixed index.
#  13. The "Drift check" step's own run: block contains all three drift commands, and is
#      introduced via a `run: |` block-scalar marker.
#  14. The "Install jq and shellcheck" step's own run: block contains the apt-get install command,
#      and is introduced via a `run: |` block-scalar marker.
#  15. Exactly two `run: |` block-scalar markers exist in total (install step, drift step) - the
#      "Run test suite" step is deliberately single-line and must not be counted.
#
# Scenarios 2-9 are checked twice each: once against the real, committed
# workflow file (expecting the requirement to hold), and once against a
# scratch copy deliberately gutted or corrupted in exactly the way that
# requirement exists to catch (expecting the check to report the
# requirement broken) - so a future edit cannot quietly gut CI and keep
# this test file green. Scenarios 10-15 follow the same real-then-fixture
# pattern, using scratch copies with ci.yml's lines 27, 28, 30, 33, 35, 39,
# 41, 43, 45, 46, 47, and 48 each deleted in turn (reusing scenarios 6/7's
# existing fixtures where their content is already exactly the right
# deletion) - the twelve-line matrix S8 review cycle 2 demanded proof
# against.
#
# [NEW, S8 review cycle 3, U1 BLOCKER + U3 MAJOR fixes] Cycle 3's reviewer, confirmed by the tech
# lead, reproduced three more ways to neuter CI that scenarios 1-15 above could not see, plus six
# valid-but-differently-shaped YAML forms that scenarios 10-15 falsely failed on. Two different
# problems, two different fixes:
#
# U1 (three real neutering mutations, now caught):
#  16. No `#` character appears anywhere inside a step's run: content (single-line or block-scalar).
#      GitHub treats everything after an unquoted `#` as a comment, so `run: echo skipped # sh
#      tests/run.sh` never actually runs the suite while the literal substring "sh tests/run.sh"
#      still sits in the file - scenario 6's `assert_contains` and scenario 12's structural check
#      both stayed green against this exact mutation (reproduced: suite stayed at 59/0). Reliably
#      telling a real comment from a `#` inside a quoted string is not feasible in awk, so this is
#      the strict route the tech lead specified instead: no run: content may contain a `#` at all.
#      None of this workflow's three real steps need one.
#  17. No `if:` key appears anywhere in the workflow. An `if: false` on any step (or the job) skips
#      it silently, with no failure - reproduced on the drift-check step, suite stayed at 59/0.
#  18. No `continue-on-error:` key appears anywhere in the workflow. It lets a failing step report
#      success to the job - reproduced on the "Run test suite" step, suite stayed at 59/0.
#  This workflow needs neither `if:` nor `continue-on-error:` anywhere; if a maintainer ever
#  genuinely needs one, they update this assertion deliberately - that is the point of banning both
#  outright rather than trying to allow a "safe" occurrence.
#
# U3 (six false positives on valid YAML; two are fixed, four are declared, none are silently
# tolerated):
#  19. CRLF line endings and trailing whitespace after a structural line (e.g. `run: |` with
#      trailing spaces) are editor/transport artifacts, not style choices, so they are normalised
#      away (CRLF -> LF, trailing horizontal whitespace stripped) before ANY structural or text
#      parsing runs - scenario 2's raw-tab check is the only one deliberately excluded from this
#      normalisation, since stripping trailing whitespace could otherwise hide a real trailing tab
#      from the one check whose entire job is to find tabs. Proven by round-tripping a
#      CRLF-reintroduced and a trailing-whitespace-reintroduced copy of the real file through this
#      file's own normalise-then-parse pipeline and confirming both parse identically to the
#      original.
#  The other four false positives named in cycle 3's review (`shell:` as a step's leading key, a
#  blank line inside a `run: |` block, 4-space indentation, and a quoted `runs-on:` value) are NOT
#  editor artifacts - they are alternative, equally valid YAML shapes this project's awk parser
#  does not attempt to understand, on purpose (re-implementing a real YAML parser is out of scope;
#  see the top-of-file note on why this file never tries). The fix is not to make the parser
#  cleverer: it is to declare ci.yml's layout canonical - 2-space indentation, `- name:`/`- uses:`
#  first in each step, `run: |` for multi-line blocks - state that plainly at the top of ci.yml
#  itself (so a maintainer sees it before editing the file, not only when a test fails), and make
#  every structural assertion below (scenarios 10-15) name `tests/test_ci.sh` and the specific
#  canonical rule it violated in its own failure message, so a maintainer who trips one knows
#  immediately that the fix is either "restore the canonical shape" or "update this test file on
#  purpose" - never "the parser is broken." These four forms are therefore EXPECTED to keep failing
#  against this test file, and that is correct, not a bug.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion.
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

workflow_file="$repo_root/.github/workflows/ci.yml"

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-ci-test.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT

read_file() {
  # read_file <path> - prints file content, or empty string if missing.
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf ''
  fi
}

# normalize_ci_lines <file> — [U3 fix] prints <file>'s content with CRLF line endings collapsed to
# LF (`tr -d '\r'`) and trailing horizontal whitespace (spaces/tabs) stripped from the end of every
# line (`sed 's/[ \t]*$//'`). Both are editor/transport artifacts that can silently break every
# `$`-anchored line-shape regex in parse_ci_structure below (a `run: |` marker with a trailing
# space, or a line ending in \r, no longer matches `/^        run: \|$/` at all) without changing
# what the workflow actually means to GitHub's own YAML parser. This normalisation is deliberately
# narrow: it never touches LEADING whitespace or any character before the end of a line, so it
# cannot mask a real indentation problem or hide a tab anywhere except the exact end of a line. That
# is also why scenario 2's tab check below reads the RAW, un-normalised $workflow_file directly
# instead of this function's output — a stray tab at the end of a line is still exactly the kind of
# real YAML syntax error scenario 2 exists to catch, and must not be silently stripped away by the
# same normalisation that helps every OTHER check tolerate an end-of-line artifact.
normalize_ci_lines() {
  file=$1
  tr -d '\r' <"$file" | sed 's/[ 	]*$//'
}

# ================================================================================================
# T2 fix (S8 review cycle 2 MAJOR). Scenarios 1-9 above are TEXT-only: they can see that a literal
# string like "sh tests/run.sh" appears SOMEWHERE in the file, but not where. Reproduced, line by
# line, in a scratch copy: deleting the "- name:" on ci.yml's line 43 merges the drift-check step
# into the "Run test suite" step via YAML last-key-wins, so `sh tests/run.sh` never executes in
# CI - yet every scenario 1-9 assertion above still passes, because the literal text of every
# required command survives somewhere in the file regardless of which step (or no step at all) it
# ends up folded into.
#
# What follows parses the workflow's STRUCTURE with `awk` (no new dependency - the same constraint
# as the rest of this file, and the reason a real YAML parser is not used is explained at the top
# of this file). It hardcodes the indentation levels THIS workflow's five-level-deep, one-job shape
# uses (0/2/4/6/8/10 spaces) - exactly as much structure as this specific file needs, no more. A
# step index only increments on a NEW "- uses:"/"- name:" marker line, so if a step's own marker
# line is deleted, everything that follows it (shell:, run:, commands) is mis-attributed to the
# PRECEDING step instead of starting a new one - reproducing the *effect* of YAML's last-key-wins
# merge, not its literal parsing mechanics.
# ================================================================================================

# parse_ci_structure <file> — prints the workflow's structurally significant lines as KEY=VALUE
# pairs, one per stdout line, in file order:
#   HAS_JOBS=1                    a line "jobs:" was seen at 0 indent
#   JOB_ID=<name>                 the first job id seen at 2-space indent under jobs:
#   RUNS_ON=<value>               the "runs-on:" value at 4-space indent
#   HAS_STEPS=1                   a line "steps:" was seen at 4-space indent
#   STEP_<n>_MARKER=uses:<value>  the n-th step (0-based, file order) is a "- uses:" step
#   STEP_<n>_MARKER=name:<value>  the n-th step is a "- name:" step
#   STEP_<n>_RUNLINE=<value>      that step's single-line "run: <value>"
#   STEP_<n>_RUNBLOCK=1           that step's "run: |" block-scalar marker was seen
#   STEP_<n>_RUNCMD=<value>       one command line inside that step's "run: |" block (repeats)
parse_ci_structure() {
  file=$1
  awk '
    BEGIN { in_jobs = 0; in_steps = 0; step_idx = -1; run_mode = ""; job_seen = 0 }
    /^jobs:$/ { print "HAS_JOBS=1"; in_jobs = 1; next }
    in_jobs == 1 && job_seen == 0 && /^  [A-Za-z0-9_-]+:$/ {
      job_id = $0
      sub(/^  /, "", job_id)
      sub(/:$/, "", job_id)
      print "JOB_ID=" job_id
      job_seen = 1
      next
    }
    /^    runs-on: / {
      val = $0
      sub(/^    runs-on: /, "", val)
      print "RUNS_ON=" val
      next
    }
    /^    steps:$/ { print "HAS_STEPS=1"; in_steps = 1; next }
    in_steps == 1 && /^      - uses: / {
      step_idx++
      val = $0
      sub(/^      - uses: /, "", val)
      print "STEP_" step_idx "_MARKER=uses:" val
      run_mode = ""
      next
    }
    in_steps == 1 && /^      - name: / {
      step_idx++
      val = $0
      sub(/^      - name: /, "", val)
      print "STEP_" step_idx "_MARKER=name:" val
      run_mode = ""
      next
    }
    in_steps == 1 && step_idx >= 0 && /^        run: \|$/ {
      print "STEP_" step_idx "_RUNBLOCK=1"
      run_mode = "block"
      next
    }
    in_steps == 1 && step_idx >= 0 && /^        run: / {
      val = $0
      sub(/^        run: /, "", val)
      print "STEP_" step_idx "_RUNLINE=" val
      run_mode = ""
      next
    }
    in_steps == 1 && step_idx >= 0 && run_mode == "block" && /^          / {
      val = $0
      sub(/^          /, "", val)
      print "STEP_" step_idx "_RUNCMD=" val
      next
    }
    {
      if (run_mode == "block" && $0 !~ /^          /) { run_mode = "" }
    }
  ' "$file" 2>/dev/null || true
}

# ci_field <blob> <key> — prints the value of the FIRST "KEY=..." line in <blob> whose key equals
# <key> exactly, or empty if none.
ci_field() {
  blob=$1
  key=$2
  printf '%s\n' "$blob" | sed -n "s/^${key}=//p" | head -n 1
}

# ci_step_markers <blob> — prints every "STEP_<n>_MARKER=..." value, one per line, in step-index
# order (file order: step_idx only ever increases).
ci_step_markers() {
  blob=$1
  printf '%s\n' "$blob" | sed -n 's/^STEP_[0-9]*_MARKER=//p'
}

# ci_step_run_text <blob> <idx> — prints every STEP_<idx>_RUNLINE and STEP_<idx>_RUNCMD value,
# concatenated with spaces, for substring checks against required commands. Empty if the step has
# neither (no run: content was ever attributed to it) — including when step <idx> does not exist
# at all, which is exactly what happens when that step's own marker line was deleted.
ci_step_run_text() {
  blob=$1
  idx=$2
  printf '%s\n' "$blob" | sed -n "s/^STEP_${idx}_RUNLINE=//p; s/^STEP_${idx}_RUNCMD=//p" | tr '\n' ' '
}

# ci_step_has_runblock <blob> <idx> — prints "yes"/"no": was a "run: |" block-scalar marker seen
# for step <idx>.
ci_step_has_runblock() {
  blob=$1
  idx=$2
  hit=$(printf '%s\n' "$blob" | grep -c "^STEP_${idx}_RUNBLOCK=1$" 2>/dev/null || true)
  hit=${hit:-0}
  if [ "$hit" -gt 0 ]; then
    echo yes
  else
    echo no
  fi
}

# ci_runblock_total <blob> — prints the total count of "run: |" block-scalar markers seen across
# ALL steps. This workflow uses exactly two (one per multi-line step): the install step and the
# drift-check step. The "Run test suite" step's `run: sh tests/run.sh` is single-line and must NOT
# count here.
ci_runblock_total() {
  blob=$1
  count=$(printf '%s\n' "$blob" | grep -cE '^STEP_[0-9]+_RUNBLOCK=1$' 2>/dev/null || true)
  count=${count:-0}
  echo "$count"
}

# find_step_index_by_marker <blob> <marker-substring> — prints the 0-based step index whose
# MARKER value contains <marker-substring>, or "-1" if no step matches. Used to locate a step by
# NAME rather than assuming a fixed index, because a mutation that deletes an earlier step's
# marker line shifts every later step's index — exactly the corruption this file exists to detect,
# so the lookup itself must not assume indices are stable.
find_step_index_by_marker() {
  blob=$1
  needle=$2
  result=-1
  marker_lines=$(printf '%s\n' "$blob" | grep -E '^STEP_[0-9]+_MARKER=' 2>/dev/null || true)
  if [ -n "$marker_lines" ]; then
    old_ifs=$IFS
    IFS='
'
    for line in $marker_lines; do
      idx=${line#STEP_}
      idx=${idx%%_MARKER=*}
      marker_val=${line#*_MARKER=}
      case "$marker_val" in
        *"$needle"*)
          if [ "$result" = -1 ]; then
            result=$idx
          fi
          ;;
      esac
    done
    IFS=$old_ifs
  fi
  echo "$result"
}

# ================================================================================================
# 1. The workflow file exists and is non-empty.
# ================================================================================================
assert_file_exists "$workflow_file" ".github/workflows/ci.yml must exist"
if [ -s "$workflow_file" ]; then
  workflow_nonempty=yes
else
  workflow_nonempty=no
fi
assert_eq "yes" "$workflow_nonempty" ".github/workflows/ci.yml must be non-empty"

# [U3 fix] Every check from here on (except scenario 2's raw-tab check just below, which must see
# the file exactly as committed) reads this normalised copy instead of $workflow_file directly, so
# a CRLF line ending or trailing whitespace on a structural line can never produce a false failure
# anywhere in this file - not just in the two dedicated proof fixtures in scenario 19 below.
normalized_workflow_file="$scratch_dir/normalized_ci.yml"
normalize_ci_lines "$workflow_file" >"$normalized_workflow_file"

workflow_body=$(read_file "$normalized_workflow_file")

# ================================================================================================
# 2. No tab character anywhere in the file (a real YAML syntax-validity signal, not a style
#    preference: YAML forbids tabs in indentation). Uses a literal tab character via `printf`
#    and `grep -F`, deliberately avoiding the non-POSIX `grep -P`, so this runs identically on
#    GNU and BSD grep. Checked against the real file (expect none), then against a fixture with
#    a tab inserted (expect one).
# ================================================================================================
tab_char=$(printf '\t')
# NOTE: `grep -c` prints "0" (with a NON-zero exit status) on zero matches -
# it does not print nothing. A trailing `|| printf '0'` would therefore
# double up, running the fallback ON TOP of the "0" grep already printed.
# `|| true` alone (no extra printf) is correct here.
real_tab_count=$(grep -cF "$tab_char" "$workflow_file" 2>/dev/null || true)
real_tab_count=${real_tab_count:-0}
assert_eq "0" "$real_tab_count" "no tab character may appear anywhere in .github/workflows/ci.yml"

tab_fixture="$scratch_dir/tab_inserted.yml"
printf '%s\n%sname: gutted\n' "$workflow_body" "$tab_char" >"$tab_fixture"
fixture_tab_count=$(grep -cF "$tab_char" "$tab_fixture" 2>/dev/null || true)
fixture_tab_count=${fixture_tab_count:-0}
assert_eq "1" "$fixture_tab_count" "FAILURE PROOF (scenario 2): a tab character inserted into a scratch copy must be detected"

# ================================================================================================
# 3. Triggers on both push and pull_request. Checked against the real file (expect yes/yes), then
#    against a fixture with the pull_request trigger removed (expect no).
# ================================================================================================
check_triggers_ok() {
  file=$1
  has_on=no
  has_push=no
  has_pr=no
  if grep -qE '^on:' "$file" 2>/dev/null; then has_on=yes; fi
  if grep -qE '^  push:' "$file" 2>/dev/null; then has_push=yes; fi
  if grep -qE '^  pull_request:' "$file" 2>/dev/null; then has_pr=yes; fi
  if [ "$has_on" = yes ] && [ "$has_push" = yes ] && [ "$has_pr" = yes ]; then
    echo yes
  else
    echo no
  fi
}

real_triggers_ok=$(check_triggers_ok "$normalized_workflow_file")
assert_eq "yes" "$real_triggers_ok" "the workflow must declare 'on:' with both 'push:' and 'pull_request:' triggers"

trigger_fixture="$scratch_dir/no_pr_trigger.yml"
awk '!/^  pull_request:$/' "$normalized_workflow_file" >"$trigger_fixture"
fixture_triggers_ok=$(check_triggers_ok "$trigger_fixture")
assert_eq "no" "$fixture_triggers_ok" "FAILURE PROOF (scenario 3): removing the pull_request trigger from a scratch copy must be detected"

# ================================================================================================
# 4. runs-on is pinned to a specific, versioned Ubuntu image, never the floating "ubuntu-latest"
#    alias. Checked against the real file (expect yes), then against a fixture using
#    "ubuntu-latest" instead (expect no).
# ================================================================================================
check_runs_on_pinned() {
  file=$1
  body=$(cat "$file" 2>/dev/null || true)
  case "$body" in
    *"runs-on: ubuntu-latest"*) echo no; return 0 ;;
  esac
  if printf '%s' "$body" | grep -qE 'runs-on: ubuntu-[0-9]+\.[0-9]+'; then
    echo yes
  else
    echo no
  fi
}

real_runs_on_ok=$(check_runs_on_pinned "$normalized_workflow_file")
assert_eq "yes" "$real_runs_on_ok" "runs-on must be pinned to a specific, versioned Ubuntu image (e.g. ubuntu-24.04), not ubuntu-latest"

runs_on_fixture="$scratch_dir/floating_runs_on.yml"
sed -E 's/runs-on: ubuntu-[0-9]+\.[0-9]+/runs-on: ubuntu-latest/' "$normalized_workflow_file" >"$runs_on_fixture"
fixture_runs_on_ok=$(check_runs_on_pinned "$runs_on_fixture")
assert_eq "no" "$fixture_runs_on_ok" "FAILURE PROOF (scenario 4): floating ubuntu-latest in a scratch copy must be detected"

# ================================================================================================
# 5. actions/checkout is pinned to a specific major version tag (v4), and no OTHER third-party
#    "uses:" action appears anywhere in the file (minimal, per PLAN.md Section 5's CI
#    requirement: "no third-party actions beyond actions/checkout"). Checked against the real
#    file (expect yes), then against a fixture with an added third-party action (expect no).
# ================================================================================================
check_actions_minimal_and_pinned() {
  file=$1
  uses_lines=$(grep -oE 'uses: [^ ]+' "$file" 2>/dev/null || true)
  if [ -z "$uses_lines" ]; then
    echo no
    return 0
  fi
  bad=0
  old_ifs=$IFS
  IFS='
'
  for line in $uses_lines; do
    action=${line#uses: }
    case "$action" in
      actions/checkout@v[0-9]*) ;;
      *) bad=$((bad + 1)) ;;
    esac
  done
  IFS=$old_ifs
  if [ "$bad" -eq 0 ]; then
    echo yes
  else
    echo no
  fi
}

real_actions_ok=$(check_actions_minimal_and_pinned "$normalized_workflow_file")
assert_eq "yes" "$real_actions_ok" "the only 'uses:' action in the workflow must be actions/checkout, pinned to a major version tag"

actions_fixture="$scratch_dir/extra_action.yml"
awk '{ print } /uses: actions\/checkout@v[0-9]+/ { print "      - uses: some-third-party/action@v1" }' "$normalized_workflow_file" >"$actions_fixture"
fixture_actions_ok=$(check_actions_minimal_and_pinned "$actions_fixture")
assert_eq "no" "$fixture_actions_ok" "FAILURE PROOF (scenario 5): an added third-party action in a scratch copy must be detected"

# ================================================================================================
# 6. The workflow actually invokes `sh tests/run.sh`. Checked against the real file (expect
#    present), then against a fixture with that line removed (expect absent).
# ================================================================================================
assert_contains "$workflow_body" "sh tests/run.sh" "the workflow must invoke 'sh tests/run.sh'"

run_sh_fixture="$scratch_dir/no_run_sh.yml"
grep -v 'sh tests/run.sh' "$normalized_workflow_file" >"$run_sh_fixture" || true
run_sh_fixture_body=$(read_file "$run_sh_fixture")
assert_not_contains "$run_sh_fixture_body" "sh tests/run.sh" "FAILURE PROOF (scenario 6): removing the 'sh tests/run.sh' invocation from a scratch copy must be detected"

# ================================================================================================
# 7. The workflow actually invokes ALL THREE lines of the drift check: `sh scripts/build.sh`,
#    `git diff --exit-code`, and `git status --porcelain` somewhere after it (PLAN.md Section 5's
#    explicit CI requirement). The third line is pinned separately from the other two (S8-6 MAJOR
#    fix): `git diff --exit-code` alone only catches a TRACKED generated file that changed; it says
#    nothing about a brand-new, previously untracked generated artifact, which is exactly what
#    `git status --porcelain` catches (a non-empty porcelain listing includes untracked files).
#    Checked against the real file (expect yes), then against three fixtures, one with each third
#    of the drift check removed (expect no, for each).
# ================================================================================================
check_drift_check_present() {
  file=$1
  body=$(cat "$file" 2>/dev/null || true)
  has_build=no
  has_diff=no
  has_porcelain=no
  case "$body" in *"sh scripts/build.sh"*) has_build=yes ;; esac
  case "$body" in *"git diff --exit-code"*) has_diff=yes ;; esac
  case "$body" in *'git status --porcelain'*) has_porcelain=yes ;; esac
  if [ "$has_build" = yes ] && [ "$has_diff" = yes ] && [ "$has_porcelain" = yes ]; then
    echo yes
  else
    echo no
  fi
}

real_drift_ok=$(check_drift_check_present "$normalized_workflow_file")
assert_eq "yes" "$real_drift_ok" "the workflow must rebuild generated artifacts (sh scripts/build.sh), diff them (git diff --exit-code), and check for new untracked ones (git status --porcelain) - the full drift check"

drift_fixture_a="$scratch_dir/no_rebuild.yml"
grep -v 'sh scripts/build.sh' "$normalized_workflow_file" >"$drift_fixture_a" || true
fixture_drift_a_ok=$(check_drift_check_present "$drift_fixture_a")
assert_eq "no" "$fixture_drift_a_ok" "FAILURE PROOF (scenario 7a): removing 'sh scripts/build.sh' from a scratch copy must be detected"

drift_fixture_b="$scratch_dir/no_diff.yml"
grep -v 'git diff --exit-code' "$normalized_workflow_file" >"$drift_fixture_b" || true
fixture_drift_b_ok=$(check_drift_check_present "$drift_fixture_b")
assert_eq "no" "$fixture_drift_b_ok" "FAILURE PROOF (scenario 7b): removing 'git diff --exit-code' from a scratch copy must be detected"

drift_fixture_c="$scratch_dir/no_porcelain.yml"
grep -v 'git status --porcelain' "$normalized_workflow_file" >"$drift_fixture_c" || true
fixture_drift_c_ok=$(check_drift_check_present "$drift_fixture_c")
assert_eq "no" "$fixture_drift_c_ok" "FAILURE PROOF (scenario 7c, S8-6): removing 'git status --porcelain' from a scratch copy - the line that catches a brand-new untracked generated artifact - must be detected"

# ================================================================================================
# 8. The workflow installs its two hard prerequisites, jq and shellcheck (see
#    .build-checkpoint.md's "Harness capabilities" section: these are the test suite's own hard
#    prerequisites, so CI must actually provide them, not just claim to run the suite). Checked
#    against the real file (expect present), then against a fixture with that line removed
#    (expect absent).
# ================================================================================================
assert_contains "$workflow_body" "apt-get install -y jq shellcheck" "the workflow must install jq and shellcheck as prerequisites"

prereq_fixture="$scratch_dir/no_prereqs.yml"
grep -v 'apt-get install -y jq shellcheck' "$normalized_workflow_file" >"$prereq_fixture" || true
prereq_fixture_body=$(read_file "$prereq_fixture")
assert_not_contains "$prereq_fixture_body" "apt-get install -y jq shellcheck" "FAILURE PROOF (scenario 8): removing the jq/shellcheck install line from a scratch copy must be detected"

# ================================================================================================
# 9. The workflow declares a minimal `permissions:` block pinning `contents: read`
#    (least-privilege default - PLAN.md names no broader permission this workflow needs. A
#    workflow with no `permissions:` block at all defaults to the repository's configured default,
#    which is not guaranteed to be this restrictive). Checked against the real file (expect both
#    lines present), then against a fixture with both lines removed (expect absent).
# ================================================================================================
assert_contains "$workflow_body" "permissions:" "the workflow must declare a permissions: block"
assert_contains "$workflow_body" "contents: read" "the workflow's permissions block must pin contents: read"

perm_fixture="$scratch_dir/no_permissions.yml"
awk '!/^permissions:$/ && !/^  contents: read$/' "$normalized_workflow_file" >"$perm_fixture"
perm_fixture_body=$(read_file "$perm_fixture")
assert_not_contains "$perm_fixture_body" "contents: read" "FAILURE PROOF (scenario 9): removing the permissions block from a scratch copy must be detected"

# ================================================================================================
# 10. [NEW, T2 MAJOR fix] Structural skeleton, parsed positionally rather than grepped for as bare
#     text anywhere in the file: `jobs:` at 0 indent, a job id at 2-space indent immediately under
#     it, `runs-on:` pinned (not `-latest`) at 4-space indent, and `steps:` at 4-space indent.
#     Checked against the real file (expect all four present/correct), then against three scratch
#     copies with ci.yml's line 27 (`jobs:`), line 28 (`  test:`), and line 30 (`    steps:`) each
#     deleted in turn (expect the corresponding structural marker to go missing).
# ================================================================================================
real_parsed=$(parse_ci_structure "$normalized_workflow_file")
real_has_jobs=$(ci_field "$real_parsed" "HAS_JOBS")
real_job_id=$(ci_field "$real_parsed" "JOB_ID")
real_runs_on=$(ci_field "$real_parsed" "RUNS_ON")
real_has_steps=$(ci_field "$real_parsed" "HAS_STEPS")

# [U3 fix] CANONICAL_SHAPE_NOTE is appended to every structural assertion below that a
# non-canonical-but-otherwise-valid YAML shape (4-space indentation, a quoted runs-on: value,
# shell: reordered ahead of name:/uses:, ...) would trip. It names this file and the specific
# layout ci.yml's own top-of-file comment declares canonical, so a maintainer who hits one of these
# knows immediately whether to restore that layout or to update tests/test_ci.sh's parser on
# purpose — never "the parser is broken."
CANONICAL_SHAPE_NOTE=" [tests/test_ci.sh enforces the canonical layout declared at the top of ci.yml: 2-space indentation, unquoted scalar values, '- name:'/'- uses:' as each step's own first key, 'run: |' for every multi-line command block. Restore that layout, or update tests/test_ci.sh's parser deliberately if the shape is changing on purpose.]"

assert_eq "1" "$real_has_jobs" "the workflow must have a top-level 'jobs:' key.$CANONICAL_SHAPE_NOTE"
assert_eq "test" "$real_job_id" "the workflow's job id must be 'test'.$CANONICAL_SHAPE_NOTE"
assert_eq "ubuntu-24.04" "$real_runs_on" "the job's runs-on value must be the real, pinned Ubuntu image.$CANONICAL_SHAPE_NOTE"
assert_eq "1" "$real_has_steps" "the job must have a 'steps:' key.$CANONICAL_SHAPE_NOTE"

no_jobs_fixture="$scratch_dir/no_jobs_key.yml"
awk '!/^jobs:$/' "$normalized_workflow_file" >"$no_jobs_fixture"
fixture_no_jobs_parsed=$(parse_ci_structure "$no_jobs_fixture")
fixture_no_jobs_has_jobs=$(ci_field "$fixture_no_jobs_parsed" "HAS_JOBS")
assert_eq "" "$fixture_no_jobs_has_jobs" "FAILURE PROOF (ci.yml line 27, 'jobs:' deleted): the parser must no longer see a 'jobs:' key"

no_job_id_fixture="$scratch_dir/no_job_id.yml"
awk '!/^  test:$/' "$normalized_workflow_file" >"$no_job_id_fixture"
fixture_no_job_id_parsed=$(parse_ci_structure "$no_job_id_fixture")
fixture_no_job_id=$(ci_field "$fixture_no_job_id_parsed" "JOB_ID")
assert_eq "" "$fixture_no_job_id" "FAILURE PROOF (ci.yml line 28, '  test:' deleted): the parser must no longer see a job id"

no_steps_fixture="$scratch_dir/no_steps_key.yml"
awk '!/^    steps:$/' "$normalized_workflow_file" >"$no_steps_fixture"
fixture_no_steps_parsed=$(parse_ci_structure "$no_steps_fixture")
fixture_no_steps=$(ci_field "$fixture_no_steps_parsed" "HAS_STEPS")
assert_eq "" "$fixture_no_steps" "FAILURE PROOF (ci.yml line 30, '    steps:' deleted): the parser must no longer see a 'steps:' key"
fixture_no_steps_markers=$(ci_step_markers "$fixture_no_steps_parsed")
assert_eq "" "$fixture_no_steps_markers" "FAILURE PROOF (ci.yml line 30, '    steps:' deleted): with no 'steps:' key, no step markers may be parsed at all"

# ================================================================================================
# 11. [NEW, T2 MAJOR fix] The steps list contains EXACTLY the four expected steps, each identified
#     by its own "- uses:"/"- name:" marker, IN ORDER — not just that four strings exist somewhere
#     in the file. Checked against the real file (expect an exact 4-item match), then against
#     scratch copies with ci.yml's line 33 (Install step's own name), line 39 (Run-suite step's own
#     name), and line 43 (Drift-check step's own name) each deleted in turn — the actual S8-6/T2
#     bug class: YAML last-key-wins folds the orphaned content into the PRECEDING step, so the
#     literal command text can survive elsewhere in the file while the step identity does not.
# ================================================================================================
expected_step_markers="uses:actions/checkout@v4
name:Install jq and shellcheck
name:Run test suite
name:Drift check - rebuild generated artifacts and diff"

real_step_markers=$(ci_step_markers "$real_parsed")
assert_eq "$expected_step_markers" "$real_step_markers" "the workflow must have exactly these four steps, in this order, each identified by its own marker.$CANONICAL_SHAPE_NOTE"

no_install_name_fixture="$scratch_dir/no_install_name.yml"
grep -v 'Install jq and shellcheck' "$normalized_workflow_file" >"$no_install_name_fixture" || true
fixture_no_install_name_parsed=$(parse_ci_structure "$no_install_name_fixture")
fixture_no_install_name_idx=$(find_step_index_by_marker "$fixture_no_install_name_parsed" "Install jq and shellcheck")
assert_eq "-1" "$fixture_no_install_name_idx" "FAILURE PROOF (ci.yml line 33, Install step's '- name:' deleted): no step named 'Install jq and shellcheck' may be found once its own marker line is gone"
fixture_no_install_name_step_count=$(printf '%s\n' "$fixture_no_install_name_parsed" | grep -cE '^STEP_[0-9]+_MARKER=' 2>/dev/null || true)
fixture_no_install_name_step_count=${fixture_no_install_name_step_count:-0}
assert_eq "3" "$fixture_no_install_name_step_count" "FAILURE PROOF (ci.yml line 33 deleted): deleting the Install step's own marker line must collapse the step count from four to three (its shell:/run:/commands fold into the checkout step instead)"

no_suite_name_fixture="$scratch_dir/no_suite_name.yml"
grep -v 'Run test suite' "$normalized_workflow_file" >"$no_suite_name_fixture" || true
fixture_no_suite_name_parsed=$(parse_ci_structure "$no_suite_name_fixture")
fixture_no_suite_name_idx=$(find_step_index_by_marker "$fixture_no_suite_name_parsed" "Run test suite")
assert_eq "-1" "$fixture_no_suite_name_idx" "FAILURE PROOF (ci.yml line 39, Run-suite step's '- name:' deleted): no step named 'Run test suite' may be found once its own marker line is gone"
fixture_no_suite_name_step_count=$(printf '%s\n' "$fixture_no_suite_name_parsed" | grep -cE '^STEP_[0-9]+_MARKER=' 2>/dev/null || true)
fixture_no_suite_name_step_count=${fixture_no_suite_name_step_count:-0}
assert_eq "3" "$fixture_no_suite_name_step_count" "FAILURE PROOF (ci.yml line 39 deleted): deleting the Run-suite step's own marker line must collapse the step count from four to three"

no_drift_name_fixture="$scratch_dir/no_drift_name.yml"
grep -v 'Drift check - rebuild generated artifacts and diff' "$normalized_workflow_file" >"$no_drift_name_fixture" || true
fixture_no_drift_name_parsed=$(parse_ci_structure "$no_drift_name_fixture")
fixture_no_drift_name_idx=$(find_step_index_by_marker "$fixture_no_drift_name_parsed" "Drift check")
assert_eq "-1" "$fixture_no_drift_name_idx" "FAILURE PROOF (ci.yml line 43, Drift-check step's own '- name:' deleted — the exact S8-6 regression): no step named 'Drift check' may be found once its own marker line is gone"
fixture_no_drift_name_step_count=$(printf '%s\n' "$fixture_no_drift_name_parsed" | grep -cE '^STEP_[0-9]+_MARKER=' 2>/dev/null || true)
fixture_no_drift_name_step_count=${fixture_no_drift_name_step_count:-0}
assert_eq "3" "$fixture_no_drift_name_step_count" "FAILURE PROOF (ci.yml line 43 deleted, S8-6): deleting the Drift-check step's own marker line must collapse the step count from four to three — its run: block, including 'sh tests/run.sh', now silently folds into the PRECEDING step and never runs as its own step"

# ================================================================================================
# 12. [NEW, T2 MAJOR fix] `sh tests/run.sh` appears INSIDE the "Run test suite" step's own run:
#     content specifically — not merely somewhere in the file. Checked against the real file
#     (expect present, in that step, at the step index found by NAME), then against a scratch copy
#     with ci.yml's line 41 (`run: sh tests/run.sh`) deleted, reusing scenario 6's existing
#     $run_sh_fixture (its content is already exactly "line 41 removed").
# ================================================================================================
run_suite_idx=$(find_step_index_by_marker "$real_parsed" "Run test suite")
assert_eq "2" "$run_suite_idx" "sanity check: the real 'Run test suite' step must be step index 2 (vacuous-pass guard for scenario 12)"
run_suite_text=$(ci_step_run_text "$real_parsed" "$run_suite_idx")
assert_contains "$run_suite_text" "sh tests/run.sh" "the 'Run test suite' step's own run: content must contain 'sh tests/run.sh'.$CANONICAL_SHAPE_NOTE"

fixture_run_sh_parsed=$(parse_ci_structure "$run_sh_fixture")
fixture_run_sh_idx=$(find_step_index_by_marker "$fixture_run_sh_parsed" "Run test suite")
fixture_run_sh_text=$(ci_step_run_text "$fixture_run_sh_parsed" "$fixture_run_sh_idx")
assert_not_contains "$fixture_run_sh_text" "sh tests/run.sh" "FAILURE PROOF (ci.yml line 41, 'run: sh tests/run.sh' deleted): the 'Run test suite' step must have no run: content left once its 'run:' line is gone"

# ================================================================================================
# 13. [NEW, T2 MAJOR fix] The "Drift check" step's own run: block contains ALL THREE required
#     commands (rebuild, diff, porcelain check), and is introduced via a `run: |` block-scalar
#     marker. Checked against the real file, then against a scratch copy with ci.yml's line 45
#     (the drift step's own `run: |`, the SECOND occurrence of that exact line in the file — the
#     first, line 35, belongs to the install step and must be left alone) deleted, plus reuse of
#     scenarios 7a/7b/7c's existing fixtures for lines 29/30/31 (each already "that one command
#     line removed").
# ================================================================================================
drift_idx=$(find_step_index_by_marker "$real_parsed" "Drift check")
assert_eq "3" "$drift_idx" "sanity check: the real 'Drift check' step must be step index 3 (vacuous-pass guard for scenario 13)"
drift_has_runblock=$(ci_step_has_runblock "$real_parsed" "$drift_idx")
assert_eq "yes" "$drift_has_runblock" "the 'Drift check' step must use a 'run: |' block scalar.$CANONICAL_SHAPE_NOTE"
drift_text=$(ci_step_run_text "$real_parsed" "$drift_idx")
assert_contains "$drift_text" "sh scripts/build.sh" "the 'Drift check' step's own run: block must contain 'sh scripts/build.sh'.$CANONICAL_SHAPE_NOTE"
assert_contains "$drift_text" "git diff --exit-code" "the 'Drift check' step's own run: block must contain 'git diff --exit-code'.$CANONICAL_SHAPE_NOTE"
# shellcheck disable=SC2016 # single-quoted deliberately: the dollar-paren below is literal text
# to match inside the workflow file, not a command substitution.
assert_contains "$drift_text" 'test -z "$(git status --porcelain)"' "the 'Drift check' step's own run: block must contain the git-status-porcelain check.$CANONICAL_SHAPE_NOTE"

no_drift_runblock_fixture="$scratch_dir/no_drift_runblock.yml"
awk '
  /^        run: \|$/ { c++; if (c == 2) next }
  { print }
' "$normalized_workflow_file" >"$no_drift_runblock_fixture"
fixture_no_drift_runblock_parsed=$(parse_ci_structure "$no_drift_runblock_fixture")
fixture_no_drift_runblock_idx=$(find_step_index_by_marker "$fixture_no_drift_runblock_parsed" "Drift check")
fixture_no_drift_runblock_has_block=$(ci_step_has_runblock "$fixture_no_drift_runblock_parsed" "$fixture_no_drift_runblock_idx")
assert_eq "no" "$fixture_no_drift_runblock_has_block" "FAILURE PROOF (ci.yml line 45, drift step's 'run: |' deleted): the 'Drift check' step must no longer show a block-scalar run:"
fixture_no_drift_runblock_text=$(ci_step_run_text "$fixture_no_drift_runblock_parsed" "$fixture_no_drift_runblock_idx")
assert_not_contains "$fixture_no_drift_runblock_text" "sh scripts/build.sh" "FAILURE PROOF (ci.yml line 45 deleted): the 'Drift check' step's run: content must be empty once its block-scalar marker is gone"

fixture_drift_a_parsed=$(parse_ci_structure "$drift_fixture_a")
fixture_drift_a_idx=$(find_step_index_by_marker "$fixture_drift_a_parsed" "Drift check")
fixture_drift_a_text=$(ci_step_run_text "$fixture_drift_a_parsed" "$fixture_drift_a_idx")
assert_not_contains "$fixture_drift_a_text" "sh scripts/build.sh" "FAILURE PROOF (ci.yml line 46, 'sh scripts/build.sh' deleted): the 'Drift check' step's run: block must no longer contain it"

fixture_drift_b_parsed=$(parse_ci_structure "$drift_fixture_b")
fixture_drift_b_idx=$(find_step_index_by_marker "$fixture_drift_b_parsed" "Drift check")
fixture_drift_b_text=$(ci_step_run_text "$fixture_drift_b_parsed" "$fixture_drift_b_idx")
assert_not_contains "$fixture_drift_b_text" "git diff --exit-code" "FAILURE PROOF (ci.yml line 47, 'git diff --exit-code' deleted): the 'Drift check' step's run: block must no longer contain it"

fixture_drift_c_parsed=$(parse_ci_structure "$drift_fixture_c")
fixture_drift_c_idx=$(find_step_index_by_marker "$fixture_drift_c_parsed" "Drift check")
fixture_drift_c_text=$(ci_step_run_text "$fixture_drift_c_parsed" "$fixture_drift_c_idx")
assert_not_contains "$fixture_drift_c_text" "git status --porcelain" "FAILURE PROOF (ci.yml line 48, S8-6, 'git status --porcelain' deleted): the 'Drift check' step's run: block must no longer contain it — this is the specific line that catches a brand-new untracked generated artifact"

# ================================================================================================
# 14. [NEW, T2 MAJOR fix] The "Install jq and shellcheck" step's own run: block contains the
#     prerequisite install command, and is introduced via a `run: |` block-scalar marker. Checked
#     against the real file, then against a scratch copy with ci.yml's line 35 (the install step's
#     own `run: |`, the FIRST occurrence of that exact line — the second, line 45, belongs to the
#     drift step and must be left alone) deleted.
# ================================================================================================
install_idx=$(find_step_index_by_marker "$real_parsed" "Install jq and shellcheck")
assert_eq "1" "$install_idx" "sanity check: the real 'Install jq and shellcheck' step must be step index 1 (vacuous-pass guard for scenario 14)"
install_has_runblock=$(ci_step_has_runblock "$real_parsed" "$install_idx")
assert_eq "yes" "$install_has_runblock" "the 'Install jq and shellcheck' step must use a 'run: |' block scalar.$CANONICAL_SHAPE_NOTE"
install_text=$(ci_step_run_text "$real_parsed" "$install_idx")
assert_contains "$install_text" "apt-get install -y jq shellcheck" "the 'Install jq and shellcheck' step's own run: block must contain the apt-get install command.$CANONICAL_SHAPE_NOTE"

no_install_runblock_fixture="$scratch_dir/no_install_runblock.yml"
awk '
  /^        run: \|$/ { c++; if (c == 1) next }
  { print }
' "$normalized_workflow_file" >"$no_install_runblock_fixture"
fixture_no_install_runblock_parsed=$(parse_ci_structure "$no_install_runblock_fixture")
fixture_no_install_runblock_idx=$(find_step_index_by_marker "$fixture_no_install_runblock_parsed" "Install jq and shellcheck")
fixture_no_install_runblock_has_block=$(ci_step_has_runblock "$fixture_no_install_runblock_parsed" "$fixture_no_install_runblock_idx")
assert_eq "no" "$fixture_no_install_runblock_has_block" "FAILURE PROOF (ci.yml line 35, install step's 'run: |' deleted): the 'Install jq and shellcheck' step must no longer show a block-scalar run:"
fixture_no_install_runblock_text=$(ci_step_run_text "$fixture_no_install_runblock_parsed" "$fixture_no_install_runblock_idx")
assert_not_contains "$fixture_no_install_runblock_text" "apt-get install -y jq shellcheck" "FAILURE PROOF (ci.yml line 35 deleted): the 'Install jq and shellcheck' step's run: content must be empty once its block-scalar marker is gone"

# Sanity check the two "run: |" deletion fixtures above are not accidentally colliding with each
# other (i.e. that deleting the Nth occurrence really did leave the OTHER occurrence intact): the
# install-step fixture (line 35 deleted) must still show the drift step's block scalar, and the
# drift-step fixture (line 45 deleted) must still show the install step's block scalar.
fixture_no_install_runblock_drift_has_block=$(ci_step_has_runblock "$fixture_no_install_runblock_parsed" "$(find_step_index_by_marker "$fixture_no_install_runblock_parsed" "Drift check")")
assert_eq "yes" "$fixture_no_install_runblock_drift_has_block" "deleting the install step's 'run: |' (line 35) must leave the drift step's own 'run: |' (line 45) untouched"
fixture_no_drift_runblock_install_has_block=$(ci_step_has_runblock "$fixture_no_drift_runblock_parsed" "$(find_step_index_by_marker "$fixture_no_drift_runblock_parsed" "Install jq and shellcheck")")
assert_eq "yes" "$fixture_no_drift_runblock_install_has_block" "deleting the drift step's 'run: |' (line 45) must leave the install step's own 'run: |' (line 35) untouched"

# ================================================================================================
# 15. [NEW, T2 MAJOR fix] Both `run: |` block-scalar markers are present where a multi-line block
#     is actually used — exactly two, total, across the whole job (the install step and the drift
#     step; the "Run test suite" step is deliberately single-line and must NOT be counted). Checked
#     against the real file (expect 2), then against the two fixtures from scenarios 13/14 above,
#     each of which deletes exactly one of the two (expect 1 in each case).
# ================================================================================================
real_runblock_total=$(ci_runblock_total "$real_parsed")
assert_eq "2" "$real_runblock_total" "the workflow must have exactly two 'run: |' block-scalar markers (install step and drift step).$CANONICAL_SHAPE_NOTE"

fixture_no_install_runblock_total=$(ci_runblock_total "$fixture_no_install_runblock_parsed")
assert_eq "1" "$fixture_no_install_runblock_total" "FAILURE PROOF (ci.yml line 35 deleted): exactly one 'run: |' block-scalar marker must remain (the drift step's)"

fixture_no_drift_runblock_total=$(ci_runblock_total "$fixture_no_drift_runblock_parsed")
assert_eq "1" "$fixture_no_drift_runblock_total" "FAILURE PROOF (ci.yml line 45 deleted): exactly one 'run: |' block-scalar marker must remain (the install step's)"

# ================================================================================================
# 16. [NEW, S8 review cycle 3, U1 BLOCKER fix] No `#` character appears anywhere inside a step's
#     run: content (single-line RUNLINE or block-scalar RUNCMD), across every step. GitHub treats
#     everything after an unquoted `#` as a YAML comment: `run: echo skipped # sh tests/run.sh`
#     never actually runs the suite, while the substring "sh tests/run.sh" still sits in the line
#     and satisfies scenario 6's assert_contains and scenario 12's structural "contains" check
#     (reproduced by the tech lead: the suite stayed at 59/0 against this exact mutation). Reliably
#     telling a real comment from a `#` inside a quoted string is not feasible in awk, so this takes
#     the strict route instead: no `#` at all, anywhere in run: content. None of this workflow's
#     three real steps need one. Checked against the real file (expect 0 steps with a `#`), then
#     against a fixture with the "Run test suite" step's real command moved into a trailing
#     comment — the exact cycle-3 BLOCKER mutation (expect 1).
# ================================================================================================
check_run_content_has_hash() {
  # check_run_content_has_hash <blob> — prints the count of STEP_*_RUNLINE / STEP_*_RUNCMD values
  # (from parse_ci_structure's output) that contain a literal '#' character anywhere.
  blob=$1
  bad=0
  values=$(printf '%s\n' "$blob" | sed -n 's/^STEP_[0-9]*_RUNLINE=//p; s/^STEP_[0-9]*_RUNCMD=//p')
  if [ -n "$values" ]; then
    old_ifs=$IFS
    IFS='
'
    for v in $values; do
      case "$v" in
        *'#'*) bad=$((bad + 1)) ;;
      esac
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

real_hash_bad=$(check_run_content_has_hash "$real_parsed")
assert_eq "0" "$real_hash_bad" "no step's run: content (single-line or block) may contain a '#' character anywhere - this project takes the strict route rather than trying to distinguish a real YAML comment from a '#' inside a quoted string in awk; none of this workflow's three real steps need one"

hash_fixture="$scratch_dir/hash_hidden_command.yml"
sed 's|run: sh tests/run.sh|run: echo skipped # sh tests/run.sh|' "$normalized_workflow_file" >"$hash_fixture"
fixture_hash_parsed=$(parse_ci_structure "$hash_fixture")
fixture_hash_bad=$(check_run_content_has_hash "$fixture_hash_parsed")
assert_eq "1" "$fixture_hash_bad" "FAILURE PROOF (U1 BLOCKER, scenario 16): moving the real 'sh tests/run.sh' invocation into a trailing YAML comment ('run: echo skipped # sh tests/run.sh') must be caught, even though scenarios 6 and 12 both still see the literal substring"

# Sanity check this exact mutation really would have slipped past scenarios 6 and 12 before this
# fix (confirms scenario 16 adds real coverage, not a duplicate of an existing check).
fixture_hash_body=$(read_file "$hash_fixture")
assert_contains "$fixture_hash_body" "sh tests/run.sh" "sanity check: the comment-hidden mutation must still contain the literal substring 'sh tests/run.sh' textually (proving scenario 6's assert_contains alone cannot catch it)"
fixture_hash_run_suite_idx=$(find_step_index_by_marker "$fixture_hash_parsed" "Run test suite")
fixture_hash_run_suite_text=$(ci_step_run_text "$fixture_hash_parsed" "$fixture_hash_run_suite_idx")
assert_contains "$fixture_hash_run_suite_text" "sh tests/run.sh" "sanity check: the comment-hidden mutation must still pass scenario 12's structural substring check (proving scenario 16 adds coverage scenario 12 alone does not have)"

# ================================================================================================
# 17. [NEW, S8 review cycle 3, U1 BLOCKER fix] No `if:` key appears anywhere in the workflow. An
#     `if: false` on any step (or the job) skips it silently - no failure, no red build - which is
#     the second neutering mutation the tech lead reproduced against the drift-check step (suite
#     stayed at 59/0). This workflow needs no conditional execution anywhere; if a maintainer ever
#     genuinely needs one, they update this assertion deliberately - that is the point of banning
#     the key outright. Checked against the real file (expect 0), then against a fixture with
#     `if: false` inserted on the drift-check step (expect 1).
# ================================================================================================
real_if_hits=$(grep -cE '(^|[[:space:]])if:' "$normalized_workflow_file" 2>/dev/null || true)
real_if_hits=${real_if_hits:-0}
assert_eq "0" "$real_if_hits" "the workflow must not declare an 'if:' key anywhere - an 'if: false' on any step silently skips it with no failure, and this workflow needs no conditional execution"

if_fixture="$scratch_dir/if_false.yml"
awk '{ print } /- name: Drift check/ { print "        if: false" }' "$normalized_workflow_file" >"$if_fixture"
fixture_if_hits=$(grep -cE '(^|[[:space:]])if:' "$if_fixture" 2>/dev/null || true)
fixture_if_hits=${fixture_if_hits:-0}
assert_eq "1" "$fixture_if_hits" "FAILURE PROOF (U1 BLOCKER, scenario 17): an 'if: false' inserted on the drift-check step must be detected"

# ================================================================================================
# 18. [NEW, S8 review cycle 3, U1 BLOCKER fix] No `continue-on-error:` key appears anywhere in the
#     workflow. It lets a failing step report success to the job - the third neutering mutation the
#     tech lead reproduced against the "Run test suite" step (suite stayed at 59/0). This workflow
#     needs no step allowed to fail; if a maintainer ever genuinely needs one, they update this
#     assertion deliberately. Checked against the real file (expect 0), then against a fixture with
#     `continue-on-error: true` inserted on the "Run test suite" step (expect 1).
# ================================================================================================
real_continue_hits=$(grep -cE '(^|[[:space:]])continue-on-error:' "$normalized_workflow_file" 2>/dev/null || true)
real_continue_hits=${real_continue_hits:-0}
assert_eq "0" "$real_continue_hits" "the workflow must not declare a 'continue-on-error:' key anywhere - it lets a failing step report success, and this workflow needs no step allowed to fail"

continue_fixture="$scratch_dir/continue_on_error.yml"
awk '{ print } /- name: Run test suite/ { print "        continue-on-error: true" }' "$normalized_workflow_file" >"$continue_fixture"
fixture_continue_hits=$(grep -cE '(^|[[:space:]])continue-on-error:' "$continue_fixture" 2>/dev/null || true)
fixture_continue_hits=${fixture_continue_hits:-0}
assert_eq "1" "$fixture_continue_hits" "FAILURE PROOF (U1 BLOCKER, scenario 18): a 'continue-on-error: true' inserted on the 'Run test suite' step must be detected"

# ================================================================================================
# 19. [NEW, S8 review cycle 3, U3 MAJOR fix] CRLF line endings and trailing whitespace after a
#     structural line are editor/transport artifacts, not style choices, and must not fail this
#     file (two of the six false positives cycle 3's reviewer reported). Proven by round-tripping a
#     CRLF-reintroduced copy and a trailing-whitespace-reintroduced copy of the real, normalised
#     file through normalize_ci_lines + parse_ci_structure again and confirming both still parse to
#     the exact same structural result as the original.
# ================================================================================================
crlf_raw="$scratch_dir/crlf_raw.yml"
awk '{ printf "%s\r\n", $0 }' "$normalized_workflow_file" >"$crlf_raw"
crlf_normalized="$scratch_dir/crlf_normalized.yml"
normalize_ci_lines "$crlf_raw" >"$crlf_normalized"
crlf_parsed=$(parse_ci_structure "$crlf_normalized")
crlf_runs_on=$(ci_field "$crlf_parsed" "RUNS_ON")
crlf_step_markers=$(ci_step_markers "$crlf_parsed")
crlf_runblock_total=$(ci_runblock_total "$crlf_parsed")
assert_eq "ubuntu-24.04" "$crlf_runs_on" "U3 fix: a CRLF-terminated copy of ci.yml, once normalised by this file's own pipeline, must still parse the pinned runs-on value correctly"
assert_eq "$expected_step_markers" "$crlf_step_markers" "U3 fix: a CRLF-terminated copy of ci.yml, once normalised, must still parse to the exact same four steps in order"
assert_eq "2" "$crlf_runblock_total" "U3 fix: a CRLF-terminated copy of ci.yml, once normalised, must still show both 'run: |' block-scalar markers"

# Vacuous-pass guard: the CRLF really was present before normalisation stripped it.
crlf_cr_count=$(grep -c "$(printf '\r')$" "$crlf_raw" 2>/dev/null || true)
crlf_cr_count=${crlf_cr_count:-0}
if [ "$crlf_cr_count" -gt 0 ]; then crlf_raw_had_cr=yes; else crlf_raw_had_cr=no; fi
assert_eq "yes" "$crlf_raw_had_cr" "vacuous-pass guard: the CRLF fixture must actually contain a carriage return before normalisation, or the proof above proves nothing"

trailing_ws_raw="$scratch_dir/trailing_ws_raw.yml"
sed -E 's/^(    steps:)$/\1   /; s/^(  test:)$/\1  /; s/^(        run: \|)$/\1    /' "$normalized_workflow_file" >"$trailing_ws_raw"
trailing_ws_normalized="$scratch_dir/trailing_ws_normalized.yml"
normalize_ci_lines "$trailing_ws_raw" >"$trailing_ws_normalized"
tws_parsed=$(parse_ci_structure "$trailing_ws_normalized")
tws_has_steps=$(ci_field "$tws_parsed" "HAS_STEPS")
tws_job_id=$(ci_field "$tws_parsed" "JOB_ID")
tws_runblock_total=$(ci_runblock_total "$tws_parsed")
assert_eq "1" "$tws_has_steps" "U3 fix: trailing whitespace after 'steps:' must not break structural parsing once normalised"
assert_eq "test" "$tws_job_id" "U3 fix: trailing whitespace after the job id line must not break structural parsing once normalised"
assert_eq "2" "$tws_runblock_total" "U3 fix: trailing whitespace after a 'run: |' marker must not break block-scalar detection once normalised"

# Vacuous-pass guard: the trailing whitespace really was present before normalisation stripped it.
trailing_ws_raw_body=$(cat "$trailing_ws_raw")
case "$trailing_ws_raw_body" in
  *"    steps:   "*) tws_raw_had_trailing=yes ;;
  *) tws_raw_had_trailing=no ;;
esac
assert_eq "yes" "$tws_raw_had_trailing" "vacuous-pass guard: the trailing-whitespace fixture must actually contain trailing spaces before normalisation, or the proof above proves nothing"

# ================================================================================================
# 20. [NEW, S8 review cycle 3, U3 MAJOR fix] The four false positives that are NOT editor artifacts
#     (a quoted runs-on: value, 4-space indentation, shell: reordered ahead of name:/uses:, a blank
#     line inside a run: | block) are deliberately left UNSUPPORTED by this file's parser - see the
#     top-of-file note on why a real YAML parser is out of scope here. What changed for these four is
#     the FAILURE MESSAGE, not the outcome: it must name tests/test_ci.sh and the canonical rule
#     violated, not print a bare value mismatch. All four are demonstrated below: a quoted
#     runs-on: value and 4-space indentation on the job id line (20a/20b) go red through scenario
#     10's assertions; shell: reordered ahead of the Install step's own name: (20c) goes red
#     through scenario 11's exact-marker-list assertion, because the reordered step's marker line no
#     longer matches the parser's fixed-indentation "- name: "/"- uses: " patterns at all, so the
#     whole step silently disappears from the parsed list rather than merely misparsing; a blank
#     line inside the Drift check step's run: | block (20d) goes red through scenario 13's
#     drift_text assertions, because the parser's own catch-all rule resets run_mode to "" the
#     moment it sees a line that is not indented 10 spaces - including a blank line - so every
#     RUNCMD line after the blank one is silently dropped from that step's run: content. Both are
#     confirmed here, not merely asserted by comment: each fixture is built, parsed, and the
#     resulting failure message is captured and checked for the same CANONICAL_SHAPE_NOTE text
#     scenarios 10-15 already carry.
# ================================================================================================
quoted_runs_on_fixture="$scratch_dir/quoted_runs_on.yml"
sed 's/runs-on: ubuntu-24.04/runs-on: "ubuntu-24.04"/' "$normalized_workflow_file" >"$quoted_runs_on_fixture"
quoted_runs_on_parsed=$(parse_ci_structure "$quoted_runs_on_fixture")
quoted_runs_on_value=$(ci_field "$quoted_runs_on_parsed" "RUNS_ON")
if [ "$quoted_runs_on_value" = "ubuntu-24.04" ]; then quoted_runs_on_matches=yes; else quoted_runs_on_matches=no; fi
assert_eq "no" "$quoted_runs_on_matches" "sanity check: a quoted runs-on: value must NOT parse as the bare pinned value - this is exactly the non-canonical shape scenario 20 documents as intentionally unsupported"

quoted_proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  assert_eq "ubuntu-24.04" "$quoted_runs_on_value" "the job's runs-on value must be the real, pinned Ubuntu image.$CANONICAL_SHAPE_NOTE"
) )
case "$quoted_proof_output" in
  *"tests/test_ci.sh"*"canonical layout"*) quoted_runs_on_message_ok=yes ;;
  *) quoted_runs_on_message_ok=no ;;
esac
assert_eq "yes" "$quoted_runs_on_message_ok" "FAILURE PROOF (U3, scenario 20a): a quoted runs-on: value must still fail, and its failure message must name tests/test_ci.sh and the canonical layout rule"

four_space_fixture="$scratch_dir/four_space_indent.yml"
sed 's/^  test:$/    test:/' "$normalized_workflow_file" >"$four_space_fixture"
four_space_parsed=$(parse_ci_structure "$four_space_fixture")
four_space_job_id=$(ci_field "$four_space_parsed" "JOB_ID")
assert_eq "" "$four_space_job_id" "sanity check: a job id re-indented to 4 spaces must NOT be recognised - this is exactly the non-canonical shape scenario 20 documents as intentionally unsupported"

four_space_proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  assert_eq "test" "$four_space_job_id" "the workflow's job id must be 'test'.$CANONICAL_SHAPE_NOTE"
) )
case "$four_space_proof_output" in
  *"tests/test_ci.sh"*"canonical layout"*) four_space_message_ok=yes ;;
  *) four_space_message_ok=no ;;
esac
assert_eq "yes" "$four_space_message_ok" "FAILURE PROOF (U3, scenario 20b): 4-space indentation on the job id line must still fail, and its failure message must name tests/test_ci.sh and the canonical layout rule"

# 20c: shell: reordered ahead of the Install step's own "- name:" line. Valid YAML (key order in a
# mapping is not significant), but the parser only recognises a step boundary at the fixed
# "      - name: "/"      - uses: " indentation and key position, so the reordered step's own name
# line ("        name: Install jq and shellcheck", 8 spaces, no leading "- ") matches neither
# pattern - the whole step vanishes from ci_step_markers, not merely its shell: key.
shell_reorder_fixture="$scratch_dir/shell_reorder.yml"
awk '
  /^      - name: Install jq and shellcheck$/ {
    print "      - shell: sh"
    print "        name: Install jq and shellcheck"
    getline
    next
  }
  { print }
' "$normalized_workflow_file" >"$shell_reorder_fixture"
shell_reorder_parsed=$(parse_ci_structure "$shell_reorder_fixture")
shell_reorder_markers=$(ci_step_markers "$shell_reorder_parsed")
assert_not_contains "$shell_reorder_markers" "name:Install jq and shellcheck" "sanity check: reordering shell: ahead of the Install step's own name: must drop that step's marker entirely - this is exactly the non-canonical shape scenario 20 documents as intentionally unsupported"

shell_reorder_proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  assert_eq "$expected_step_markers" "$shell_reorder_markers" "the workflow must have exactly these four steps, in this order, each identified by its own marker.$CANONICAL_SHAPE_NOTE"
) )
case "$shell_reorder_proof_output" in
  *"tests/test_ci.sh"*"canonical layout"*) shell_reorder_message_ok=yes ;;
  *) shell_reorder_message_ok=no ;;
esac
assert_eq "yes" "$shell_reorder_message_ok" "FAILURE PROOF (U3, scenario 20c): shell: reordered ahead of a step's own name: must still fail, and its failure message must name tests/test_ci.sh and the canonical layout rule"

# 20d: a blank line inside the Drift check step's own run: | block. Valid YAML (a blank line inside
# a block scalar is just an empty line of content), but the parser's catch-all rule treats any line
# not indented 10 spaces - including a blank one - as the end of the block, so every command after
# the blank line silently drops out of that step's parsed run: content.
blank_line_fixture="$scratch_dir/blank_line_in_runblock.yml"
awk '
  /^          sh scripts\/build\.sh$/ { print; print ""; next }
  { print }
' "$normalized_workflow_file" >"$blank_line_fixture"
blank_line_parsed=$(parse_ci_structure "$blank_line_fixture")
blank_line_drift_idx=$(find_step_index_by_marker "$blank_line_parsed" "Drift check")
blank_line_drift_text=$(ci_step_run_text "$blank_line_parsed" "$blank_line_drift_idx")
assert_contains "$blank_line_drift_text" "sh scripts/build.sh" "sanity check: the content before the injected blank line must still parse"
assert_not_contains "$blank_line_drift_text" "git diff --exit-code" "sanity check: a blank line inside the run: | block must drop everything after it from the parsed run: content - this is exactly the non-canonical shape scenario 20 documents as intentionally unsupported"

blank_line_proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  assert_contains "$blank_line_drift_text" "git diff --exit-code" "the 'Drift check' step's own run: block must contain 'git diff --exit-code'.$CANONICAL_SHAPE_NOTE"
) )
case "$blank_line_proof_output" in
  *"tests/test_ci.sh"*"canonical layout"*) blank_line_message_ok=yes ;;
  *) blank_line_message_ok=no ;;
esac
assert_eq "yes" "$blank_line_message_ok" "FAILURE PROOF (U3, scenario 20d): a blank line inside a run: | block must still fail, and its failure message must name tests/test_ci.sh and the canonical layout rule"

assert_report
