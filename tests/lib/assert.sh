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
# NARROWED TO THIS SUITE'S OWN PREFIX, deliberately, and this is what it
# costs. The snapshot subtracts residue that existed BEFORE the run; it
# cannot subtract a file some unrelated process drops into $TMPDIR
# DURING it, and a suite run takes minutes on a real machine whose
# $TMPDIR is shared with everything else the user is running. Without a
# filter this lock would eventually go red naming a path the suite never
# touched - a guard that blocks correct work, which this repo deletes
# rather than ships. So it only judges entries named `squirrel-*`, which
# every mktemp template in tests/ uses, scratch roots included. WHAT
# THAT GIVES UP, since a narrowing that does not say so is the half-true
# guarantee these files exist to stop: a future helper that mktemps
# under some other prefix leaks silently, exactly as the four fixed here
# did. The prefix is the contract; keep to it.
#
# NARROW IS ALSO WHAT KEEPS THIS PAIR CHEAP, and that is the second
# reason it is not negotiable. Both loops below hand the shell a pattern
# that already carries the prefix, so it expands this suite's own
# scratch and nothing else. The form they replaced expanded EVERY entry
# $TMPDIR holds and sorted the names out afterwards, which billed this
# guard for the user's junk drawer rather than for anything the suite
# created - and billed it QUADRATICALLY, because appending one path at a
# time to a shell string makes macOS's /bin/sh (bash 3.2) copy the whole
# string on every append. Measured in one shell, on entries this suite
# never made: 1.81 s at 2000 of them, 27.58 s at 8000, 174.12 s at
# 20000. The $TMPDIR of the machine this was written on holds 176299
# entries, and one run of tests/test_skills.sh against a 20000-entry
# $TMPDIR took 383.96 s with the wide walk against 1.08 s with these
# two - same file, the same 307 assertions, the same verdict. 1.05 s of
# that second figure is what the file costs on an EMPTY $TMPDIR, so what
# the narrowing bought back is very nearly the whole of it.
#
# scripts/hoard-search.sh carries the identical mechanism under the
# heading "THE PER-FILE FORM IS QUADRATIC"; read the two together,
# because this one arrived INSIDE the guard written one round earlier to
# stop scratch mess. The shape that costs is deliberately not spelled
# out anywhere in this file: tests/test_shell_dialect.sh greps THIS file
# for it, and a guard its own subject's comment satisfies is a guard
# that cannot fail.
#
# Called BEFORE the trap fires (the last assertions in a file), so the
# paths still exist: what is asserted is that each is on the list the
# trap will remove, not that it is already gone.
scratch_snapshot() {
  # scratch_snapshot - the `squirrel-` entries $TMPDIR holds right now,
  # as "|path|path|...|" for a substring test. Nothing else in this
  # harness needs the format, so it is a private one rather than a
  # newline list: `case` can test it with no subshell, no temp file, and
  # no dependence on how a path sorts.
  #
  # STREAMED, NEVER ACCUMULATED. Each path goes straight to this
  # function's standard output, which every caller is already capturing
  # with `$( )`, so the cost is linear in what it prints and this
  # function assigns nothing at all. Growing a variable instead would
  # keep the copy-per-append above alive on the one list that can still
  # grow here - the suite's own leftover scratch, which is reachable:
  # interrupting a run leaves it behind, and one run left 443 paths
  # before the structural fix described above. Both forms were timed on
  # 20000 planted `squirrel-` entries, each printing the identical
  # 3260001 characters: 0.80 s streamed, 392.47 s accumulated.
  printf '|'
  for ss_e in "${TMPDIR:-/tmp}"/squirrel-*; do
    [ -e "$ss_e" ] || continue
    printf '%s|' "$ss_e"
  done
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
  # This suite's scratch, by the prefix every mktemp template here uses,
  # selected by the pattern itself rather than by testing each name the
  # directory happens to hold - see the header above both for what
  # judging only these gives up and for what walking the whole directory
  # cost. An unmatched glob stays literal in POSIX sh and the literal
  # names no file, which is what the `[ -e ]` below drops; it is also
  # why no separate test of the name survives here, since one that
  # could never say no is a guard that cannot fail.
  for ansl_e in "${TMPDIR:-/tmp}"/squirrel-*; do
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
