#!/bin/sh
# Shell-dialect gate for the squirrel-mode test harness.
#
# tests/test_repo_invariants.sh checks that every tracked .sh file is
# executable and every tracked .json file is valid JSON, but neither check
# says anything about shell DIALECT. A script using `[[ ]]`, `local`,
# `source`, an array, or `${var,,}` would pass both of those checks while
# violating .build-checkpoint.md invariant 5 ("Shell scripts are POSIX sh,
# pass shellcheck"). This file closes that gap by running `shellcheck
# --shell=sh` over every tracked .sh file, discovered the same glob-free way
# test_repo_invariants.sh discovers files: `git ls-files`. No path or
# directory name is hardcoded, so a script added by any later step (S4's
# hook scripts, S5's skills, S7's targets/*/install.sh) is picked up
# automatically with no edit to this file. `tests/` itself is NOT excluded:
# the test files are shell too and are held to the same standard.
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

# Treat the shellcheck binary as a hard prerequisite, the same way
# tests/run.sh treats jq (and now also checks for the shellcheck binary
# up-front, before any test file runs). This repo is largely shell; a
# contributor without it installed must be told plainly, not silently
# handed a weaker gate that only checks executable bits and JSON validity.
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "ERROR: 'shellcheck' is required to run the test suite but was not found on PATH." >&2
  echo "Install shellcheck (e.g. 'brew install shellcheck' or 'apt-get install shellcheck') and re-run." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: 'git' is required for the shell-dialect check but was not found on PATH." >&2
  exit 1
fi

# Discover every tracked .sh file via `git ls-files` — glob-free, no
# hardcoded paths or directory names. Collected into the positional
# parameters (not a space-joined string variable) so the later
# `shellcheck ... "$@"` call needs no unquoted expansion of a variable,
# which would itself be a dialect wart this very file would then fail its
# own check for.
set --
sh_file_count=0
for f in $(git -C "$repo_root" ls-files); do
  case "$f" in
    *.sh)
      set -- "$@" "$f"
      sh_file_count=$((sh_file_count + 1))
      ;;
  esac
done

# A dialect test that discovers zero scripts and reports success is the
# vacuous-pass anti-pattern: assert the scanned set is non-empty BEFORE
# trusting a clean shellcheck run (or a clean "nothing to check") to mean
# anything.
if [ "$sh_file_count" -gt 0 ]; then
  nonempty=yes
else
  nonempty=no
fi
assert_eq "yes" "$nonempty" "git ls-files must discover at least one tracked .sh file to scan (vacuous-pass guard)"

if [ "$sh_file_count" -gt 0 ]; then
  # Run from repo_root: .shellcheckrc (source-path=SCRIPTDIR) lives there,
  # and git ls-files already returned repo-root-relative paths, so this is
  # the working directory that lets shellcheck resolve both correctly.
  if shellcheck_output=$(cd "$repo_root" && shellcheck --shell=sh "$@" 2>&1); then
    shellcheck_exit=0
  else
    shellcheck_exit=$?
  fi
  if [ "$shellcheck_exit" -ne 0 ]; then
    # Surfaced verbatim so the developer sees exactly which file and which
    # SC code failed, not just a bare non-zero exit status.
    echo "---- shellcheck --shell=sh output ----" >&2
    printf '%s\n' "$shellcheck_output" >&2
    echo "---------------------------------------" >&2
  fi
  assert_eq "0" "$shellcheck_exit" "shellcheck --shell=sh must exit 0 across all $sh_file_count tracked .sh files"
fi

# --- CDPATH hardening (A10, S7 review) --------------------------------
#
# Any tracked .sh file that resolves its own location via `cd` inside a
# command substitution (the "script_dir=$(cd "$(dirname "$0")" && pwd)"
# idiom used throughout this repo) is vulnerable to a CDPATH entry
# containing "." - `cd` then ECHOES the resolved path to stdout, in
# addition to changing directory, corrupting the command substitution
# with an extra line before the script ever gets past resolving its own
# paths (a reviewer-verified failure: with CDPATH=. set, the
# pre-S7-fix installer died with a raw "No such file or directory"
# before argument parsing even ran). Every such file must `unset
# CDPATH` at its own top, before that idiom runs - never rely on the
# invoking shell's environment being clean. This is a STATIC check (it
# greps source text, not runtime behaviour); tests/test_targets.sh and
# tests/test_build.sh separately prove the fix works at runtime, with
# CDPATH actually set, against the two installers and scripts/build.sh.
cdpath_violation=""
for f in "$@"; do
  path="$repo_root/$f"
  [ -f "$path" ] || continue
  if grep -qE '=\$\(cd ' "$path" 2>/dev/null; then
    if ! grep -q 'unset CDPATH' "$path" 2>/dev/null; then
      cdpath_violation="$cdpath_violation $f"
    fi
  fi
