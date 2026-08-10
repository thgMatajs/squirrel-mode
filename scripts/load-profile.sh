#!/bin/sh
# load-profile.sh - SessionStart hook.
#
# Fires on session startup/resume/clear/compact (matcher in hooks.json).
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
#     to write a sentinel the check-off-flag.sh hook can later match
#     against ITS OWN `cwd` - a value the model computes itself, e.g. by
#     running a shell command, can disagree with that even on a healthy
#     machine (a symlinked project path, a trailing slash, a different
#     shell context), and the failure is silent: the sentinel just never
#     matches. This line is ALWAYS emitted, even when `cwd` is empty, so
#     the skill has a definite, always-present "missing or empty" case to
#     branch on - the same discipline `/squirrel:pickup` already applies
#     to the checkpoint-path line below).
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
#   - "Legacy checkpoint file: <path>" if, and only if, a pre-P1 flat
#     checkpoint file still exists for this project - see
#     "P1 PER-SESSION CHECKPOINT LAYOUT" below.
#   - "Resume available - run /squirrel:pickup" if a checkpoint already
#     exists for this project - never the checkpoint's own body text
#     (PLAN.md is explicit that the contents are not dumped into chat).
# It also prunes stale ~/.squirrel/off/<session_id> flag files
# (see check-off-flag.sh) and stale per-session checkpoint files (see
# prune_stale_session_checkpoints) so neither accumulates forever.
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
# Contract: this hook runs on every session start. It must NEVER exit
# non-zero and must always print one well-formed SessionStart JSON
# object on stdout for every command FAILURE it depends on, and for
# every broken / bare / missing ~/.squirrel/ layout a fresh install can
# present (nothing under ~/.squirrel/ at all is the common case on turn
# one, not an edge case). Audited under a scratch HOME (P4 item 2): bad
# HOME shapes, unreadable or non-file profile.md, malformed / empty /
# closed-as-/dev/null stdin, jq absent, jq exiting non-zero, jq exiting
# 0 with the literal `null` or with no output, a non-empty object that
# is not a SessionStart payload, one-at-a-time absence of
# cksum/od/cut/wc/tail/basename/tr/find/awk/sed, locales C and
# pt_BR.UTF-8, and C0 / invalid-UTF-8 profile bodies all return exit 0
# with a parseable SessionStart object (the jq-null and jq-empty cases
# used to print `null` / a blank line and are closed in emit_json
# below; the non-SessionStart-object case used to be emitted verbatim
# and is closed by the same function's hookEventName check; the rest
# already held).
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
# narrower (line-oriented for extraction, byte-oriented for escaping)
# parser. See extract_field() and emit_json() below. The escaping
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

# --- JSON field extraction ------------------------------------------
#
# extract_field <json> <key>: best-effort read of a top-level string
# field named <key> from <json>. Prefers jq; falls back to a
# line-oriented sed scan for `"<key>": "<value>"` when jq is not on
# PATH. The sed fallback assumes the key/value pair for a STRING field
# sits on one line - true for both compact and pretty-printed JSON,
# since a string value never legitimately contains a raw newline.
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
CHECKPOINT_PRUNE_MIN_AGE_DAYS=30
CHECKPOINT_PRUNE_KEEP_NEWEST=10
CHECKPOINT_PRUNE_MAX_CANDIDATES=100

