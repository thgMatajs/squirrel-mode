#!/bin/sh
# allow-checkpoint.sh - PreToolUse hook (matcher: Write|Edit).
#
# ADR-0002 + tech-lead Decision 2: the plugin auto-approves writes to
# its OWN checkpoint directory only, so a checkpoint update never costs
# a permission prompt. `hooks.json` cannot express this safely on its
# own (the `if` field's permission-rule syntax cannot see the user's
# real $HOME at plugin-build time, and it is unverified whether it even
# expands `~`/$HOME) - so it matches broadly on Write|Edit and hands
# the actual decision to THIS script, which reads `tool_input.file_path`
# from stdin and returns `allow` or `defer`. It never returns `deny`:
# denying is not this hook's job, and `defer` hands the decision back
# to the normal permission flow exactly as if this hook did not exist.
#
# THIS SCRIPT IS A SECURITY BOUNDARY. `allow` must only ever come back
# for a path that genuinely, after normalisation, resolves inside
# $HOME/.claude/squirrel/checkpoints/. Two layers enforce that:
#
#   Layer 1 (always active, pure POSIX sh, no external tool required):
#   normalize_path() lexically resolves "." and ".." segments in the
#   given absolute path AGAINST THE PATH TEXT ITSELF - no filesystem
#   access, no symlink awareness - and the result is compared against
#   the checkpoints directory via a LITERAL (non-glob) prefix strip,
#   `${normalized#"$prefix"}`, not a `case`/glob pattern match. This
#   matters: quoting a variable inside a `${var#pattern}` pattern makes
#   its glob-metacharacters (`*`, `?`, `[`) literal per POSIX, which a
#   bare `case "$x" in $prefix*)` would not guarantee if $HOME ever
#   contained one. This layer alone defeats both required attacks:
#     - traversal: ".../checkpoints/../../../.ssh/id_rsa" normalizes to
#       "/.../.ssh/id_rsa", which does not start with the checkpoints
#       prefix at all.
#     - prefix-escape: ".../checkpoints-evil/x" is never touched by the
#       ".." logic (no such segment) and is rejected by the literal
#       prefix strip because "checkpoints-evil" is not "checkpoints"
#       followed by "/" - the boundary character is checked, not merely
#       the substring.
#   Layer 1 has no symlink awareness at all - a symlink's target is a
#   filesystem fact, not something present in the path's own text - so
#   it cannot by itself defeat a symlink planted AT or BELOW
#   checkpoints_dir.
#
#   Layer 2 (ALWAYS ACTIVE, the only fallback, zero external tools):
#   component_walk_has_symlink() tests checkpoints_dir ITSELF, then
#   walks every path component between checkpoints_dir and the leaf -
#   "escape-dir", then "escape-dir/evil.md", and so on - and defers the
#   instant `[ -L ... ]` (a POSIX shell builtin, not an external
#   command) finds ANY of them, INCLUDING checkpoints_dir, to be a
#   symlink, regardless of where it points. It never calls `realpath`
#   or `readlink` at all, so it works identically with an empty PATH.
#
# FIXED BLOCKER (cycle 3): before this fix, `component_walk_has_symlink`
# set `current=$base` and only tested `[ -L "$current" ]` AFTER
# appending each component of the relative remainder - so `base` itself
# (checkpoints_dir) was never tested. A symlink planted AT
# checkpoints_dir - `ln -s $HOME/outside-secret
# $HOME/.claude/squirrel/checkpoints` - walked straight past that check
# and into a since-removed Layer 3 that compared
# `best_effort_realpath(dirname of file_path)` against
# `best_effort_realpath(checkpoints_dir)`: with the symlink AT
# checkpoints_dir, both sides resolve through the SAME symlink and
# always compare equal, so Layer 3 could never have caught this, with
# or without `realpath` installed - it is one level shallower than "a
# symlink below checkpoints_dir", not "no additional check", and no
# comment framing it as tool-absence-only was accurate. The fix is the
# single `[ -L "$base" ]` test added at the top of
# component_walk_has_symlink(), below.
#
# WHERE THE TRUST BOUNDARY SITS, DELIBERATELY: this walk starts AT
# checkpoints_dir and never inspects anything above it. `checkpoints/`
# is created by this plugin itself (on first checkpoint write or
# `/squirrel:init`), so a symlink AT or BELOW it is never legitimate -
# every one of those must defer. `$HOME/.claude` and
# `$HOME/.claude/squirrel`, by contrast, are ordinary user configuration
# that this plugin did not create: dotfile managers (chezmoi, stow,
# yadm) routinely make `~/.claude` itself a symlink into a dotfiles
# repo, and that is a legitimate, common setup, not an attack. Walking
# the whole ancestry back to $HOME and rejecting every symlink in it -
# the reviewer's original suggestion - was REJECTED by the tech lead for
# exactly this reason: it would defer every checkpoint write for any
# user running one of those tools, which is a regression, not a fix.
# See scenario 29/30 (attack: symlink AT checkpoints_dir defers) and
# scenario 31 (regression guard: symlink AT ~/.claude still allows) in
# tests/test_hooks.sh.
#
# LAYER 3 WAS REMOVED, NOT RELABELLED. The version this replaces had a
# third layer - resolve_target_dir() + best_effort_realpath(), preferring
# `realpath` then `readlink -f` - layered "additively" on top of Layer 2
# to catch a symlink ABOVE checkpoints_dir that Layer 2's walk could not
# see. Two things are true at once: (a) that framing is now explicitly
# the wrong thing to do (see the trust-boundary note above - an ancestor
# symlink must NOT be rejected), and (b) it is also now PROVABLY DEAD
# CODE given the Layer-2 fix above, independent of (a). Proof sketch:
# Layer 3 only ever ran after Layer 2 had already confirmed checkpoints_dir
# and every component down to the leaf are ALL symlink-free. Resolving an
# already-symlink-free absolute path with `realpath`/`readlink -f` can
# only ever rewrite its SHARED ancestor prefix (whatever lies above
# checkpoints_dir, symlinked or not) - both sides of Layer 3's comparison
# share that exact same prefix, because both are built from the same
# `$home_dir/.claude/squirrel/checkpoints` string - so resolving it never
# changes whether one is a prefix of the other. Layer 3 therefore could
# never turn Layer 2's "no symlink found" into a rejection, in any
# configuration, with or without `realpath`/`readlink` on PATH: it was
# dead weight that read as protection, which is the precise anti-pattern
# that produced the wrong header comment this fix corrects. Keeping it
# around "just in case", even re-labelled, invites the same rot again the
# next time Layer 2 changes and Layer 3 does not; removing it is the
# more honest option, and it also deletes two `realpath`/`readlink`
# subprocess spawns from the hot path of every single checkpoint write.
# tests/test_hooks.sh scenario 25 (unchanged in number, still exercising
# the same symlink-below-checkpoints_dir fixtures) keeps proving Layer 2
# alone - not any realpath-based layer - is what defeats the symlink
# attack with both tools stripped from PATH.
#
# FIXED MAJOR (cycle 3, quadratic-time DoS): normalize_path() and
# component_walk_has_symlink() are both O(n) per segment processed
# against a shrinking-but-still-linear-cost remainder string, so total
# cost is quadratic in the number of "/"-separated segments in
# `file_path` - and `file_path` is an arbitrary JSON string, not a real
# filesystem path, so no OS-level `PATH_MAX` ever protected this. Both
# functions ran unconditionally, before any prefix check, so even a
# `file_path` with nothing to do with checkpoints/ paid the full cost.
# Measured on the pre-fix script (this machine, single-char segments):
# 200 segs 27ms, 500 segs 80ms, 1000 segs 317ms, 1500 segs 945ms, 3000
# segs 6118ms - and an unrelated path (outside $HOME entirely) paid the
# same cost, stalling every Write/Edit tool call in the session. The
# fix below caps `file_path` at MAX_FILE_PATH_LEN bytes and defers
# immediately, before normalize_path or component_walk_has_symlink ever
# run on it - removing the exposure regardless of how many segments a
# malicious `file_path` claims to have. Rewriting normalize_path's
# lexical scan to be strictly linear was considered and deliberately
# NOT done: the only safe, POSIX-portable technique available (IFS-based
# word-splitting via unquoted `set -- $remaining`) reintroduces exactly
# the glob-expansion trap this file's own Layer-1 comment above warns
# against (a literal `*` in file_path must never be glob-expanded), and
# a bug introduced while "optimising" a security boundary is a worse
# outcome than a bounded-but-still-measurable cost under the cap. The
# cap is what removes the DoS; see tests/test_hooks.sh scenario 33 for
# the permanent regression assertion and timing.
#
# `set -e` vs. "never `deny`, never crash, always valid JSON": exactly
# the load-profile.sh pattern. `set -e` stays on inside decide() so an
# unexpected failure aborts THAT FUNCTION at the point of failure
# rather than silently continuing with wrong state; decide() is only
# ever called as `if decision=$(decide ...); then ... fi`, which is
# exempt from `set -e`, so nothing inside it can make this script exit
# non-zero. Whatever decide() does or does not manage to print, the
# final `case` below always emits exactly one well-formed JSON decision
# and this script always exits 0.
#
# jq: preferred, not required - see extract_field's sed fallback.
set -eu