done
assert_eq "" "$cdpath_violation" "every tracked .sh file that resolves its own path via \"cd\" inside a command substitution must \"unset CDPATH\" at its own top (missing in: $cdpath_violation)"

# --- The scratch-leak lock may not walk the whole of $TMPDIR ----------
#
# A SHAPE GUARD, in the sense scenario 14 of tests/test_hoard.sh means
# it: what it forbids is invisible to every other test in this suite,
# because the forbidden form returns exactly the same answers as the one
# it replaces. It only costs.
#
# tests/lib/assert.sh's scratch_snapshot and assert_no_scratch_leak used
# to expand EVERY entry $TMPDIR holds and sort out the interesting names
# afterwards, with the snapshot built one append at a time into a shell
# string - and appending to a string in macOS's /bin/sh (bash 3.2)
# copies the whole string, so the pair cost O(n^2) in what the
# DIRECTORY holds rather than in what the suite creates. Measured in one
# shell on entries the suite never made: 1.81 s at 2000, 27.58 s at
# 8000, 174.12 s at 20000, against a real developer $TMPDIR holding
# 176299 - a suite that looks hung, inside the guard written to catch
# scratch mess. scripts/hoard-search.sh documents the identical
# mechanism under "THE PER-FILE FORM IS QUADRATIC"; this is the same bug
# in a second place, and the assertions below are what stop a third.
#
# Scoped to tests/lib/assert.sh, exactly as scenario 14 is scoped to
# scripts/hoard-search.sh, and for a reason worth writing down: this
# file is itself one of the tracked .sh files scanned above, so a needle
# applied to ALL of them would match the needle's own definition here
# and the guard could never go green. The comment in assert.sh has the
# mirror-image duty - it explains the trap WITHOUT spelling the pattern,
# so it cannot satisfy the very needles that judge it.
assert_lib="$repo_root/tests/lib/assert.sh"
assert_file_exists "$assert_lib" "the scratch-leak lock must live at tests/lib/assert.sh for the shape guard below to have a subject"

# `|| true` on the ASSIGNMENT, never a fallback inside the substitution:
# `grep -c` prints its count and THEN exits 1 when that count is zero,
# so a fallback inside would append a second "0" and the wide-form
# assertion would read "0\n0" - failing exactly when the file is right.
# shellcheck disable=SC2016 # literal SOURCE TEXT of the file under scan: '${TMPDIR:-/tmp}' is what is being searched for, not an expansion this file wants evaluated.
tmpdir_narrow_lines=$(grep -cF '"${TMPDIR:-/tmp}"/squirrel-*' "$assert_lib" 2>/dev/null) || true
assert_eq "2" "$tmpdir_narrow_lines" "both loops in tests/lib/assert.sh must select this suite's scratch with the PREFIX IN THE PATTERN - the snapshot's and the assertion's - so the shell expands what the suite created instead of everything the user's \$TMPDIR happens to hold"
# shellcheck disable=SC2016 # literal source text, see above.
tmpdir_wide_lines=$(grep -cF '"${TMPDIR:-/tmp}"/*' "$assert_lib" 2>/dev/null) || true
assert_eq "0" "$tmpdir_wide_lines" "and NEITHER may expand \$TMPDIR whole: that form bills the leak lock for the user's junk drawer, quadratically. One run of tests/test_skills.sh against a \$TMPDIR holding 20000 foreign entries took 383.96 s that way and 1.08 s narrowed, for the same 307 assertions and the same verdict - and the machine this was written on has 176299 entries in \$TMPDIR"

