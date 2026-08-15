#!/bin/sh
# POSIX sh assertion library for the squirrel-mode test harness.
#
# This file is SOURCED (not executed) by tests/test_*.sh files, e.g.:
#   . "$(dirname "$0")/lib/assert.sh"
#
# NOTE on `set -eu`: every tests/test_*.sh file that sources this library
# also runs under `set -e`. If an assert_* helper below returned a
# non-zero exit status on a failed assertion, `set -e` would abort the
# whole test file on the FIRST failure and hide every assertion after
# it — exactly the "abrupt exit that hides the remaining tests" this
# harness must avoid. Every assert_* function therefore always finishes
# with an explicit `return 0`, regardless of whether the thing it
# checked passed or failed. Pass/fail is tracked instead in the
# ASSERT_PASS_COUNT / ASSERT_FAIL_COUNT counters, and a failure prints
# its message, expected value, and actual value immediately so it is
# unmistakable in the output. The only place a failure becomes a
# non-zero exit code is assert_report, called once at the very end of a
# test file, after every assertion has had its chance to run.
set -eu

ASSERT_PASS_COUNT=${ASSERT_PASS_COUNT:-0}
ASSERT_FAIL_COUNT=${ASSERT_FAIL_COUNT:-0}

_assert_pass() {
  ASSERT_PASS_COUNT=$((ASSERT_PASS_COUNT + 1))
  return 0
}

_assert_fail() {
  # $1 = message, $2 = expected, $3 = actual
  ASSERT_FAIL_COUNT=$((ASSERT_FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
  printf '  expected: %s\n' "$2"
  printf '  actual:   %s\n' "$3"
  return 0
}

assert_eq() {
  # assert_eq <expected> <actual> <message>
  expected=$1
  actual=$2
  message=$3
  if [ "$expected" = "$actual" ]; then
    _assert_pass
  else
    _assert_fail "$message" "$expected" "$actual"
  fi
  return 0
}

assert_contains() {
  # assert_contains <haystack> <needle> <message>
  #
  # An empty needle is rejected explicitly rather than left to the glob
  # match below: `case "$haystack" in *""*)` is `**`, which matches any
  # haystack (even an empty one) unconditionally, so an empty needle
  # would vacuously PASS every time regardless of what was actually
  # being checked — almost always a bug in the calling test (e.g. an
  # unset/blank variable used as the needle), not a real assertion.
  haystack=$1
  needle=$2
  message=$3
  if [ -z "$needle" ]; then
    _assert_fail "$message (empty needle passed to assert_contains — fix the calling test)" "a non-empty needle" "<empty needle>"
    return 0
  fi
  case "$haystack" in
    *"$needle"*)
      _assert_pass
      ;;
    *)
      _assert_fail "$message" "string containing: $needle" "$haystack"
      ;;
  esac
  return 0
}

assert_not_contains() {
  # assert_not_contains <haystack> <needle> <message>
  #
  # Same guard, mirrored: with an empty needle, `case "$haystack" in
  # *""*)` (i.e. `**`) always matches, so this would always land in the
  # "found it" branch and vacuously FAIL every time, for every
  # haystack — accidentally "safe" (it never lets a bad assertion slip
  # through as a pass) but for the wrong reason, and just as much a
  # symptom of a broken calling test as the assert_contains case. Made
  # explicit here instead of relying on that accident.
  haystack=$1
  needle=$2
  message=$3
  if [ -z "$needle" ]; then
    _assert_fail "$message (empty needle passed to assert_not_contains — fix the calling test)" "a non-empty needle" "<empty needle>"
    return 0
  fi
  case "$haystack" in
    *"$needle"*)
      _assert_fail "$message" "string NOT containing: $needle" "$haystack"
      ;;
    *)
      _assert_pass
      ;;
  esac
  return 0
}

assert_file_exists() {
  # assert_file_exists <path> <message>
  path=$1
  message=$2
  if [ -f "$path" ]; then
    _assert_pass
  else
    _assert_fail "$message" "file exists: $path" "missing"
  fi
  return 0
}

assert_file_absent() {
  # assert_file_absent <path> <message>
  path=$1
  message=$2
  if [ -e "$path" ]; then
    _assert_fail "$message" "absent: $path" "present"
  else
    _assert_pass
  fi
  return 0
}

