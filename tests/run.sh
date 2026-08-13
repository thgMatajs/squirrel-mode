#!/bin/sh
# Test runner for the squirrel-mode plugin test harness.
#
# Discovers and executes every tests/test_*.sh file (or, if an argument
# is given, just that one file), aggregates the pass/fail counts each
# file reports via `assert_report` (see tests/lib/assert.sh), and exits
# non-zero if any assertion failed OR if zero test files were
# discovered — a harness that quietly reports success after finding
# nothing is worse than no harness.
#
# NOTE on `set -eu`: this script never lets one failing *test file*
# abort the run early. `if output=$(sh "$test_file" 2>&1); then ... else
# ... fi` is exempt from `set -e` (it is the condition of an `if`), so
# every discovered test file always gets a chance to run and be
# counted, even after an earlier one fails.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line. Unset
# unconditionally, before that `cd` runs.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: 'jq' is required to run the test suite but was not found on PATH." >&2
  echo "Install jq (e.g. 'brew install jq' or 'apt-get install jq') and re-run." >&2
  exit 1
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "ERROR: 'shellcheck' is required to run the test suite but was not found on PATH." >&2
  echo "Install shellcheck (e.g. 'brew install shellcheck' or 'apt-get install shellcheck') and re-run." >&2
  exit 1
fi

# python3 + PyYAML is the THIRD hard prerequisite, gated here for the
# same reason jq and shellcheck are, and for one more specific to it.
#
# tests/test_build.sh and tests/test_skills.sh each detect PyYAML at
# runtime and wrap their structural-YAML assertions - roughly a dozen
# between them, the only ones that parse frontmatter as YAML rather than
# pattern-matching it with sed/awk - in `if [ "$have_yaml_parser" =
# "yes" ]`. Nothing asserted the parser was found, nothing warned, and
# nothing pinned an expected assertion count, so on a machine without
# PyYAML those assertions simply did not exist: the files still printed
# "SUMMARY pass=N fail=0" and the run was still green. A skipped
# assertion that is indistinguishable from a passing one is worse than
# no assertion, because the green tells you something it did not check.
#
# Made a hard prerequisite rather than a warning: the alternative -
# tolerating its absence - is exactly the state that produced a green
# run nobody could interpret.
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: 'python3' is required to run the test suite but was not found on PATH." >&2
  echo "It provides the structural YAML frontmatter checks in tests/test_build.sh and tests/test_skills.sh." >&2
  echo "Install python3 (e.g. 'brew install python3' or 'apt-get install python3') and re-run." >&2
  exit 1
fi

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "ERROR: the PyYAML module is required to run the test suite but 'python3 -c \"import yaml\"' failed." >&2
  echo "It provides the structural YAML frontmatter checks in tests/test_build.sh and tests/test_skills.sh," >&2
  echo "which are SILENTLY SKIPPED without it - a green run would not mean they passed." >&2
  echo "Install PyYAML (e.g. 'pip3 install pyyaml' or 'apt-get install python3-yaml') and re-run." >&2
  exit 1
fi

target=${1:-}

if [ -n "$target" ]; then
  if [ -f "$target" ]; then
    set -- "$target"
  elif [ -f "$script_dir/$target" ]; then
    set -- "$script_dir/$target"
  else
    echo "ERROR: test file not found: $target" >&2
    exit 1
  fi
else
  set --
  for f in "$script_dir"/test_*.sh; do
    if [ -f "$f" ]; then
      set -- "$@" "$f"
    fi
  done
fi

if [ $# -eq 0 ]; then
  echo "ERROR: no test files discovered (looked for $script_dir/test_*.sh)." >&2
  echo "A harness that finds zero tests must not report success." >&2
  exit 1
fi

total_pass=0
total_fail=0
files_run=0
files_failed=0

for test_file in "$@"; do
  files_run=$((files_run + 1))
  echo "==== $test_file ===="
  if output=$(sh "$test_file" 2>&1); then
    file_exit=0
  else
    file_exit=$?
  fi
  printf '%s\n' "$output"

  summary_line=$(printf '%s\n' "$output" | grep '^SUMMARY ' || true)
  if [ -z "$summary_line" ]; then
    echo "ERROR: $test_file produced no SUMMARY line (did it call assert_report?)." >&2
    file_pass=0
    file_fail=1
  else
    file_pass=$(printf '%s\n' "$summary_line" | sed -n 's/^SUMMARY pass=\([0-9][0-9]*\) fail=\([0-9][0-9]*\)$/\1/p')
    file_fail=$(printf '%s\n' "$summary_line" | sed -n 's/^SUMMARY pass=\([0-9][0-9]*\) fail=\([0-9][0-9]*\)$/\2/p')
    file_pass=${file_pass:-0}
    file_fail=${file_fail:-0}
  fi

  total_pass=$((total_pass + file_pass))
  total_fail=$((total_fail + file_fail))
  if [ "$file_fail" -gt 0 ] || [ "$file_exit" -ne 0 ]; then
    files_failed=$((files_failed + 1))
  fi

  echo "---- $test_file: pass=$file_pass fail=$file_fail (exit=$file_exit) ----"
  echo ""
done

echo "===================================="
echo "TOTAL: files_run=$files_run pass=$total_pass fail=$total_fail files_failed=$files_failed"

if [ "$total_fail" -gt 0 ] || [ "$files_run" -eq 0 ]; then
  exit 1
fi

exit 0