snapshot_assignments() {
  # snapshot_assignments <file> - how many lines of that file's
  # scratch_snapshot body assign to a shell variable. Zero is the
  # contract: the function prints each path straight to its own stdout,
  # which every caller already captures, so no list is built up in
  # memory and the copy-per-append cannot come back on the one input
  # that can still grow - the suite's own leftover scratch. Counted from
  # the function's body rather than pinned to a variable NAME, which a
  # rename would walk straight past.
  SA_SRC=$1 python3 -c '
import io
import os
import re
lines = io.open(os.environ["SA_SRC"], encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("scratch_snapshot() {"))
end = next(i for i, l in enumerate(lines[start:], start) if l == "}")
print(sum(1 for l in lines[start + 1:end] if re.match(r"\s*[A-Za-z_][A-Za-z_0-9]*=", l)))
'
}
assert_eq "0" "$(snapshot_assignments "$assert_lib")" "scratch_snapshot must ASSIGN NOTHING - it prints. Building the answer in a variable is the copy-per-append form again, on the one list that can still grow here: the suite's own leftovers, 443 paths from a single run before the leak lock existed. Timed on 20000 planted \`squirrel-\` entries, both forms printing the identical 3260001 characters - 0.80 s streamed, 392.47 s accumulated"

# --- FAILURE PROOF: the wide walk, restored, and what it does not break
#
# Generated from the file as it stands now, not from the copy the defect
# was found in: a proof that mutates yesterday's text proves something
# about yesterday. The controls come first - a replacement that matched
# nothing would leave a byte-identical copy that the assertions above
# correctly pass, and this proof would then report clean while showing
# the opposite of what it claims.
dialect_scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-dialect-test.XXXXXX")
trap 'rm -rf "$dialect_scratch"' EXIT
dialect_mutant="$dialect_scratch/assert-wide.sh"
dialect_revert="$dialect_scratch/revert.py"
# Quoted heredoc: every dollar sign below is source text being searched
# for and written out, never something this shell may expand.
cat >"$dialect_revert" <<'PY'
import sys
src = open(sys.argv[1]).read()
pairs = [
    ("  printf '|'\n"
     '  for ss_e in "${TMPDIR:-/tmp}"/squirrel-*; do\n'
     '    [ -e "$ss_e" ] || continue\n'
     "    printf '%s|' \"$ss_e\"\n"
     '  done\n',
     '  ss_out="|"\n'
     '  for ss_e in "${TMPDIR:-/tmp}"/*; do\n'
     '    [ -e "$ss_e" ] || continue\n'
     '    ss_out="$ss_out$ss_e|"\n'
     '  done\n'
     "  printf '%s' \"$ss_out\"\n"),
    ('  for ansl_e in "${TMPDIR:-/tmp}"/squirrel-*; do\n'
     '    [ -e "$ansl_e" ] || continue\n',
     '  for ansl_e in "${TMPDIR:-/tmp}"/*; do\n'
     '    [ -e "$ansl_e" ] || continue\n'
     '    case "${ansl_e##*/}" in\n'
     '      squirrel-*)\n'
     '        ;;\n'
     '      *)\n'
     '        continue\n'
     '        ;;\n'
     '    esac\n'),
]
applied = 0
for old, new in pairs:
    if old in src:
        src = src.replace(old, new, 1)
        applied += 1
open(sys.argv[2], "w").write(src)
sys.stdout.write(str(applied))
PY
dialect_applied=$(python3 "$dialect_revert" "$assert_lib" "$dialect_mutant")
assert_eq "2" "$dialect_applied" "FAILURE PROOF, control: the revert must put the wide walk back in BOTH helpers - fewer, and the mutant is not the regression this proof claims to reproduce"
if cmp -s "$assert_lib" "$dialect_mutant"; then dialect_differs=no; else dialect_differs=yes; fi
assert_eq "yes" "$dialect_differs" "FAILURE PROOF, control: the revert must genuinely change tests/lib/assert.sh"

# Counted the same way the assertions above count, against the same
# needles, so the proof exercises their mechanism and not a lookalike.
# shellcheck disable=SC2016 # literal source text, see above.
mutant_narrow_lines=$(grep -cF '"${TMPDIR:-/tmp}"/squirrel-*' "$dialect_mutant" 2>/dev/null) || true
assert_eq "0" "$mutant_narrow_lines" "FAILURE PROOF: the reverted copy must lose both narrowed patterns - 0 where the real file has 2"
# shellcheck disable=SC2016 # literal source text, see above.
mutant_wide_lines=$(grep -cF '"${TMPDIR:-/tmp}"/*' "$dialect_mutant" 2>/dev/null) || true
assert_eq "2" "$mutant_wide_lines" "FAILURE PROOF: and must carry the wide walk the assertion above forbids - 2 where the real file has 0"
assert_eq "2" "$(snapshot_assignments "$dialect_mutant")" "FAILURE PROOF: and its scratch_snapshot must build its answer in a variable again - the copy-per-append the count of 0 above forbids"