assert_json_valid() {
  # assert_json_valid <path> <message>
  path=$1
  message=$2
  if [ ! -f "$path" ]; then
    _assert_fail "$message" "valid JSON at: $path" "file missing"
    return 0
  fi
  if jq empty "$path" >/dev/null 2>&1; then
    _assert_pass
  else
    _assert_fail "$message" "valid JSON at: $path" "invalid JSON"
  fi
  return 0
}

assert_json_eq() {
  # assert_json_eq <path> <jq-filter> <expected> <message>
  path=$1
  filter=$2
  expected=$3
  message=$4
  if [ ! -f "$path" ]; then
    _assert_fail "$message" "$expected" "<file missing: $path>"
    return 0
  fi
  actual=$(jq -r "$filter" "$path" 2>/dev/null) || actual="<jq error>"
  if [ "$actual" = "$expected" ]; then
    _assert_pass
  else
    _assert_fail "$message" "$expected" "$actual"
  fi
  return 0
}

assert_exit_code() {
  # assert_exit_code <expected> <command...>
  expected=$1
  shift
  message="exit code of: $*"
  if "$@" >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [ "$actual" = "$expected" ]; then
    _assert_pass
  else
    _assert_fail "$message" "$expected" "$actual"
  fi
  return 0
}

# --- Scratch-directory leak lock ---------------------------------------
#
# Every test file here creates scratch paths under $TMPDIR and removes
# them with ONE `trap ... EXIT`. The mechanism has a silent hole, and it
# was open in three files at once: a helper called as `h=$(new_home)`
# runs in a SUBSHELL, so `cleanup_paths="$cleanup_paths $h"` inside it
# dies with that subshell and the trap never learns the path. Measured
# before the fix, under a private $TMPDIR: one run of tests/run.sh left
# 443 scratch directories and files behind, ~14 MB, and the header of
# tests/test_hoard.sh claimed "one EXIT trap for every scratch path"
# while it was happening.
#
# The fix is structural (each file mktemps helper scratch inside ONE
# registered parent directory, so no registration has to survive a
# subshell at all); this pair is what stops it silently coming back.
# scratch_snapshot records what $TMPDIR held before a run;
# assert_no_scratch_leak fails on anything that appeared during the run
# and is not scheduled for removal by the trap.
#
# PRESENCE, not a count: the assertion names the unscheduled paths
# instead of comparing "how many are left" against a number, because a
# number would rot the moment a file gained one scenario, and because
# these files run on a developer's real $TMPDIR, which already holds
# other programs' scratch. The snapshot is what makes that residue
# invisible to the check - it subtracts whatever was already there.
#
# Called BEFORE the trap fires (the last assertions in a file), so the
# paths still exist: what is asserted is that each is on the list the
# trap will remove, not that it is already gone.
scratch_snapshot() {
  # scratch_snapshot - the entries $TMPDIR holds right now, as
  # "|path|path|...|" for a substring test. Nothing else in this harness
  # needs the format, so it is a private one rather than a newline list:
  # `case` can test it with no subshell, no temp file, and no dependence
  # on how a path sorts.
  ss_out="|"
  for ss_e in "${TMPDIR:-/tmp}"/*; do
    [ -e "$ss_e" ] || continue
    ss_out="$ss_out$ss_e|"
  done
  printf '%s' "$ss_out"
}

assert_no_scratch_leak() {
  # assert_no_scratch_leak <snapshot> <scheduled paths> <message>
  #
  # <snapshot> comes from scratch_snapshot, taken before the file
  # created anything. <scheduled paths> is the space-joined list the
  # file's own EXIT trap removes - normally "$cleanup_paths".
  ansl_before=$1
  ansl_scheduled=$2
  ansl_message=$3
  ansl_leaked=""
  for ansl_e in "${TMPDIR:-/tmp}"/*; do
    [ -e "$ansl_e" ] || continue
    case "$ansl_before" in
      *"|$ansl_e|"*)
        # Already there before this file ran - not ours.
        continue
        ;;
    esac
    case " $ansl_scheduled " in
      *" $ansl_e "*)
        continue
        ;;
    esac
    ansl_leaked="$ansl_leaked $ansl_e"
  done
  assert_eq "" "$ansl_leaked" "$ansl_message"
  return 0
}

assert_report() {
  # Prints a machine-parseable summary line that tests/run.sh parses to
  # aggregate results across files, then exits 1 if any assertion in
  # this file failed, 0 otherwise. Must be the last thing a test file
  # calls.
  printf 'SUMMARY pass=%s fail=%s\n' "$ASSERT_PASS_COUNT" "$ASSERT_FAIL_COUNT"
  if [ "$ASSERT_FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
}
