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
# ONLY THE NO-OPINION PATH CHANGED (at v0.3.1). The `allow` branch's
# JSON was byte-for-byte what it always was - verified working by live
# probe both before and after that fix, and deliberately left untouched
# by it. AMENDED, Task 8 of the hoard phase: its
# permissionDecisionReason TEXT has since changed, because it named the
# checkpoint directory for a hoard write too. The JSON's SHAPE - the
# three keys, their order, one object on one line - is what the probe
# froze and is still exactly that; see "THE `allow` ARM'S JSON SHAPE IS
# UNCHANGED" at the emission layer below. decide() below likewise still speaks in the two internal
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
# for a path that genuinely, after normalisation, NAMES A LOCATION inside
# one of the two roots this script governs -
# $HOME/.squirrel/checkpoints/ or $HOME/.squirrel/hoard/. A gate and three
# layers enforce that, identically for whichever root matched:
#
# (CORRECTED, Task 8 of the hoard phase. This sentence named only
# checkpoints/ until then, so the file's own primary statement of what it
# guarantees UNDERSTATED the boundary from the moment Task 4 added the
# second root. The gate and both layers below were already shared by both
# roots in code; only this description was behind. tests/test_hooks.sh
# HOARD-13c pins that both roots are NAMED here - it is an
# assert_contains over this file's own text, so what it proves is that
# the sentence is PRESENT, never that it is TRUE - and HOARD-13d proves
# the pin fires on the stale one. The behaviour behind the sentence is
# proved separately, by running the hook: HOARD-1/2/3 for the two roots
# and every layer, HOARD-3f..3n for the rest of the attack matrix against
# the hoard shape, and HOARD-14 for the sub-clause corrected next.)
#
# (CORRECTED AGAIN, the hard-link fix, and this correction is the reason
# the words above are "NAMES A LOCATION" rather than the "resolves
# inside" they replace. Every reader of the old wording - including the
# author of the layers below - took it to mean THE BYTES REACHED ARE
# INSIDE THE ROOT. For a hard link that is false, and it was false in
# production: `ln $HOME/.ssh/id_rsa $HOME/.squirrel/hoard/global/notes.md`
# creates a second NAME for the private key inside the governed root, and
# both a Read and a Write of that name came back `allow` - the key read
# and overwritten with no prompt, in either root. No layer saw it,
# because a hard link is not a symlink, is indistinguishable from an
# ordinary file by every `[ -L ]` test, and leaves the path text
# completely ordinary. Layer 2b below closes it. What the corrected
# sentence claims is exactly what the layers check: the NAME, at the
# moment this hook is asked. Three limits of that claim, each stated
# where it is enforced rather than only here: it is a decision-time test
# and nothing in POSIX sh survives the file being swapped between the
# decision and the tool call it approved (see the `..` section's TOCTOU
# paragraph); Layer 2b needs `find` and does not run without it; and the
# secret refusal needs `grep` and does not run without it.)
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
#   EACH GOVERNED ROOT IN TURN (the checkpoints directory, then the
#   hoard directory; the first one that matches is the root the rest of
#   decide() reasons about, and no match at all defers) via a LITERAL
#   (non-glob) prefix strip,
#   `${normalized#"$prefix"}`, not a `case`/glob pattern match. This
#   matters: quoting a variable inside a `${var#pattern}` pattern makes
#   its glob-metacharacters (`*`, `?`, `[`) literal per POSIX, which a
#   bare `case "$x" in $prefix*)` would not guarantee if $HOME ever
#   contained one. What this layer defeats, stated for what it is:
#     - prefix-escape: ".../checkpoints-evil/x" is rejected by the
#       literal prefix strip because "checkpoints-evil" is not
#       "checkpoints" followed by "/" - the boundary character is
#       checked, not merely the substring. ".../hoard-evil/x" is
#       rejected by the identical strip against the identical boundary
#       character, which is the whole point of the roots sharing one
#       loop rather than each getting its own test. Layer 1 is the WHOLE
#       defence here, and its `..` handling is not involved at all.
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
#   it cannot by itself defeat a symlink planted AT or BELOW whichever
#   root matched.
#
#   Layer 2 (ALWAYS ACTIVE, the only fallback, zero external tools):
#   component_walk_has_symlink() tests THE MATCHED ROOT ITSELF -
#   checkpoints_dir or hoard_dir, whichever Layer 1 selected - then
#   walks every path component between that root and the leaf -
#   "escape-dir", then "escape-dir/evil.md", and so on - and defers the
#   instant `[ -L ... ]` (a POSIX shell builtin, not an external
#   command) finds ANY of them, INCLUDING the root itself, to be a
#   symlink, regardless of where it points. It never calls `realpath`
#   or `readlink` at all, so it works identically with an empty PATH.
#   Layer 2 walks the NORMALISED remainder, which is only the same set
#   of components the OS will actually traverse because Layer 0 has
#   already removed every `..` from the string - see below.
#
#   Layer 2b (the hard-link refusal; needs `find`, and does not run
#   without it): if the LEAF already exists and is a regular file, its
#   link count must be 1. This is the one layer that is not free and the
#   one that is not always active, and both facts are load-bearing enough
#   to be stated in its name. See "A HARD LINK IS THE ONE ESCAPE THE
#   COMPONENT WALK CANNOT SEE", below, for the attack, and the code at
#   the end of decide() for why it is the last test rather than an early
#   one.
#
# A HARD LINK IS THE ONE ESCAPE THE COMPONENT WALK CANNOT SEE (Layer 2b).
# Layers 0 to 2 all reason about the path: its text, its prefix, and
# whether any component of it is a symlink. A hard link is none of those
# things. It is a second directory entry pointing at an inode that
# already has one somewhere else, it is not distinguishable from "the"
# file by any test in POSIX `sh`, and the path leading to it is entirely
# ordinary. Reproduced against this script before the fix, on both roots
# and for both tools:
#
#   printf 'CHAVE\n' > "$HOME/.ssh/id_rsa"
#   ln "$HOME/.ssh/id_rsa" "$HOME/.squirrel/hoard/global/notes.md"   # no -s
#
# Read of that path: `allow`. Write of that path: `allow`. The hook read
# the user's private key and let it be overwritten, with the permission
# prompt suppressed by this very script - while the SYMLINK spelling of
# the identical attack deferred at Layer 2, which is what made the gap
# easy to miss for anyone reasoning from the tests rather than from the
# filesystem.
#
# THE TEST IS LINK COUNT, AND WHAT IT COSTS IS ONE PROMPT ON A
# DEDUPLICATED STORE (CORRECTED, cycle 2). Every file either root
# legitimately holds is created by one Write from this plugin's own flow,
# and NOTHING THIS PLUGIN DOES gives it a second name. That is a property
# of the plugin. It is not a property of the user's filesystem, and the
# sentence here used to claim the stronger thing - "has exactly one name,
# so this is a guard with no correct traffic behind it". A filesystem-wide
# deduplicator breaks it without any attack: `jdupes -L`,
# `rdfind -makehardlinks` and `hardlink(1)` all replace duplicate files
# with hard links, and two identical memories - or a memory and its own
# copy elsewhere - become one inode with two names, BOTH of them inside
# the governed root. Every later read or rewrite of such a file then costs
# one permission prompt. That is the honest cost of this layer: not zero,
# but one prompt per deduplicated file, never a denial, on a machine whose
# owner ran a deduplicator. Two neighbouring cases were checked and are
# NOT affected: an APFS clone (`cp -c`) leaves nlink at 1, and a directory
# is never tested at all.
#
# A leaf that does not exist yet has no link count and is not tested. A
# directory is not tested either - directories always carry at least two
# links, so testing them would defer the legitimate `Read` of a
# checkpoint's per-project directory for a reason unrelated to this
# attack. What is left is the one shape with no producer inside this
# plugin: an existing regular file inside a governed root that some other
# name also points at.
#
# THE COST, AND THE ESCAPE HATCH THIS FILE TOOK. There is no way to read
# a link count from POSIX `sh` without an external command; `[ ]` has no
# operator for it and neither does any expansion. `find <file> -links +1`
# is the narrowest one available (no output parsing, no `stat`, whose
# flags are not portable between BSD and GNU). The tech-lead rule for
# this file is that the `allow` path may take one more command - it
# already REQUIRES `jq` - while the defer path may take no NEW one, so
# the test is placed after every other decision, where the answer would
# otherwise already be `allow`. With `find` absent from PATH the layer
# does not run and the hard link is auto-approved again; that limit is
# recorded here, in docs/adr/0008-hoard-auto-allow.md, and asserted by
# tests/test_hooks.sh HOARD-14e, which runs the real hook on a PATH
# holding only jq, cat and grep - grep is there deliberately, because
# HOARD-14e's isolation assertion needs the secret refusal to still work
# - and pins the `allow` it produces.
#
# WHAT "THE DEFER PATH TAKES NO NEW COMMAND" MEANS, MEASURED (CORRECTED,
# cycle 2). It does not mean a defer is free of processes, and the
# sentence that used to sit here implied that. Counted with shims that
# log every invocation, on this file as it stands:
#
#   over MAX_PAYLOAD_LEN     defer   1 cat
#   `..` component           defer   1 cat, 2 jq
#   outside both roots       defer   1 cat, 2 jq
#   symlink component        defer   1 cat, 2 jq
#   credential in the body   defer   1 cat, 4 jq, 1 grep
#   hard link, Read          defer   1 cat, 2 jq, 1 find
#   hard link, Write         defer   1 cat, 4 jq, 2 grep, 1 find
#   allow, leaf absent       allow   1 cat, 4 jq, 2 grep
#   allow, leaf present      allow   1 cat, 4 jq, 2 grep, 1 find
#
# `input=$(cat)` runs on every call before any decision, and the two
# field extractions run `jq`. The true and narrow claim, and the only one
# Layer 2b's placement buys, has to be stated with its enumeration
# attached: EVERY DEFER DECIDED BEFORE LAYER 2B - the five classes above
# the rule - SPAWNS NO `find`. `find` runs only after every other layer
# has already said `allow`, and only when the leaf already exists. The
# sixth and seventh rows are the exception and they are not a leak in the
# claim: THAT defer is Layer 2b's own, and it is produced BY the `find`,
# exactly as the credential defer is produced by a `grep`. Writing the
# claim without its enumeration - "no find on any defer" - is false for
# precisely those two rows, which is the same shape of overstatement this
# paragraph exists to correct. HOARD-14f asserts every row.
#
# WHY A HARD LINK IS NOT ALSO REJECTED ABOVE THE LEAF: it cannot be
# there. POSIX forbids hard links to directories, so every component
# between a governed root and its leaf is either a directory (unlinkable)
# or a symlink (Layer 2's job). The leaf is the whole surface.
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
# checkpoints_dir and never inspects anything above it. Nothing this
# plugin's own flow ever produces is a symlink AT or BELOW either
# governed root, so every one of those must defer.
#
# (CORRECTED, audit item 10. That sentence used to justify itself by
# asserting that the plugin creates these directories - naming the first
# checkpoint write or `/squirrel:init` for checkpoints/, and saying the
# same of both roots in component_walk_has_symlink's own doc comment.
# The stale phrasings are not restated here, so that
# tests/test_hooks.sh HOARD-18 can forbid them by needle without this
# correction being the thing its needle finds. It is not true of
# either root and `grep -rn mkdir` over this repo is the whole
# disproof: no shipped script, skill or rule creates
# $HOME/.squirrel/checkpoints/ or $HOME/.squirrel/hoard/. `/squirrel:init`
# creates $HOME/.squirrel/ and writes profile.md into it, nothing deeper.
# Both governed roots come into existence IMPLICITLY, as the parent
# directories the model's first Write to a path inside them creates. The
# conclusion survives the correction and the reasoning is now the one
# that actually holds: what makes a symlink there illegitimate is not
# that this plugin owns the inode, it is that the only mechanism that
# ever creates either root is a plain file write through this plugin's
# own flow, and a plain file write never produces a symlink. The cost
# when this fires is one ordinary permission prompt, never a denial -
# which is also why the boundary can afford to be drawn this strictly on
# a directory nobody explicitly created.)
#
# `$HOME/.squirrel` itself, by contrast,
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
#
# ======================================================================
# ADDED BY THE HOARD, PHASE 1. Self-contained; nothing above this line is
# restated or amended by it.
# ======================================================================
#
# This script now governs TWO roots under $HOME/.squirrel/: the original
# `checkpoints/` and the new `hoard/` (durable cross-project memory - see
# docs/adr/0008-hoard-auto-allow.md and
# docs/specs/2026-08-13-hoard-design.md).
#
# THE SECURITY BOUNDARY DID NOT LOOSEN, IT WAS COPIED. Layer 0 (the `..`
# rejection), the length cap, Layer 1 (literal prefix strip) and Layer 2
# (component symlink walk) are shared verbatim by both roots; the walk
# starts at whichever root matched and, exactly as before, tests that
# root ITSELF first, so a symlink planted AT hoard/ defers the same way
# one planted at checkpoints/ does. The whole attack matrix is run
# against the hoard shape rather than assumed to transfer - see
# tests/test_hooks.sh's HOARD-* scenarios.
#
# (CORRECTED, audit item 8, and the correction was to the TESTS rather
# than to the claim. When this sentence was written, HOARD-3 held four
# assertions - a `..` component, a prefix escape, a symlink below the
# root and a symlink at the root - while the matrix the checkpoint root
# is held to also contains field shadowing (AB1), the nested decoy (AC1),
# jq absent, jq returning `null`, jq returning empty, a malformed
# payload, a file_path over the length cap, and $HOME absent, empty or
# relative. None of those had ever been run with a hoard path, so "the
# whole attack matrix" named eight things that had not happened. Running
# them showed the behaviour does transfer - every one defers - which is
# what makes the honest fix adding the assertions rather than shrinking
# the sentence: the claim is now true because the scenarios exist, in
# HOARD-3f through HOARD-3n, each with the checkpoint-root scenario it
# mirrors named in its own comment.)
#
# TWO RULES DIFFER, deliberately, and both ADD refusals to the hoard
# root rather than removing any from it. (This paragraph said "ONE RULE
# DIFFERS" until the secret refusal below was added; it is corrected
# here rather than left to read as a complete list it no longer is.)
#
#   1. A DIRECT CHILD FILE of hoard/ defers for EVERY tool, including
#      Read, while the same shape under checkpoints/ still allows a Read
#      (the pre-P1 legacy fold, decision D1 above). The hoard has no
#      legacy flat layout - every memory lives one level down in global/
#      or projects/<slug>/ - so the Read exception has nothing to serve
#      there and is not granted.
#
#   2. THE SECRET REFUSAL: a Write or Edit whose written text looks like
#      it carries a credential does not get auto-approved. It is REFUSAL
#      OF AUTO-APPROVAL, never a denial - the operation falls back to the
#      ordinary permission prompt and the user decides, which is exactly
#      what would happen if this hook did not exist. It is the last line
#      of a defence whose earlier lines are advisory: the agent writes
#      memories with the Write tool, so a "do not record secrets" rule
#      stated in a skill is a request, and this is the only place it is
#      enforced. Scoped to the hoard root only - a scan over
#      checkpoints/ would put a permission prompt in the middle of the
#      one write ADR-0002 exists to keep silent - and to Write/Edit only,
#      since a Read writes nothing there is to leak. Oversized written
#      text defers rather than being scanned, on the same reasoning as
#      MAX_FILE_PATH_LEN. See payload_has_secret() for what it does and
#      does not claim to detect.
set -eu