# MAX_FILE_PATH_LEN: the DoS cap (see "FIXED MAJOR" above). 4096 bytes
# comfortably covers every real filesystem path this plugin will ever
# be asked to write (well past PATH_MAX on every OS this plugin ships
# to) while bounding the absolute worst case of the quadratic scan
# below to a fixed, small number of segments - not to "fast", but to
# "bounded, and never growing with attacker input".
MAX_FILE_PATH_LEN=4096

extract_field() {
  # extract_field <json> <key>: reads a top-level string field, OR (as a
  # fallback within the same call) `.tool_input.<key>`, from <json>.
  # That second path is what lets one call site pull `file_path` out of
  # `tool_input.file_path` without a separate nested-access helper. jq's
  # `//` also swallows an error from a null `.tool_input` (indexing null
  # normally raises), so a completely absent `tool_input` degrades to
  # "no value" rather than a jq failure.
  json=$1
  key=$2
  if command -v jq >/dev/null 2>&1; then
    if val=$(printf '%s' "$json" | jq -r --arg k "$key" '(.[$k] // .tool_input[$k] // empty)' 2>/dev/null); then
      if [ "$val" != "null" ] && [ -n "$val" ]; then
        printf '%s' "$val"
        return 0
      fi
    fi
  fi
  printf '%s\n' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

# normalize_path <absolute-path>: purely lexical (no filesystem access)
# resolution of "." and ".." segments and repeated slashes. Prints ""
# and returns 1 if <path> does not start with "/" - a relative
# file_path is always rejected outright by the caller, never guessed
# to be "relative to" anything.
normalize_path() {
  p=$1
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  result=""
  remaining=$p
  while [ -n "$remaining" ]; do
    remaining=${remaining#/}
    case "$remaining" in
      */*)
        seg=${remaining%%/*}
        remaining=${remaining#*/}
        ;;
      *)
        seg=$remaining
        remaining=""
        ;;
    esac
    case "$seg" in
      "" | ".") ;;
      "..")
        result=${result%/*}
        ;;
      *)
        result="$result/$seg"
        ;;
    esac
  done
  [ -n "$result" ] || result="/"
  printf '%s' "$result"
  return 0
}

# component_walk_has_symlink <base> <relative-path>: THE Layer 2
# defence, and - since the cycle-3 fix - the ONLY symlink defence this
# script has (see "LAYER 3 WAS REMOVED" above). First tests <base>
# ITSELF (this is the cycle-3 BLOCKER fix: <base> is always
# checkpoints_dir at the one call site below, and a symlink planted
# there is never legitimate - see the header's trust-boundary note for
# why this stops at <base> and never inspects anything above it). Then
# walks every component of <relative-path> - for "escape-dir/evil.md"
# that is "escape-dir", then "escape-dir/evil.md" - joined onto <base>,
# and returns 0 (true - a symlink WAS found) the instant `[ -L ... ]`
# says any one of those, INCLUDING <base>, is itself a symlink. `[ -L ]`
# is a POSIX shell builtin: no `realpath`, no `readlink`, no external
# command of any kind, so this works identically whether or not either
# tool is on PATH. Returns 1 (false) once <base> and every component
# have been walked with none found to be a symlink. A component that
# does not exist yet (the ordinary case for a brand-new checkpoint
# write, or for the leaf of an about-to-be-created file) is correctly
# "not a symlink" either, per `-L`'s own semantics - so this never
# blocks a legitimate first-time write, only ever a planted symlink.
component_walk_has_symlink() {
  base=$1
  rel=$2
  if [ -L "$base" ]; then
    return 0
  fi
  current=$base
  remaining=$rel
  while [ -n "$remaining" ]; do
    case "$remaining" in
      */*)
        seg=${remaining%%/*}
        remaining=${remaining#*/}
        ;;
      *)
        seg=$remaining
        remaining=""
        ;;
    esac
    if [ -n "$seg" ]; then
      current="$current/$seg"
      if [ -L "$current" ]; then
        return 0
      fi
    fi
  done
  return 1
}