prune_stale_session_checkpoints() {
  slug_dir=$1
  [ -d "$slug_dir" ] || return 0

  examined=0
  # Pathname expansion is ON for the for-lists below (portable depth-1).
  # Session file names are sanitised to [A-Za-z0-9._-]+, so a literal
  # "*" or "?" cannot appear in a real candidate name and re-expand.
  for candidate in "$slug_dir"/*; do
    # Regular file only: [ -f ] follows symlinks, so require [ ! -L ]
    # too (same trust boundary as checkpoint_dir_has_any). A depth-1
    # symlink to a regular file must neither be pruned as a candidate
    # nor inflate newer_count and delete a real ancient session file.
    [ -f "$candidate" ] && [ ! -L "$candidate" ] || continue
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
      [ -f "$peer" ] && [ ! -L "$peer" ] || continue
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
# regular file that is not a symlink. This is what drives the "Resume
# available" line now that a project's memory lives in a directory
# rather than in one file. A dangling symlink is not a regular file and
# correctly does not count; a symlink to a regular file is also
# rejected - only the plugin writes real checkpoint files here, so a
# symlink is never legitimate resume data (same trust boundary
# allow-checkpoint.sh enforces on the write path).
checkpoint_dir_has_any() {
  dir=$1
  [ -d "$dir" ] || return 1
  for entry in "$dir"/*; do
    if [ -f "$entry" ] && [ ! -L "$entry" ]; then
      return 0
    fi
  done
  return 1
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
# profile.md is injected into the model's context VERBATIM, framed as
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
PROFILE_MAX_LINES=100
PROFILE_MAX_BYTES=4096

# strip_incomplete_utf8_tail <text>: FIXED MINOR (cycle 3) - `cut -b`
# below slices at an exact BYTE position with no awareness of UTF-8
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
      printf '%s' "$text" | cut -b "1-$keep"
    fi
  else
    printf '%s' "$text"
  fi
}

cap_profile_body() {
  body=$1
  truncated=0

  line_count=$(printf '%s\n' "$body" | wc -l | awk '{print $1}')
  if [ "$line_count" -gt "$PROFILE_MAX_LINES" ]; then
    body=$(printf '%s\n' "$body" | head -n "$PROFILE_MAX_LINES")
    truncated=1
  fi

  byte_count=$(printf '%s' "$body" | wc -c | awk '{print $1}')
  if [ "$byte_count" -gt "$PROFILE_MAX_BYTES" ]; then
    body=$(printf '%s' "$body" | cut -b "1-$PROFILE_MAX_BYTES")
    body=$(strip_incomplete_utf8_tail "$body")
    truncated=1
  fi

  if [ "$truncated" -eq 1 ]; then
    body="$body
[squirrel-mode: profile.md truncated - exceeds the ${PROFILE_MAX_LINES}-line / ${PROFILE_MAX_BYTES}-byte cap]"
  fi

  printf '%s' "$body"
}

# --- Context assembly -------------------------------------------------
build_context() {
  input=$(cat)
  cwd=$(extract_field "$input" "cwd")
  raw_session_id=$(extract_field "$input" "session_id")

  home_dir="${HOME:-}"
  squirrel_dir="$home_dir/.squirrel"
  profile_file="$squirrel_dir/profile.md"
  checkpoints_dir="$squirrel_dir/checkpoints"
  off_dir="$squirrel_dir/off"

  prune_stale_off_flags "$off_dir"

  slug=$(project_slug "$cwd")
  session_dir="$checkpoints_dir/$slug"
  # The pre-P1 flat path. Named here exactly once, only ever read, and
  # handed to /squirrel:pickup so it can fold it in - see "LEGACY FLAT
  # FILE" in the header.
  legacy_checkpoint_file="$checkpoints_dir/$slug.md"

  session_file_name=$(session_checkpoint_name "$raw_session_id") || session_file_name=""
  [ -n "$session_file_name" ] || session_file_name="anon-$$.md"
  checkpoint_file="$session_dir/$session_file_name"

  prune_stale_session_checkpoints "$session_dir"

  if [ -n "$home_dir" ] && [ -f "$profile_file" ]; then
    profile_body=$(cat "$profile_file" 2>/dev/null) || profile_body=""
    profile_body=$(cap_profile_body "$profile_body")
    context="A squirrel-mode profile exists at $profile_file. These field values OVERRIDE the defaults already given to you in the squirrel-mode output style, field by field.

$profile_body"
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
Project checkpoint directory: $session_dir
Project checkpoint path: $checkpoint_file"

  if [ -n "$home_dir" ] && [ -f "$legacy_checkpoint_file" ]; then
    context="$context
Legacy checkpoint file: $legacy_checkpoint_file"
  fi

  if [ -n "$home_dir" ] && { checkpoint_dir_has_any "$session_dir" || [ -f "$legacy_checkpoint_file" ]; }; then
    context="$context
Resume available - run /squirrel:pickup"
  fi

  printf '%s' "$context"
}

if context=$(build_context 2>/dev/null); then
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
