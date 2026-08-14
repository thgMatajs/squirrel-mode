#!/bin/sh
# load-profile.sh - SessionStart hook, and (P3) a second UserPromptSubmit
# hook for profile mtime reinjection.
#
# SessionStart (matcher in hooks.json: startup|resume|clear|compact):
# Emits hookSpecificOutput.additionalContext containing:
#   - the user's ~/.squirrel/profile.md, if it exists, with a
#     line stating its fields override the output style's defaults; or
#     a single short line suggesting /squirrel:init if it does not.
#   - a one-line migration notice if data from an install that predates
#     S11 still exists on disk - see "S11 migration notice" below for
#     the exact path checked.
#   - the literal `cwd` this hook was invoked with, as
#     "Session working directory: <cwd>" (ADR-0005, amended, cycle 3
#     BLOCKER fix: /squirrel:off and /squirrel:on need this exact string
#     to write as sentinel CONTENTS the check-off-flag.sh hook can later
#     match against ITS OWN `cwd` on the legacy tokenless path - a value
#     the model computes itself, e.g. by running a shell command, can
#     disagree with that even on a healthy machine (a symlinked project
#     path, a trailing slash, a different shell context), and the failure
#     is silent: the sentinel just never matches. This line is ALWAYS
#     emitted, even when `cwd` is empty, so the skill has a definite,
#     always-present "missing or empty" case to branch on - the same
#     discipline `/squirrel:pickup` already applies to the
#     checkpoint-path line below).
#   - an opaque session off-token, as "Session off-token: <token>"
#     (ADR-0005 Amendment P2): /squirrel:off and /squirrel:on name their
#     sentinels PENDING.<token> / CLEAR.<token>. The token is the
#     sanitised session_id when that value is valid, otherwise
#     anon-<random> - the same exclusivity rule session_checkpoint_name
#     uses. The skill copies this exact string into the filename; the
#     UserPromptSubmit hook recomputes the same value from the
#     session_id it receives on stdin and claims only PENDING.<that> /
#     CLEAR.<that>. Same value, two channels - the skill never invents a
#     token the hook cannot recompute. ALWAYS emitted.
#   - the RESOLVED, absolute checkpoint DIRECTORY for this project's
#     `cwd`, as "Project checkpoint directory: <dir>", AND the RESOLVED,
#     absolute checkpoint file this ONE session owns, as
#     "Project checkpoint path: <file>" (tech-lead Decision 1: the model
#     cannot compute the project-slug algorithm itself, so the paths are
#     handed to it, always, even before any checkpoint file exists).
#     Both lines are emitted, and they are not redundant: rule 14 writes
#     to the single file this session owns, and /squirrel:pickup reads
#     the whole directory and folds every session's file into one
#     answer. Neither consumer can derive the other's value without
#     re-implementing the slug algorithm, which is exactly what
#     Decision 1 forbids.
#   - the project's existing checkpoint files, newest first, as a BLOCK:
#     one header line,
#     "Project checkpoint files, newest first (session <token>):",
#     carrying the same off-token as the line above it, then one ABSOLUTE
#     path per line, at most CHECKPOINT_LIST_MAX_FILES of
#     them, the run of paths ending at the first line that does not begin
#     with "/". Emitted ONLY when there is at least one such file that
#     this hook could name - no header, no block, nothing, otherwise.
#     When the block does NOT name everything in that directory - the cap
#     was reached, or a real file's name fell outside the class - one
#     further line closes it,
#     "(more checkpoint files exist in that directory than are listed
#     here - session <token>)", carrying that same token and beginning
#     with "(" rather than "/" so it terminates the run of paths instead
#     of joining it. Its absence is a positive guarantee that the list is
#     whole; see checkpoint_file_lines for both grammars stated together.
#     The
#     token is in the header because the profile body quoted ABOVE this
#     block COULD otherwise spell any line it likes, forged header
#     included. A body line that begins with one of squirrel-mode's own
#     prefixes - this header's included - is now marked as profile text
#     before it reaches the model (see neutralise_forged_lines), and the
#     token stays exactly as load-bearing as it was, because that step
#     fails open; see checkpoint_file_lines for the reproduction and for
#     why a session token beats reordering. This is the same Decision 1
#     move applied one level further out: knowing the DIRECTORY is not
#     enough for /squirrel:pickup, which has to ENUMERATE it, and on a
#     harness that exposes no Glob or Grep tool (Read, Write, Edit and
#     Bash only - the shape verified while this was written) the sole
#     enumeration tool left is Bash. hooks.json's PreToolUse matcher is
#     Write|Edit|Read, so allow-checkpoint.sh can never auto-approve a
#     Bash call, and an ordinary pickup therefore cost a permission
#     prompt. Handing over the list makes Read on already-approved
#     checkpoint paths sufficient. See checkpoint_file_lines below for
#     the format's full grammar and for what `ls` is, and is not,
#     trusted for there.
#   - "Legacy checkpoint file: <path>" if, and only if, a pre-P1 flat
#     checkpoint file still exists for this project - see
#     "P1 PER-SESSION CHECKPOINT LAYOUT" below.
#   - "Resume available - run /squirrel:pickup" if a checkpoint already
#     exists for this project - never the checkpoint's own body text
#     (PLAN.md is explicit that the contents are not dumped into chat).
# It also prunes stale ~/.squirrel/off/<session_id> flag files
# (see check-off-flag.sh), stale per-session checkpoint files (see
# prune_stale_session_checkpoints) and stale
# ~/.squirrel/profile-seen/<session_id> stamps (see
# prune_stale_profile_seen) so none of the three accumulates forever.
# Both the pruning and the "Resume available" check REFUSE to act at all
# when ~/.squirrel/checkpoints or ~/.squirrel/checkpoints/<slug> is a
# symlink - see checkpoint_slug_dir_untrusted, which mirrors the
# write-side trust boundary allow-checkpoint.sh already enforces, and
# which deliberately still permits a symlinked ~/.squirrel itself
# (dotfile managers).
# After injecting a REAL profile body it touches
# ~/.squirrel/profile-seen/<sanitised-session-id> so later prompts know
# the baseline (P3). Sanitize failure skips that touch only - SessionStart
# JSON emission is unchanged.
#
# UserPromptSubmit (P3, second command alongside check-off-flag.sh):
# Does NOT re-run prune, migration notice, off-token, checkpoint path,
# checkpoint file list, or resume banner. Reads hook_event_name from
# stdin. When the event is UserPromptSubmit: if profile.md is absent,
# print nothing (no /init nag every prompt); if this session has no seen
# file yet, or its seen file
# is NOT strictly newer than profile.md, emit the SAME profile framing
# SessionStart uses for the body as PLAIN TEXT additionalContext (same
# stdout convention as check-off-flag.sh - not SessionStart JSON), then
# touch the seen file. Otherwise empty stdout. Sanitize failure skips
# seen tracking and reinjection (empty stdout). emit_json stays
# SessionStart-only.
#
# FORGED SESSION LINES IN THE QUOTED BODY, on BOTH paths above: the body
# is quoted with exactly one transformation. A line of it that BEGINS
# with one of the prefixes squirrel-mode uses for its own injected lines
# is emitted with "[profile] " in front of it, so it no longer begins
# with that prefix and cannot be read as squirrel-mode's own. Nothing is
# deleted, reordered or otherwise rewritten. Both paths get it because
# both put the body through cap_profile_body; see
# SQUIRREL_RESERVED_LINE_PREFIXES and neutralise_forged_lines below for
# the list, for why it lives there, and for the fail-open behaviour that
# makes the reading rules in skills/dig/SKILL.md and
# skills/pickup/SKILL.md a second layer rather than a redundant one.
#
# AN EXACT MTIME TIE REINJECTS - fixed MINOR, this cycle. The gate used
# to be `find "$profile_file" -newer "$seen_file"`, which is STRICTLY
# newer, so a profile.md and a seen stamp sharing an mtime silently
# meant the tune was never propagated to that session at all - not late,
# never. That is reachable without anything exotic: a filesystem with
# one-second mtime granularity, or a /squirrel:tune landing in the same
# second SessionStart touched the stamp. The gate is now the mirror
# image, "reinject unless the seen stamp is strictly newer than
# profile.md", so the tie falls the other way. The worst case that
# creates is ONE redundant reinjection of a profile the session already
# has, and it converges on the very next prompt, because touching the
# seen file afterwards makes it strictly newer. Losing a tune forever is
# not recoverable by the next prompt, or by any prompt; that asymmetry
# is the whole reason the tie was moved.
#
# S11 MIGRATION NOTICE: squirrel-mode's data directory migrated from
# ~/.claude/squirrel/ to ~/.squirrel/ (docs/adr/0003's Amendment (S11) -
# ~/.claude is a protected path Claude Code will not let a hook `allow`
# write into, which made ADR-0002's whole auto-approval mechanism
# impossible at the old location; see docs/adr/0002's Amendment (S11)
# for the experiment that established this). Anyone still on the old
# layout (a v0.1.x install) has a profile and checkpoints sitting at the
# old path this build no longer reads or writes. detect_old_data_dir
# below only DETECTS that and asks the model to TELL the user, once per
# session, in one line - it never moves, copies, or deletes anything
# itself. Silently `mv`-ing a user's own data at session start is
# exactly the kind of automatic action that goes wrong badly and cannot
# be undone (a partial move racing a concurrent session, a destination
# that already has its own newer profile.md and would be clobbered), so
# this hook only ever reports what it finds and leaves the decision, and
# the move itself, to the user. The notice re-appears every session for
# as long as the old directory exists - identical in spirit to how the
# "no profile found" line below re-appears every session until
# /squirrel:init actually creates one - and stops the moment the old
# directory is gone, with no separate "already told them" state to
# track or get out of sync.
#
# P1 PER-SESSION CHECKPOINT LAYOUT: checkpoints moved from one flat file
# per project, ~/.squirrel/checkpoints/<slug>.md, to one file per
# session inside a per-project directory,
# ~/.squirrel/checkpoints/<slug>/<session-id>.md. The defect this
# removes is concrete and was reproduced against the real hook: two
# sessions open in the same `cwd` were handed the SAME path, and two
# interleaved whole-file read-modify-write cycles on it lose an entry
# from the Done log - the second writer's copy was read before the first
# writer's append landed. Giving every session a file no other session
# writes removes the shared mutable cell entirely; nothing has to lock,
# retry, or merge at write time. The cost is paid at READ time instead,
# where it is safe: /squirrel:pickup folds the directory by mtime.
#
# The `<slug>/` directory is NEVER created by this hook. It is created
# implicitly by the first Write the model performs into it (the Write
# tool creates missing parents). This hook only ever reads, so a
# permissions problem or a read-only $HOME cannot turn into a failed
# session start.
#
# LEGACY FLAT FILE: an install that predates P1 has real work sitting in
# ~/.squirrel/checkpoints/<slug>.md. This hook emits its path as
# "Legacy checkpoint file:" whenever it still exists, and
# /squirrel:pickup folds it in on read, oldest, with a one-line warning.
# It is never moved, rewritten, or deleted - not by this hook and not by
# the skill. Folding on read (rather than only detecting and telling, as
# the S11 data-directory migration above deliberately does) is
# defensible here precisely because these are the plugin's OWN files in
# the plugin's OWN directory, written by rule 14 in a format this plugin
# defines - not the user's documents, and not a directory the user is
# expected to have curated. Reading one of them costs nothing and cannot
# be wrong; moving one could be.
#
# Contract: this hook must NEVER exit non-zero. On SessionStart (or when
# hook_event_name is missing/other) it must always print one well-formed
# SessionStart JSON object on stdout for every command FAILURE it depends
# on, and for every broken / bare / missing ~/.squirrel/ layout a fresh
# install can present (nothing under ~/.squirrel/ at all is the common
# case on turn one, not an edge case). On UserPromptSubmit it prints
# plain text or nothing - never SessionStart JSON. Audited under a
# scratch HOME (P4 item 2): bad HOME shapes, unreadable or non-file
# profile.md, malformed / empty / closed-as-/dev/null stdin, jq absent,
# jq exiting non-zero, jq exiting 0 with the literal `null` or with no
# output, a non-empty object that is not a SessionStart payload,
# one-at-a-time absence of cksum/od/cut/wc/tail/basename/tr/find/awk/sed,
# locales C and pt_BR.UTF-8, and C0 / invalid-UTF-8 profile bodies all
# return exit 0 with a parseable SessionStart object on the SessionStart
# path (the jq-null and jq-empty cases used to print `null` / a blank
# line and are closed in emit_json below; the non-SessionStart-object
# case used to be emitted verbatim and is closed by the same function's
# hookEventName check; the rest already held).
#
# `set -e` vs. "never exit non-zero": `set -e` stays ON for the whole
# script, including inside build_context() below, so a bug fails fast
# during development instead of limping on silently with half-built
# state. What guarantees the PROCESS itself always exits 0 is that
# every fallible step is either (a) explicitly guarded with its own
# `if`/`||` (both of which are exempt from `set -e` by POSIX definition
# - see tests/lib/assert.sh's own note on this same pattern), or (b)
# wrapped at the call site the same way. build_context is called via
# `if context=$(build_context ...); then ... else ... fi` at the
# bottom of this file: if ANYTHING inside it fails unexpectedly despite
# those inner guards, `set -e` aborts build_context() at that exact
# point (and only that function, per POSIX function semantics) and
# control returns to the `if`, which supplies a safe fallback context
# instead of ever propagating a non-zero exit out of this script.
#
# WHAT THE CONTRACT DOES NOT COVER (P4 item 2, audit) - the same two
# never-returns gaps allow-checkpoint.sh and check-off-flag.sh already
# disclose, reproduced against this script too:
#
#   1. A `jq` PRESENT on PATH but WEDGED - stopped, deadlocked, never
#      returns. The `if json_out=$(emit_json ...)` / `if context=$(
#      build_context ...)` wrappers catch FAILING; they cannot catch
#      never FINISHING. No POSIX `sh` construct interrupts a command
#      substitution already in flight, and `timeout(1)` is GNU
#      coreutils, absent from stock macOS. NOT closable here;
#      reaffirmed. Bounded only by the harness's own hook timeout.
#
#   2. A CLOSED fd 0 - stdin not an open descriptor at all, as distinct
#      from empty or /dev/null. `input=$(cat)` in build_context() then
#      hangs forever: `$(...)` builds its capture pipe on the lowest
#      free file descriptor, which with fd 0 closed IS fd 0, so `cat`
#      reads the very pipe the substitution's own subshell writes to
#      and EOF never arrives. Closable with `if ! ( exec 3<&0 )
#      2>/dev/null; then exec 0</dev/null; fi` ahead of the first
#      command substitution (probe in a SUBSHELL so a failed `exec`
#      redirection cannot exit this hook non-zero). Deliberately NOT
#      applied here: it is a behaviour change to the entry path of all
#      three hooks and belongs in one coordinated change across them,
#      not a one-hook patch. Documented so the limit stays honest.
#
# jq dependency: PREFERRED, not required. jq is used when present on
# PATH (correct JSON construction and field extraction, including
# proper escaping) but every jq call has an awk fallback so a machine
# without jq installed still gets correct behaviour, just via a
# narrower (byte-oriented in both directions - see
# extract_top_level_string's own list of what its scanner does not
# cover) parser. See extract_field() and emit_json() below. The escaping
# fallback (json_escape) runs entirely under `LC_ALL=C` so the result
# does not depend on the invoking shell's locale - see json_escape's
# own comment for why that matters even when jq IS present elsewhere
# in this file. emit_json additionally treats a jq that exits 0 but
# prints nothing, the literal `null`, or a non-empty object that is
# not a SessionStart payload (wrong/missing hookEventName) as a
# FAILURE of the jq path and falls through to the awk emitter - the
# null/empty shapes allow-checkpoint.sh already enumerates for its own
# jq calls, plus the object-shape check that closes trusting any `{...}`.
set -eu

