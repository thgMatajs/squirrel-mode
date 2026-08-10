#!/bin/sh
# allow-checkpoint.sh - PreToolUse hook (matcher: Write|Edit|Read).
#
# ADR-0002 + tech-lead Decision 2: the plugin auto-approves reads AND
# writes of its OWN checkpoint directory only, so a checkpoint
# interaction never costs a permission prompt. `hooks.json` cannot
# express this safely on its own (the `if` field's permission-rule
# syntax cannot see the user's real $HOME at plugin-build time, and it
# is unverified whether it even expands `~`/$HOME) - so it matches
# broadly on Write|Edit|Read and hands the actual decision to THIS
# script, which reads `tool_input.file_path` from stdin and returns
# `allow` or `defer`. It never returns `deny`: denying is not this
# hook's job, and `defer` hands the decision back to the normal
# permission flow exactly as if this hook did not exist.
#
# FIXED BLOCKER (S10-1): the matcher and this script originally covered
# only Write and Edit. Every checkpoint interaction actually STARTS with
# a Read - `/squirrel:pickup` reads the checkpoint file before showing
# anything, and rule 14's own update path has to read the current Done
# log to keep only the last 10 entries before it can write the new one
# - so the very first tool call of a checkpoint interaction was falling
# through to the normal permission prompt, contradicting ADR-0002, rule
# 14's "do not ask permission first", and README's disclosure that a
# checkpoint update never stops mid-task to ask. A live probe caught
# this; no static test could, because every existing scenario asked this
# script about `Write`. `Read` is now handled identically to `Write` and
# `Edit` below - same path validation, same symlink defence, same
# length cap - because a read is strictly narrower in risk than a write
# and the boundary must not be loosened to accommodate it.
#
# FIXED MAJOR (S10 review cycle 1, AB1 - field-shadowing bypass): the
# path validated below used to come from a helper that preferred a
# TOP-LEVEL `file_path` over `tool_input.file_path`. The tool's real
# parameters live under `tool_input` (this is the PreToolUse contract
# the paragraph above already describes); the top-level fallback was
# never part of that contract, so a payload carrying a benign top-level
# `file_path` alongside a malicious `tool_input.file_path` made this
# script validate a field the operation never reads and `allow` the
# operation on the field it does. Reproduced for Read, Write, and Edit
# alike, in both the jq path and the sed fallback (the sed fallback had
# the identical bug independently, order-dependent rather than
# preference-dependent - see extract_tool_input_field's own comment,
# below, for the mechanism). Fixed: `file_path` is now read via
# extract_tool_input_field, which reads ONLY `tool_input.file_path`,
# never a sibling top-level field of the same name, in either the jq or
# the sed path. `tool_name` is unaffected and still read from the top
# level (via extract_field) - that is where it legitimately lives in
# the real PreToolUse payload, a sibling of `tool_input`, not nested
# inside it.
#
# THIS SCRIPT IS A SECURITY BOUNDARY. `allow` must only ever come back
# for a path that genuinely, after normalisation, resolves inside
# $HOME/.squirrel/checkpoints/. Two layers enforce that:
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
# $HOME/.squirrel/checkpoints` - walked straight past that check
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
# every one of those must defer. `$HOME/.squirrel` itself, by contrast,
# is ordinary user configuration that this plugin did not create once it
# exists: dotfile managers (chezmoi, stow, yadm) routinely symlink a
# whole config directory like this one into a dotfiles repo, and that is
# a legitimate, common setup, not an attack - the identical trust this
# script gave its old parent directory before the S11 move (see
# docs/adr/0003's Amendment (S11) for that history and why the data
# moved); moving it did not change which ancestor directory is trusted,
# only its name and depth - one level instead of two. Walking the whole
# ancestry back to $HOME and rejecting
# every symlink in it - the reviewer's original suggestion - was
# REJECTED by the tech lead for exactly this reason: it would defer
# every checkpoint write for any user running one of those tools, which
# is a regression, not a fix.
# See scenario 29/30 (attack: symlink AT checkpoints_dir defers) and
# scenario 31 (regression guard: symlink AT ~/.squirrel still allows) in
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
# `$home_dir/.squirrel/checkpoints` string - so resolving it never
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
# and this script always exits 0 - PROVIDED decide() returns AT ALL.
#
# CORRECTED CLAIM (cycle-3 review, AD1): the paragraph above used to stop
# at "always exits 0", stated with no qualification. That is false for
# one input this script cannot bound: a `jq` that is PRESENT on PATH but
# WEDGED - stopped, deadlocked, or otherwise never returns. Reproduced
# directly (this fix): a `jq` shim that loops forever left this script
# still running, with zero bytes of stdout, two seconds in - at which
# point the process was killed externally to end the reproduction, not
# because the script itself ever returned. The `if decision=$(decide
# 2>/dev/null); then ...` wrapper catches decide() FAILING (a non-zero
# exit); it cannot catch decide() never FINISHING, because the shell has
# to wait for that command substitution's subshell - itself blocked
# inside `jq` - to return before the `if` can even be evaluated. No
# construct in POSIX `sh` interrupts a command substitution already in
# flight, and adding one is not this project's call to make: `timeout(1)`
# is GNU coreutils, not POSIX, and is absent from stock macOS - wrapping
# the jq calls in extract_field/extract_tool_input_field with it would
# add a dependency to a security hook to cover a pathological system
# state (a wedged system binary), which is the wrong trade for what it
# buys.
#
# The honest, correctable claim: this script's "always exits 0, always
# exactly one well-formed JSON decision" contract holds for EVERY input
# and for every command FAILURE it depends on - `jq` exiting non-zero,
# `jq` exiting 0 with no output, and `jq` printing the literal string
# `null` are all reproduced (this fix) to defer correctly in well under a
# second (112-272ms, measured on the author's machine - stated as
# machine-specific data, not a portable performance guarantee). It does
# NOT hold for an invoked command that is never given the chance to fail
# or succeed because it never returns at all. That one gap is bounded
# only by the harness's own hook timeout (Claude Code kills a hook
# process that overruns its configured or default timeout), never by
# anything in this script.
#
# jq: REQUIRED for an "allow" decision (S10 review cycle 2, AC1). Without
# it on PATH, extract_tool_input_field below returns nothing, file_path
# resolves empty, and decide() defers - EVERY Write/Edit/Read on a
# checkpoint path falls back to the normal permission prompt instead of
# being auto-approved. This is a deliberate narrowing of the previous
# behaviour, not an oversight: the sed/awk fallback that used to stand in
# for jq could not parse nested JSON (a regex matches text shapes, it
# does not track brace depth, and doing so would be writing a parser by
# another name) - see extract_tool_input_field's own comment for the
# exact reproduction the tech lead found. `tests/run.sh` already treats
# `jq` as a hard prerequisite for running this project's own test suite,
# so requiring it for this one decision is consistent with, not beyond,
# the project's existing posture. This cost is stated in README.md and
# docs/adr/0002-checkpoint-auto-allow.md, wherever the auto-approval
# mechanism is described.
set -eu

