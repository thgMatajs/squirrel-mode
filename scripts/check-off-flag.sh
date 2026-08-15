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
# jq: preferred, not required - see extract_field, whose no-jq path is
# extract_top_level_string's top-level-only byte scanner (and that
# function's own list of what the scanner does not cover).
set -eu

# extract_top_level_string <json> <key>: prints the value of the STRING
# field named <key> that sits at DEPTH 1 - directly inside the payload's
# own outermost object - and prints nothing at all when there is no such
# field. This is the no-jq path for extract_field below.
#
# DUPLICATED, DELIBERATELY, between scripts/check-off-flag.sh and
# scripts/load-profile.sh, exactly as sanitize_session_id already is and
# for the identical reason: this project forbids `source`/`.` between
# shipped scripts, so each hook must be a single self-contained file
# that runs correctly no matter what else is or is not installed
# alongside it. The two copies are byte-identical and have no state; if
# one changes, the other must be changed to match. scripts/
# allow-checkpoint.sh deliberately does NOT get a third copy - see the
# note inside its own extract_field for why it keeps the old scan.
#
# FIXED (this cycle) - what this replaces and why a scanner, not a
# narrower pattern. The fallback used to be one sed substitution,
# `s/.*"<key>"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p`. POSIX sed is
# leftmost-longest, so the leading `.*` swallowed as much as it could
# and the LAST occurrence of <key> on the line won - INCLUDING one
# nested inside a sub-object. Reproduced with jq stripped from PATH: a
# UserPromptSubmit payload carrying `"session_id":"sessionBBB"` at the
# top level and `"meta":{"session_id":"sessionAAA"}` beneath it made
# THIS script read sessionAAA, claim session A's own
# off/PENDING.sessionAAA sentinel by the token path, rename it to
# off/sessionAAA and print the counter-instruction - so session B was
# silenced and session A's /squirrel:off never took effect. That is
# precisely the cross-session theft Amendment P2's token binding exists
# to prevent, reintroduced one layer lower down. Claude Code's real
# payloads are flat, so it was not reachable in production; this file's
# header nevertheless advertises "jq: preferred, not required", which is
# what makes closing the class the honest option rather than documenting
# it away. It is a scanner rather than a tighter regex for the reason
# allow-checkpoint.sh's extract_tool_input_field already records: a
# regex matches text shapes and cannot track brace depth, so each
# narrower pattern only shrinks the class of shapes that defeat it -
# the same "narrower guard, same bug" outcome this project has now hit
# seven times.
#
# HOW IT SCANS. One `awk` pass. The payload is SPLIT on the double-quote
# character, which turns it into alternating OUTSIDE-a-string and
# INSIDE-a-string segments, and the three things a regex cannot track
# are then all derived from that split: string state, escape state, and
# `{`/`[` nesting depth.
#   - The split separator is written as the bracket expression `["]`,
#     never as a bare `"`. With a SINGLE-character separator the
#     one-true-awk shipped as /usr/bin/awk on macOS also breaks at every
#     NEWLINE, which silently shreds any pretty-printed payload; a
#     two-or-more-character separator takes awk's regex path and does
#     not. Verified against that awk, gawk, and mawk.
#   - A quote whose preceding segment ends in an ODD number of
#     backslashes is escaped, so the string continues across it and the
#     two segments are re-joined. That is what stops a `"` inside a
#     value from being read as a delimiter.
#   - ONLY the outside segments are inspected for structure, so a `{`,
#     `}`, `[`, `]` or `:` appearing inside a value can never change the
#     nesting depth or turn its string into a key. Depth is maintained
#     by COUNTING the opening and closing brackets in each outside
#     segment with `gsub`.
#   - A string is a KEY only when the outside segment that follows it
#     begins with `:`, and its value is a string only when that segment
#     is EXACTLY `:` once whitespace is removed.
#   - The value is taken only when the depth recorded at its key is
#     exactly 1 - the key sits directly inside the payload's own
#     outermost object. Anything nested deeper is outside what this
#     scan looks at, which is the whole point.
# Only the matched value is ever unescaped; keys are compared, and
# non-matching values skipped, in their raw form.
#
# COST. Proportional to the payload's length plus the number of string
# tokens in it - deliberately NOT a character-at-a-time `substr` walk
# over the whole buffer, which is how this fix was first written and
# which is quadratic in practice: the macOS awk's `substr` is O(length)
# per call, and that version took 8.9 SECONDS on a single 500 KB prompt
# (10 KB 25 ms, 100 KB 408 ms, 500 KB 8889 ms). That matters here more
# than anywhere else in this plugin, because THIS hook runs on the hot
# path of every message. Measured after the rewrite, same machine:
# 500 KB 40 ms, 2 MB 91 ms, 20 000 levels of nesting 109 ms, and a
# deliberately pathological 1 MB payload of 50 000 separate top-level
# keys 1.7 s. Those are machine-specific figures, not a portable
# performance guarantee - the point they support is that the cost no
# longer grows with the SQUARE of an input this hook does not control.
# This path only runs at all when jq is absent, or when jq is present
# and reports the field genuinely missing.
#
# Run entirely under `LC_ALL=C`, for the reason load-profile.sh's
# json_escape sets out at length: BSD tools abort mid-stream on a byte
# that is not valid UTF-8 under a UTF-8 locale, and `LC_ALL=C` makes
# `length`/`substr`/`split` here genuinely byte-indexed so an invalid
# byte simply passes through instead. The key is handed over through the
# ENVIRONMENT rather than `awk -v`, because POSIX awk re-processes
# backslash escapes in a `-v` assignment (the same trap
# tests/test_hooks.sh's own line_of helper documents).
#
# WHAT IT DOES NOT DO - the residual limits, stated rather than implied:
#   - `\uXXXX` inside a VALUE is left in the output literally, as the
#     six bytes `\u` plus four hex digits, not decoded to a character.
#     Decoding it means UTF-8 re-encoding and surrogate pairing in awk,
#     which is a great deal of machinery for a shape neither key this is
#     ever called for (`session_id`, `cwd`) carries in practice. The
#     failure direction is closed, not open: sanitize_session_id rejects
#     a backslash outright, and a `cwd` carrying a literal `\u` simply
#     fails the byte-for-byte comparison sentinel_matches_this_session
#     makes against a sentinel's contents, so a mangled value can only
#     ever produce "no match", never a wrong match. The two-character
#     escapes JSON defines - \" \\ \/ \b \f \n \r \t - ARE decoded.
#   - A KEY spelled with ANY escape for one of its own characters -
#     a `\u` sequence, or a needlessly escaped `\/` - is not recognised
#     as that key: key names are compared in their RAW form, and a real
#     parser would resolve the escape before matching. Same direction:
#     the field reads as absent, never as some other field.
#   - Two top-level occurrences of the same key: the LAST string-valued
#     one wins, which is what jq's own object construction does, so the
#     jq path and this path agree rather than diverging.
#   - Malformed JSON (an unterminated string) stops the scan; nothing is
#     printed.
#   - `awk` absent from PATH: prints nothing and still returns 0 (the
#     trailing `|| true`), so a missing awk degrades this to "no field
#     found" - which this hook already treats as "nothing to say" -
#     instead of failing the hook.
extract_top_level_string() {
  printf '%s\n' "$1" | SQUIRREL_JSON_KEY="$2" LC_ALL=C awk '
    function take_raw(   s, seg, bs, closed) {
      s = ""
      while (i <= m) {
        seg = part[i]
        bs = 0
        if (match(seg, /\\+$/)) { bs = RLENGTH }
        closed = (i < m)
        i = i + 1
        if (closed == 0) { unterminated = 1; return s seg }
        if (bs % 2 == 1) { s = s seg "\""; continue }
        return s seg
      }
      unterminated = 1
      return s
    }
    function decode(s,   out, p, nx) {
      if (index(s, "\\") == 0) { return s }
      out = ""
      while (1) {
        p = index(s, "\\")
        if (p == 0) { return out s }
        out = out substr(s, 1, p - 1)
        nx = substr(s, p + 1, 1)
        if (nx == "n") { out = out "\n" }
        else if (nx == "t") { out = out "\t" }
        else if (nx == "r") { out = out "\r" }
        else if (nx == "b") { out = out sprintf("%c", 8) }
        else if (nx == "f") { out = out sprintf("%c", 12) }
        else if (nx == "\"") { out = out "\"" }
        else if (nx == "\\") { out = out "\\" }
        else if (nx == "/") { out = out "/" }
        else { out = out "\\" nx }
        s = substr(s, p + 2)
      }
    }
    { buf = buf $0 "\n" }
    END {
      key = ENVIRON["SQUIRREL_JSON_KEY"]
      m = split(buf, part, "[\"]")
      depth = 0
      found = 0
      val = ""
      have_prev = 0
      prev_str = ""
      prev_depth = 0
      expect_value = 0
      unterminated = 0
      i = 1
      while (i <= m) {
        o = part[i]
        gsub(/[ \t\r\n]/, "", o)
        if (have_prev == 1 && substr(o, 1, 1) == ":") {
          if (o == ":" && prev_depth == 1 && prev_str == key) { expect_value = 1 }
        }
        have_prev = 0
        t = o
        opens = gsub(/[{[]/, "", t)
        t = o
        closes = gsub(/[]}]/, "", t)
        depth = depth + opens - closes
        i = i + 1
        if (i > m) { break }
        raw = take_raw()
        if (unterminated == 1) { break }
        if (expect_value == 1) { found = 1; val = decode(raw); expect_value = 0 }
        else { prev_str = raw; prev_depth = depth; have_prev = 1 }
      }
      if (found == 1) { printf "%s", val }
    }
  ' 2>/dev/null || true
}

