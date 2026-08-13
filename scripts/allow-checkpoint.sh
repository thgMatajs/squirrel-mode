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
# script, which reads `tool_input.file_path` from stdin and either
# AUTO-APPROVES the operation or declines to decide. It never denies:
# denying is not this hook's job, and declining hands the decision back
# to the normal permission flow exactly as if this hook did not exist.
#
# HOW "NO OPINION" IS EXPRESSED - FIXED BLOCKER (v0.3.1). This script
# used to print `{"hookSpecificOutput":{"hookEventName":"PreToolUse",
# "permissionDecision":"defer"}}` for every non-allow case, and this
# header, README.md and docs/adr/0002 all described that as handing the
# decision back "exactly as if this hook did not exist". That was
# FALSE. `defer` is a real Claude Code permissionDecision, but it does
# not mean "no opinion" - it means "defer this tool call for LATER":
# the session PAUSES, the tool never executes, and a headless run ends
# with stop_reason "tool_deferred". The documented way for a PreToolUse
# hook to express "I have no opinion, use the normal permission flow"
# is to exit 0 with EMPTY stdout, which is what the final `case` below
# now does.
#
# What that bug cost, measured on this machine with the real `claude`
# CLI, same prompt and project, only the plugin varying:
#
#   scenario                                | no plugin | as shipped     | fixed
#   default mode, Read a file in cwd        | end_turn  | tool_deferred  | end_turn
#   bypassPermissions, Write a file         | end_turn  | tool_deferred  | end_turn
#   default mode, write own checkpoint      | n/a       | allowed        | allowed
#
# So as shipped, installing this plugin broke ORDINARY file operations
# for every user - and it is also why /squirrel:off, /squirrel:init and
# /squirrel:tune came back completely empty in live runs: the first
# tool call each of them makes was being parked, not permitted.
#
# ONLY THE NO-OPINION PATH CHANGED. The `allow` branch's JSON is
# byte-for-byte what it always was - it was verified working by live
# probe both before and after this fix, and was deliberately left
# untouched. decide() below likewise still speaks in the two internal
# tokens `allow` and `defer`; "defer" remains the right word for the
# CONCEPT (this hook declines to decide) and is used that way
# throughout this file. What changed is one thing: what the process
# WRITES when that concept applies, which is now nothing at all.
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
# $HOME/.squirrel/checkpoints/. A gate and two layers enforce that:
#
#   Layer 0 (the `..` gate, always active, no external tool): a
#   file_path carrying a `..` PATH COMPONENT defers outright, before
#   Layer 1 or Layer 2 ever runs on it. See "WHY A `..` COMPONENT IS
#   REJECTED OUTRIGHT", immediately below, for the attack this closes
#   and why it is closed by rejection rather than by making Layer 1
#   cleverer.
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
#   contained one. What this layer defeats, stated for what it is:
#     - prefix-escape: ".../checkpoints-evil/x" is rejected by the
#       literal prefix strip because "checkpoints-evil" is not
#       "checkpoints" followed by "/" - the boundary character is
#       checked, not merely the substring. Layer 1 is the WHOLE defence
#       here, and its `..` handling is not involved at all.
#     - traversal: ".../checkpoints/../../../.ssh/id_rsa" normalizes to
#       "/.../.ssh/id_rsa", which does not start with the checkpoints
#       prefix at all - so this defers at Layer 1 too. But Layer 1 is NO
#       LONGER what is relied on for it, and the paragraph that used to
#       say "this layer alone defeats both required attacks" was wrong
#       about exactly this case (see the `..` section below): Layer 0
#       now rejects the traversal before Layer 1 is reached, and Layer
#       1's `..` handling is left in place only because normalize_path
#       is also applied to checkpoints_dir, whose own text this script
#       does not control.
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
#   Layer 2 walks the NORMALISED remainder, which is only the same set
#   of components the OS will actually traverse because Layer 0 has
#   already removed every `..` from the string - see below.
#
# WHY A `..` COMPONENT IS REJECTED OUTRIGHT (Layer 0). Layer 1 resolves
# `..` LEXICALLY - against the path's own text, with no filesystem
# access. The OS does not: it resolves symlinks PHYSICALLY, as it walks,
# and applies `..` to WHERE THE SYMLINK LANDED, not to the name that
# preceded it. Those two readings of the same string disagree the moment
# a symlink sits in front of a `..`, and the disagreement erased the
# symlink from the text before Layer 2 could ever `[ -L ]` it:
#
#   ln -s "$HOME" "$HOME/.squirrel/checkpoints/EVIL"
#   file_path = "$HOME/.squirrel/checkpoints/EVIL/../<home-basename>/.ssh/id_rsa"
#
# Layer 1 cancelled "EVIL" against the following ".." and handed Layer 2
# a remainder with no EVIL component left in it, so the component walk
# had nothing to test and returned "no symlink found"; the normalised
# text still began with the checkpoints prefix, so Layer 1 was satisfied
# too, and `allow` came back. The OS, asked to open the same string,
# would have followed EVIL to $HOME first and then applied ".." to
# $HOME's PARENT - reading (or writing) the user's private key with a
# permission prompt the plugin had just suppressed. Reproduced for Read
# and for Write alike.
#
# The fix is REJECTION, not a cleverer Layer 1. Making normalize_path
# "symlink-aware" means resolving the filesystem, which is (a) a
# `realpath`/`readlink` dependency this file deliberately removed once
# already (see "LAYER 3 WAS REMOVED" below) and (b) TOCTOU-exposed
# regardless: whatever this script resolves, the symlink can be
# repointed between that resolution and the tool call it approved.
# Rejecting the `..` COMPONENT closes the whole class instead of
# narrowing it, and it is a guard that cannot bar correct work: nothing
# this plugin ships ever emits a `..` segment in a checkpoint path. The
# model is handed the absolute checkpoint path verbatim, on the
# "Project checkpoint path:" line load-profile.sh injects, and every
# path in the injected file-list block is absolute and already
# normalised. The cost when this does fire is one ordinary permission
# prompt - never a denial - which is this script's cost for every
# no-opinion answer.
#
# It is the COMPONENT that is rejected, never the two characters. A
# filename may contain any number of dots and is unaffected:
# "my..file.md", "..hidden.md" and "..." are all handled exactly as they
# were before this gate existed. See tests/test_hooks.sh scenario 19d
# for both halves - the attack deferring, and those three names still
# reaching a normal decision.
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
# final `case` below always emits exactly ONE OF THE TWO WELL-FORMED
# OUTCOMES - a single line of `allow` JSON, or nothing at all - and this
# script always exits 0, PROVIDED decide() returns AT ALL.
#
# NARROWED BY THE v0.3.1 EMISSION FIX: this paragraph used to say the
# final `case` "always emits exactly one well-formed JSON decision".
# That is no longer true and is not restated as though it were - the
# no-opinion path now emits NO JSON, by design (see "HOW 'NO OPINION' IS
# EXPRESSED" above). The property that actually still holds, and the one
# every caller depends on, is the one stated above: exactly one of the
# two outcomes, always exit 0. An empty stdout from this hook is a
# COMPLETE, well-formed answer, not a truncated one.
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
# exactly one of the two well-formed outcomes" contract holds for every
# command
# FAILURE it depends on - `jq` exiting non-zero, `jq` exiting 0 with no
# output, and `jq` printing the literal string `null` are all reproduced
# (this fix) to defer correctly in well under a second (112-272ms,
# measured on the author's machine - stated as machine-specific data, not
# a portable performance guarantee). It does NOT hold for an invoked
# command that is never given the chance to fail or succeed because it
# never returns at all. That gap is bounded only by the harness's own
# hook timeout (Claude Code kills a hook process that overruns its
# configured or default timeout), never by anything in this script.
#
# NARROWED AGAIN (P4 item 1, audit). The paragraph above used to open
# "holds for EVERY input and for every command FAILURE". The "EVERY
# input" half was itself an overstatement, and the word is removed above
# rather than left standing: there is a SECOND way to reach the same
# never-returns state, and it is reached through this hook's INPUT, with
# every binary on the machine perfectly healthy.
#
# If fd 0 is CLOSED when this hook is exec'd - not empty, not
# /dev/null, genuinely not an open descriptor - then `input=$(cat)` in
# decide() hangs forever instead of reading nothing. `$(...)` builds its
# capture pipe on the lowest free file descriptor, which with fd 0 closed
# IS fd 0, so the pipe's READ end lands on stdin and `cat` reads the very
# pipe the substitution's own subshell is writing to. The write end never
# closes, EOF never arrives. Reproduced against this script: zero bytes
# of stdout, still running when killed externally. Confirmed by
# inspecting /dev/fd inside the substitution, where fd 0 is a pipe read
# end ("pr--r-----") rather than the caller's stdin. load-profile.sh and
# check-off-flag.sh share the identical construction and the identical
# hang; this is a property of `input=$(cat)` under a closed fd 0, not of
# anything specific to this file.
#
# The two causes are NOT equally closable, and that difference is the
# whole reason one is reaffirmed and the other only documented here:
#   - A WEDGED `jq` cannot be bounded from inside POSIX `sh` at all
#     (the paragraph above; `timeout(1)` is not portable). Permanent.
#   - A CLOSED fd 0 CAN be: `if ! ( exec 3<&0 ) 2>/dev/null; then exec
#     0</dev/null; fi` before the first command substitution, which needs
#     no external command. The probe runs in a SUBSHELL deliberately - a
#     failed `exec` redirection exits a non-interactive shell, so running
#     it here would exit this hook non-zero, the one thing it must never
#     do. (`[ -r /dev/fd/0 ]` was tried and rejected: where /dev/fd is
#     not mounted it reads false for a perfectly good stdin and would
#     discard the hook's real input - a guard that bars correct work.)
# That guard is deliberately NOT applied in this change: it is a
# behaviour change to the entry path of a security hook, it belongs in
# ONE coordinated change across all three hooks rather than in a
# comment-only correction to one of them, and this file's own history
# (Layer 3) is the standing argument against adding protection to this
# script without reviewing it as new surface. Documented here so the
# limit is recorded honestly and the remedy is not rediscovered from
# scratch.
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
#
# ======================================================================
# ADDED BY P1 (per-session checkpoint layout). Self-contained; nothing
# above this line is restated or amended by it.
# ======================================================================
#
# P1 moved a project's memory from one flat file,
# checkpoints/<slug>.md, to one file per session inside a per-project
# directory, checkpoints/<slug>/<session-id>.md. The security boundary
# did NOT move with it: it is still the `checkpoints/` directory, and
# every layer below still asks the single question "does this path
# resolve inside checkpoints/, with no symlink at or below
# checkpoints/". The nested layout adds one more intermediate component
# (`<slug>/`) for the component walk to inspect, which it already does
# by construction - it walks every component of the remainder, however
# many there are - so the whole attack matrix was re-run against the
# nested shape rather than assumed to still hold. See tests/
# test_hooks.sh's nested-layout scenarios.
#
# One behaviour DOES change, tech-lead decision D1: on a path that is a
# DIRECT CHILD FILE of checkpoints/ - i.e. the pre-P1 flat shape, with
# no further "/" after checkpoints/ - `Read` still allows, while `Write`
# and `Edit` now defer.
#
# Why the split rather than deferring the old path outright: the
# migration path needs to READ the old flat file (/squirrel:pickup folds
# it in, once, on first read), and ADR-0002's promise is that an
# ordinary checkpoint interaction never costs the user a permission
# prompt. Deferring that read would break both. Why the write side
# defers at all: post-P1 the model is only ever handed a nested path, so
# nothing correct writes a flat one. That makes the write-side defer a
# tripwire with no legitimate traffic behind it, rather than a guard
# that bars correct work - and its cost when it does fire is one
# ordinary permission prompt, never a denial.
#
# The test is the SHAPE of the path, not the identity of the slug:
# matching "the old file" exactly would mean recomputing the project
# slug here, which needs `cwd` - a field the PreToolUse payload does not
# carry. The shape test is also the more conservative of the two: it
# covers every flat child of checkpoints/, not just the one this project
# happens to own.
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
  #
  # THE THREE COPIES HAVE DELIBERATELY DIVERGED - recorded here so the
  # divergence is written down rather than discovered later. The sibling
  # scripts' extract_field (load-profile.sh, check-off-flag.sh) no longer
  # has this sed fallback at all: it now calls a top-level-only awk byte
  # scanner, extract_top_level_string, because the greedy scan below
  # binds the LAST occurrence of a key on the line - including one nested
  # inside a sub-object - which in check-off-flag.sh let a crafted
  # payload steal another session's off-switch sentinel with jq absent.
  # THIS file keeps the old scan, on purpose, for three reasons, each
  # re-verified rather than assumed:
  #   (a) It is called for exactly one key, `tool_name`, at one call site
  #       in decide() below. `file_path` never comes through here - it
  #       comes through extract_tool_input_field, which has no fallback.
  #   (b) So no `allow` decision can be reached on the strength of this
  #       function's scan. With jq stripped from PATH,
  #       extract_tool_input_field returns empty, file_path fails the
  #       `case ... in /*)` test, and decide() defers. Confirmed by
  #       running this script both ways against a legitimate nested
  #       checkpoint Write: jq absent defers, jq present allows.
  #   (c) tests/test_hooks.sh scenarios 16/17 build HISTORICAL,
  #       pre-AB1-shaped mutant decide() bodies that call this function
  #       for `file_path` precisely to simulate "reads file_path from
  #       anywhere in the payload" while proving an older, different bug.
  #       Narrowing this function to the top level would empty their
  #       file_path and turn those proofs green-for-the-wrong-reason.
  # If a future change ever routes a security-relevant key through this
  # function, that reasoning expires with it and the scanner must be
  # copied in here too.
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

  # DOTDOT REJECTION (see "WHY A `..` COMPONENT IS REJECTED OUTRIGHT" in
  # the header). Any `..` PATH COMPONENT defers, before normalize_path or
  # component_walk_has_symlink ever see this string. Wrapping both ends
  # in "/" is what makes ONE pattern cover all four spellings - a bare
  # "..", a leading "../x", a trailing "x/..", and an interior "/../" -
  # while a filename that merely CONTAINS two dots ("my..file.md",
  # "..hidden.md", "...") never produces the literal four-byte sequence
  # "/../" and is handled normally, exactly as before.
  #
  # Placed AFTER the length cap directly above, deliberately: the cap is
  # not a decision about what the path MEANS, it is the bound on
  # attacker-controlled input that the "FIXED MAJOR" paragraph above
  # exists for, and it must stay first so no unbounded string is ever
  # pattern-matched here either. Both arms defer, so the order between
  # them cannot change any decision - and no `allow` is reachable past
  # either of them.
  case "/$file_path/" in
    */../*)
      printf 'defer'
      return 0
      ;;
  esac

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

  # Layer 1b (P1, tech-lead decision D1): a DIRECT CHILD FILE of
  # checkpoints/ - no further "/" in the remainder - is the pre-P1 flat
  # layout. Reading one is legitimate (that is how the legacy file gets
  # folded in); writing one is not, because post-P1 nothing correct
  # targets it. See the P1 paragraph in this file's header.
  case "$after" in
    */*) ;;
    *)
      case "$tool_name" in
        Read) ;;
        *)
          printf 'defer'
          return 0
          ;;
      esac
      ;;
  esac

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

# THE EMISSION LAYER (see "HOW 'NO OPINION' IS EXPRESSED" in the header).
# decide() still speaks in the two internal tokens `allow` and `defer`;
# only the translation into what this process actually WRITES changed.
# The `allow` arm is byte-for-byte the JSON it has always been - it is
# the verified-working half and was deliberately not touched. The
# no-opinion arm prints NOTHING at all, which is the documented way for
# a PreToolUse hook to decline to decide.
case "$decision" in
  allow)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"squirrel-mode: operation targets its own checkpoint directory (ADR-0002)."}}\n'
    ;;
  *)
    :
    ;;
esac
exit 0