# THE HALF THAT MAKES THIS GUARD NECESSARY, and the same half scenario
# 14b of tests/test_hoard.sh turns on: the regression is
# behaviour-preserving. The probe below drives the leak lock end to end
# against whichever library it is handed - a `squirrel-` entry that was
# already there, one the trap is scheduled to remove, a foreign file
# dropped in mid-run by nobody's test, and a genuinely leaked one - and
# both libraries must answer IDENTICALLY, in the failing case and the
# clean case. No output comparison anywhere in this suite could tell
# them apart, which is why the pins above are the only thing standing
# between the leak lock and its quadratic form.
dialect_probe="$dialect_scratch/probe.sh"
cat >"$dialect_probe" <<'PROBE'
#!/bin/sh
# probe.sh <assert.sh to test> <fixture TMPDIR> <plant a leak: yes|no>
#
# Prints that library's own verdict on a $TMPDIR of its own. Run as a
# separate `sh` process on purpose: assert_no_scratch_leak is asked here
# to FAIL, and a failure counted in the caller's process would turn the
# calling test file red for doing its job.
set -eu
. "$1"
TMPDIR=$2
export TMPDIR
mkdir -p "$TMPDIR/squirrel-from-an-earlier-run"
probe_before=$(scratch_snapshot)
mkdir -p "$TMPDIR/squirrel-scheduled"
: >"$TMPDIR/a-stranger-process-file"
if [ "$3" = yes ]; then
  mkdir -p "$TMPDIR/squirrel-leaked"
fi
assert_no_scratch_leak "$probe_before" "$TMPDIR/squirrel-scheduled" "PROBE"
assert_report
PROBE

probe_run() {
  # probe_run <library> <plant a leak> - one fixture path, rebuilt from
  # empty for every run, so two verdicts can be compared as strings: a
  # per-run directory name would print into the failure message and make
  # two identical answers look different.
  pr_fixture="$dialect_scratch/probe-fixture"
  rm -rf "$pr_fixture"
  mkdir -p "$pr_fixture"
  sh "$dialect_probe" "$1" "$pr_fixture" "$2" 2>&1 || true
}

probe_real_leak=$(probe_run "$assert_lib" yes)
probe_mutant_leak=$(probe_run "$dialect_mutant" yes)
probe_real_clean=$(probe_run "$assert_lib" no)
probe_mutant_clean=$(probe_run "$dialect_mutant" no)

assert_contains "$probe_real_leak" "FAIL: PROBE" "the leak lock must still go RED on a leaked \`squirrel-\` directory - the narrowing is a change of what the shell expands, not of what the assertion judges"
assert_contains "$probe_real_leak" "squirrel-leaked" "and must NAME the leaked path, which is the whole reason it reports presence rather than a count"
assert_not_contains "$probe_real_leak" "a-stranger-process-file" "and must still ignore a file some other process dropped into \$TMPDIR while the run was in progress - the narrowing exists to keep this true"
assert_not_contains "$probe_real_leak" "squirrel-from-an-earlier-run" "and must still subtract \`squirrel-\` residue the snapshot saw before the run, which is also the non-vacuity check on the snapshot: a snapshot that recorded nothing would flag this one"
assert_not_contains "$probe_real_leak" "squirrel-scheduled" "and must still pass a path the trap is scheduled to remove"
assert_eq "SUMMARY pass=1 fail=0" "$probe_real_clean" "with no leak planted, the same probe must come back clean - a lock that fails either way proves nothing when it fails"
assert_eq "$probe_mutant_leak" "$probe_real_leak" "FAILURE PROOF, the half that makes the shape guard necessary: the wide-walk mutant must return an IDENTICAL verdict on the leaking fixture. The regression changes cost and nothing else, so no behavioural test in this suite could ever catch it"
assert_eq "$probe_mutant_clean" "$probe_real_clean" "FAILURE PROOF: and an identical verdict on the clean fixture too, so the equality above is not one lucky case"

assert_report