# MAX_FILE_PATH_LEN: the DoS cap (see "FIXED MAJOR" above). 4096 bytes
# comfortably covers every real filesystem path this plugin will ever
# be asked to write (well past PATH_MAX on every OS this plugin ships
# to) while bounding the absolute worst case of the quadratic scan
# below to a fixed, small number of segments - not to "fast", but to
# "bounded, and never growing with attacker input".
MAX_FILE_PATH_LEN=4096

extract_field() {
  # extract_field <json> <key>: reads a TOP-LEVEL string field ONLY,
  # e.g. `tool_name` - which the real PreToolUse payload always carries
  # at top level, a sibling of `tool_input`, never nested inside it.
  # Matches the sibling scripts' own `extract_field` (load-profile.sh,
  # check-off-flag.sh), which are top-level-only reads for the same
  # reason. Never reads `tool_input` at all: a field whose real, only
  # home is the top level must not be satisfiable by anything the
  # operation's own parameters carry either (that would be the identical
  # shadowing class extract_tool_input_field below exists to close, just
  # mirrored - see there for the concrete attack).
  #
  # NOT touched by AC1 (S10 review cycle 2), deliberately. AC1's finding
  # and fix are scoped to extract_tool_input_field's isolation of a
  # NESTED object below `tool_input` - a regex cannot track brace depth,
  # so it cannot tell "tool_input's own closing brace" from "a nested
  # object's closing brace" (see that function's own comment for the
  # exact reproduction). This function's sed fallback has no equivalent
  # nested-object hazard: `tool_name` (its only real caller's key) is a
  # flat top-level string with nothing nested inside it to be confused
  # with, and decide() below never calls this function for `file_path` -
  # only extract_tool_input_field is on that path. Removing this
  # fallback anyway was tried and reverted: it made this function return
  # empty for `file_path` too, which broke unrelated failure-proof
  # fixtures (tests/test_hooks.sh scenarios 16/17) that deliberately
  # construct a HISTORICAL, pre-AB1-shaped mutant calling this function
  # for `file_path` to prove a DIFFERENT, older bug (naive prefix
  # matching with no lexical normalisation) - those mutants rely on this
  # function's own unscoped sed scan to simulate "reads file_path from
  # anywhere in the payload," a property this function has always had
  # and that AC1 was never asked to change. Scope kept precisely to the
  # function actually implicated.
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

extract_tool_input_field() {
  # extract_tool_input_field <json> <key>: reads <key> from INSIDE
  # `tool_input` ONLY, e.g. `file_path` - the tool's real parameters, per
  # the PreToolUse contract (see the header). Never reads a top-level
  # field of the same name. jq REQUIRED, no fallback of any kind - see
  # the "SECURITY FIX (S10 review cycle 2, AC1)" paragraph below for why.
  #
  # SECURITY FIX (S10 review, AB1): the previous version of this
  # function (formerly folded into extract_field itself) preferred a
  # top-level field over `.tool_input.<key>`. A payload carrying a
  # BENIGN top-level `file_path` alongside a MALICIOUS
  # `tool_input.file_path` made the old jq filter
  # `(.[$k] // .tool_input[$k] // empty)` return the benign value and
  # `allow`, while the tool call Claude Code actually executes reads
  # `tool_input.file_path` - the malicious one. Reproduced for Read,
  # Write, and Edit alike; see tests/test_hooks.sh's AB1 scenarios. The
  # jq filter below (`.tool_input[$k] // empty`) is that fix and is
  # UNCHANGED by AC1 - it reads only `tool_input.<key>`, correctly,
  # because jq is an actual JSON parser and tracks object nesting for
  # real. AC1, below, is about what happens when jq is not there to do
  # that.
  #
  # SECURITY FIX (S10 review cycle 2, AC1): AB1's own fix left a sed
  # fallback in place for when jq is absent - isolating `tool_input`'s
  # own text via `sed -n 's/^.*"tool_input"[[:space:]]*:[[:space:]]*{
  # \([^}]*\)}.*/\1/p'` (capture everything up to the FIRST literal "}"
  # after "tool_input":{) and then key-searching inside that capture.
  # That isolation regex cannot parse nested JSON: given
  #   {"tool_name":"Write","tool_input":{"file_path":"/etc/passwd",
  #    "decoy":{"file_path":"$HOME/.squirrel/checkpoints/legit.md"}}}
  # the FIRST "}" in tool_input's text closes the NESTED decoy object,
  # not tool_input's own - so the capture became
  # `"file_path":"/etc/passwd","decoy":{"file_path":".../legit.md"`, and
  # the greedy-last-match key search inside it returned the DECOY value
  # (a legitimate-looking checkpoints/ path) instead of the REAL
  # tool_input.file_path (/etc/passwd) the Write tool actually operates
  # on. Reproduced: jq present -> defer (correct - jq parses the real
  # nested structure and finds /etc/passwd, outside checkpoints/); jq
  # stripped from PATH -> allow (WRONG, on the operation that targets
  # /etc/passwd). No isolation regex written in sed/awk closes this: a
  # regex matches text shapes, it cannot track brace depth without
  # becoming a parser by another name, and each narrower pattern tried
  # only shrinks the class of nested shapes that defeat it, never closes
  # the class - the same "narrower guard, same bug" pattern this project
  # has hit seven times now. This also closes, at the root rather than by
  # separately patching each one, two narrower jq/sed disagreements the
  # same review found: a literal "}" inside an unrelated STRING field's
  # own VALUE, appearing before `file_path` in the raw text (which also
  # terminates the old `[^}]*` capture early, on a payload with no
  # nesting at all - e.g. tool_input carrying a `content` field whose
  # text contains a "}"), and pretty-printed (multi-line, indented)
  # `tool_input` JSON, which the old single-pass isolation regex handled
  # inconsistently depending on exact whitespace shape. jq parses both
  # correctly and unconditionally, being an actual parser; a regex
  # standing in for one cannot be patched into being one.
  #
  # Fix: the sed decision path is REMOVED, not narrowed. Without jq, this
  # function prints nothing and returns 0. decide() below already treats
  # an empty file_path as nothing legitimate to allow - the `case
  # "$file_path" in /*) ;; *) defer` check a few lines down rejects an
  # empty string outright, since it does not start with "/" - so no
  # special-casing is needed here for "jq absent" specifically: it falls
  # out of the existing empty-value handling. The cost is real and
  # deliberate, not hidden: on a machine without jq, EVERY checkpoint
  # Write/Edit/Read defers to the normal permission prompt, including a
  # perfectly legitimate one. See tests/test_hooks.sh's AC1 scenarios for
  # the permanent nested-decoy assertion (both with jq present and
  # absent) and its mutation proof.
  json=$1
  key=$2
  if command -v jq >/dev/null 2>&1; then
    if val=$(printf '%s' "$json" | jq -r --arg k "$key" '(.tool_input[$k] // empty)' 2>/dev/null); then
      if [ "$val" != "null" ] && [ -n "$val" ]; then
        printf '%s' "$val"
        return 0
      fi
    fi
  fi
  return 0
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
  file_path=$(extract_tool_input_field "$input" "file_path")

  case "$tool_name" in
    Write | Edit | Read) ;;
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
  checkpoints_dir=$(normalize_path "$home_dir/.squirrel/checkpoints") || checkpoints_dir="$home_dir/.squirrel/checkpoints"

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
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"squirrel-mode: operation targets its own checkpoint directory (ADR-0002)."}}\n'
    ;;
  *)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}\n'
    ;;
esac
exit 0