# MAX_FILE_PATH_LEN: the DoS cap (see "FIXED MAJOR" above). 4096 bytes
# comfortably covers every real filesystem path this plugin will ever
# be asked to write (well past PATH_MAX on every OS this plugin ships
# to) while bounding the absolute worst case of the quadratic scan
# below to a fixed, small number of segments - not to "fast", but to
# "bounded, and never growing with attacker input".
MAX_FILE_PATH_LEN=4096

# MAX_SCAN_LEN: the bound on how much written text is scanned for
# credentials. A memory body is a title and a short paragraph; 65536 is
# far past anything legitimate. Beyond it, the write DEFERS
# rather than being scanned - an unbounded scan of attacker-controlled
# text is a cost that grows with attacker input, which is the property
# MAX_FILE_PATH_LEN exists to remove too, and deferring is this script's
# cost for every answer it will not give.
#
# WHAT MAX_FILE_PATH_LEN CLOSES IS NOT WHAT THIS ONE CLOSES (CORRECTED,
# hard-link/measurement fix). This comment used to call the two "the same
# shape of exposure". They are not the same shape and the difference is
# the whole reason the third cap below exists. MAX_FILE_PATH_LEN bounds a
# QUADRATIC cost - normalize_path and component_walk_has_symlink are
# O(segments^2), so a few thousand segments already cost seconds (the
# measurements are in the "FIXED MAJOR" paragraph above). The scan below
# is LINEAR in the text it walks. Linear is not free - it is unbounded
# unless something bounds it - but capping it is a bound on a straight
# line, not the removal of a curve, and saying otherwise overstated what
# one of the two caps was doing.
#
# WHAT `${#var}` COUNTS IS DECIDED BY THE LOCALE, and the cap is
# therefore looser OR TIGHTER than 65536 bytes depending on where this
# hook runs (CORRECTED, measurement fix). This comment used to state
# without qualification that "THE UNIT IS CHARACTERS, NOT BYTES ... POSIX
# defines as the length in CHARACTERS", and concluded the cap was loose -
# up to roughly four times 65536 bytes. That is only the multibyte-locale
# half of the truth. Under LC_ALL=C the same expansion counts BYTES, so
# the cap is TIGHTER there, and the difference is observable end to end:
# one 40000-character payload of `€` (three bytes each) DEFERS under
# LC_ALL=C and is AUTO-APPROVED under LC_ALL=en_US.UTF-8, same hook, same
# input, same machine. Apple's /bin/dash counts bytes under both.
# docs/adr/0008-hoard-auto-allow.md had this right from the start - "the
# 65536 cap admits between 65536 bytes and roughly four times that many"
# - and this comment was the copy that fell behind it.
#
# What survives either reading, and the only property the cap is here
# for: it is a FIXED bound at both ends and it never grows with attacker
# input. Tightening it to an exact byte count would mean an external
# command on the hot path of every hoard write, which is the wrong trade.
# MAX_FILE_PATH_LEN and MAX_PAYLOAD_LEN are measured the same way and
# carry the same locale slack.
MAX_SCAN_LEN=65536