# extract_field <json> <key>: best-effort read of a TOP-LEVEL string
# field named <key> from <json>. Prefers jq (a real parser); falls back
# to extract_top_level_string's byte scanner above when jq is not on
# PATH, or when jq is present and reports the field absent. Both paths
# read the top level only, so which one ran is not observable in the
# result for any payload shape either can parse.
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
  extract_top_level_string "$json" "$key"
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

# cr: the carriage return, built with printf for the reason a literal one
# cannot be used - it cannot be seen in a source file, and an editor that
# normalises line endings would silently eat it. Needed alongside $nl by
# fold_line_breaks below, which folds the same two bytes
# scripts/load-profile.sh folds, in the same order and by the same
# structure - see that function for why the order is load-bearing.
cr=$(printf '\r')

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
#     trimmed contents equal <cwd>, OR equal the FOLDED spelling of
#     <cwd> that the model was actually shown (see below), and <cwd>
#     is non-empty
#
# THE FOLDED SPELLING IS ACCEPTED TOO, AND THAT CLOSES A REAL DIVERGENCE
# BETWEEN TWO HOOKS. The value the model writes into a legacy sentinel is
# the one it was given, and it was given the "Session working directory:"
# line that scripts/load-profile.sh emits - which that hook FOLDS, every
# line break in the value becoming one space, so the interpolated value
# cannot open a second line in the model's context. This hook then
# compared the sentinel against the RAW `cwd` off its own stdin. For any
# project whose path contains a line break the two hooks were therefore
# talking about different strings: what was emitted could never equal
# what was compared, and the legacy claim silently never fired.
#
# NOT A REGRESSION, AND SAID SO PLAINLY: before the fold existed that
# same path broke the injected line in two, so the model was never shown
# a usable value either. What was missing was that the fold's own list of
# costs did not name this consumer at all. Accepting BOTH spellings
# closes it without invalidating any sentinel already on disk - the raw
# comparison is tried first and is unchanged.
#
# THE FOLD IS RE-IMPLEMENTED HERE RATHER THAN SHARED. These are two
# separate POSIX sh programs that the harness runs as separate processes
# on different events; there is no library either can source, and this
# plugin ships no mechanism to make one. So the rule is duplicated, and
# it is duplicated VISIBLY, named after its origin, rather than hidden
# behind a helper that reads as if it were independent.
#
# THE RESIDUAL COLLISION, STATED RATHER THAN CLOSED: a path containing a
# literal space and a path containing a line break in the same position
# fold to the SAME string, so a legacy sentinel written by one is
# claimable by the other. It costs an off-switch binding between two
# sibling projects whose paths differ only by that byte, on the legacy
# tokenless path that every current /squirrel:off has already stopped
# writing. Narrowing it would mean not folding, which re-opens the
# forged-line hole the fold exists to close.
#
# THE CAP IS NOT MIRRORED, deliberately. load-profile.sh also caps the
# emitted value at 4096 bytes, so a cwd past that is emitted shortened
# and would not match here. That case is left alone because no real path
# reaches it - macOS PATH_MAX is 1024 and Linux's 4096 - and mirroring a
# cut here would mean this hook could claim a sentinel on a PREFIX of a
# path, which is a worse failure than not claiming one.
squash_one_break_local() {
  # squash_one_break_local <text> <delimiter>: <text> with every
  # occurrence of <delimiter> replaced by a single space. Deliberately
  # the same shape, and the same name-stem, as squash_one_break in
  # scripts/load-profile.sh: this must mirror that function, and a mirror
  # that is spelled differently is a mirror nobody can check.
  sobl_text=$1
  sobl_sep=$2
  sobl_out=""
  while :; do
    case "$sobl_text" in
      *"$sobl_sep"*)
        sobl_out="$sobl_out${sobl_text%%"$sobl_sep"*} "
        sobl_text=${sobl_text#*"$sobl_sep"}
        ;;
      *) break ;;
    esac
  done
  printf '%s%s' "$sobl_out" "$sobl_text"
}