# A CDPATH entry containing "." makes the `cd` below ECHO its resolved
# path to stdout as well as changing directory, which would corrupt the
# command substitution with an extra line. Unset unconditionally, before
# any `cd` in this file runs. (scripts/build.sh and every test file open
# the same way, for the same reason.)
unset CDPATH

# THIS SCRIPT'S OWN DIRECTORY, resolved once, here, rather than inside
# build_context: a failed `cd` under `set -eu` would abort the caller,
# and build_context's contract is that every fallible step in it is
# guarded at the call site. Guarded the same way here - `|| script_dir=""`
# is exempt from `set -e`, so an unresolvable $0 (a deleted or unreadable
# directory) leaves this empty and costs the session nothing.
#
# It exists for ONE consumer: the "Hoard search command:" line
# build_context injects, so /squirrel:dig can run scripts/hoard-search.sh
# through the Bash tool. A Bash call a model makes does NOT inherit the
# plugin-root variable this hook process is given, and the plugin's
# install path is not knowable when the skill is written, so the path has
# to be handed over at session start the way the checkpoint paths already
# are. Deriving it from $0 rather than from that variable also means the
# injected path can never disagree with where this script actually lives.
script_dir=$(cd "$(dirname "$0")" && pwd) || script_dir=""

# --- JSON field extraction ------------------------------------------
#
# extract_top_level_string <json> <key>: prints the value of the STRING
# field named <key> that sits at DEPTH 1 - directly inside the payload's
# own outermost object - and prints nothing at all when there is no such
# field. This is the no-jq path for extract_field below.
#
# DUPLICATED, DELIBERATELY, between scripts/load-profile.sh and
# scripts/check-off-flag.sh, exactly as sanitize_session_id already is
# and for the identical reason: this project forbids `source`/`.`
# between shipped scripts, so each hook must be a single self-contained
# file that runs correctly no matter what else is or is not installed
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
# check-off-flag.sh read sessionAAA, claim another session's
# off/PENDING.sessionAAA sentinel, and print the counter-instruction -
# while session A's own /squirrel:off silently never took effect. The
# same payload shape aimed at `hook_event_name` misroutes THIS script
# between its SessionStart and UserPromptSubmit contracts. Claude Code's
# real payloads are flat, so neither was reachable in production; both
# files nevertheless advertise "jq: preferred, not required", which is
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
# (10 KB 25 ms, 100 KB 408 ms, 500 KB 8889 ms). Measured after the
# rewrite, same machine: 500 KB 40 ms, 2 MB 91 ms, 20 000 levels of
# nesting 109 ms, and a deliberately pathological 1 MB payload of 50 000
# separate top-level keys 1.7 s. Those are machine-specific figures, not
# a portable performance guarantee - the point they support is that the
# cost no longer grows with the SQUARE of an input this hook does not
# control. This path only runs at all when jq is absent, or when jq is
# present and reports the field genuinely missing.
#
# Run entirely under `LC_ALL=C`, for the reason json_escape's own
# comment sets out at length: BSD tools abort mid-stream on a byte that
# is not valid UTF-8 under a UTF-8 locale (this machine's real LANG is
# pt_BR.UTF-8), and `LC_ALL=C` makes `length`/`substr`/`split` here
# genuinely byte-indexed so an invalid byte simply passes through
# instead. The key is handed over through the ENVIRONMENT rather than
# `awk -v`, because POSIX awk re-processes backslash escapes in a `-v`
# assignment (the same trap tests/test_hooks.sh's own line_of helper
# documents).
#
# WHAT IT DOES NOT DO - the residual limits, stated rather than implied:
#   - `\uXXXX` inside a VALUE is left in the output literally, as the
#     six bytes `\u` plus four hex digits, not decoded to a character.
#     Decoding it means UTF-8 re-encoding and surrogate pairing in awk,
#     which is a great deal of machinery for a shape none of the three
#     keys this is ever called for (`session_id`, `cwd`,
#     `hook_event_name`) carries in practice. The failure direction is
#     closed, not open: sanitize_session_id rejects a backslash
#     outright, and a `cwd` carrying a literal `\u` simply fails
#     check-off-flag.sh's byte-for-byte comparison against a sentinel's
#     contents, so a mangled value can only ever produce "no match",
#     never a wrong match. The two-character escapes JSON defines - \"
#     \\ \/ \b \f \n \r \t - ARE decoded.
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
#     found" instead of failing the hook - see the Contract paragraph in
#     this file's header, which claims exactly that for one-at-a-time
#     tool absence.
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

# --- Project slug (tech-lead Decision 1 support) ---------------------
#
# ALGORITHM: `<sanitized-basename>-<hash-of-full-path>`.
#   1. Take the basename of `cwd` for human readability, and replace
#      every byte outside [A-Za-z0-9._-] with "-" (filesystem-safe on
#      every target OS this plugin ships to).
#   2. Append a hash of the FULL `cwd` string (not just the basename).
#      This is what makes it collision-resistant: two different
#      directories that happen to share a basename ("myapp" checked out
#      twice under different parents) hash their distinct full paths to
#      different values, so they land at different checkpoint files.
#      A bare `basename` alone cannot do this - it is explicitly what
#      the spec forbids.
#   3. The hash prefers `cksum` (POSIX-adjacent, shipped by default on
#      both macOS and Linux) for simplicity; if it is ever missing, a
#      pure POSIX awk/od fallback (a base-31 rolling hash over the raw
#      bytes, reduced modulo a large prime) keeps the algorithm working
#      with zero additional dependencies. Neither path needs to be
#      cryptographically strong - it only needs to make two DIFFERENT
#      inputs land on different outputs with overwhelming probability,
#      which a 32-bit CRC (or the awk fallback's ~30-bit reduction)
#      comfortably provides for the number of directories a single
#      developer will ever have open.
#   DETERMINISM: both hash paths are pure functions of the input bytes
#   - same `cwd` in, same digits out, every time, on the same machine.
compute_hash() {
  str=$1
  if command -v cksum >/dev/null 2>&1; then
    printf '%s' "$str" | cksum | awk '{print $1}'
  else
    printf '%s' "$str" | od -An -v -tu1 | awk '
      { for (i = 1; i <= NF; i++) { h = (h * 31 + $i) % 1000000007 } }
      END { printf "%d", h }
    '
  fi
}

# --- Per-session checkpoint file name --------------------------------
#
# sanitize_session_id <raw>: DUPLICATED, DELIBERATELY, from
# scripts/check-off-flag.sh's function of the same name - same accepted
# character class ([A-Za-z0-9_-] only, which by construction excludes
# "/" and "." and therefore ".." and every path-separator traversal),
# same non-empty requirement, same 128-byte upper bound. It is copied
# rather than shared because this project forbids `source`/`.` between
# shipped scripts: each hook must be a single self-contained file that
# runs correctly no matter what else is or is not installed alongside
# it, and a sourced library turns one missing or half-written file into
# a broken session start for every hook at once. The two copies are
# small, closed, and have no state; if one changes, the other must be
# changed to match - that is the price of the isolation, and it is
# stated here rather than left to be discovered.
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

# random_suffix: prints a short token drawn from the best source of
# randomness available, following the same `command -v` probing idiom
# compute_hash above uses for its hash. The chain, most to least
# preferred:
#   1. 8 bytes of /dev/urandom decoded by `od` - present on every OS
#      this plugin ships to, and the only link in the chain whose output
#      does not depend on the clock.
#   2. POSIX awk: `srand()` with no argument seeds from the time of day,
#      mixed with this process's own pid. Neither alone is enough - two
#      sessions starting inside the same second share the awk seed, and
#      pids are reused - but the pair collides only when two sessions
#      start in the same second AND land on the same pid.
#   3. The bare pid. Guaranteed to exist, guaranteed to be weak; it is
#      here so this function has no failure case at all, not because it
#      is good.
# The result is filtered through the same character class
# sanitize_session_id accepts, so whatever the chain produces can only
# ever be a safe single path component.
random_suffix() {
  suffix=""
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    suffix=$(od -An -v -N 8 -tx1 </dev/urandom 2>/dev/null | tr -d ' \n') || suffix=""
  fi
  if [ -z "$suffix" ]; then
    suffix=$(awk -v pid="$$" 'BEGIN { srand(); printf "%x%x", pid, int(rand() * 2147483647) }' 2>/dev/null) || suffix=""
  fi
  if [ -z "$suffix" ]; then
    suffix=$$
  fi
  printf '%s' "$suffix" | tr -c 'A-Za-z0-9_-' '-'
}

# session_checkpoint_name <raw_session_id>: the BASENAME of the file
# this one session owns inside its project's checkpoint directory.
#
# When `session_id` is present and survives sanitisation, the name is
# "<session-id>.md" - stable for the whole session, so the same session
# resuming, clearing, or compacting keeps writing the same file.
#
# When `session_id` is missing or fails sanitisation, the name is
# "anon-<random>.md". A FIXED name such as "anon.md" would reinstate,
# for exactly the sessions whose identity is unknown, the shared mutable
# cell this whole change exists to remove. The random name is exclusive
# in practice because the only place it is ever written down is the
# context injected into this one session; no other session can be handed
# it, so no other session can write it. The cost is one extra file per
# anonymous session, which the pruner below bounds.
session_checkpoint_name() {
  raw=$1
  if name=$(sanitize_session_id "$raw"); then
    printf '%s.md' "$name"
    return 0
  fi
  suffix=$(random_suffix) || suffix=""
  [ -n "$suffix" ] || suffix=$$
  printf 'anon-%s.md' "$suffix"
  return 0
}

# session_off_token <raw_session_id>: the opaque token /squirrel:off and
# /squirrel:on embed in PENDING.<token> / CLEAR.<token> filenames
# (ADR-0005 Amendment P2). Same sanitise-or-anon rule as
# session_checkpoint_name, without the ".md" suffix: when session_id
# survives sanitisation the token IS that sanitised value, so
# check-off-flag.sh - which receives session_id on UserPromptSubmit
# stdin and sanitises it the same way - recomputes the identical string
# and claims only PENDING.<that> / CLEAR.<that>. When session_id is
# missing or fails sanitisation the token is anon-<random>, exclusive
# to the SessionStart context of this one session; UserPromptSubmit
# still cannot bind an off flag without a valid session_id (sanitize
# failure leaves every sentinel untouched, as before), so an anon off
# token is documentation-and-exclusivity only, not a second claiming
# channel the hook can recompute.
session_off_token() {
  raw=$1
  if name=$(sanitize_session_id "$raw"); then
    printf '%s' "$name"
    return 0
  fi
  suffix=$(random_suffix) || suffix=""
  [ -n "$suffix" ] || suffix=$$
  printf 'anon-%s' "$suffix"
  return 0
}

project_slug() {
  cwd_in=$1
  base=$(basename "$cwd_in" 2>/dev/null) || base=""
  [ -n "$base" ] || base="root"
  safe_base=$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '-')
  [ -n "$safe_base" ] || safe_base="root"
  hash=$(compute_hash "$cwd_in")
  [ -n "$hash" ] || hash="0"
  printf '%s-%s' "$safe_base" "$hash"
}

# --- Stale off-flag pruning ------------------------------------------
#
# ADR-0005: `/squirrel:off` writes ~/.squirrel/off/<session_id>
# and flags accumulate over time (sessions end without ever running
# `/squirrel:on`). "Stale" here means older than 7 days - a
# deliberately generous cushion so no realistically long-lived session
# ever has its own still-active flag pruned out from under it. Never
# allowed to fail the hook: guarded to a no-op when the directory does
# not exist, and the `find` itself is `|| true`-guarded in case of a
# permissions problem on one stray file.
prune_stale_off_flags() {
  off_dir=$1
  [ -d "$off_dir" ] || return 0
  find "$off_dir" -type f -mtime +7 -exec rm -f -- {} + >/dev/null 2>&1 || true
  return 0
}

# --- Stale profile-seen stamp pruning ----------------------------------
#
# P3 added a THIRD per-session directory,
# ~/.squirrel/profile-seen/<sanitised-session-id>, and shipped no pruning
# for it, so it grew by one empty file per session forever (19 files
# accumulated in a single afternoon of testing). This closes that, in the
# same posture as the two pruners above: a no-op when the directory is
# absent, every fallible step guarded, and no path through it can fail
# the hook.
#
# WHY AGE ALONE IS SAFE HERE, when it explicitly is NOT for checkpoints.
# prune_stale_session_checkpoints goes to considerable trouble to avoid a
# pure "older than N days" rule, because a checkpoint's whole purpose is
# to still be there after a long interruption and deleting one loses work
# the user cannot get back. A profile-seen stamp is the opposite kind of
# thing: it is derived, per-session bookkeeping that answers exactly one
# question - "has THIS session already been shown the current
# profile.md?" - and it is worthless the moment that session ends. It is
# therefore much closer to an off-flag than to a checkpoint, and it gets
# the off-flag's rule and threshold: `find ... -mtime +7 -exec rm -f`,
# same idiom, same 7-day cushion so no realistically long-lived session
# has its own still-live stamp pruned out from under it. The worst case
# if this ever deletes a stamp too early is ONE redundant reinjection of
# a profile that session already has, which converges on the very next
# prompt (touching the stamp afterwards makes it strictly newer) - the
# exact failure mode the "AN EXACT MTIME TIE REINJECTS" fix in this
# file's header already chose deliberately, for the same reason.
#
# THE SYMLINK GUARD IS NOT DECORATION. `[ -d ]` follows symlinks, which
# is precisely how the checkpoint pruner came to delete a user's own
# files through a symlinked slug directory (see the FIXED MAJOR note on
# prune_stale_session_checkpoints). The `[ -L ]` test below states the
# boundary explicitly rather than leaving it to `find`'s own default:
# profile-seen/ is created by this script alone (touch_profile_seen), so
# a symlink AT it is never legitimate and nothing behind one gets
# touched. A dotfile-managed symlink at ~/.squirrel ITSELF is unaffected
# and still works, exactly as it does for the other two pruners - this
# never looks above its own directory. Belt and braces, and deliberately
# so: POSIX `find` does not follow a symbolic link given as an OPERAND
# either (no -H, no -L, no trailing slash - the same property verified on
# this machine for prune_stale_off_flags above), so the `[ -L ]` here is
# the second of two independent reasons this cannot delete through a
# symlink, not the only one. It is stated in the code because a boundary
# that depends solely on a tool's default flag is one refactor away from
# being gone.
# The parameter is deliberately NOT named `seen_dir`: POSIX sh has no
# function-local scope, and touch_profile_seen below uses `seen_dir` for
# its own copy of this same path. Distinct names keep the two from ever
# writing over each other if either is later called from somewhere new.
prune_stale_profile_seen() {
  profile_seen_dir=$1
  [ -d "$profile_seen_dir" ] || return 0
  if [ -L "$profile_seen_dir" ]; then
    return 0
  fi
  find "$profile_seen_dir" -type f -mtime +7 -exec rm -f -- {} + >/dev/null 2>&1 || true
  return 0
}

