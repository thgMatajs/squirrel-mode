#!/bin/sh
# load-profile.sh - SessionStart hook.
#
# Fires on session startup/resume/clear/compact (matcher in hooks.json).
# Emits hookSpecificOutput.additionalContext containing:
#   - the user's ~/.claude/squirrel/profile.md, if it exists, with a
#     line stating its fields override the output style's defaults; or
#     a single short line suggesting /squirrel:init if it does not.
#   - the RESOLVED, absolute checkpoint path for this project's `cwd`
#     (tech-lead Decision 1: the model cannot compute the project-slug
#     algorithm itself, so the path must be handed to it, always, even
#     before any checkpoint file exists).
#   - "Resume available - run /squirrel:pickup" if a checkpoint already
#     exists for this project - never the checkpoint's own body text
#     (PLAN.md is explicit that the contents are not dumped into chat).
# It also prunes stale ~/.claude/squirrel/off/<session_id> flag files
# (see check-off-flag.sh) so they do not accumulate forever.
#
# Contract: this hook runs on every session start. It must NEVER exit
# non-zero and must always print valid JSON on stdout, no matter how
# broken its input or how bare/missing ~/.claude/squirrel/ is - a
# fresh install (nothing under ~/.claude/squirrel/ at all) is the
# common case on turn one, not an edge case.
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
# jq dependency: PREFERRED, not required. jq is used when present on
# PATH (correct JSON construction and field extraction, including
# proper escaping) but every jq call has an awk fallback so a machine
# without jq installed still gets correct behaviour, just via a
# narrower (line-oriented for extraction, byte-oriented for escaping)
# parser. See extract_field() and emit_json() below. The escaping
# fallback (json_escape) runs entirely under `LC_ALL=C` so the result
# does not depend on the invoking shell's locale - see json_escape's
# own comment for why that matters even when jq IS present elsewhere
# in this file.
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
# ADR-0005: `/squirrel:off` writes ~/.claude/squirrel/off/<session_id>
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
    if out=$(jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' 2>/dev/null); then
      printf '%s\n' "$out"
      return 0
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

  home_dir="${HOME:-}"
  squirrel_dir="$home_dir/.claude/squirrel"
  profile_file="$squirrel_dir/profile.md"
  checkpoints_dir="$squirrel_dir/checkpoints"
  off_dir="$squirrel_dir/off"

  prune_stale_off_flags "$off_dir"

  slug=$(project_slug "$cwd")
  checkpoint_file="$checkpoints_dir/$slug.md"

  if [ -n "$home_dir" ] && [ -f "$profile_file" ]; then
    profile_body=$(cat "$profile_file" 2>/dev/null) || profile_body=""
    profile_body=$(cap_profile_body "$profile_body")
    context="A squirrel-mode profile exists at $profile_file. These field values OVERRIDE the defaults already given to you in the squirrel-mode output style, field by field.

$profile_body"
  else
    context="squirrel-mode: no profile found yet. Suggest /squirrel:init once, briefly."
  fi

  context="$context

Project checkpoint path: $checkpoint_file"

  if [ -n "$home_dir" ] && [ -f "$checkpoint_file" ]; then
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