# MAX_PAYLOAD_LEN: the bound on the WHOLE stdin payload, applied before
# any field is extracted from it.
#
# WHY IT EXISTS (added by the measurement fix). The comment beside the
# secret scan below used to say "Both length caps are applied BEFORE
# either scan, so no oversized string is walked by `case` or handed to
# `grep` on any path." That was true of the SCAN and false of everything
# in front of it. `${#written}` cannot exist until `written` does, and
# `written=$(extract_tool_input_field "$input" "content")` has by then
# run `jq` over the entire payload and materialised the entire field.
# The same is true one step earlier still: `tool_name` and `file_path`
# are each read by a `jq` invocation over the whole payload, before ANY
# cap in this file has been consulted, on EVERY tool call this hook sees.
# Measured on this machine, 32 MB of `content` in one payload, before
# this cap existed: 8.22s wall and 407 MB peak RSS for a hoard write
# (which reaches the scan), 2.91s and 237 MB for a checkpoint write
# (which does not) - so even the path with no scan at all was paying for
# two full parses of an attacker-sized string. Machine-specific numbers,
# not a portable guarantee; the shape is what matters.
#
# 1048576 is sixteen times MAX_SCAN_LEN and orders of magnitude past any
# real Write, Edit or Read payload Claude Code emits for a path this hook
# can approve. Over it, this script defers - one ordinary permission
# prompt - before `jq` is invoked even once. It is checked with
# `${#input}`, a shell parameter expansion, so the cap itself adds no
# command to any path, including the defer path.
#
# The same 32 MB payloads, same machine, after this cap: 0.71s / 273 MB
# for the hoard write and 0.70s / 273 MB for the checkpoint write - the
# two paths converge because neither now parses anything.
#
# WHAT THIS CAP DOES NOT BOUND, said plainly rather than left to be
# rediscovered: `input=$(cat)` runs BEFORE it and reads whatever the
# harness hands this process, so the residual 0.70s and 273 MB above are
# stdin itself and are not removed by any number written here. Bounding
# THAT would mean reading stdin incrementally and abandoning it partway,
# which POSIX `sh` cannot do without an external command on the entry
# path of every file operation in the session. What the cap removes is
# every DERIVED copy and every parse: nothing past this point is
# proportional to an oversized payload.
MAX_PAYLOAD_LEN=1048576

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
  #       function's scan. The scan is now reached ONLY when jq is absent
  #       or failed to parse the payload (see the FIXED (audit, LOW) note
  #       at the `return 0` below for the case that used to slip past
  #       this), and on either of those paths extract_tool_input_field
  #       returns empty, file_path fails the `case ... in /*)` test, and
  #       decide() defers. Confirmed by running this script both ways
  #       against a legitimate nested checkpoint Write: jq absent defers,
  #       jq present allows.
  #   (c) It used to be true that tests/test_hooks.sh scenarios 16/17
  #       depended on this scan - their mutant decide() bodies called
  #       this function for `file_path` to simulate "reads file_path from
  #       anywhere in the payload". They no longer do: those mutants now
  #       call extract_tool_input_field, which is both a faithful reader
  #       of the field the tool actually uses and irrelevant to the bug
  #       they exist to prove (naive prefix matching with no lexical
  #       normalisation). That dependency is therefore no longer a reason
  #       to keep this fallback broad, and it is not cited as one.
  # If a future change ever routes a security-relevant key through this
  # function, that reasoning expires with it and the top-level-only awk
  # scanner the sibling scripts use must be copied in here too.
  json=$1
  key=$2
  if command -v jq >/dev/null 2>&1; then
    if val=$(printf '%s' "$json" | jq -r --arg k "$key" '(.[$k] // empty)' 2>/dev/null); then
      # FIXED (audit, LOW): this `return 0` used to sit INSIDE the
      # non-empty test, so a jq that PARSED the payload and correctly
      # reported the field ABSENT fell through to the sed scan below -
      # and that scan is greedy over the WHOLE payload, so it bound a
      # `tool_name` nested inside `tool_input`. Reproduced with jq
      # present and no top-level tool_name at all:
      #   {"tool_input":{"file_path":"<a real checkpoints/ path>",
      #    "tool_name":"Write"}}
      # came back `allow` - on an operation whose actual tool this hook
      # never established. The same happened for an explicit
      # `"tool_name":null`. The comment block above claimed no `allow`
      # was reachable through this function's scan; that claim was true
      # only for jq ABSENT, and is now true unconditionally.
      #
      # The rule is: if jq PARSED the document, its answer is
      # authoritative, INCLUDING "the field is not there". Only a jq
      # that is absent, or one that failed to parse at all (malformed
      # JSON, non-zero exit), reaches the fallback - and on that path
      # extract_tool_input_field cannot produce a file_path either, so
      # decide() defers on the empty-file_path check and no `allow` is
      # reachable regardless of what the scan below binds. That is what
      # keeps this fallback safe to keep, and keeping it is what lets
      # tests/test_hooks.sh's malformed-payload scenarios still exercise
      # the shapes they were written for.
      if [ "$val" != "null" ] && [ -n "$val" ]; then
        printf '%s' "$val"
      fi
      return 0
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
# ITSELF (this is the cycle-3 BLOCKER fix: <base> is the root Layer 1
# matched - checkpoints_dir or hoard_dir, never a fixed one - at the one
# call site below, and a symlink planted at either root is never
# legitimate, because the only thing that ever creates either root is a
# plain file write through this plugin's own flow and a plain file write
# never produces a symlink - see the header's trust-boundary note, which
# records which earlier justification this replaced and why that one was
# false, and why this stops at <base> and never inspects anything above
# it). Then
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

