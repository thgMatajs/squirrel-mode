#!/bin/sh
# check-off-flag.sh - UserPromptSubmit hook.
#
# ADR-0005 (as amended, P2): `/squirrel:off` cannot learn its own
# session_id (Claude Code hands that to hooks, never to a running
# skill), so it cannot write `off/<session_id>` directly. Instead
# SessionStart injects an opaque "Session off-token: <token>" line
# (token === sanitised session_id when valid) and `/squirrel:off`
# writes `off/PENDING.<token>` whose contents are still the cwd.
# `/squirrel:on` gets the mirror: `off/CLEAR.<token>`, same contents.
# THIS hook - which does receive both `session_id` and `cwd` on every
# prompt - recomputes the token by sanitising session_id and claims
# only `PENDING.<that>` / `CLEAR.<that>` by TOKEN first. Same value,
# two channels: the skill copies the injected token into the filename;
# this hook never needs the SessionStart context (UserPromptSubmit
# does not receive it).
#
# Tech-lead D3 / Amendment P2 claiming rules:
#   - Token path: sentinel suffix sanitises AND equals THIS session's
#     sanitised session_id → claim by token only (contents/cwd
#     optional; a cwd mismatch must NOT block the claim).
#   - Foreign token-shaped: suffix sanitises but is NOT this session's
#     id → leave untouched. Claiming these by cwd would re-open the
#     same-directory race P2 closes (session B would steal session A's
#     PENDING.<A>).
#   - Legacy tokenless: suffix fails sanitise (pre-P2 random suffixes
#     that are not a valid session_id shape, e.g. containing ".") →
#     claim-by-cwd as today.
#
# Only after both kinds of sentinel have been processed does it check
# whether `off/<session_id>` exists and, if so, inject the
# counter-instruction - so a session that just ran `/squirrel:off` is
# suppressed starting with THIS SAME prompt, not the one after it.
#
# The five steps, in the order ADR-0005 requires (and the order below):
#   1. Extract session_id and cwd from stdin JSON.
#   2. Sanitise session_id. On failure, touch nothing under off/ at all -
#      a later, valid invocation (e.g. once whatever produced the bad
#      session_id is fixed) must still find every sentinel intact.
#   3. Claim a matching PENDING.* sentinel (rename to off/<session_id>).
#   4. Claim a matching CLEAR.* sentinel (delete off/<session_id> + it).
#      CYCLE-3 MAJOR FIX: a matching PENDING and a matching CLEAR
#      sentinel can both exist for the same session at once (already
#      off, then /squirrel:on followed by /squirrel:off before either
#      reaches a hook). Claiming steps 3 and 4 in a fixed order always
#      let whichever one is checked last win, regardless of which one
#      the user actually issued more recently. ADR-0005 now requires
#      the NEWER sentinel to win, resolved with `find -newer` (the only
#      portable way to compare two files' mtimes in POSIX sh - there is
#      no portable `stat`), with PENDING winning an exact mtime tie.
#      This is computed ONCE, before either claiming step runs (see
#      newest_matching_pending/newest_matching_clear and the
#      SENTINEL_WINNER computation in decide() below), so the decision
#      never depends on execution order, and the LOSING sentinel(s) are
#      discarded rather than claimed, so they cannot linger and flip the
#      flag again on some later prompt.
#   5. Check off/<session_id> and inject the counter-instruction if it
#      exists - LAST, so steps 3/4's effect is visible to THIS check.
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
# either way. Every sentinel-claiming step below is guarded the same
# way (`|| true` / `|| continue`) for the identical reason: a failed
# `mv` or `rm` most likely means a concurrent invocation already claimed
# that exact sentinel first, which is not an error worth surfacing.
#
# WHAT "NEVER exit non-zero" DOES NOT COVER (P4 item 1, audit). Stated
# here because the two paragraphs above assert it without qualification,
# and this file - unlike allow-checkpoint.sh, which has carried the
# disclosure since its cycle-3 review - had none. Both paragraphs are
# accurate about EXITING: nothing below can make this script exit
# non-zero. Neither says anything about RETURNING AT ALL, and there are
# two reproduced ways this hook never returns, on every prompt in the
# session, with zero bytes of output:
#
#   1. A `jq` PRESENT on PATH but WEDGED - stopped, deadlocked, never
#      returns. `if output=$(decide 2>/dev/null); then` catches decide()
#      FAILING; it cannot catch decide() never FINISHING, because the
#      shell must wait for that command substitution's subshell - itself
#      blocked inside `jq` - before the `if` is even evaluated. No POSIX
#      `sh` construct interrupts a command substitution already in
#      flight, and `timeout(1)` is GNU coreutils, absent from stock
#      macOS. NOT closable here; see allow-checkpoint.sh's own
#      "CORRECTED CLAIM (cycle-3 review, AD1)" for the full argument.
#
#   2. A CLOSED fd 0 - stdin not an open descriptor at all, as distinct
#      from empty or /dev/null. `input=$(cat)` in decide() then hangs
#      forever: `$(...)` builds its capture pipe on the lowest free file
#      descriptor, which with fd 0 closed IS fd 0, so `cat` reads the
#      very pipe the substitution's own subshell writes to and EOF never
#      arrives. Reproduced against this script directly. This one IS
#      closable, with `if ! ( exec 3<&0 ) 2>/dev/null; then exec
#      0</dev/null; fi` ahead of the first command substitution - the
#      probe belongs in a SUBSHELL because a failed `exec` redirection
#      exits a non-interactive shell, which would exit this hook
#      non-zero. Deliberately not applied in this change: it is a
#      behaviour change and belongs in one coordinated change across all
#      three hooks, not a comment-only correction to one of them.
#
# Both are bounded only by the harness's own hook timeout, never by
# anything in this script.
#
# `session_id` sanitisation: `session_id` comes from outside this
# script's control (the hook's stdin JSON). sanitize_session_id below
# accepts only [A-Za-z0-9_-], rejecting anything containing "/" or "."
# (which also rejects ".." outright) before it ever becomes part of a
# path, so a value like "../../../etc/passwd" is treated as "no
# session id" - not read, not stat'd, not opened - rather than
# resolved relative to the off/ directory.
#
# Sentinel contents are read as OPAQUE TEXT and compared byte-for-byte
# against `cwd`, never interpreted, executed, or path-resolved - the
# same posture allow-checkpoint.sh takes toward `file_path`. Contents
# matter only on the legacy tokenless path; the token path ignores them.
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
# nothing - the caller treats that identically to "no flag", and (per
# ADR-0005) leaves every sentinel under off/ completely untouched.
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

