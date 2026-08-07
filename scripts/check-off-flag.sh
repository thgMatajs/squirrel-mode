#!/bin/sh
# check-off-flag.sh - UserPromptSubmit hook.
#
# ADR-0005: `/squirrel:off` writes ~/.claude/squirrel/off/<session_id>;
# `/squirrel:on` removes it. While that file exists for the CURRENT
# session, this hook injects a counter-instruction on every prompt, so
# suppression arrives at the same cadence as the output-style reminders
# it has to keep beating. When the flag does not exist - the common
# path, since this hook runs on every single prompt for the entire
# life of every session - it prints nothing at all and exits 0.
#
# Runs on the hot path of every message, so it must be fast, silent
# when there is nothing to say, and NEVER exit non-zero: a crash here
# breaks every prompt in the session, not just this one.
#
# `set -e` vs. "never exit non-zero": as in load-profile.sh, `set -e`
# stays on inside decide() (so a real bug aborts that function
# immediately instead of producing a half-computed, wrong answer), but
# decide() is only ever invoked as `if output=$(decide ...); then ...
# fi` below - the `if` is exempt from `set -e` by POSIX definition, so
# nothing decide() does can make THIS script exit non-zero. Its output
# is empty ("") both when there is genuinely nothing to say and when it
# failed internally, which is exactly the same, safe, silent behaviour
# either way.
#
# `session_id` sanitisation: `session_id` comes from outside this
# script's control (the hook's stdin JSON). sanitize_session_id below
# accepts only [A-Za-z0-9_-], rejecting anything containing "/" or "."
# (which also rejects ".." outright) before it ever becomes part of a
# path, so a value like "../../../etc/passwd" is treated as "no
# session id" - not read, not stat'd, not opened - rather than
# resolved relative to the off/ directory.
#
# jq: preferred, not required - see extract_field's sed fallback.
set -eu

extract_field() {
  json=$1
  key=$2
  if command -v jq >/dev/null 2>&1; then
    if val=$(printf '%s' "$json" | jq -r --arg k "$key" '(.[$k] // empty)' 2>/dev/null); then
      if [ "$val" != "null" ] && [ -n "$val" ]; then
        printf '%s' "$val"
        return 0
      fi
    fi
  fi
  printf '%s\n' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

# sanitize_session_id <raw>: prints <raw> and returns 0 only if it is a
# plausible session id - non-empty, composed solely of letters, digits,
# underscore, and hyphen (which by construction excludes "/" and "."
# and therefore excludes ".." and any path-separator-based traversal),
# and no longer than 128 bytes (a defensive upper bound; real session
# ids are short UUID-like tokens). Anything else returns 1 and prints
# nothing - the caller treats that identically to "no flag".
sanitize_session_id() {
  raw=$1
  case "$raw" in
    '') return 1 ;;
  esac
  case "$raw" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  # ${#raw} is POSIX parameter-length expansion, not a bashism.
  if [ "${#raw}" -gt 128 ]; then
    return 1
  fi
  printf '%s' "$raw"
  return 0
}

COUNTER_INSTRUCTION="squirrel-mode is OFF for this session (per /squirrel:off). Ignore the squirrel-mode output style and every base rule it carries for the rest of this session; respond in your ordinary default style instead. This stays in effect until /squirrel:on is run in this same session."

decide() {
  input=$(cat)
  raw_session_id=$(extract_field "$input" "session_id")

  session_id=$(sanitize_session_id "$raw_session_id") || { printf ''; return 0; }
  [ -n "$session_id" ] || { printf ''; return 0; }

  home_dir="${HOME:-}"
  [ -n "$home_dir" ] || { printf ''; return 0; }

  flag_file="$home_dir/.claude/squirrel/off/$session_id"
  if [ -f "$flag_file" ]; then
    printf '%s' "$COUNTER_INSTRUCTION"
  else
    printf ''
  fi
  return 0
}

if output=$(decide 2>/dev/null); then
  :
else
  output=""
fi

if [ -n "$output" ]; then
  printf '%s\n' "$output"
fi
exit 0