# --- Stale per-session checkpoint pruning ------------------------------
#
# One file per session accumulates without bound (see "P1 PER-SESSION
# CHECKPOINT LAYOUT" in the header). Pruning them is NOT the same
# problem as pruning off-flags above, and the thresholds are
# deliberately not the same: an off-flag is a scrap of session state
# that is worthless the moment its session ends, whereas a checkpoint's
# entire purpose is to still be there after a long interruption. Age
# ALONE is therefore a time bomb aimed at exactly the wrong data - a
# project picked up again after four months is the case this feature
# exists for, and a pure "older than N days" rule deletes precisely
# that project's memory.
#
# The rule, within ONE slug's directory, DEPTH-1 ONLY: delete a file
# only if it is BOTH older than 30 days AND not among the 10 most
# recently modified DIRECT CHILDREN of that slug. The second clause is
# what makes the first safe: no matter how long a project lies
# untouched, its ten newest checkpoints always survive, so "resume
# after a long gap" never comes back empty.
#
# Depth-1 is load-bearing. allow-checkpoint.sh still auto-allows writes
# nested deeper than the shipped layout (scenario 14deep: the boundary
# is containment in checkpoints/, not a fixed depth), so a
# junk/deep/ tree of fresh files can appear under a slug without anyone
# noticing. A recursive `find "$slug_dir" -type f` would let those deep
# files outrank a lone >30-day session file sitting as a direct child
# and delete it - exactly the wrong data. Ranking and candidacy both
# use `"$slug_dir"/*` only.
#
# "Among the 10 most recently modified" is decided with `find -newer`
# against each peer FILE (a file path never recurses) - the only
# portable way to compare two files' mtimes in POSIX sh (there is no
# portable `stat`) - the same idiom check-off-flag.sh uses to pick the
# newer of two sentinels. A file is deleted when at least 10 OTHER
# direct-child files are strictly newer than it. An exact mtime tie
# counts as "not newer", so a tie keeps the file.
#
# Deleting inside the same pass only ever makes the count SMALLER for
# candidates examined later, i.e. only ever makes this function more
# conservative than a two-pass version; a file spared for that reason is
# simply reconsidered next session.
#
# CHECKPOINT_PRUNE_MAX_CANDIDATES bounds the work per invocation. The
# scan is O(candidates x files), and this runs on session start, so a
# directory that accumulated hundreds of files during a period when this
# pruner did not exist must not turn into a multi-second stall on turn
# one. Pruning is best-effort and converges over sessions; being slow is
# a worse failure here than being late.
#
# Follows prune_stale_off_flags' posture exactly: a no-op when the
# directory is absent, every fallible step guarded, and no path through
# it can fail the hook.
#
# FIXED MAJOR (this cycle) - the pruner deleted the user's own files
# through a symlinked slug directory. `[ -d "$slug_dir" ]` FOLLOWS
# symlinks, so with ~/.squirrel/checkpoints/<slug> pointing at any other
# directory, the globs below enumerated THAT directory's real files and
# `rm -f`-ed the ones the age-and-rank rule selected. Reproduced against
# the real hook: twelve files in an unrelated directory, one of them
# back-dated, one SessionStart, and the back-dated file was gone. The
# `[ ! -L ]` guards already on the candidate and peer loops could not
# see this: they reject a symlinked ENTRY, not a symlinked CONTAINER.
# checkpoint_slug_dir_untrusted below is the fix, and it is applied to
# checkpoint_dir_has_any too - the identical `[ -d ]` follows the
# identical symlink there and made "Resume available" fire on a stranger's
# files (also reproduced).
#
# prune_stale_off_flags above was audited for the same mistake and is
# genuinely NOT affected, so it is deliberately left alone rather than
# "hardened" to look symmetrical: its `[ -d "$off_dir" ]` follows a
# symlink exactly the same way, but the deletion is done by
# `find "$off_dir" -type f`, and POSIX find does not follow a symbolic
# link given as an OPERAND unless -H or -L is passed (there is no
# trailing slash on that path to change this). Verified on this machine:
# with ~/.squirrel/off symlinked at a directory holding a back-dated
# file, the file survived, and the same `find` re-run with a trailing
# slash appended DID list it - so the guard is find's own default, not
# an accident of the fixture.
CHECKPOINT_PRUNE_MIN_AGE_DAYS=30
CHECKPOINT_PRUNE_KEEP_NEWEST=10
CHECKPOINT_PRUNE_MAX_CANDIDATES=100

# CHECKPOINT_LIST_MAX_FILES: how many checkpoint paths the injected
# "Project checkpoint files, newest first (session <token>):" block
# (checkpoint_file_lines, below) may name in one session's context.
#
# WHY THIS NUMBER. It is CHECKPOINT_PRUNE_KEEP_NEWEST, and it is written
# as that name rather than as a second literal 10 because the two are the
# same number for a reason and must not drift apart. The pruner above
# guarantees that the N most recently modified direct children of a slug
# directory always survive, whatever else it deletes. N is therefore
# exactly the count that is both safe - every path this hook names is one
# the pruner is committed to keeping, so the model is never handed a path
# that the next session start will delete - and sufficient - listing
# fewer would hide memory the pruner deliberately preserves.
#
# WHY A CAP AT ALL. This block goes into EVERY session start, and "the
# pruner bounds the directory" is not on its own a bound: the pruner only
# deletes a file that is ALSO older than CHECKPOINT_PRUNE_MIN_AGE_DAYS,
# so a developer with thirty sessions open this month legitimately has
# thirty files there and none of them is a deletion candidate. Uncapped,
# that is thirty absolute paths injected into every session start.
CHECKPOINT_LIST_MAX_FILES=$CHECKPOINT_PRUNE_KEEP_NEWEST

# CHECKPOINT_LIST_CHUNK: the largest number of operands checkpoint_file_lines
# will hand a single `ls` call.
#
# FIXED MEDIUM (audit): past roughly ten thousand checkpoint files the
# `ls -td -- "$@"` in that function died with E2BIG ("Argument list too
# long", `ls exit=127` through the shell), and because the retry loop
# there correctly declines to keep a FAILING `ls`'s partial, possibly
# mis-ordered output, the whole block vanished. Reproduced with 10 000
# real files: 20.6 s at SessionStart, "Resume available - run
# /squirrel:pickup" still injected, and no list block at all - so
# /squirrel:pickup fell back to enumerating the directory itself, which
# is exactly the permission prompt this block exists to remove.
#
# The fix is a reduction pass, not a bigger buffer: the block only ever
# names CHECKPOINT_LIST_MAX_FILES files, so the operand list is reduced
# in rounds - each round slices the candidates into chunks of at most
# CHECKPOINT_LIST_CHUNK, sorts each chunk on its own, and keeps only that
# chunk's newest CHECKPOINT_LIST_MAX_FILES - until what is left fits in
# one call. That is a tournament, and it is exactly correct for "the
# newest K overall": any file in the global newest K is also in its own
# chunk's newest K, because its chunk holds at most K of them. 10 000
# candidates become 20 chunks, 200 finalists, one final sorted call.
#
# 500 is chosen to be an order of magnitude below the smallest ARG_MAX
# this plugin could meet while still collapsing any realistic directory
# in a single round. The whole pass is SKIPPED when there are no more
# candidates than this, so every ordinary directory - and every existing
# scenario in tests/test_hooks.sh - reaches the same single `ls` call it
# always did, byte for byte.
CHECKPOINT_LIST_CHUNK=500

# checkpoint_slug_dir_untrusted <slug_dir>: returns 0 (true) when
# <slug_dir> must NOT be pruned or read as resume data, because either
# it or the checkpoints/ directory it sits in is a SYMLINK. `[ -L ]` is
# a POSIX shell builtin - no realpath, no readlink, no external command
# of any kind - so this holds with an empty PATH, the same property
# allow-checkpoint.sh's component_walk_has_symlink relies on.
#
# THE TRUST BOUNDARY IS THE SAME ONE, MIRRORED ONTO THE READ SIDE. See
# "WHERE THE TRUST BOUNDARY SITS, DELIBERATELY" in
# scripts/allow-checkpoint.sh for the argument in full; the short form:
#   - checkpoints/ and checkpoints/<slug>/ are created by this plugin
#     alone, and allow-checkpoint.sh already DEFERS every write that
#     goes through a symlink at or below checkpoints/. Nothing correct
#     can have written through one, so a symlink AT either of those two
#     places is never legitimate and this refuses to touch what is
#     behind it.
#   - ~/.squirrel ITSELF, by contrast, is ordinary user configuration
#     that dotfile managers (chezmoi, stow, yadm) routinely symlink into
#     a dotfiles repo. That is a supported setup, not an attack, and
#     this function never looks that far up - exactly as the write-side
#     walk never inspects anything above checkpoints_dir. See
#     tests/test_hooks.sh scenario 31 for the write-side regression
#     guard and 6g7c for the read-side one.
#
# The parent is taken LEXICALLY, with `${slug_dir%/*}`, and that is
# exactly checkpoints_dir at both call sites rather than approximately:
# build_context builds <slug_dir> as "$checkpoints_dir/$slug", and
# project_slug puts its output through `tr -c 'A-Za-z0-9._-' '-'` plus a
# numeric hash, a character class that cannot contain "/". So there is
# always exactly one "/" between the two, and no filesystem access is
# needed to find it.
checkpoint_slug_dir_untrusted() {
  candidate_slug_dir=$1
  if [ -L "$candidate_slug_dir" ]; then
    return 0
  fi
  parent_checkpoints_dir=${candidate_slug_dir%/*}
  if [ -n "$parent_checkpoints_dir" ] && [ "$parent_checkpoints_dir" != "$candidate_slug_dir" ]; then
    if [ -L "$parent_checkpoints_dir" ]; then
      return 0
    fi
  fi
  return 1
}

prune_stale_session_checkpoints() {
  slug_dir=$1
  [ -d "$slug_dir" ] || return 0
  if checkpoint_slug_dir_untrusted "$slug_dir"; then
    return 0
  fi

  examined=0
  # Pathname expansion is ON for the for-lists below (portable depth-1).
  # Session file names are sanitised to [A-Za-z0-9._-]+, so a literal
  # "*" or "?" cannot appear in a real candidate name and re-expand.
  for candidate in "$slug_dir"/*; do
    # Regular file only: [ -f ] follows symlinks, so require [ ! -L ]
    # too (same trust boundary as checkpoint_dir_has_any). A depth-1
    # symlink to a regular file must neither be pruned as a candidate
    # nor inflate newer_count and delete a real ancient session file.
    if [ ! -f "$candidate" ] || [ -L "$candidate" ]; then
      continue
    fi
    # Age gate on this single file: find given a file path does not
    # recurse. Empty output means "not old enough" (or find failed).
    candidate_old=$(find "$candidate" -mtime "+$CHECKPOINT_PRUNE_MIN_AGE_DAYS" 2>/dev/null) || candidate_old=""
    [ -n "$candidate_old" ] || continue

    examined=$((examined + 1))
    if [ "$examined" -gt "$CHECKPOINT_PRUNE_MAX_CANDIDATES" ]; then
      break
    fi

    newer_count=0
    for peer in "$slug_dir"/*; do
      if [ ! -f "$peer" ] || [ -L "$peer" ]; then
        continue
      fi
      peer_newer=$(find "$peer" -newer "$candidate" 2>/dev/null) || peer_newer=""
      if [ -n "$peer_newer" ]; then
        newer_count=$((newer_count + 1))
      fi
    done
    case "$newer_count" in
      '' | *[!0-9]*) newer_count=0 ;;
    esac
    if [ "$newer_count" -ge "$CHECKPOINT_PRUNE_KEEP_NEWEST" ]; then
      rm -f -- "$candidate" >/dev/null 2>&1 || true
    fi
  done
  return 0
}

# checkpoint_dir_has_any <dir>: true when <dir> holds at least one
# regular file that is not a symlink, AND <dir> is itself a directory
# this plugin is willing to read (see checkpoint_slug_dir_untrusted).
# This is what drives the "Resume available" line now that a project's
# memory lives in a directory rather than in one file. A dangling
# symlink is not a regular file and correctly does not count; a symlink
# to a regular file is also rejected - only the plugin writes real
# checkpoint files here, so a symlink is never legitimate resume data
# (same trust boundary allow-checkpoint.sh enforces on the write path).
#
# FIXED (this cycle, alongside the pruner's MAJOR): `[ -d "$dir" ]`
# follows symlinks, so a symlinked <slug> directory used to make the
# per-entry `[ ! -L ]` test below run against a STRANGER'S regular
# files and report "Resume available" for them. Reproduced against the
# real hook with a slug directory symlinked at an unrelated folder
# holding one ordinary .md file. The per-entry guard could not catch it
# - it rejects a symlinked entry, not a symlinked container.
checkpoint_dir_has_any() {
  dir=$1
  [ -d "$dir" ] || return 1
  if checkpoint_slug_dir_untrusted "$dir"; then
    return 1
  fi
  for entry in "$dir"/*; do
    if [ -f "$entry" ] && [ ! -L "$entry" ]; then
      return 0
    fi
  done
  return 1
}

# --- The injected checkpoint file list --------------------------------
#
# checkpoint_list_candidates <slug_dir>: pass 1 of checkpoint_file_lines,
# and its ONLY caller. Prints, in directory-glob order:
#
#   zero or more ABSOLUTE paths, one per line - the entries eligible to
#   be named in the injected block;
#   then exactly ONE final line, "0" or "1" - whether an entry that IS
#   this project's memory was rejected anyway, which is one of the two
#   things that raise the incompleteness marker.
#
# A stream rather than two variables because the caller captures this
# with `$( )` and a subshell cannot hand a variable back; a path line
# always begins with "/", so the flag line is never mistaken for one.
#
# WHY A SEPARATE FUNCTION AT ALL, given it has one caller: bash 3.2 -
# /bin/sh on macOS, and therefore what this file's shebang selects there
# - cannot parse a `case` inside `$( )`. See "WHY A SEPARATE FUNCTION" in
# checkpoint_file_lines' header for the reproduction.
#
# TWO TESTS, DELIBERATELY DIFFERENT IN KIND:
#   - The NAME must lie within [A-Za-z0-9._-], the class
#     session_checkpoint_name produces via sanitize_session_id. This is a
#     COLLATION range and therefore locale-dependent, which is why this
#     function is only ever called from inside checkpoint_file_lines'
#     LC_ALL=C subshell - see "WHY THE BODY RUNS UNDER LC_ALL=C" there.
#   - The PATH must be a regular file that is not a symlink, the same
#     `[ -f ] && [ ! -L ]` trust boundary checkpoint_dir_has_any and
#     prune_stale_session_checkpoints already enforce.
#
# The flag is raised only where those two DISAGREE - name rejected, file
# test passed - because that is exactly the case where this hook reports
# "Resume available" for a file it will not name. A subdirectory, a FIFO,
# a symlink, and the unmatched-glob literal "<slug_dir>/*" all fail the
# file test, are none of them memory, and so raise nothing: a marker for
# any of those would cost the user a permission prompt for nothing.
#
# The `-eq 0` guard in front of the flag is not decoration. It
# short-circuits the two extra stat calls away for every further rejected
# entry once the flag is already set, so a directory full of
# non-conforming names costs at most one of them.
#
# The glob is newline-safe where `ls` output is not: the shell hands back
# one word per directory entry however that entry is spelled.
checkpoint_list_candidates() {
  clc_dir=$1
  clc_omitted=0
  for clc_path in "$clc_dir"/*; do
    clc_name=${clc_path##*/}
    case "$clc_name" in
      '' | *[!A-Za-z0-9._-]*)
        if [ "$clc_omitted" -eq 0 ] && [ -f "$clc_path" ] && [ ! -L "$clc_path" ]; then
          clc_omitted=1
        fi
        continue
        ;;
    esac
    if [ ! -f "$clc_path" ] || [ -L "$clc_path" ]; then
      continue
    fi
    printf '%s\n' "$clc_path"
  done
  printf '%s\n' "$clc_omitted"
}