# nl: a variable holding exactly one literal newline byte, built the
# same way tests/test_hooks.sh itself builds one for IFS (an actual
# line break inside single quotes, not an escape sequence some POSIX
# `sh` builtins would need to interpret) - portable across every shell
# this plugin ships to.
nl='
'

# read_sentinel_trimmed <path>: sets the global SENTINEL_CONTENTS to the
# exact byte content of <path> with AT MOST ONE trailing newline byte
# removed - not "however many trailing newlines happen to be there"
# (what a bare `contents=$(cat "$path")` gives, since POSIX command
# substitution strips ALL trailing newlines unconditionally, nor
# whatever a SECOND, later `$(...)` around the result would strip, for
# the identical reason). ADR-0005 requires comparing a sentinel's
# contents to `cwd` byte-for-byte after trimming at most one, so a
# sentinel that (by accident, or by something other than /squirrel:off
# having written it) carries two or more trailing newlines must NOT be
# silently treated as if it carried none.
#
# CYCLE-3 MAJOR FIX: an earlier version of this file split the work into
# two functions - one that appended a sentinel "X" byte inside a `$(...)`
# to shield the file's OWN trailing newline(s) from command
# substitution's automatic stripping, and a second, separate function
# that trimmed at most one of them via parameter expansion - but the
# CALLER combined them as `contents=$(read_sentinel_exact "$f")`
# followed by `contents=$(trim_one_trailing_newline "$contents")`. BOTH
# of those are themselves command substitutions, so the SECOND one
# stripped every trailing newline unconditionally before the first
# function's careful protection - or the second function's careful
# "at most one" logic - ever got a chance to matter: a sentinel with two
# or more trailing newlines was silently claimed as if it had none.
#
# This function fixes that by never crossing a command-substitution
# boundary more than once: `raw=$(...)` below is the ONLY `$(...)` in
# the whole path. Its output always ends in a literal "X" byte (never a
# newline), so command substitution here strips nothing but that "X" -
# none of the file's own trailing newline(s) are touched by it. Both the
# "X" strip (`${raw%X}`) and the at-most-one-newline strip
# (`${SENTINEL_CONTENTS%"$nl"}`) that follow are plain PARAMETER
# EXPANSION on the already-captured `$raw`/`$SENTINEL_CONTENTS`, in the
# same assignment chain, with no further `$(...)` anywhere - the exact
# discipline the caller-side bug above violated.
read_sentinel_trimmed() {
  path=$1
  raw=$(cat "$path" 2>/dev/null; printf 'X') || raw='X'
  SENTINEL_CONTENTS=${raw%X}
  case "$SENTINEL_CONTENTS" in
    *"$nl")
      SENTINEL_CONTENTS=${SENTINEL_CONTENTS%"$nl"}
      ;;
  esac
  return 0
}