payload_has_secret() {
  # payload_has_secret <text>: 0 (true) when <text> looks like it carries
  # a credential. Used ONLY to withhold auto-approval for a hoard write -
  # never to deny one. A hit costs the user one ordinary permission
  # prompt, which is exactly what would happen if this hook did not exist.
  #
  # PRECISION IS NOT THE POINT HERE, AND THAT IS DELIBERATE. A false
  # positive costs one prompt on one write; a false negative writes a
  # credential into a store that is re-read in every future session, in
  # every project. The two costs are not comparable, so the patterns
  # below are the unambiguous shapes only - PEM private-key headers and
  # provider token prefixes - plus one assignment-shaped rule for the
  # `<name> = <long opaque string>` case that carries no prefix of its
  # own. It is not, and does not claim to be, a complete secret scanner.
  #
  # THE ASSIGNMENT RULE'S KEY NAME IS A SUBSTRING OF THE NAME, NOT THE
  # WHOLE NAME (FIXED, audit item 2). The rule used to require one of its
  # keywords to sit IMMEDIATELY before the `[:=]`, which meant every
  # compound name escaped it while the rule's own comment claimed to
  # cover "the `api_key = <long opaque string>` case". An AWS secret
  # access key IS that case, and `aws_secret_access_key = <40 opaque
  # chars>` was auto-approved; so were `secret_key = ...`,
  # `password_hash=...` and `token_value: ...`, while the bare
  # `api_key = ...` deferred. A `[A-Za-z0-9_-]*` run is now allowed
  # between the keyword and the separator, so the keyword may sit
  # anywhere in the name rather than only at its end.
  #
  # THE VALUE MAY CARRY PUNCTUATION (FIXED, audit item 3). The value
  # class used to be `[A-Za-z0-9/+_-]{16,}`, which breaks at the first
  # character outside it: `password = Tr0ub4dor&3xK9!zQmW#pL2vN` was
  # auto-approved because of the `&`. The class is now
  # `[^[:space:]]{16,}` - any run of sixteen or more non-blank
  # characters. `grep` matches within one line, so this can never run
  # past a line ending; it is a run inside one line, not the rest of the
  # file. The widening is stated in ADR-0008 with the false positives it
  # buys, because it does buy some: a prose value of sixteen unbroken
  # characters after a keyword-bearing name now defers too.
  #
  # The caller is responsible for bounding <text> to MAX_SCAN_LEN BEFORE
  # calling this: neither the `case` below nor `grep` is given an
  # unbounded attacker-controlled string to walk.
  #
  # WHAT IT STOPS CATCHING WITH `grep` ABSENT FROM PATH, stated here and
  # in docs/adr/0008-hoard-auto-allow.md rather than left for someone to
  # find. The `case` arms are pure shell and always run, so PEM headers
  # and provider token prefixes still defer. The assignment rule below
  # is the only part that shells out, and with no `grep` on PATH the
  # pipeline fails, `-q` reports no match, and `api_key = <opaque
  # string>` is auto-approved. It degrades safely - it never crashes,
  # never denies, and never turns a defer into a wrong allow for a
  # credential the `case` arms know - but that class stops being caught.
  #
  # AND WHAT IT CATCHES THAT IS NOT A CREDENTIAL. The prefixes above are
  # matched as SUBSTRINGS, unanchored, so ordinary prose containing
  # AKIA, AIza, sk-ant or ghp_ defers - a memory ABOUT this guard would,
  # and so would the word MAKIAVELIAN. The two widenings recorded above
  # add their own: a name is matched by a keyword ANYWHERE inside it, so
  # `secretary:` and `tokens_left=` reach the rule, and a value is any
  # sixteen unbroken characters, so `password: correct-horse-battery`
  # does too. Each costs one permission prompt, never a denial. That
  # asymmetry is the design and is argued in full in ADR-0008.
  phs_text=$1
  case "$phs_text" in
    # `PRIVATE KEY-----` (ADDED, audit item 4) catches every PEM private
    # key by its delimiter rather than by algorithm: DSA - which the five
    # explicit arms below missed and which was auto-approved - and any
    # algorithm invented after this line was written. The five explicit
    # arms are kept beside it rather than folded into it: they also match
    # a header whose trailing dashes have been stripped or reflowed,
    # which the delimiter arm by construction cannot.
    *"PRIVATE KEY-----"* | \
    *"BEGIN RSA PRIVATE KEY"* | *"BEGIN OPENSSH PRIVATE KEY"* | \
    *"BEGIN PRIVATE KEY"* | *"BEGIN EC PRIVATE KEY"* | \
    *"BEGIN PGP PRIVATE KEY"*)
      return 0
      ;;
    # Provider token prefixes. `sk-proj-` (OpenAI project keys),
    # `sk_live_`/`sk_test_` (Stripe), `glpat-` (GitLab personal access
    # tokens), `GOCSPX-` (Google OAuth client secrets) and `xapp-1-`
    # (Slack app-level tokens) were ADDED by audit item 4; every one of
    # them was auto-approved before. Which families were deliberately
    # left OUT, and why, is in docs/adr/0008-hoard-auto-allow.md - the
    # short version is that a prefix is a false-positive surface as well
    # as a catch, and `ASIA` (AWS STS) or a bare `sk-` would fire on the
    # continent and on the word "task-force" respectively.
    *sk-ant-* | *sk-proj-* | *sk_live_* | *sk_test_* | \
    *ghp_* | *gho_* | *github_pat_* | *glpat-* | \
    *AKIA* | *xoxb-* | *xoxp-* | *xapp-1-* | *GOCSPX-* | *AIza*)
      return 0
      ;;
  esac
  # The bracket expressions carry a literal double quote and a literal
  # single quote (the two ways a value is commonly wrapped). Spelled as a
  # DOUBLE-quoted assignment with the double quotes backslash-escaped and
  # the single quotes written plainly - the equivalent single-quoted
  # spelling needs the '"'"' splice four times over and is a transcription
  # hazard for no gain. There is no `$` or backtick in the pattern, so
  # double quoting expands nothing.
  phs_re="(api[_-]?key|secret|token|password|passwd)[A-Za-z0-9_-]*[\" ']*[[:space:]]*[:=][[:space:]]*[\" ']*[^[:space:]]{16,}"
  if printf '%s' "$phs_text" | grep -qiE "$phs_re"; then
    return 0
  fi
  return 1
}

