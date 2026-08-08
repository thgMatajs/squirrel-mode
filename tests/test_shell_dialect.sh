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

assert_report