# is_unclaimable_sentinel <path>: returns 0 (true) iff <path> must NOT
# be treated as a real sentinel - it is a symlink (rejected outright,
# regardless of what it points at - the same posture
# allow-checkpoint.sh's component_walk_has_symlink takes: `[ -L ]` is a
# POSIX shell builtin, no external tool, so this holds with or without
# realpath/readlink on PATH) or it is not a regular file at all (e.g. a
# directory that happens to match the glob).
is_unclaimable_sentinel() {
  path=$1
  if [ -L "$path" ]; then
    return 0
  fi
  if [ ! -f "$path" ]; then
    return 0
  fi
  return 1
}

# SENTINEL_WINNER: which sentinel TYPE wins when a matching PENDING and
# a matching CLEAR sentinel both exist for this session - "pending",
# "clear", or "none" (no competition, i.e. at most one type matched at
# all). Computed once in decide(), before either claim_pending or
# claim_clear runs (see the SENTINEL_WINNER computation there and
# newest_matching_pending/newest_matching_clear below), and consulted by
# both functions below. Defaulted here, not left unset, so referencing
# it under `set -u` is always safe even if a future caller invokes
# either function without going through decide() first - "pending" is
# the safe default in that case, since it is also ADR-0005's own
# tie-break winner.
SENTINEL_WINNER=pending

# sentinel_basename_suffix <path> <prefix>:
#   PENDING.foo -> foo, CLEAR.foo.bar -> foo.bar. Empty if <path>'s
#   basename does not start with <prefix>.
sentinel_basename_suffix() {
  path=$1
  prefix=$2
  base=$(basename "$path")
  case "$base" in
    "$prefix"*)
      printf '%s' "${base#"$prefix"}"
      ;;
    *)
      printf ''
      ;;
  esac
}

# sentinel_matches_this_session <path> <prefix> <session_id> <cwd>:
# returns 0 iff <path> is claimable by THIS session under Amendment P2:
#   - token path: suffix sanitises AND equals <session_id> (contents
#     ignored; cwd may be empty)
#   - foreign token-shaped: suffix sanitises but differs → not claimable
#   - legacy tokenless: suffix fails sanitise → claimable only when
#     trimmed contents equal <cwd> and <cwd> is non-empty
sentinel_matches_this_session() {
  path=$1
  prefix=$2
  session_id=$3
  cwd=$4
  suffix=$(sentinel_basename_suffix "$path" "$prefix")
  [ -n "$suffix" ] || return 1
  if tok=$(sanitize_session_id "$suffix"); then
    if [ "$tok" = "$session_id" ]; then
      return 0
    fi
    return 1
  fi
  [ -n "$cwd" ] || return 1
  read_sentinel_trimmed "$path"
  if [ "$SENTINEL_CONTENTS" = "$cwd" ]; then
    return 0
  fi
  return 1
}