decide() {
  input=$(cat)
  tool_name=$(extract_field "$input" "tool_name")
  file_path=$(extract_field "$input" "file_path")

  case "$tool_name" in
    Write | Edit) ;;
    *)
      printf 'defer'
      return 0
      ;;
  esac

  # DoS cap (see "FIXED MAJOR" in the header): reject an oversized
  # file_path OUTRIGHT, before normalize_path or
  # component_walk_has_symlink ever run on it - both are O(segments^2)
  # and file_path is attacker-controlled JSON, not a filesystem path
  # bounded by PATH_MAX. `${#file_path}` is POSIX parameter-length
  # expansion (see check-off-flag.sh's identical use), not a bashism.
  if [ "${#file_path}" -gt "$MAX_FILE_PATH_LEN" ]; then
    printf 'defer'
    return 0
  fi

  case "$file_path" in
    /*) ;;
    *)
      printf 'defer'
      return 0
      ;;
  esac

  home_dir="${HOME:-}"
  if [ -z "$home_dir" ]; then
    printf 'defer'
    return 0
  fi

  # normalize_path is applied to checkpoints_dir too, not just
  # file_path: $HOME is outside this script's control and can itself
  # contain a repeated slash (observed in practice: some platforms set
  # TMPDIR with a trailing "/", so a $HOME built under it - as this
  # repo's own tests do - carries "//" into every path derived from
  # it). Comparing a LEXICALLY NORMALIZED file_path against an
  # unnormalized checkpoints_dir would make the literal-prefix check
  # below mismatch on nothing but whitespace-equivalent slashes,
  # producing a false "defer" for an otherwise legitimate write - a
  # safe failure mode (never a false "allow"), but still a correctness
  # bug worth closing rather than shipping.
  checkpoints_dir=$(normalize_path "$home_dir/.claude/squirrel/checkpoints") || checkpoints_dir="$home_dir/.claude/squirrel/checkpoints"

  normalized=$(normalize_path "$file_path") || { printf 'defer'; return 0; }

  # Layer 1: literal (non-glob) prefix containment.
  prefix="$checkpoints_dir/"
  after=${normalized#"$prefix"}
  if [ "$after" = "$normalized" ] || [ -z "$after" ]; then
    printf 'defer'
    return 0
  fi

  # Layer 2: unconditional POSIX component walk (see header) - the
  # only, always-active fallback, zero external tools. Tests
  # checkpoints_dir itself first, then defers the instant any component
  # between checkpoints_dir and the leaf is itself a symlink.
  if component_walk_has_symlink "$checkpoints_dir" "$after"; then
    printf 'defer'
    return 0
  fi

  printf 'allow'
  return 0
}

if decision=$(decide 2>/dev/null); then
  :
else
  decision="defer"
fi

case "$decision" in
  allow)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"squirrel-mode: write targets its own checkpoint directory (ADR-0002)."}}\n'
    ;;
  *)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}\n'
    ;;
esac
exit 0