# checkpoint_file_lines <slug_dir> <session_token>: prints the block
# /squirrel:pickup reads - or nothing at all.
#
# EXACT FORMAT. It is a format rather than a sentence because something
# has to parse it:
#
#   Project checkpoint files, newest first (session <token>):
#   <absolute path>
#   <absolute path>
#   ...
#   (more checkpoint files exist in that directory than are listed here - session <token>)
#
# One header line, spelled exactly as above and carrying THIS session's
# off-token, then one ABSOLUTE path per line, most recently modified
# first, at most CHECKPOINT_LIST_MAX_FILES of them. The RUN OF PATHS ends
# at the first line that does not begin with "/" (or at the end of the
# injected context) - that clause is unchanged, and it is still all a
# path extractor needs. NOTHING is printed - not even the header - when
# the directory is absent, untrusted, or holds no eligible file, so a
# fresh project never gains a dangling empty header for
# /squirrel:pickup to read as "the list is here, and it is empty".
#
# THE INCOMPLETENESS MARKER is that last line, and it appears if and only
# if this function left something out. Its grammar, stated here beside
# the block's own: ONE line, matched WHOLE and never by prefix, spelled
#
#   (more checkpoint files exist in that directory than are listed here - session <token>)
#
# carrying the same session token the header carries. Two deliberate
# properties:
#   - It does NOT begin with "/", so it TERMINATES the run of paths
#     instead of joining it, and no reader of the clause above can
#     mistake it for a path. (It also holds no ": ", so a reader that
#     splits a line on its first ": " to get a single value finds
#     nothing here either - the same care the header itself takes.)
#   - It carries the token for the identical reason the header does, and
#     the reason is sharper here: a marker is an instruction to go
#     ENUMERATE a directory, and the profile body quoted above this block
#     COULD otherwise spell this line exactly. An unbound marker would be
#     a way for profile text to spend a permission prompt.
#     neutralise_forged_lines now marks a body line beginning with this
#     marker's own spelling - that prefix is in
#     SQUIRREL_RESERVED_LINE_PREFIXES precisely because this line is
#     worth forging - and the token is kept unchanged all the same, since
#     that step fails open and the token is what is left when it does.
#
# WHY IT EXISTS. Without it this block is a list that LOOKS complete and
# is not, and skills/pickup/SKILL.md - the only reader there is - said so
# in as many words while forbidding the enumeration that would find the
# rest. So: a block WITHOUT this line names every checkpoint file in that
# directory this hook could see, and pickup may rely on that. A block
# WITH it does not, and pickup is told to enumerate when the request
# actually needs the unnamed ones and to say so in one line when it does
# not.
#
# IT FIRES ON EXACTLY TWO CONDITIONS, both of which leave real memory
# unnamed:
#   - THE CAP. More eligible files than CHECKPOINT_LIST_MAX_FILES, so the
#     oldest of them are not named. This is not a rare shape, and the cap
#     comment above names it exactly: the pruner only deletes a file that
#     is ALSO older than CHECKPOINT_PRUNE_MIN_AGE_DAYS, so a developer
#     with fourteen sessions open this month legitimately has fourteen
#     files there and not one of them is a deletion candidate. Reproduced
#     with fourteen such files: ten named, four still on disk and named
#     nowhere.
#   - THE NAME CLASS. A depth-1 REGULAR, NON-SYMLINK file whose NAME
#     falls outside [A-Za-z0-9._-]. That is deliberately the same
#     `[ -f ] && [ ! -L ]` test checkpoint_dir_has_any uses to decide
#     "this project has memory", so the marker fires exactly when this
#     function and the resume banner DISAGREE about a file, and not
#     otherwise. A subdirectory, a FIFO, a symlink, and the literal
#     unmatched-glob word "<slug_dir>/*" all fail that test, are none of
#     them memory, and so raise no marker - a marker for any of those
#     would cost the user a permission prompt for nothing. Reproduced
#     under LC_ALL=pt_BR.UTF-8 with a slug directory holding sess-01.md,
#     sess-02.md, "café.md" and "sess-café.md": the block named the two
#     ASCII files and omitted the two NEWEST, one of which was that
#     session's OWN checkpoint path, emitted verbatim on the
#     "Project checkpoint path:" line.
#
# IT DOES NOT FIRE when `ls` printed fewer lines than it was handed
# operands. That is the concurrent-deletion case - a peer session's
# prune_stale_session_checkpoints deleting in this very directory - and
# `ls` prints every SURVIVING operand, correctly sorted, rather than a
# prefix. A file deleted between the glob and the `ls` is not something
# enumerating the directory afterwards could reach either, so a marker
# there would send the model looking for something that no longer exists.
#
# WHY THE HEADER CARRIES THE SESSION TOKEN, AND WHAT THIS COMMENT NO
# LONGER CLAIMS. It used to claim the block "cannot collide with any
# other line this hook emits", and enumerated the single-value
# "<Label>: <value>" lines to prove it. That enumeration omitted the
# LARGEST thing this hook emits - the profile body - and was therefore
# false. build_context puts profile.md's body into the injected context
# FIRST (format_profile_framing interpolates it with %s, no fencing) and
# appends this block some thirty lines later, so a profile body was free
# to contain a line that reads exactly like this header followed by any
# absolute paths it likes, and that forged block landed BEFORE the real
# one. Reproduced with a profile.md holding
# "Project checkpoint files, newest first:" and "/etc/passwd", and again
# on the UserPromptSubmit reinjection path, which emits the profile body
# and no block of its own. profile.md is a documented, privileged
# prompt-injection surface that the cap above only BOUNDS (see
# PROFILE_MAX_LINES), and /squirrel:tune writes it from user-dictated
# text, so "the profile is trusted" was never available as an answer.
#
# neutralise_forged_lines below now marks such a header inside the body,
# so it no longer reaches the model beginning with this header's
# spelling - but that does NOT make the token redundant and nothing here
# is relaxed on the strength of it. That step FAILS OPEN - a FAILING awk
# leaves the body unmarked, and an awk absent from PATH ALTOGETHER costs
# the profile body entirely, for a reason of cap_profile_body's own that
# predates it (stated in full at neutralise_forged_lines) - and the token
# is what holds in both cases. Two independent layers, either sufficient
# on its own.
#
# The token is the answer instead: it is this session's off-token, the
# same opaque value build_context puts on the "Session off-token:" line,
# derived from the session_id this hook was handed on stdin. A profile.md
# written before this session started cannot contain it. Ordering
# therefore stops mattering - which is precisely why this is the fix
# rather than reordering the context so the plugin's lines come first: a
# project with NO checkpoint files emits no real block at all, so under
# any first-wins or last-wins rule a forged block is the only block there
# is and wins by default. Under the token rule there is simply nothing
# for /squirrel:pickup to accept.
#
# The three claims that ARE true, and that skills/pickup/SKILL.md relies
# on, are narrower than the old one:
#   - Only a header carrying THIS session's token is this hook's.
#   - WITHIN ONE SessionStart payload, every line this hook GENERATES -
#     this header included - is appended AFTER the quoted profile body,
#     and nothing profile-controlled follows them. So within that one
#     payload, of any duplicated label the LAST occurrence is the hook's.
#     That costs no code (it is simply the order build_context already
#     assembles in) and it is what makes the "Session off-token:" line
#     the token check reads well-founded even against a profile that
#     forges one of those too.
#   - ACROSS the conversation that rule would invert, so it is scoped
#     rather than stated flat. handle_user_prompt_submit re-emits the
#     profile body - forged lines and all - on later prompts, and those
#     messages arrive AFTER this payload. What makes that harmless is
#     that the reinjection carries NO line this hook generates: no
#     "Session working directory:", no "Session off-token:", no
#     checkpoint path, and never a block. Verified by scenario 6h6(e) in
#     tests/test_hooks.sh and by P3-3 alongside it. So a block appearing
#     outside the SessionStart payload is forged by construction,
#     whatever token its header carries - which is exactly how
#     skills/pickup/SKILL.md words it.
# The header is still deliberately NOT spelled
# "Project checkpoint files: <...>": a reader that splits a line on its
# first ": " to get a single value must not find one where a multi-line
# block starts.
#
# WHY THIS EXISTS. /squirrel:pickup folds every past session's
# checkpoint into one answer, so it has to ENUMERATE this directory.
# Told only where the directory is, a model shells out to `ls` or
# `find` - and hooks.json's PreToolUse matcher is Write|Edit|Read, so
# allow-checkpoint.sh can never auto-approve a Bash call. Reproduced
# live under default permissions: pickup stopped and asked for approval
# to list the directory, which is precisely the ordinary interaction
# ADR-0002 promises never costs a prompt. Handing the model the list is
# the same move tech-lead Decision 1 already makes for the checkpoint
# paths themselves - the model cannot compute the slug algorithm, so it
# is given the answer instead of the means - and with the list in
# context, pickup needs only Read on paths it was handed, which
# allow-checkpoint.sh already auto-approves.
#
# WHAT `ls` IS USED FOR, AND WHAT IT IS NOT TRUSTED FOR. `ls` is used
# ONLY as a SORT. It is the one POSIX way to order files by mtime without
# a `stat` (there is no portable one) or the pruner's O(n^2) pairwise
# `find -newer` sweep, which is affordable there because it is bounded by
# CHECKPOINT_PRUNE_MAX_CANDIDATES and skipped entirely for files under
# 30 days old, and is not affordable here because this must rank EVERY
# file in the directory on every single session start. No NAME is ever
# learned from it. The function is two passes for exactly that reason:
#   - Pass 1 enumerates the directory with a GLOB - the same newline-safe
#     idiom checkpoint_dir_has_any and prune_stale_session_checkpoints
#     already use - and validates every entry before `ls` ever sees it:
#     its NAME must lie within [A-Za-z0-9._-] (the character class
#     session_checkpoint_name produces, via sanitize_session_id) and the
#     path it names must be a regular file that is not a symlink, the
#     same `[ -f ] && [ ! -L ]` trust boundary the other two already
#     enforce. Survivors, and only survivors, become `ls` OPERANDS.
#   - Pass 2 runs `ls -td --` over exactly those operands and prints back
#     the lines it returns. Every operand is
#     "<slug_dir>/<name in [A-Za-z0-9._-]>", so no operand's final
#     component can hold a newline, a space, or a glob character: `ls`
#     returns exactly one line per operand, and the mapping from line to
#     file is unambiguous by construction rather than by inspection.
#
# HOW PASS 1 ACCUMULATES, AND THE TWO QUADRATICS IT AVOIDS. Pass 1's loop
# lives in checkpoint_list_candidates, which PRINTS one survivor per
# line; this function CAPTURES that whole stream once and splits it into
# positional parameters once, under `set -f` and IFS=newline.
#
# Both obvious alternatives are quadratic, and this code path has a
# standard to meet: prune_stale_session_checkpoints' own comment says a
# directory that accumulated hundreds of files "must not turn into a
# multi-second stall on turn one", and it bounds itself at
# CHECKPOINT_PRUNE_MAX_CANDIDATES to keep that promise. This function has
# no such bound - it must rank EVERY file - so its loop has to be linear
# in fact and not merely in intent. Measured on this machine (Apple
# silicon, bash 3.2 as /bin/sh, APFS - machine-specific, like the other
# timings in this file), accumulating 5000 already-validated paths:
#
#   set -- "$@" "$p"   (rebuild the positional list each iteration)  103.68s
#   s="$s$p<newline>"  (append to a shell string each iteration)      28.41s
#   printf, captured with $( ) once                                    0.31s
#
# The middle one is the trap: it LOOKS linear and is not, because each
# append copies the whole string built so far. Only the capture is
# actually O(n) - the shell collects the subshell's stdout into one
# buffer and hands it over once.
#
# Whole-hook wall time, same machine, one back-to-back run:
#
#          files:                    200    500   1000   2000    5000
#   this change, first attempt:     0.49s  1.31s  2.98s  7.76s  33.03s
#   this change, as it now stands:  0.45s  1.03s  2.03s  4.02s  10.37s
#   v0.3.1, with no list at all:    0.48s  1.05s  2.08s  4.10s  10.24s
#
# i.e. as it now stands this whole feature is inside the measurement
# noise of the pruner that was already there, at every size, where the
# first attempt cost 23 extra seconds at 5000 files.
#
# NOTHING IN THE SUITE BOUNDS THIS, AND THAT IS A DECISION WITH NUMBERS
# BEHIND IT. tests/test_hooks.sh bounds allow-checkpoint.sh by wall time
# (scenarios 33/33r) and check-off-flag.sh too (57), and the same was
# attempted here. It does not survive the measurement. Whole-hook wall
# time on this machine, a slug directory of N files, against hand-mutated
# copies that accumulate the survivors the two quadratic ways instead:
#
#                         N=4000            N=8000
#                    /bin/sh    dash    /bin/sh    dash
#   as it stands      10-11s      8s        22s     16s
#   set -- "$@" "$p"  24-25s     13s        79s     36s
#   s="$s$p<newline>"    15s       -          -     16s
#
# A single threshold has to be GREEN for row 1 on every platform and RED
# for row 2. The shipped code is slowest under bash 3.2 (22s at N=8000)
# and the mutant is fastest under dash (36s at N=8000), so the entire
# admissible window is (22s, 36s) - and dash is what /bin/sh IS on CI's
# ubuntu-24.04, so that narrow end is the end that decides it. Picking
# 30s leaves 1.36x of headroom over the shipped code's own worst
# measured cost, on the FASTEST hardware in play; repeat runs here vary
# by ~20% under ordinary load, and a slower runner turns that into a red
# build with no defect in it. Scenario 57, by contrast, bounds a 0.73s
# operation at 3s.
#
# Worse, the string-append row - which is the trap this section is
# actually about, being what an "inline the helper" edit naturally
# produces - is INSIDE THE NOISE at both sizes on both shells (15s vs
# 10-11s, 16s vs 16s). So even a threshold that worked would catch only
# the one shape nobody writes by accident, at a cost of ~90s of suite
# time for the N=8000 fixture.
#
# The limit is therefore written down rather than asserted, which is this
# repo's stated preference over a green-but-flaky test: THE THREE-PIECE
# SHAPE BELOW - a separate checkpoint_list_candidates, ONE `$( )`
# capture, ONE split - IS LOAD-BEARING FOR THE O(n) PROPERTY, AND NO TEST
# WILL NOTICE IF IT GOES. Inlining the loop, or accumulating into a
# positional list or a shell string, passes the whole suite green and
# costs what the table above says.
#
# WHY A SEPARATE FUNCTION rather than the loop inline inside the
# capture. bash 3.2 - which is /bin/sh on this machine, and therefore
# what the shebang actually selects here - CANNOT PARSE a `case` inside
# `$( )`: `syntax error near unexpected token ';;'`, reproduced with
# exactly this loop, while dash and zsh-as-sh both accept it. Moving the
# loop into a function leaves the substitution body a single command and
# sidesteps the bug entirely.
#
# THE STREAM'S SHAPE, and why the flag rides in it. The capture is zero
# or more path lines followed by EXACTLY ONE final line, "0" or "1",
# which is the incompleteness marker's name-class trigger. A subshell
# cannot hand a variable back to its parent, and this is the one bit of
# state pass 1 has to return besides the paths, so it travels in the same
# stream and is split off by the last-newline. A path line always begins
# with "/", so the flag line can never be mistaken for one - and when
# there is no newline at all, there were no paths.
#
# Splitting the captured stream on newline is safe HERE, and only because
# of the character class checkpoint_list_candidates enforces: a surviving
# name cannot contain a newline, so no entry can split into two. `set -f`
# around the split is what stops a $HOME containing "*", "?" or "[" from
# turning one word into a glob expansion. IFS=newline alone would still
# leave names holding spaces or tabs intact, which is why the join is a
# newline rather than a space even though the class forbids both.
#
# FIXED (this cycle): those two passes used to be the other way round -
# `ls -t` on the DIRECTORY, names parsed out of its output - and the
# comment here claimed "a name carrying a newline therefore arrives as
# two candidate names, and both are rejected (neither names an existing
# regular file)". That is false the moment one half names a real file.
# Reproduced against the real hook with a directory holding sess-dup.md,
# sess-zzz.md, and a file literally named "junk<newline>sess-dup.md": the
# block named sess-dup.md TWICE and put the OLDER of the two real files
# FIRST, inverting the newest-first order that is the entire reason this
# block exists, and burning a slot of the cap on the duplicate. Note that
# neither dropping duplicates nor keeping the last of them repairs it -
# a spurious half sits at the PATHOLOGICAL file's mtime rank, which can
# fall on either side of the real entry's, so first-wins and last-wins
# are each wrong for one arrangement of the fixture. The split is removed
# at its source instead: a name containing a newline fails the character
# class in pass 1 and never becomes an operand at all.
#
# THE NEWLINE $HOME GUARD, and why this block is guarded where the two
# single-value lines are not. This paragraph used to say the opposite -
# that a newline in $HOME was "the one assumption left, stated rather
# than guarded", that it "would break this block into lines that are not
# paths", and that "a guard here could not fire without those two lines
# already being broken". BOTH HALVES WERE FALSE once the pass-2 retry
# below existed. Reproduced against the real hook:
#
#   $HOME = <W>/nl/h<newline>x   (a directory)
#   <W>/nl/h                     (an ORDINARY REGULAR FILE - not a
#                                 checkpoint, not even in ~/.squirrel)
#   $HOME/.squirrel/checkpoints/<slug>/sess-01.md, sess-02.md
#
# Pass 1 prints two paths, each carrying the newline. The one split turns
# those two words into FOUR - "<W>/nl/h" and the relative fragment
# "x/.squirrel/..." twice over. The first `ls` fails on the two relative
# fragments; the retry's `[ -f ] && [ ! -L ]` re-filter KEEPS both
# "<W>/nl/h" words, because that path really is a regular file; `$#`
# shrank, so the retry fires; the second `ls` succeeds. What came out was
# a block of two syntactically PERFECT absolute paths naming a file that
# is not a checkpoint at all, with no incompleteness marker on it. It is
# not "lines that are not paths" - it is worse, because nothing about it
# reads as broken: the neighbouring "Project checkpoint directory:" and
# "Project checkpoint path:" lines degrade into obviously-mangled text in
# the same fixture, while these two read as ordinary output, and
# skills/pickup/SKILL.md Case 1 promises "every path it names is correct"
# and tells the model to Read each one.
#
# Proven to be the retry's doing rather than the split's: the identical
# fixture against a copy whose retry loop is replaced by the old single
# `listing=$(ls -td -- "$@" 2>/dev/null) || listing=""` emits NO BLOCK AT
# ALL - the first `ls` fails and there is no second chance.
#
# Hence the `case` at the top of checkpoint_file_lines: a newline
# anywhere in <slug_dir> and this function emits nothing. That is the
# stated bar for this input - it may legitimately produce no block, but
# it must never emit a corrupted path. The two single-value lines above
# are still unguarded, and still on purpose: they degrade VISIBLY, they
# are one value each rather than a run this block's grammar invites a
# reader to walk, and nothing tells the model to Read what they name
# without first noticing they are broken.
#
# WHY THE BODY RUNS UNDER LC_ALL=C. `case "$name" in *[!A-Za-z0-9._-]*)`
# is a COLLATION range, and collation is locale-dependent. Reproduced on
# this hook with nothing but LC_ALL varying: "café.md" is REJECTED under
# LC_ALL=C and ACCEPTED under en_US.UTF-8 and pt_BR.UTF-8 (bash-as-
# /bin/sh and ksh; dash is locale-blind here and rejects under all
# three). This machine's real locale is pt_BR.UTF-8 and CI's is C.UTF-8,
# so the stated "[A-Za-z0-9._-]" invariant was true in CI and false
# locally. The whole body therefore runs in one explicit SUBSHELL with
# LC_ALL=C exported - the same discipline json_escape and
# strip_incomplete_utf8_tail already apply to their `awk` - which makes
# the comparison byte-wise on every platform. The subshell costs nothing:
# this function's only output is its stdout, and build_context already
# calls it inside a command substitution. `ls -t` sorts by mtime, never
# by collation, so the C locale cannot change the order it returns.
#
# The range itself now lives in checkpoint_list_candidates, which is
# called from INSIDE that subshell and inherits the exported LC_ALL - so
# the pinning still covers it. That is the only reason that function may
# not be called from anywhere else, and its own header says so.
#
# A DELIBERATE, DOCUMENTED MISMATCH, AND WHAT NOW CARRIES IT. A depth-1
# regular file whose NAME falls outside that character class still makes
# checkpoint_dir_has_any report "Resume available", but is never named
# here. This comment used to answer that with "if the list does not
# account for it, /squirrel:pickup's own fallback covers the gap", and
# that was FALSE whenever the directory ALSO holds conforming files:
# pickup's fallback is keyed on there being NO block, and a mixed
# directory emits one. Reproduced - the "café.md" fixture in the marker
# section above. So the answer is now the incompleteness marker, which
# fires on exactly this condition and is what makes the asymmetry
# recoverable rather than merely written down. `ls` absent from PATH
# entirely is the other half and is unchanged: no block at all, "Resume
# available" unchanged, exit 0, and with no block there IS no list for
# pickup to over-trust, so its fallback genuinely does cover that one.
#
# The LC_ALL=C above opens one further route into that same asymmetry,
# and it is deliberate. sanitize_session_id keeps the plain, unpinned
# range form, so under a UTF-8 locale it accepts a session_id holding
# non-ASCII letters and this session's own checkpoint is then named, say,
# "sess-café.md" - which this function, reading byte-wise, will not name.
# Verified: "Resume available" fires and "Project checkpoint path:" is
# emitted unchanged; if that file is the only one in the directory no
# block appears, and if it sits alongside conforming files a block
# appears WITH the marker. Claude Code session ids are UUIDs, so no real
# session reaches it; the point of writing it down is that the two
# character classes now differ ON PURPOSE, and the difference falls on
# the side that under-reports - and now says that it is under-reporting -
# rather than the side that hands over a path.
#
# <session_token> is passed in rather than recomputed: build_context
# already holds the value it puts on the "Session off-token:" line, and
# it guarantees that value is non-empty and within [A-Za-z0-9_-]. Two
# derivations of one token is exactly how they drift apart.
#
# Same posture as the two pruners: a no-op when the directory is absent,
# every fallible step guarded, and no path through it can fail the hook.
checkpoint_file_lines() {
  (
    LC_ALL=C
    export LC_ALL

    list_dir=$1
    list_token=$2
    [ -d "$list_dir" ] || exit 0
    # A NEWLINE ANYWHERE IN <slug_dir> - which means a newline in $HOME,
    # since everything below it is [A-Za-z0-9._-] by construction - and
    # this function emits nothing at all. See "THE NEWLINE $HOME GUARD"
    # above for the reproduction and for why the retry below makes this
    # a guard rather than a stated assumption. A plain `( )` body, not
    # `$( )`: bash 3.2 cannot parse a `case` inside a command
    # substitution (see "WHY A SEPARATE FUNCTION"), and this one sits in
    # the same subshell as the `case` at the split below.
    case "$list_dir" in
      *"
"*) exit 0 ;;
    esac
    # The identical refusal prune_stale_session_checkpoints and
    # checkpoint_dir_has_any make, through the identical helper rather
    # than a second check of its own: a symlink at <slug> or at
    # checkpoints/ means these are not this plugin's files, and it must
    # neither read, rank, nor name them.
    if checkpoint_slug_dir_untrusted "$list_dir"; then
      exit 0
    fi

    # Pass 1, captured once - see "HOW PASS 1 ACCUMULATES" above for the
    # measurements, for why the loop lives in its own function, and for
    # the stream's shape. Split the trailing flag line off first: the
    # last line is always "0" or "1", and a stream with no newline in it
    # at all had no paths in it at all.
    list_cands=$(checkpoint_list_candidates "$list_dir")
    list_nl='
'
    list_omitted=${list_cands##*"$list_nl"}
    case "$list_cands" in
      *"$list_nl"*) list_cands=${list_cands%"$list_nl"*} ;;
      *) list_cands="" ;;
    esac
    # Total, not defensive-looking-but-partial: anything that is not the
    # literal "1" is "not omitted", so no value of this variable can
    # reach the arithmetic test below and fail it.
    [ "$list_omitted" = "1" ] || list_omitted=0

    # Pass 1b - REDUCE the operand list until one `ls` can take it. See
    # CHECKPOINT_LIST_CHUNK above for the E2BIG failure this closes, for
    # why a tournament is exactly correct for "the newest K overall", and
    # for why 500 is the chunk size.
    #
    # A NO-OP AT ORDINARY SIZES, deliberately and checkably: the outer
    # `while` never runs unless there are MORE than CHECKPOINT_LIST_CHUNK
    # candidates, so a directory with anything short of 501 checkpoint
    # files reaches the split below with `list_cands` untouched and gets
    # the identical single `ls` call it always did. That is what keeps
    # this addition off the path every existing scenario exercises.
    #
    # A CHUNK WHOSE `ls` FAILS RAISES THE MARKER RATHER THAN GOING
    # QUIET. Its candidates are dropped - keeping a failing `ls`'s
    # partial output would reintroduce the mis-ordering the Pass 2
    # comment below rejects at length - so real memory goes unnamed, and
    # that is precisely the condition the incompleteness marker exists to
    # report. If EVERY chunk fails, `list_cands` ends up empty, the
    # `[ "$#" -gt 0 ]` guard below emits no block at all, and
    # /squirrel:pickup reads the absent block plus the "Resume available"
    # line as its case 2 and enumerates the directory itself. Both
    # degradations are honest; neither can present a short list as
    # complete.
    if [ -n "$list_cands" ]; then
      list_total=$(printf '%s\n' "$list_cands" | wc -l | awk '{print $1}')
    else
      list_total=0
    fi
    while [ "$list_total" -gt "$CHECKPOINT_LIST_CHUNK" ]; do
      list_round=""
      list_start=1
      while [ "$list_start" -le "$list_total" ]; do
        list_end=$((list_start + CHECKPOINT_LIST_CHUNK - 1))
        list_chunk=$(printf '%s\n' "$list_cands" | sed -n "${list_start},${list_end}p")
        # The subshell is what makes this safe to nest: `set --` inside
        # it rebinds only its own positional parameters, so the outer
        # list is untouched, and `set -f` / IFS are restored by the
        # subshell ending rather than by hand. It exits non-zero - and so
        # leaves list_top empty - whenever `ls` itself failed, so a
        # failing call's partial output is never piped onward.
        list_top=$(
          set -f
          IFS=$list_nl
          # shellcheck disable=SC2086
          # Splitting on newline IS the conversion; `set -f` above
          # removes the globbing half of the hazard. Same idiom, same
          # reasons, as the one split just below.
          set -- $list_chunk
          # No IFS/`set +f` restore: this subshell exits a few lines
          # below, and nothing between here and there reads either. The
          # split at the end of this function DOES restore both, because
          # the rest of build_context runs after it.
          [ "$#" -gt 0 ] || exit 1
          # shellcheck disable=SC2012
          # SC2012 (prefer find over ls) is disabled for the reason given
          # at the Pass 2 call below: `find` has no portable mtime SORT.
          if list_chunk_out=$(ls -td -- "$@" 2>/dev/null); then
            printf '%s\n' "$list_chunk_out" | head -n "$CHECKPOINT_LIST_MAX_FILES"
          else
            exit 1
          fi
        ) || list_top=""
        if [ -n "$list_top" ]; then
          list_round="$list_round$list_top$list_nl"
        else
          list_omitted=1
        fi
        list_start=$((list_end + 1))
      done
      list_cands=${list_round%"$list_nl"}
      if [ -n "$list_cands" ]; then
        list_new_total=$(printf '%s\n' "$list_cands" | wc -l | awk '{print $1}')
      else
        list_new_total=0
      fi
      # Termination is guarded on ACTUAL progress rather than on the
      # arithmetic being obviously convergent: a round that failed to
      # shrink the list (every chunk lost, or a chunk size at or below
      # CHECKPOINT_LIST_MAX_FILES) must end the loop, not spin in it.
      [ "$list_new_total" -lt "$list_total" ] || break
      list_total=$list_new_total
    done

    # The one split. `set -f` for the whole of it: a $HOME holding "*",
    # "?" or "[" would otherwise make the shell glob these words on the
    # way into "$@", and the paths they name are about to be handed to
    # the model. The function's own two arguments were saved above,
    # before `set --` discards them. `$#` is 0 for an empty $list_cands,
    # which is also the guard that stops a bare `ls -td --` from being
    # run with no operands at all - that would list the CURRENT
    # DIRECTORY.
    set -f
    list_old_ifs=$IFS
    IFS=$list_nl
    # shellcheck disable=SC2086
    # SC2086 (quote to prevent splitting) is exactly what this line wants:
    # splitting on newline is the conversion, and `set -f` above has
    # already removed the globbing half of the hazard SC2086 warns about.
    set -- $list_cands
    IFS=$list_old_ifs
    set +f
    [ "$#" -gt 0 ] || exit 0

    # Pass 2. `ls` sorts the operands and nothing else - AT MOST TWICE.
    #
    # THE DEFECT THIS LOOP FIXES. This was one line, `listing=$(ls -td --
    # "$@" 2>/dev/null) || listing=""`. `ls` exits 1 when ANY operand is
    # missing, so a single file vanishing between the glob above and this
    # call threw away the ENTIRE block - converting the whole benefit of
    # this feature back into the permission prompt it exists to remove.
    # The race is not hypothetical: prune_stale_session_checkpoints
    # deletes in this very directory at every SessionStart, so a peer
    # session in the same project is the trigger. Reproduced with an `ls`
    # shim that removed one operand and then exec'd the real `ls`:
    # thirteen survivors printed by `ls`, no block emitted at all.
    #
    # WHY NOT SIMPLY `|| true` AND KEEP THE PARTIAL OUTPUT. Because on
    # BSD `ls` the partial output is NOT NEWEST-FIRST, and the order is
    # the entire reason this block exists. Measured on this machine's
    # /bin/ls across 172 (operand count, missing index) combinations: 10
    # of them come back as TWO descending runs rather than one, and they
    # are exactly the ones where the missing operand sits at the MIDDLE
    # of the argument list - N=8 missing the 4th, N=14 missing the 7th,
    # N=32 missing the 16th, and so on, deterministic on repeat, plainly
    # a merge artifact. GNU `ls` returns a single correct run in all 172.
    # Keeping that output would hand /squirrel:pickup a list whose FIRST
    # path is not the newest file, and pickup takes "You were doing" and
    # "Next action" from the first file that records them - so the cost
    # would be a silently stale answer, where the cost of no block at all
    # is one permission prompt and a correct one. This file has ruled the
    # same way once already: see FIXED (this cycle) above, where a
    # different route to an inverted order was removed at its source
    # rather than papered over.
    #
    # SO: on failure, rebuild the operand list from the operands that
    # STILL EXIST and ask `ls` once more. The second call has no missing
    # operand and therefore returns one correctly sorted run. Bounded at
    # two calls - a second concurrent deletion inside that window leaves
    # no block, which is the pre-existing behaviour and still correct.
    # The re-filter is skipped, and the loop breaks, when nothing
    # actually vanished: `ls` absent from PATH and an operand list past
    # ARG_MAX both fail with EVERY operand still on disk, and a second
    # identical call would fail identically, so those two keep costing
    # exactly one `ls` invocation and emit no block, as before.
    list_attempt=0
    listing=""
    while :; do
      list_attempt=$((list_attempt + 1))
      # shellcheck disable=SC2012
      # SC2012 (prefer find over ls) is disabled deliberately and
      # narrowly - see "WHAT `ls` IS USED FOR" above for the argument in
      # full. `find` has no portable mtime SORT, which is the one thing
      # this line needs.
      if listing=$(ls -td -- "$@" 2>/dev/null); then
        break
      fi
      # A failed command substitution still ASSIGNS whatever was printed.
      # That partial, possibly mis-ordered output is exactly what must
      # not survive to the emit loop, so it is cleared here rather than
      # anywhere later.
      listing=""
      [ "$list_attempt" -lt 2 ] || break
      list_before=$#
      # Captured the same way pass 1 is, and for the same reason: at 5000
      # operands, appending to a shell string instead costs 28s. No name
      # check here - every operand already passed one - and no `case`, so
      # this one is safe to write inline.
      list_cands=$(
        for cand_path in "$@"; do
          [ -f "$cand_path" ] && [ ! -L "$cand_path" ] || continue
          printf '%s\n' "$cand_path"
        done
      )
      set -f
      list_old_ifs=$IFS
      IFS=$list_nl
      # shellcheck disable=SC2086
      # Splitting on newline IS the conversion; `set -f` above removes
      # the globbing half of the hazard. Same idiom, same reasons, as the
      # one split in pass 1.
      set -- $list_cands
      IFS=$list_old_ifs
      set +f
      [ "$#" -gt 0 ] && [ "$#" -lt "$list_before" ] || break
    done
    [ -n "$listing" ] || exit 0

    # The header is printed LAZILY, from inside the loop, on the first
    # line. That, and nothing else, is what guarantees a directory with
    # no eligible file emits no header: there is no code path that prints
    # the header without also printing a path under it. The marker is
    # gated on the same `emitted` counter for the same reason - a marker
    # with no block above it would be a bare instruction to go enumerate,
    # which is the one thing this feature exists to avoid paying for.
    #
    # `read` rather than a `for` over a word-split string, and therefore a
    # subshell: `emitted` lives and dies inside the pipeline, which is
    # fine because nothing outside needs it. list_omitted is INHERITED
    # into that subshell from pass 1 and raised again here for the cap -
    # the marker is printed from inside the pipeline precisely so both
    # triggers can be read in one place. The `|| true` is the pruners'
    # own idiom - it makes the pipeline exempt from `set -e` so a `read`
    # or `printf` failing on some pathological input cannot abort
    # build_context.
    #
    # The cap branch raises the flag rather than merely breaking: entering
    # it means a further line was read that will not be emitted, so the
    # block is short of files that are on disk right now. With exactly
    # CHECKPOINT_LIST_MAX_FILES files there is no further line, the branch
    # never runs, and no marker appears - which is what makes "no marker"
    # mean "you have everything" instead of "probably everything".
    printf '%s\n' "$listing" | {
      emitted=0
      while IFS= read -r entry_path; do
        if [ "$emitted" -ge "$CHECKPOINT_LIST_MAX_FILES" ]; then
          list_omitted=1
          break
        fi
        if [ "$emitted" -eq 0 ]; then
          printf 'Project checkpoint files, newest first (session %s):\n' "$list_token"
        fi
        printf '%s\n' "$entry_path"
        emitted=$((emitted + 1))
      done
      if [ "$emitted" -gt 0 ] && [ "$list_omitted" -ne 0 ]; then
        printf '(more checkpoint files exist in that directory than are listed here - session %s)\n' "$list_token"
      fi
    } || true
    exit 0
  ) || true
  return 0
}