# claim_pending <off_dir> <session_id> <cwd>: globs off/PENDING.*, and
# for each one that is a genuine regular file (not a symlink) claimable
# by THIS session (token path or legacy cwd path - see
# sentinel_matches_this_session), renames it to off/<session_id> - the
# binding ADR-0005 describes. A non-matching or unclaimable sentinel is
# left exactly as it was found. Every fallible step is
# `|| continue`/`|| true`-guarded: a `mv` failing most likely means a
# concurrent invocation already claimed this exact sentinel first.
#
# CYCLE-3 MAJOR FIX: when SENTINEL_WINNER is "clear" - a matching CLEAR
# sentinel for this same session is newer - a matching PENDING sentinel
# is superseded and must NOT be claimed. It is discarded outright
# instead of being left in place: leaving it would let it linger and
# flip the flag back off on some later prompt, once the winning CLEAR
# sentinel has already been consumed and can no longer out-vote it
# again.
claim_pending() {
  off_dir=$1
  session_id=$2
  cwd=$3
  for f in "$off_dir"/PENDING.*; do
    [ -e "$f" ] || continue
    is_unclaimable_sentinel "$f" && continue
    if sentinel_matches_this_session "$f" "PENDING." "$session_id" "$cwd"; then
      if [ "$SENTINEL_WINNER" = "clear" ]; then
        rm -f -- "$f" 2>/dev/null || true
      else
        mv -- "$f" "$off_dir/$session_id" 2>/dev/null || true
      fi
    fi
  done
  return 0
}

# claim_clear <off_dir> <session_id> <cwd>: the mirror of claim_pending
# for off/CLEAR.* - on a match, deletes off/<session_id> (if it exists)
# and then the sentinel itself.
#
# CYCLE-3 MAJOR FIX: when SENTINEL_WINNER is "pending" - a matching
# PENDING sentinel for this same session is at least as new (a tie
# favours PENDING, per ADR-0005) - a matching CLEAR sentinel is
# superseded and must NOT delete the flag. It is discarded outright
# instead, for the same reason claim_pending discards a superseded
# PENDING sentinel above: left in place, it would delete the flag again
# on some later prompt once the winning PENDING sentinel is gone and
# can no longer out-vote it.
claim_clear() {
  off_dir=$1
  session_id=$2
  cwd=$3
  for f in "$off_dir"/CLEAR.*; do
    [ -e "$f" ] || continue
    is_unclaimable_sentinel "$f" && continue
    if sentinel_matches_this_session "$f" "CLEAR." "$session_id" "$cwd"; then
      if [ "$SENTINEL_WINNER" = "pending" ]; then
        rm -f -- "$f" 2>/dev/null || true
      else
        rm -f -- "$off_dir/$session_id" 2>/dev/null || true
        rm -f -- "$f" 2>/dev/null || true
      fi
    fi
  done
  return 0
}

# newest_matching_pending <off_dir> <session_id> <cwd>: sets the global
# CHAMPION_PATH to the path of the most-recently-modified off/PENDING.*
# sentinel claimable by THIS session, or "" if none match. Skips
# anything is_unclaimable_sentinel rejects, the same as claim_pending
# itself. Recency is compared with `find -newer` - the only portable
# way to compare two files' mtimes in POSIX sh, there being no portable
# `stat`. Read-only: never claims, renames, or deletes anything, so it
# is safe to call before deciding what claim_pending/claim_clear should
# actually do.
newest_matching_pending() {
  off_dir=$1
  session_id=$2
  cwd=$3
  CHAMPION_PATH=""
  for f in "$off_dir"/PENDING.*; do
    [ -e "$f" ] || continue
    is_unclaimable_sentinel "$f" && continue
    if sentinel_matches_this_session "$f" "PENDING." "$session_id" "$cwd"; then
      if [ -z "$CHAMPION_PATH" ] || [ -n "$(find "$f" -newer "$CHAMPION_PATH" 2>/dev/null)" ]; then
        CHAMPION_PATH=$f
      fi
    fi
  done
  return 0
}