fold_line_breaks() {
  # fold_line_breaks <text>: <text> with every LF and CR replaced by one
  # space - the same transformation scripts/load-profile.sh performs on
  # the value it emits, applied here to the value this hook compares.
  #
  # ONE DELIMITER PER PASS, TWO PASSES, IN THAT ORDER, because the
  # obvious single loop over both delimiters IS WRONG and the origin's
  # own comment says why: "a single pass that tried to handle two
  # delimiters would have to decide which comes first in the remaining
  # text, and getting that wrong drops bytes."
  #
  # This function was first written as that single loop and reproduced
  # the predicted defect exactly. On a CRLF value "A\r\nB" the LF arm
  # matches first and swallows the CR into the output, where nothing ever
  # revisits it: the result was "A\r B", CR intact, while load-profile.sh
  # emits "A  B". So the two hooks STILL disagreed on precisely the input
  # this function exists to reconcile - a fix whose own headline claim
  # was false for CRLF. Written the origin's way, they agree.
  flb_text=$1
  flb_text=$(squash_one_break_local "$flb_text" "$nl")
  flb_text=$(squash_one_break_local "$flb_text" "$cr")
  printf '%s' "$flb_text"
}

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
  # The folded spelling, tried only when the raw one did not match, so
  # the ordinary case is byte-identical to what it always was and costs
  # nothing extra. Guarded with `case` first for the same reason: a cwd
  # with no line break in it cannot fold to anything different, and most
  # have none.
  case "$cwd" in
    *"$nl"* | *"$cr"*)
      if [ "$SENTINEL_CONTENTS" = "$(fold_line_breaks "$cwd")" ]; then
        return 0
      fi
      ;;
  esac
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

  # THE CONTAINER GUARD (audit fix, LOW). checkpoints/ and profile-seen/
  # both refuse to be operated on through a symlink AT the directory
  # itself - see checkpoint_slug_dir_untrusted and prune_stale_profile_seen
  # in load-profile.sh, and component_walk_has_symlink's `[ -L "$base" ]`
  # in allow-checkpoint.sh. off/ had no such guard, so a symlink planted
  # there let every step below - the champion scans, both claims, and the
  # final flag read - operate inside whatever it pointed at: a sentinel
  # claimed through it, a file `mv`d into it, an `rm -f` aimed into it.
  #
  # off/ is created by /squirrel:off and /squirrel:on alone, so a symlink
  # AT it is never legitimate and returning early costs nothing correct.
  # This deliberately does NOT look above off/: a dotfile manager
  # symlinking ~/.squirrel itself is ordinary, supported, and left
  # working, exactly as the other two guards leave it - the trust
  # boundary is this directory, not its ancestry.
  #
  # `[ -L ]` is a POSIX shell builtin: no realpath, no readlink, no
  # external command, so this holds with an empty PATH like every other
  # symlink check in this plugin.
  if [ -L "$off_dir" ]; then
    printf ''
    return 0
  fi

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