# --- S11 migration notice --------------------------------------------
#
# detect_old_data_dir <home_dir> <new_squirrel_dir>: the migration check -
# prints ONE line addressed to the model (the same idiom as the "no
# profile found" line above - text the model is meant to relay, briefly,
# not raw data) if and only if the migration source directory,
# ~/.claude/squirrel/ (the pre-S11 location), still exists on disk.
# Prints nothing and is a no-op when home_dir is empty
# or the old directory is absent, so a fresh, always-been-on-S11-or-later
# install never sees this line at all.
#
# DETECTION ONLY, DELIBERATELY. This function never creates, moves,
# copies, or deletes a single byte - see the "S11 MIGRATION NOTICE"
# paragraph in this file's own header for why an automatic `mv` at
# session start is exactly the wrong kind of automation here (it cannot
# be undone, and a destination that already has its own newer data would
# be silently clobbered by a naive move). The user decides what to move
# and when; this only makes sure they are told, every session, for as
# long as the old directory keeps existing.
detect_old_data_dir() {
  home_dir=$1
  new_dir=$2
  [ -n "$home_dir" ] || return 0
  old_dir="$home_dir/.claude/squirrel"
  [ -d "$old_dir" ] || return 0
  printf 'squirrel-mode: found data from an older install at %s - squirrel-mode now uses %s instead. Tell the user once, briefly: move whatever they want to keep (profile.md, the checkpoints/ directory) from the old location into the new one, then remove the old directory. This message will keep appearing every session until the old directory is gone; nothing here moves or deletes anything automatically.' "$old_dir" "$new_dir"
}