# newest_matching_clear <off_dir> <session_id> <cwd>: the mirror of
# newest_matching_pending for off/CLEAR.*.
newest_matching_clear() {
  off_dir=$1
  session_id=$2
  cwd=$3
  CHAMPION_PATH=""
  for f in "$off_dir"/CLEAR.*; do
    [ -e "$f" ] || continue
    is_unclaimable_sentinel "$f" && continue
    if sentinel_matches_this_session "$f" "CLEAR." "$session_id" "$cwd"; then
      if [ -z "$CHAMPION_PATH" ] || [ -n "$(find "$f" -newer "$CHAMPION_PATH" 2>/dev/null)" ]; then
        CHAMPION_PATH=$f
      fi
    fi
  done
  return 0
}

COUNTER_INSTRUCTION="squirrel-mode is OFF for this session (per /squirrel:off). Ignore the squirrel-mode output style and every base rule it carries for the rest of this session; respond in your ordinary default style instead. This stays in effect until /squirrel:on is run in this same session."

decide() {
  input=$(cat)

  # Step 1: extract both fields this hook needs. `cwd` is available to
  # UserPromptSubmit the same way it already is to SessionStart (see
  # load-profile.sh's own extract_field use of the same key).
  raw_session_id=$(extract_field "$input" "session_id")
  cwd=$(extract_field "$input" "cwd")

  # Step 2: sanitise session_id. On failure, return immediately, before
  # off_dir is even computed - nothing under off/ is touched, so every
  # sentinel is still there for a later, valid invocation.
  session_id=$(sanitize_session_id "$raw_session_id") || { printf ''; return 0; }
  [ -n "$session_id" ] || { printf ''; return 0; }

  home_dir="${HOME:-}"
  [ -n "$home_dir" ] || { printf ''; return 0; }

  off_dir="$home_dir/.squirrel/off"

  # CYCLE-3 MAJOR FIX: before claiming anything, decide - ONCE, so the
  # answer cannot depend on which of steps 3/4 happens to run first -
  # which sentinel type wins when a matching PENDING and a matching
  # CLEAR both exist for this same session (token path or legacy cwd
  # path). Read-only: neither newest_matching_pending nor
  # newest_matching_clear claims, renames, or deletes anything, so
  # computing this cannot itself race with the claiming steps that
  # follow.
  newest_matching_pending "$off_dir" "$session_id" "$cwd"
  pending_champion=$CHAMPION_PATH
  newest_matching_clear "$off_dir" "$session_id" "$cwd"
  clear_champion=$CHAMPION_PATH

  if [ -n "$pending_champion" ] && [ -n "$clear_champion" ]; then
    # Both types matched: the newer one wins, resolved with `find
    # -newer` (ADR-0005). An exact mtime tie is NOT "clear strictly
    # newer than pending", so the `else` branch - PENDING - is what
    # runs on a tie, exactly as ADR-0005 requires.
    if [ -n "$(find "$clear_champion" -newer "$pending_champion" 2>/dev/null)" ]; then
      SENTINEL_WINNER=clear
    else
      SENTINEL_WINNER=pending
    fi
  elif [ -n "$pending_champion" ]; then
    SENTINEL_WINNER=pending
  elif [ -n "$clear_champion" ]; then
    SENTINEL_WINNER=clear
  else
    SENTINEL_WINNER=none
  fi

  # Steps 3 and 4: claim any matching PENDING/CLEAR sentinel. Both are
  # no-ops (safe, silent) when off_dir does not exist yet - the glob
  # simply never matches anything real. Each consults SENTINEL_WINNER,
  # computed just above, to discard rather than act on a sentinel that
  # lost to a newer one of the opposite type.
  claim_pending "$off_dir" "$session_id" "$cwd"
  claim_clear "$off_dir" "$session_id" "$cwd"

  # Step 5: THE existing check, now running LAST - after steps 3/4 have
  # had a chance to create or remove off/<session_id> - so a PENDING
  # sentinel claimed a moment ago on this exact invocation already
  # produces the counter-instruction on this exact invocation too.
  flag_file="$off_dir/$session_id"
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