decide() {
  input=$(cat)

  # PAYLOAD CAP, FIRST OF EVERYTHING (see MAX_PAYLOAD_LEN above). This
  # has to precede the two extractions below, not merely the scan: each
  # of them invokes `jq` over the WHOLE payload, so a cap applied to
  # their RESULTS bounds nothing about the work that produced them.
  # `${#input}` is a shell parameter expansion, so this adds no command
  # to any path - the defer path included.
  if [ "${#input}" -gt "$MAX_PAYLOAD_LEN" ]; then
    printf 'defer'
    return 0
  fi

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
  # TWO ROOTS, ONE BOUNDARY (phase 1 of the hoard). This script now
  # governs `checkpoints/` and `hoard/`. Every layer above and below is
  # shared verbatim: the `..` rejection, the length cap, the literal
  # prefix strip and the component symlink walk all run identically on
  # whichever root matched. Two rules differ between
  # them - the direct-child rule below, and the secret refusal further
  # down - and each difference is stated where it is applied. (This said
  # "Only the direct-child rule differs" until Task 8. It was false the
  # moment the secret refusal landed; the file's header was corrected
  # then and this comment was not, which is the whole reason a list that
  # claims to be complete has to be checked against the code below it.)
  #
  # THIS SCRIPT'S NAME NOW NAMES ONLY ONE OF THE TWO ROOTS IT GOVERNS.
  # That is a known, deliberate mismatch, not an oversight: renaming it
  # touches hooks/hooks.json and, in tests/test_hooks.sh, the three
  # figures recorded below. Doing that in the same change that widens a
  # security boundary braids two risky edits together. The rename is
  # deferred to the phase that rewrites this file's ADR trail. Recorded
  # here so the mismatch is documented rather than discovered.
  #
  # THE FIGURES WERE NEVER RIGHT, AND NOTHING RECOUNTED THEM (FIXED,
  # audit item 7). This note used to read "103 occurrences of the literal
  # filename plus 136 uses of the variable built from it - counted, not
  # estimated, against the 8300-line file this note was written beside,
  # because the figure it replaced ('roughly forty') was neither." At the
  # commit that introduced that sentence the file held 104, 146 and 8510;
  # no counting method available produces 136 or 8300, so the sentence
  # censured an estimate for being an estimate while being wrong itself,
  # in the same breath, twice. The fix is not a better number - a number
  # nobody rechecks rots again on the next edit, which is exactly how
  # this one rotted. The three figures are written below one per line, in
  # a fixed shape a machine can read, and tests/test_hooks.sh
  # RENAME-COUNT re-derives all three on every run and fails with the
  # recomputed values when any of them has drifted. That test is the
  # reason these numbers can be trusted; the numbers themselves are just
  # its last known-good state.
  #
  # "occurrences" below means what the test counts, stated exactly so the
  # words and the assertion cannot disagree: every occurrence of the
  # literal string, and every occurrence of the identifier (which
  # includes the one line that assigns it, not only the uses of it).
  #
  #   rename-cost literal-occurrences: 121
  #   rename-cost identifier-occurrences: 193
  #   rename-cost test-file-lines: 10251
  checkpoints_dir=$(normalize_path "$home_dir/.squirrel/checkpoints") || checkpoints_dir="$home_dir/.squirrel/checkpoints"
  hoard_dir=$(normalize_path "$home_dir/.squirrel/hoard") || hoard_dir="$home_dir/.squirrel/hoard"

  normalized=$(normalize_path "$file_path") || { printf 'defer'; return 0; }

  # Layer 1: literal (non-glob) prefix containment, against each root in
  # turn. `${normalized#"$prefix"}` with the variable QUOTED inside the
  # pattern is what keeps a `*` or `[` in $HOME literal - see the Layer 1
  # paragraph in this file's header; a `case ... in $prefix*)` would not
  # guarantee that.
  root=""
  after=""
  for candidate in "$checkpoints_dir" "$hoard_dir"; do
    prefix="$candidate/"
    rest=${normalized#"$prefix"}
    if [ "$rest" != "$normalized" ] && [ -n "$rest" ]; then
      root=$candidate
      after=$rest
      break
    fi
  done
  if [ -z "$root" ]; then
    printf 'defer'
    return 0
  fi

  # Layer 1b, and the first of the TWO places the two roots diverge (the
  # secret refusal below is the second; this comment said "the ONE
  # place" until Task 8, which the secret refusal had already falsified).
  #
  # checkpoints/: a direct child file is the pre-P1 flat layout. Reading
  # one is legitimate (that is how the legacy file gets folded in);
  # writing one is not. Unchanged from before the hoard existed.
  #
  # hoard/: a direct child file is legitimate for NOTHING. Every memory
  # lives one level down, in global/ or projects/<slug>/, and there is no
  # legacy flat layout to fold in - so the Read exception has nothing to
  # serve here and is not granted. Both are tripwires with no correct
  # traffic behind them, and the cost when either fires is one ordinary
  # permission prompt, never a denial.
  case "$after" in
    */*) ;;
    *)
      if [ "$root" = "$hoard_dir" ]; then
        printf 'defer'
        return 0
      fi
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
  # only, always-active fallback, zero external tools. Tests $root -
  # whichever of checkpoints_dir and hoard_dir the loop above matched -
  # itself first, then defers the instant any component between that
  # root and the leaf is itself a symlink. One call, one walk, both
  # roots: a symlink planted AT hoard/ defers exactly as one planted at
  # checkpoints/ does, and that is a property of passing $root here
  # rather than of a second copy of this check.
  if component_walk_has_symlink "$root" "$after"; then
    printf 'defer'
    return 0
  fi

  # THE SECRET REFUSAL applies to the hoard root only, and only to a
  # tool that writes. checkpoints/ is excluded on purpose: its content
  # is the model's own Doing/Next state, it is rewritten every turn under
  # rule 14, and adding a scan there would put a permission prompt in the
  # middle of a task for the one write ADR-0002 exists to keep silent.
  #
  # BOTH written fields are read and BOTH are scanned - `content` (what
  # Write carries) and `new_string` (what Edit carries) - rather than
  # reading `content` and only falling back to `new_string` when it is
  # empty. That fallback shape is bypassable in exactly the way this
  # file's header records for file_path (S10 review, AB1): `content` is
  # not a parameter the Edit tool reads, so a payload carrying a benign
  # one alongside a credential-bearing `new_string` would have had its
  # DECOY scanned and its real write auto-approved. A field the tool does
  # not read must never be able to satisfy a check on the field it does.
  # See tests/test_hooks.sh HOARD-5's field-shadowing assertions.
  #
  # Both length caps are applied BEFORE either scan, so no oversized
  # string is walked by `case` or handed to `grep`.
  #
  # WHAT THAT SENTENCE DOES NOT COVER, AND USED TO CLAIM IT DID
  # (CORRECTED, measurement fix). It used to end "on any path", which
  # read as a statement about the whole hook and was one about the two
  # `case`/`grep` calls only. By the time `${#written}` can be evaluated,
  # `extract_tool_input_field` has already run `jq` over the entire
  # payload and materialised the entire field - the cap bounds what is
  # SCANNED, never what was PARSED to produce it. MAX_PAYLOAD_LEN, tested
  # at the top of decide() before any extraction runs, is what bounds
  # that; see its own comment for the measurements that motivated it.
  if [ "$root" = "$hoard_dir" ]; then
    case "$tool_name" in
      Write | Edit)
        written=$(extract_tool_input_field "$input" "content")
        written_new=$(extract_tool_input_field "$input" "new_string")
        if [ "${#written}" -gt "$MAX_SCAN_LEN" ] || [ "${#written_new}" -gt "$MAX_SCAN_LEN" ]; then
          printf 'defer'
          return 0
        fi
        if payload_has_secret "$written" || payload_has_secret "$written_new"; then
          printf 'defer'
          return 0
        fi
        ;;
    esac
  fi

  # LAYER 2b: THE HARD-LINK REFUSAL (see "A HARD LINK IS THE ONE ESCAPE
  # THE COMPONENT WALK CANNOT SEE" in the header for the attack and the
  # reproduction).
  #
  # PLACED LAST, DELIBERATELY, AND THAT PLACEMENT IS THE WHOLE REASON
  # THIS IS AFFORDABLE. It runs ONLY where the answer would otherwise
  # already be `allow`: every defer above - a `..` component, an over-cap
  # path, a path outside both roots, a symlink, a credential - is reached
  # WITHOUT SPAWNING `find`. `jq` is already a hard requirement of this
  # exact path (no `jq`, no `allow`, ever - see the header), so one more
  # command HERE costs a path that already pays for one; one more command
  # on the defer path would have been a new cost on every file operation
  # in the session, and is not what this is.
  #
  # (CORRECTED, cycle 2. This paragraph used to open "It is the only test
  # in this file that spawns a process", which is false three times over:
  # `input=$(cat)` at the top of decide() spawns one on EVERY call before
  # any decision is taken, both field extractions spawn `jq`, and
  # payload_has_secret spawns `grep` - twice on an allowed hoard write,
  # once on a credential defer, which is a defer PRODUCED BY a spawned
  # process. The measured per-path table is in this file's header, beside
  # "THE COST, AND THE ESCAPE HATCH THIS FILE TOOK". What is true, and is
  # all that this placement ever bought, is the sentence above WITH its
  # enumeration attached: every defer decided BEFORE this rule spawns no
  # `find`. Dropping the enumeration - "no `find` on any defer" - would be
  # false, because THIS rule's own defer is produced by a `find`, exactly
  # as the credential defer is produced by a `grep`. A correction that
  # over-reaches is the defect it was correcting.)
  #
  # `[ -f ]` FIRST, for two reasons and not only for the spawn it saves.
  # A leaf that does not exist yet - the ordinary case for a brand-new
  # checkpoint or memory write - has no link count to read and cannot be
  # a hard link to anything. And a DIRECTORY always has a link count of
  # at least two (its own `.`), so testing one would defer
  # `Read $HOME/.squirrel/checkpoints/<slug>` - a legitimate, allowed
  # shape - for a reason that has nothing to do with hard links. Only an
  # existing REGULAR FILE is asked.
  #
  # THIS NEEDS `find`, AND WITH `find` ABSENT IT DOES NOT RUN. That is
  # the same shape of degradation `grep` already has for the secret scan
  # (see payload_has_secret), it is deliberate rather than overlooked,
  # and it is stated here, in docs/adr/0008-hoard-auto-allow.md, and
  # pinned by tests/test_hooks.sh HOARD-14e so the limit and the code
  # cannot drift apart. Deferring instead when `find` is missing was
  # considered and rejected: it would put a permission prompt on every
  # checkpoint write on such a machine, which is a guard that bars
  # correct work, and the hard-link hole it would close is exactly the
  # hole that exists today.
  #
  # `find <file> -links +1` prints the file when its link count is
  # greater than one and prints nothing otherwise - no output parsing, no
  # `stat`, whose flags differ between BSD and GNU. `find` is already in
  # this repo's shipped-command inventory (docs/ACCEPTANCE.md), so this
  # adds a command to one path, not a dependency to the plugin.
  #
  # THE OUTPUT MUST BE WELL FORMED, NOT MERELY NON-EMPTY (FIXED, cycle 2).
  # This used to read `[ -n "$(find ...)" ]`: ANY byte on stdout was taken
  # for "link count above one". Measured against a `find` shim that prints
  # one unrelated line - a wrapper with a banner is all it takes - an
  # ORDINARY in-place rewrite of an ordinary one-link checkpoint came back
  # `defer`, which is a permission prompt on the exact write ADR-0002
  # exists to keep silent, for a file with nothing wrong with it. The test
  # is now that some LINE of the output is the leaf's own path, which is
  # what `find` prints and what a banner is not. A noisy `find` that still
  # reports the match therefore still defers; a noisy `find` with nothing
  # to report no longer blocks correct work.
  #
  # A LEAF WHOSE NAME CARRIES A NEWLINE cannot be compared line-wise
  # against line-oriented output, so for that shape - and only that shape
  # - any output at all defers, which is what the old test did for every
  # shape. It is the conservative reading, it costs at most one prompt,
  # and nothing this plugin writes has that name.
  #
  # THE EXIT STATUS IS DELIBERATELY NOT CONSULTED, and that is a stated
  # limit rather than an oversight. There is no reading of it that changes
  # an answer: a `find` that fails and a file with exactly one link both
  # mean "no hard link was proven here", and this layer's rule for an
  # unproven hard link is `allow` - the same answer it gives with `find`
  # absent from PATH entirely, for the same reason (see the paragraph
  # above: deferring would put a prompt on every write on such a machine).
  # So a `find` that exits 127, or 1, or is a shim that does nothing, is
  # treated exactly as an absent one. What CANNOT be closed from POSIX
  # `sh` is a `find` that never returns: there is no portable timeout, so
  # a wedged `find` on PATH hangs this hook. Both limits are in
  # docs/adr/0008-hoard-auto-allow.md and pinned by HOARD-14f.
  leaf="$root/$after"
  if [ -f "$leaf" ] && command -v find >/dev/null 2>&1; then
    hl_out=$(find "$leaf" -links +1 2>/dev/null) || true
    hl_nl='
'
    hl_hit=no
    case "$hl_nl$hl_out$hl_nl" in
      *"$hl_nl$leaf$hl_nl"*) hl_hit=yes ;;
    esac
    case "$leaf" in
      *"$hl_nl"*) [ -z "$hl_out" ] || hl_hit=yes ;;
    esac
    if [ "$hl_hit" = yes ]; then
      printf 'defer'
      return 0
    fi
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
# The no-opinion arm prints NOTHING at all, which is the documented way
# for a PreToolUse hook to decline to decide.
#
# THE `allow` ARM'S JSON SHAPE IS UNCHANGED; ITS REASON TEXT IS NOT
# (Task 8). Until then this comment said the arm was byte-for-byte what
# it had always been, and that stopped being accurate here rather than
# staying true by being left alone. What was frozen after the v0.3.1
# live probe is the SHAPE - the same three keys, in the same order, in
# one object on one line - and that is untouched: same
# hookSpecificOutput, same hookEventName, same permissionDecision. Only
# permissionDecisionReason's text changed, because the old text told the
# user that a HOARD write "targets its own checkpoint directory", which
# is not where that write was going. It is a string the user reads.
#
# ONE ARM, ONE STRING, NO BRANCH. The reason names both governed
# directories rather than the one that matched, so there is still
# exactly one `allow` emission in this file and no place for two
# spellings to drift apart. tests/test_hooks.sh HOARD-13 pins the whole
# line byte for byte, asserts a hoard allow and a checkpoint allow emit
# the IDENTICAL line, and asserts this file carries exactly one such
# emission - none of which was pinned by anything before Task 8.
case "$decision" in
  allow)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"squirrel-mode: operation targets one of its own data directories - checkpoints or hoard (ADR-0002, ADR-0008)."}}\n'
    ;;
  *)
    :
    ;;
esac
exit 0