# --- JSON escaping for the manual (no-jq) emission path ---------------
#
# json_escape <text>: backslash- and double-quote-escapes <text> for
# embedding inside a JSON string literal, joins lines with the
# two-character sequence \n, drops a trailing \r per line (CRLF
# normalisation), and - the part that used to be missing - escapes
# EVERY other C0 control byte (0x00-0x1F: a pasted ESC, a bell
# character, a stray vertical tab, ...) as \uXXXX (or the shorter \b /
# \t / \f / \r JSON already defines), because JSON forbids ALL of
# 0x00-0x1F appearing raw in a string, not just the few this function
# used to special-case. A profile with an unescaped control byte used
# to come out of this function as JSON that `jq empty` itself rejects
# ("control characters ... must be escaped").
#
# Deliberately ONE `awk` invocation, not `sed` at all, run under
# `LC_ALL=C`: BSD sed aborts mid-stream with "illegal byte sequence" the
# moment it hits a byte that is not valid UTF-8 under a non-C locale
# (this machine's real LANG is pt_BR.UTF-8) - and because POSIX sh has
# no `pipefail`, nothing ever surfaced that abort: the pipeline's exit
# status came from the final stage, which still exited 0, so the script
# kept reporting success while silently truncating the profile at the
# bad byte. `awk` under `LC_ALL=C` treats every byte as its own single-byte
# "character" regardless of what LANG says, so `length`/`substr` here
# are genuinely byte-indexed and a byte that is not valid UTF-8 simply
# passes through unchanged in the `else` branch below - never crashes,
# never gets silently dropped, whichever locale is active. Verified
# under both LANG=C and LANG=pt_BR.UTF-8 to produce byte-identical
# output.
#
# The one byte this function cannot special-case is NUL (0x00): POSIX
# sh variables cannot hold a NUL byte at all (universal C-string
# semantics, not specific to this script), so by the time `$1` reaches
# this function any NUL byte in the original file is already gone -
# a platform limitation this function cannot see past, not something
# it introduces.
#
# Only used when jq is not on PATH - see emit_json.
json_escape() {
  str=$1
  printf '%s' "$str" | LC_ALL=C awk '
    BEGIN {
      for (i = 1; i < 256; i++) { ordtab[sprintf("%c", i)] = i }
      first = 1
    }
    {
      line = $0
      sub(/\r$/, "", line)
      n = length(line)
      out = ""
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        if (c == "\"") { out = out "\\\""; continue }
        b = ordtab[c] + 0
        if (b == 8)  { out = out "\\b"; continue }
        if (b == 9)  { out = out "\\t"; continue }
        if (b == 10) { out = out "\\n"; continue }
        if (b == 12) { out = out "\\f"; continue }
        if (b == 13) { out = out "\\r"; continue }
        if (b > 0 && b < 32) { out = out sprintf("\\u%04x", b); continue }
        out = out c
      }
      if (first == 0) { printf "\\n" }
      printf "%s", out
      first = 0
    }
  '
}

emit_json() {
  ctx=$1
  if command -v jq >/dev/null 2>&1; then
    # jq exiting 0 is not enough: a wedged-but-still-callable shim that
    # prints the literal `null`, prints nothing at all, or prints some
    # other JSON value - including a non-empty object that is NOT a
    # SessionStart payload (e.g. {"not":"SessionStart"}, or a
    # hookSpecificOutput with the wrong hookEventName) - used to make
    # this function emit that value verbatim. `jq empty` accepts all of
    # those while they fail the SessionStart contract. Require a
    # non-empty object whose hookSpecificOutput.hookEventName is
    # exactly SessionStart before trusting the jq path; anything else
    # falls through to json_escape.
    if out=$(jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' 2>/dev/null) \
      && [ -n "$out" ] \
      && [ "$out" != "null" ]; then
      case "$out" in
        \{*)
          # Re-parse with jq (not a regex): missing hookSpecificOutput,
          # a non-object value there, or any hookEventName other than
          # SessionStart must NOT be trusted. A shim that ignores stdin
          # and reprints garbage fails this the same way - event will
          # not equal the literal SessionStart.
          event=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null) || event=""
          if [ "$event" = "SessionStart" ]; then
            printf '%s\n' "$out"
            return 0
          fi
          ;;
      esac
    fi
  fi
  escaped=$(json_escape "$ctx")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
  return 0
}

# --- Injected profile size cap (tech-lead ruling; see PLAN.md, "The
# profile") ------------------------------------------------------------
#
# profile.md is injected into the model's context VERBATIM apart from the
# one transformation neutralise_forged_lines below applies (a line
# spelled like one of squirrel-mode's own injected lines gets a
# "[profile] " marker in front of it; nothing else changes), framed as
# authoritative field overrides ("These field values OVERRIDE the
# defaults..." below) - so anything that can write that file gets a
# persistent, privileged prompt-injection surface, and an unbounded file
# is unbounded context bloat on every single session start. The
# documented profile format is ~15 lines / well under 1 KB, so capping
# at 100 lines / 4 KB is generous by any honest measure while still
# bounding the blast radius; this hook is not, and cannot be, a security
# boundary - the cap only bounds how much damage an oversized or
# adversarial profile.md can do per session start.
#
# cap_profile_body enforces both limits (whichever is hit first: lines,
# then bytes on what's left) and appends a single-line notice - never
# silent truncation - whenever it actually had to cut something.
#
# FIXED HIGH (audit): PROFILE_MAX_BYTES was a PER-LINE bound, not a
# per-stream one, so the two limits MULTIPLIED instead of the second
# bounding the first. `cut -b 1-4096` is a per-line field operation -
# `printf 'aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n' | cut -b 1-5 | wc -c`
# prints 18, not 5 - so every one of the PROFILE_MAX_LINES lines that
# survived the line cap kept up to PROFILE_MAX_BYTES bytes of its own.
# The real bound was 100 x 4096 ~= 400 KB. Measured end to end before
# the fix, with a 100-line x 500 000-byte profile.md: 410 842 bytes
# injected into EVERY SessionStart, framed by format_profile_framing as
# authoritative instruction ("These field values OVERRIDE the
# defaults") - i.e. the exact privileged surface this cap exists to
# bound, bounded two orders of magnitude too loosely.
#
# The GATE was never wrong: `printf '%s' "$body" | wc -c` already
# measures the whole stream, so the decision to truncate fired at the
# right size. Only the truncation itself was per-line, and only it
# changed - `dd bs=1 count=$PROFILE_MAX_BYTES` copies at most that many
# bytes of the STREAM, whatever the line structure is. `dd` with `bs`
# and `count` is POSIX, needs no more of an external dependency than
# `cut` did, and at bs=1 cannot short-read: each block is one byte, so
# `count` blocks is exactly `count` bytes, or fewer only at EOF.
#
# WHAT THE BUDGET COVERS, stated exactly so it is not read as more than
# it is: PROFILE_MAX_BYTES bounds the profile BODY. The one-line
# truncation notice below is appended AFTER the cut and is deliberately
# outside it - suppressing the notice to stay under a round number
# would be silent truncation, which this function has always refused.
# So a capped body is at most PROFILE_MAX_BYTES bytes plus that single
# fixed-length line, and that is the whole of it: nothing here scales
# with the size of profile.md any more.
PROFILE_MAX_LINES=100
PROFILE_MAX_BYTES=4096

# strip_incomplete_utf8_tail <text>: FIXED MINOR (cycle 3) - the byte
# cap above slices at an exact BYTE position with no awareness of UTF-8
# multi-byte boundaries, so it can (and, given a profile.md close to
# the 4096-byte cap and a multi-byte character sitting on the boundary,
# eventually will) leave a truncated multi-byte sequence dangling at
# the very end of `body`: a lead byte with too few - or zero -
# continuation bytes after it. `jq empty` still accepts that (invalid
# byte sequences inside an otherwise well-formed JSON string are not
# something jq's parser rejects) and Node substitutes U+FFFD for it, so
# this was non-fatal in practice, but it is not strictly conformant
# JSON/UTF-8, and the cap itself must not be what manufactures it.
#
# Looks back at most 4 bytes (the longest any single UTF-8 character
# can be) via `od`, counts how many of those trailing bytes are
# CONTINUATION bytes (0x80-0xBF), and inspects the byte immediately
# before that run. If that byte is a multi-byte LEAD byte (0xC0-0xF7)
# that encodes a longer sequence than the continuation bytes actually
# present after it, the whole partial sequence - lead byte and all - is
# dropped, so the boundary never turns valid-so-far UTF-8 into an
# invalid tail. A trailing sequence that is already COMPLETE (the cut
# happened to land exactly on a character boundary) is left untouched,
# and a lead byte that is not a valid UTF-8 lead at all - i.e. `body`
# already contained invalid bytes before this ever ran - is also left
# untouched: fixing PRE-EXISTING invalid bytes elsewhere in profile.md
# is a separate, deliberately out-of-scope concern (see json_escape's
# own comment on bytes >= 0x80 passing through unchanged) - this
# function's only job is to stop the CUT ITSELF from creating new
# damage at the one byte position it controls.
strip_incomplete_utf8_tail() {
  text=$1
  len=$(printf '%s' "$text" | wc -c | awk '{print $1}')
  [ "$len" -gt 0 ] || { printf '%s' "$text"; return 0; }

  back=4
  [ "$back" -le "$len" ] || back=$len

  # tail_bytes: the ordinal value of each of the last <back> bytes of
  # <text>, one per line, oldest first (so the LAST line printed is the
  # very last byte of <text>) - `od`, not `awk`, does the byte-decoding
  # here, matching compute_hash's own `od -An -v -tu1` usage above.
  tail_bytes=$(printf '%s' "$text" | tail -c "$back" | LC_ALL=C od -An -v -tu1 | awk '{ for (i = 1; i <= NF; i++) { print $i } }')

  drop=$(printf '%s\n' "$tail_bytes" | awk '
    {
      n++
      b[n] = $1
    }
    END {
      cont = 0
      i = n
      while (i >= 1 && b[i] >= 128 && b[i] <= 191) {
        cont++
        i--
      }
      if (i < 1) { print 0; exit }
      lead = b[i]
      if (lead <= 127) {
        need = 0
      } else if (lead >= 192 && lead <= 223) {
        need = 1
      } else if (lead >= 224 && lead <= 239) {
        need = 2
      } else if (lead >= 240 && lead <= 247) {
        need = 3
      } else {
        need = -1
      }
      if (need >= 0 && cont < need) {
        print cont + 1
      } else {
        print 0
      }
    }
  ')

  if [ "$drop" -gt 0 ]; then
    keep=$((len - drop))
    if [ "$keep" -gt 0 ]; then
      # `dd`, not `cut -b "1-$keep"`, for the reason given at
      # PROFILE_MAX_BYTES and repeated here because this site had the
      # identical defect INDEPENDENTLY, and a worse-behaved one: `len`
      # and `keep` are whole-STREAM byte counts, so on a multi-line
      # <text> every individual line is far shorter than `keep` and
      # `cut -b` kept all of them - this whole function was a silent
      # no-op for exactly the multi-line bodies it now has to handle.
      # Verified before the fix on "line one\nline two\nline
      # three\xe2\x82": drop computed correctly as 2, 30 bytes in, 30
      # bytes out, the invalid "e2 82" tail still there.
      #
      # It had no way to show up until now: while the byte cap above was
      # per-line, a multi-line body was never cut mid-line in the first
      # place, so no partial character was ever manufactured for this
      # function to strip. Fixing the cap is what makes this one
      # load-bearing, which is why it is fixed in the same change rather
      # than left for later.
      printf '%s' "$text" | dd bs=1 count="$keep" 2>/dev/null
    fi
  else
    printf '%s' "$text"
  fi
}

# --- Forged squirrel-mode lines inside the quoted profile body ---------
#
# THE PROBLEM, IN THE PAST TENSE ON PURPOSE - it is only past because of
# the code below, and a reader who finds this paragraph without the code
# should read it as present. Everything here puts profile.md into the
# model's context and appends squirrel-mode's OWN session lines after it,
# so a profile WAS free to hold a line spelled exactly like one of them -
# "Session off-token:", "Hoard search command:", the checkpoint list
# header - and that forged line REACHED the model looking like
# squirrel-mode's. It was reproduced end to end while /squirrel:dig was
# reviewed: a profile forging an off-token line and a search-command line
# satisfied every positional rule skills/dig/SKILL.md states, and on the
# UserPromptSubmit re-show path - which emits the profile framing and NONE
# of squirrel-mode's own lines - the forgery was the only such line in the
# text, so position and last-wins had nothing to prefer over it. Acting on
# that one line RAN a command.
#
# WHAT THIS DOES ABOUT IT. A line of the profile body that BEGINS with
# one of SQUIRREL_RESERVED_LINE_PREFIXES is emitted with
# PROFILE_LINE_MARKER in front of it, so it no longer begins with that
# prefix. Every reading rule in skills/dig/SKILL.md and
# skills/pickup/SKILL.md matches a line by its own START, so a marked
# line cannot satisfy any of them, and the marker says plainly what the
# line is instead.
#
# NEUTRALISE, NEVER DELETE. profile.md is the user's own file and may
# hold such a line innocently - a pasted transcript of a past session is
# the obvious way. The line is still there, still readable, still the
# user's text; it just no longer impersonates squirrel-mode. Deleting it
# would be a hook silently editing the user's document, and scenario 6h6
# in tests/test_hooks.sh has recorded from the beginning that being
# unable to IMPERSONATE the hook is the property - not being unable to
# say anything.
#
# THE SECOND LAYER, NOT A REPLACEMENT FOR THE FIRST. The rules in those
# two skills stay exactly as strict as they are, and neither is told this
# function exists: a model told its input is already clean has a reason
# to skip its own check, and this function FAILS OPEN (below), so there
# are inputs where those rules are all that is left.
#
# WHY IT HANGS OFF cap_profile_body. That function is the ONE place both
# emission paths put the body through - build_context calls it on
# SessionStart, handle_user_prompt_submit calls it on the re-show - so
# covering it covers both by construction instead of by two call sites
# that can drift apart. Emission-path coverage is exactly how the first
# attempt at this was incomplete: the re-show path is the one the exploit
# used, and it shares no other code with SessionStart's assembly.
#
# ORDER: NEUTRALISE FIRST, THEN CAP. cap_profile_body appends its own
# truncation notice AFTER cutting, so neutralising first is what keeps
# that genuine notice from being marked as profile text by this very
# function - while still letting a FORGED copy of the notice inside the
# body be marked, which is why its prefix is in the list below. The cap's
# documented budget is unaffected: the cut happens after this, so what is
# injected is still at most PROFILE_MAX_BYTES plus that one notice line.

# SQUIRREL_RESERVED_LINE_PREFIXES: every prefix squirrel-mode uses at the
# START of a line it puts into the model's context, one per line. THE
# SINGLE HOME for that set - nothing else in this file, and nothing in
# tests/, restates it.
#
# WHY THE GENUINE LINES ARE NOT EMITTED BY ITERATING THIS LIST, which is
# the obvious way to guarantee one source. They are emitted as literal
# text at every site that emits one - build_context's inline assignments,
# checkpoint_file_lines' two printfs, format_profile_framing,
# detect_old_data_dir, cap_profile_body's own notice, the
# PROFILE_SEEN_UNAVAILABLE_NOTICE constant, and the two hardcoded
# fallbacks at the bottom of this file - and several of those exact source
# lines are the mutation target of an existing failure proof in
# tests/test_hooks.sh: FOUR of them, fpP1e, fpH9, fpL6 and fpL9, locate a
# line by its literal emitted text and rewrite it, across three distinct
# source lines (fpL6 and fpL9 both target the list header's printf).
# Replacing those literals with expansions of this list would silently
# turn each of those four proofs into a no-op mutation, and two of the
# sites sit inside the checkpoint file-list block, which this change is
# not permitted to touch.
#
# FOUR, NOT FIVE. This said five and named fpL5 as well, and fpL5 does
# NOT belong in the set: its `line_of` target is
# `[ "$#" -gt 0 ] || exit 0`, and it pins that the header is printed
# LAZILY, from inside the loop - only its REPLACEMENT text carries the
# header literal, which iterating this list would not disturb. The count
# was the whole justification for not doing what the plan asked for, so
# an off-by-one in it was a falsified premise inside a security
# rationale - the identical defect this file's own neutralisation exists
# to repair, one layer out. Corrected on review, and left visible here
# rather than quietly rewritten.
#
# Deriving the list at RUNTIME from the lines emitted does not work
# either: "Legacy checkpoint file:", "Resume available", the list header
# and the marker are all CONDITIONAL, absent from most sessions, so a
# derived list would leave exactly those prefixes unguarded in the
# sessions where they are absent.
#
# What replaces "one list by construction" is a test that closes the same
# gap from the other side: scenario HOARD-12e runs the hook with every
# conditional line triggered at once and asserts that every line
# squirrel-mode emitted is covered by a prefix in this list. A new
# injected line added without registering it here fails that scenario.
#
# TWO RESIDUAL LIMITS, both stated rather than implied. A future line
# emitted only under a condition that scenario does not trigger escapes
# it - and so does a future line BEGINNING WITH "/", whatever triggers
# it, because that check skips every such line by construction (the
# checkpoint list block's payload is absolute paths, and "/" is
# deliberately not a reserved prefix: a profile naming a path at the
# start of a line is entirely ordinary). The second limit is the sharper
# one, since it holds even when the fixture DOES reach the line.
#
# No entry carries a trailing space. A prefix is matched literally, so a
# shorter one only ever matches MORE - and a trailing space in a shell
# string literal cannot be seen in review and is routinely eaten by
# editors, which is not a property a guard should rest on.
#
# "squirrel-mode:" covers all three lines this hook addresses to the
# model in its own voice (the no-profile suggestion, the S11 migration
# notice, the profile-seen notice). The truncation notice is listed
# separately because it begins with "[" and would not otherwise match.
SQUIRREL_RESERVED_LINE_PREFIXES='A squirrel-mode profile exists at
squirrel-mode:
[squirrel-mode: profile.md truncated
Session working directory:
Session off-token:
Project checkpoint directory:
Project checkpoint path:
Hoard search command:
Project checkpoint files, newest first (session
(more checkpoint files exist in that directory than are listed here - session
Legacy checkpoint file:
Resume available - run /squirrel:pickup'

# PROFILE_LINE_MARKER: what goes in front of a profile line that would
# otherwise begin with one of those prefixes. Short, because a
# pathological profile can carry PROFILE_MAX_LINES of them and every byte
# of that comes out of the same context budget; and readable as what it
# is, because the model has to be able to tell at a glance that the line
# is the user's text rather than squirrel-mode's.
PROFILE_LINE_MARKER='[profile] '

# neutralise_forged_lines <body>: <body> with PROFILE_LINE_MARKER in
# front of every line that begins with one of the reserved prefixes, and
# every other byte unchanged.
#
# FAILS OPEN, like everything else in this hook: an `awk` that is absent,
# fails, or exits 0 with nothing to show for it returns the body EXACTLY
# as it came in, and the hook still emits its context and still exits 0.
# That is the direction this file's whole header commits to, and it is the
# reason the skill-side reading rules must stay strict - on that path they
# are the only layer left. The `if` around the substitution is the file's
# own call-site guarding convention (see build_context), which is what
# keeps `set -e` from turning a failing awk into a dead session.
#
# SCOPED TO THIS STEP, deliberately, because the whole-hook claim would
# be wrong: with awk absent from PATH ALTOGETHER, cap_profile_body's own
# `wc -l | awk` pipeline below fails first, `set -e` aborts
# build_context, and the caller's fallback emits the "no profile found
# yet" line instead - behaviour that predates this function and was
# verified identical on the previous commit. So an absent awk costs the
# profile for a reason that is not this function's; what this function
# guarantees is that IT never costs the profile. Scenario HOARD-12f
# proves the guarantee with a shim awk that fails for this one call only,
# for exactly that reason.
#
# `index(line, prefix) == 1` is a LITERAL prefix test, not a regex match:
# the prefixes carry "(", "[" and "." and must never be read as pattern
# syntax. The list and the marker are handed over through the ENVIRONMENT
# rather than `awk -v`, because POSIX awk re-processes backslash escapes
# in a -v assignment - the trap line_of in tests/test_hooks.sh documents.
# `LC_ALL=C` for the reason json_escape's own comment gives at length: a
# profile body may hold bytes that are not valid UTF-8, and a BSD awk
# aborts mid-stream on one under a UTF-8 locale.
neutralise_forged_lines() {
  nfl_body=$1
  [ -n "$nfl_body" ] || { printf '%s' "$nfl_body"; return 0; }
  if nfl_out=$(printf '%s\n' "$nfl_body" \
    | SQUIRREL_NFL_PREFIXES="$SQUIRREL_RESERVED_LINE_PREFIXES" \
      SQUIRREL_NFL_MARKER="$PROFILE_LINE_MARKER" \
      LC_ALL=C awk '
      BEGIN {
        nfl_n = split(ENVIRON["SQUIRREL_NFL_PREFIXES"], nfl_pfx, "\n")
        nfl_marker = ENVIRON["SQUIRREL_NFL_MARKER"]
      }
      {
        nfl_line = $0
        for (nfl_i = 1; nfl_i <= nfl_n; nfl_i++) {
          if (nfl_pfx[nfl_i] == "") { continue }
          if (index(nfl_line, nfl_pfx[nfl_i]) == 1) {
            nfl_line = nfl_marker nfl_line
            break
          }
        }
        print nfl_line
      }
    ' 2>/dev/null); then
    # An awk that exits 0 having printed nothing for a non-empty body is
    # treated as a FAILURE of this step, not as an empty profile - the
    # same shape emit_json already refuses to trust from jq. Returning
    # the input is the fail-open direction; returning "" would delete
    # the user's profile, which is the one outcome this must not have.
    if [ -n "$nfl_out" ]; then
      printf '%s' "$nfl_out"
      return 0
    fi
  fi
  printf '%s' "$nfl_body"
  return 0
}

cap_profile_body() {
  body=$1
  truncated=0

  # See "Forged squirrel-mode lines inside the quoted profile body"
  # above: this is the single point both emission paths share, and it
  # runs BEFORE the cut so the truncation notice appended below is never
  # itself marked. Guarded at the call site the way every fallible step
  # in this file is - a failure here leaves $body exactly as it arrived.
  cap_raw_body=$body
  body=$(neutralise_forged_lines "$cap_raw_body") || body=$cap_raw_body

  line_count=$(printf '%s\n' "$body" | wc -l | awk '{print $1}')
  if [ "$line_count" -gt "$PROFILE_MAX_LINES" ]; then
    body=$(printf '%s\n' "$body" | head -n "$PROFILE_MAX_LINES")
    truncated=1
  fi

  # `dd`, not `cut -b`: a true STREAM cut. See the PROFILE_MAX_BYTES
  # comment above for what `cut -b` did here instead and what it cost.
  # stderr is discarded because dd reports its block counts there on
  # every run; a failing dd leaves $body empty, which cap_profile_body
  # is free to emit - it is smaller than the cap, not larger.
  byte_count=$(printf '%s' "$body" | wc -c | awk '{print $1}')
  if [ "$byte_count" -gt "$PROFILE_MAX_BYTES" ]; then
    body=$(printf '%s' "$body" | dd bs=1 count="$PROFILE_MAX_BYTES" 2>/dev/null)
    body=$(strip_incomplete_utf8_tail "$body")
    truncated=1
  fi

  if [ "$truncated" -eq 1 ]; then
    body="$body
[squirrel-mode: profile.md truncated - exceeds the ${PROFILE_MAX_LINES}-line / ${PROFILE_MAX_BYTES}-byte cap]"
  fi

  printf '%s' "$body"
}

# --- Profile framing + per-session seen file (P3) ---------------------
#
# format_profile_framing <profile_file> <capped_body>: the same text
# SessionStart uses for a real profile body. Shared so UserPromptSubmit
# reinjection cannot drift from SessionStart's wording.
format_profile_framing() {
  profile_file=$1
  profile_body=$2
  printf 'A squirrel-mode profile exists at %s. These field values OVERRIDE the defaults already given to you in the squirrel-mode output style, field by field.\n\n%s' "$profile_file" "$profile_body"
}

# touch_profile_seen <home_dir> <raw_session_id>: after a real profile
# inject, record that this session has seen the current profile.md.
# Returns 0 if and only if the stamp is now ON DISK; returns non-zero,
# printing nothing and failing nothing, for every reason it might not
# be - empty HOME, sanitize failure, or an unwritable ~/.squirrel.
#
# FIXED MEDIUM (audit): this used to swallow every failure
# (`mkdir -p ... || return 0`, `touch ... || true`) and return 0
# regardless, so a caller had no way to tell "recorded" from "silently
# did not record". The consequence was not a lost stamp, it was an
# unbounded, permanently silent per-prompt tax: handle_user_prompt_submit
# reinjects whenever this session has no stamp NEWER than profile.md, an
# unwritable ~/.squirrel means the stamp never appears, and so the full
# profile body was reinjected on EVERY prompt, for the whole session,
# forever, with nothing anywhere reporting why. Measured: 325 B/prompt
# with a five-line profile.md, and 20 476 B/prompt with an oversized one
# (before the PROFILE_MAX_BYTES fix above bounded that half).
#
# The `[ -f ]` re-test after `touch` is deliberate and is not belt and
# braces for its own sake: the ONLY thing the caller can do with this
# answer is decide whether the gate will find a stamp next prompt, and
# that gate is itself `[ -f "$seen_file" ]`. Asking the same question
# `touch`'s exit status is meant to imply is what makes a `touch` that
# exits 0 without producing a file - some emulated and network
# filesystems do exactly this - fail here rather than reopen the loop.
touch_profile_seen() {
  home_dir=$1
  raw_session_id=$2
  [ -n "$home_dir" ] || return 1
  session_id=$(sanitize_session_id "$raw_session_id") || return 1
  [ -n "$session_id" ] || return 1
  seen_dir="$home_dir/.squirrel/profile-seen"
  mkdir -p "$seen_dir" >/dev/null 2>&1 || return 1
  touch -- "$seen_dir/$session_id" >/dev/null 2>&1 || return 1
  [ -f "$seen_dir/$session_id" ] || return 1
  return 0
}

# PROFILE_SEEN_UNAVAILABLE_NOTICE: what UserPromptSubmit emits INSTEAD of
# the profile body when the stamp cannot be recorded. One line, addressed
# to the model - the same idiom as the "no profile found yet" line
# build_context uses - so the user learns what is wrong and can fix it.
#
# It names the directory the way this file's own header does, "~/.squirrel
# /profile-seen", rather than interpolating $HOME. That is what makes it a
# genuine CONSTANT: a $HOME of any length would otherwise be part of the
# per-prompt cost this is supposed to bound, and on a long $HOME the
# "bounded" notice measured LONGER than the small profile body it
# replaced. It is also the one place in this file where an unexpanded "~"
# is right - every other path emitted here is data the model must use
# verbatim, whereas this is prose for the user to read.
#
# WHY A NOTICE RATHER THAN SILENCE. Emitting nothing would also bound the
# cost (at zero), and it was considered and rejected: it would silently
# drop /squirrel:tune propagation for the rest of the session, which is
# the entire purpose of the reinjection path. This file has already ruled
# on that exact trade once, in the opposite direction, and for the same
# reason - see "AN EXACT MTIME TIE REINJECTS" in the header, where a gate
# that could lose a tune permanently was replaced by one that can at
# worst reinject redundantly. A condition that stops tune propagation
# must be reported, not absorbed.
#
# WHAT IS BOUNDED, precisely: the per-prompt cost stops scaling with
# profile.md and becomes this one fixed-length line. That is the whole
# claim - it is NOT once-per-session, because there is nowhere to record
# that it has been said (the missing stamp IS the thing that cannot be
# recorded), and pretending otherwise would be the same swallowed failure
# one level up.
PROFILE_SEEN_UNAVAILABLE_NOTICE="squirrel-mode: cannot record profile state (~/.squirrel/profile-seen is not writable), so a /squirrel:tune made during this session will not reach you. Tell the user once, briefly."

# handle_user_prompt_submit <input_json>: P3 reinjection path. Prints
# plain-text profile framing UNLESS this session's seen stamp is
# STRICTLY NEWER than profile.md - so no seen file at all reinjects, and
# an exact mtime TIE reinjects too; otherwise prints nothing.
#
# The direction stated above is deliberate and is NOT the mirror of
# itself: the gate used to be "reinject when profile.md is newer than
# the seen stamp", which is also strictly-newer and therefore lost the
# tie the OTHER way, dropping a tune permanently rather than late. See
# the "AN EXACT MTIME TIE REINJECTS" paragraph in this file's header for
# why the tie must fall this way, and the inline comment at the `find`
# call below for what a FAILING find does under each direction.
# Never emits SessionStart JSON. Never nags /init. Never prunes.
handle_user_prompt_submit() {
  input=$1
  raw_session_id=$(extract_field "$input" "session_id")
  session_id=$(sanitize_session_id "$raw_session_id") || { printf ''; return 0; }
  [ -n "$session_id" ] || { printf ''; return 0; }

  home_dir="${HOME:-}"
  [ -n "$home_dir" ] || { printf ''; return 0; }

  profile_file="$home_dir/.squirrel/profile.md"
  [ -f "$profile_file" ] || { printf ''; return 0; }

  seen_file="$home_dir/.squirrel/profile-seen/$session_id"
  if [ -f "$seen_file" ]; then
    # FIXED MINOR (this cycle): the test is "is the SEEN STAMP strictly
    # newer than profile.md", and reinjection happens unless it is - so
    # an exact mtime TIE reinjects. It used to be the mirror image,
    # `find "$profile_file" -newer "$seen_file"`, which is also strictly
    # newer and therefore lost the tie the other way: a profile.md and a
    # seen stamp landing on the same mtime (one-second filesystem
    # granularity, or a tune written inside the same second the stamp
    # was touched) meant the tune was NEVER propagated to that session
    # again. See the P3 paragraph in this file's header for why a
    # redundant reinjection is the better of the two failure modes.
    #
    # Note this also flips what a FAILING `find` does: seen_newer is
    # then empty, which now means reinject rather than stay silent -
    # the same safe direction, for the same reason.
    seen_newer=$(find "$seen_file" -newer "$profile_file" 2>/dev/null) || seen_newer=""
    [ -z "$seen_newer" ] || { printf ''; return 0; }
  fi

  # The stamp is attempted BEFORE anything is emitted, and what gets
  # emitted depends on whether it landed. See touch_profile_seen and
  # format_profile_seen_unavailable above for why this path must not
  # emit the body when it cannot record that it did: reinjecting a body
  # this session can never mark as seen is the per-prompt tax that fix
  # exists to remove, and it recurs for the whole session.
  if ! touch_profile_seen "$home_dir" "$raw_session_id"; then
    printf '%s' "$PROFILE_SEEN_UNAVAILABLE_NOTICE"
    return 0
  fi

  profile_body=$(cat "$profile_file" 2>/dev/null) || profile_body=""
  profile_body=$(cap_profile_body "$profile_body")
  format_profile_framing "$profile_file" "$profile_body"
  return 0
}

# --- Context assembly -------------------------------------------------
build_context() {
  input=$1
  cwd=$(extract_field "$input" "cwd")
  raw_session_id=$(extract_field "$input" "session_id")

  home_dir="${HOME:-}"
  squirrel_dir="$home_dir/.squirrel"
  profile_file="$squirrel_dir/profile.md"
  checkpoints_dir="$squirrel_dir/checkpoints"
  off_dir="$squirrel_dir/off"
  seen_prune_dir="$squirrel_dir/profile-seen"

  # THE EMPTY-$HOME GUARD (audit fix, LOW). Every read and emit site in
  # this function already tests `[ -n "$home_dir" ]` before using a path
  # derived from it; the three pruners did not, and they are the only
  # sites here that DELETE. With $HOME unset, `$squirrel_dir` is
  # "/.squirrel" and each pruner would aim a `find ... -exec rm -f` at a
  # path rooted at "/". Nothing was reachable in practice - each pruner
  # opens with `[ -d ]`, and "/.squirrel/off" does not exist - but that is
  # an accident of the filesystem, not a decision this file made, and it
  # is the wrong thing for a delete to depend on. Stated once, here,
  # rather than three times inside the pruners: they take a directory,
  # not a $HOME, and this is the only place that knows the difference.
  if [ -n "$home_dir" ]; then
    prune_stale_off_flags "$off_dir"
    # Same call site as the other two pruners, and SessionStart-only for
    # the same reason: handle_user_prompt_submit's contract is explicitly
    # "Never prunes" (it runs on the hot path of every message).
    prune_stale_profile_seen "$seen_prune_dir"
  fi

  slug=$(project_slug "$cwd")
  session_dir="$checkpoints_dir/$slug"
  # The pre-P1 flat path. Named here exactly once, only ever read, and
  # handed to /squirrel:pickup so it can fold it in - see "LEGACY FLAT
  # FILE" in the header.
  legacy_checkpoint_file="$checkpoints_dir/$slug.md"

  session_file_name=$(session_checkpoint_name "$raw_session_id") || session_file_name=""
  [ -n "$session_file_name" ] || session_file_name="anon-$$.md"
  checkpoint_file="$session_dir/$session_file_name"

  off_token=$(session_off_token "$raw_session_id") || off_token=""
  [ -n "$off_token" ] || off_token="anon-$$"

  # The third pruner, guarded for the reason given at the other two
  # above. Separate `if` rather than folded in with them because it has
  # to run after $session_dir is computed, and that needs $slug.
  if [ -n "$home_dir" ]; then
    prune_stale_session_checkpoints "$session_dir"
  fi

  injected_real_profile=0
  if [ -n "$home_dir" ] && [ -f "$profile_file" ]; then
    profile_body=$(cat "$profile_file" 2>/dev/null) || profile_body=""
    profile_body=$(cap_profile_body "$profile_body")
    context=$(format_profile_framing "$profile_file" "$profile_body")
    injected_real_profile=1
  else
    context="squirrel-mode: no profile found yet. Suggest /squirrel:init once, briefly."
  fi

  migration_notice=$(detect_old_data_dir "$home_dir" "$squirrel_dir")
  if [ -n "$migration_notice" ]; then
    context="$context

$migration_notice"
  fi

  context="$context

Session working directory: $cwd
Session off-token: $off_token
Project checkpoint directory: $session_dir
Project checkpoint path: $checkpoint_file"

  # THE HOARD SEARCH COMMAND - the absolute path /squirrel:dig runs
  # through the Bash tool. See $script_dir at the top of this file for why
  # the path is injected at all rather than built by the skill.
  #
  # EMITTED BELOW THE "Session off-token:" LINE, deliberately and not
  # incidentally. skills/dig/SKILL.md decides which of several lines
  # spelled like this one is squirrel-mode's by POSITION - only a line
  # standing below the LAST off-token line counts - because a profile body
  # quoted above these lines could otherwise spell this one exactly,
  # naming any command it likes, and acting on this line RUNS that
  # command. A hook that emitted it above the off-token line would hand a
  # forged copy the win. neutralise_forged_lines above now marks such a
  # line inside the body as well, and this ordering is kept exactly as it
  # was rather than relied on less: that step fails open, and on that path
  # position is what is left. tests/test_hooks.sh HOARD-7 asserts the
  # ordering rather than trusting this comment; HOARD-8 asserts a forging
  # profile cannot displace it, and HOARD-12 that it cannot spell it.
  #
  # Its own `if`, guarded at the call site like every other fallible step
  # in this function: an empty $script_dir (a failed `cd` at the top) or a
  # missing sibling script emits NO line at all, rather than naming a
  # command that is not there. /squirrel:dig treats an absent line as
  # "the hoard search is unavailable" and says so in one line, which is
  # the honest outcome - a line naming a nonexistent path would instead
  # spend a permission prompt to reach a failed command. Placed here,
  # before the checkpoint list block below, so it can never sit inside
  # that block and be mistaken for one of its paths.
  if [ -n "$script_dir" ] && [ -f "$script_dir/hoard-search.sh" ]; then
    context="$context
Hoard search command: $script_dir/hoard-search.sh"
  fi

  # The enumerated list, newest first, optionally closed by the
  # incompleteness marker - see checkpoint_file_lines for both grammars
  # and for why either exists at all. Gated on $home_dir the
  # same way the two blocks below are, and appended only when the
  # function actually produced something, so an absent, untrusted or
  # empty directory adds no line of any kind. Guarded at the call site
  # exactly like every other fallible step in this function.
  #
  # $off_token is handed over so the block's header - and the marker, for
  # the same reason and with sharper stakes, a marker being an
  # instruction to go enumerate - can carry it. That is
  # what makes the header unforgeable by the profile body quoted above:
  # see "WHY THE HEADER CARRIES THE SESSION TOKEN" at
  # checkpoint_file_lines. It is the SAME variable emitted on the
  # "Session off-token:" line a few lines up - one derivation, two uses,
  # so /squirrel:pickup comparing them can never be comparing two
  # independently computed values.
  if [ -n "$home_dir" ]; then
    checkpoint_list=$(checkpoint_file_lines "$session_dir" "$off_token") || checkpoint_list=""
    if [ -n "$checkpoint_list" ]; then
      context="$context
$checkpoint_list"
    fi
  fi

  if [ -n "$home_dir" ] && [ -f "$legacy_checkpoint_file" ]; then
    context="$context
Legacy checkpoint file: $legacy_checkpoint_file"
  fi

  if [ -n "$home_dir" ] && { checkpoint_dir_has_any "$session_dir" || [ -f "$legacy_checkpoint_file" ]; }; then
    context="$context
Resume available - run /squirrel:pickup"
  fi

  if [ "$injected_real_profile" -eq 1 ]; then
    # `|| true` because touch_profile_seen now REPORTS failure rather
    # than swallowing it, and this file is `set -e`: an unwritable
    # ~/.squirrel must not abort build_context half-assembled. There is
    # nothing for SessionStart to do with the answer - it has already
    # injected the profile body unconditionally, which is what makes a
    # missing stamp a UserPromptSubmit concern only.
    touch_profile_seen "$home_dir" "$raw_session_id" || true
  fi

  printf '%s' "$context"
}

# --- Entry ------------------------------------------------------------
#
# Read stdin once. UserPromptSubmit takes the P3 plain-text path;
# SessionStart (and missing/other hook_event_name) keep today's
# emit_json SessionStart contract.
input=$(cat)
hook_event_name=$(extract_field "$input" "hook_event_name")

case "$hook_event_name" in
  UserPromptSubmit)
    if output=$(handle_user_prompt_submit "$input" 2>/dev/null); then
      :
    else
      output=""
    fi
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
    fi
    exit 0
    ;;
esac

if context=$(build_context "$input" 2>/dev/null); then
  :
else
  # Last-resort fallback: something inside build_context failed in a way
  # its own inner guards did not anticipate. Still emit a safe, valid
  # line rather than nothing, and still exit 0.
  context="squirrel-mode: no profile found yet. Suggest /squirrel:init once, briefly."
fi

# emit_json is invoked the same guarded way build_context is above, not
# as a bare statement: even though emit_json's own body already always
# `return 0`s by construction, calling it as the condition of an `if`
# means `set -e` catches any FUTURE change that breaks that guarantee at
# the exact point of failure, and this hardcoded, dependency-free string
# below stands in rather than ever letting a non-zero exit or missing
# stdout escape this script.
if json_out=$(emit_json "$context" 2>/dev/null); then
  printf '%s\n' "$json_out"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"squirrel-mode: no profile found yet. Suggest /squirrel:init once, briefly."}}\n'
fi
exit 0
