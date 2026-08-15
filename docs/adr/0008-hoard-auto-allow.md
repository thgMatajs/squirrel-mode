# ADR-0008: the auto-approval boundary covers the hoard, and refuses a secret

## Status

Accepted. Extends [ADR-0002](./0002-checkpoint-auto-allow.md); does not supersede it.

## Context

Phase 1 of the hoard (`docs/specs/2026-08-13-hoard-design.md`) adds a second directory under
`~/.squirrel/` that the model writes to and reads from: `hoard/`, holding durable cross-project
memories.

ADR-0002's reasoning applies unchanged. A memory write that stopped to ask for permission would
interrupt the task at exactly the moment the user is trying not to be interrupted, and
`/squirrel:stash` is a command the user typed — the approval was the invocation.

Two things are different from the checkpoint, and both change the decision.

**The hoard has no legacy flat layout.** Every memory lives one level below `hoard/`, in `global/`
or `projects/<slug>/`. ADR-0002's carve-out that lets a `Read` of a direct child file through — the
pre-P1 fold — has nothing to serve here.

**A memory outlives the session that wrote it, in every project.** A checkpoint is this session's
working state and is pruned on a 30-day rule. A memory is read back indefinitely. A credential
written into one would be re-read in every future session, in every project, long after anyone
remembered writing it.

## Decision

`scripts/allow-checkpoint.sh` governs two roots: `checkpoints/` and `hoard/`.

1. **The layers are shared, not reimplemented.** The `..` rejection, the length cap, the literal
   prefix strip and the component symlink walk run identically on whichever root matched, and the
   walk still tests the matched root itself first — so a symlink planted at `hoard/` defers exactly
   as one planted at `checkpoints/` does. That is a property of the walk being handed `$root`
   rather than a fixed directory, not of a second copy of the check. The full attack matrix was
   re-run against the hoard shape rather than assumed to transfer; see `tests/test_hooks.sh`'s
   `HOARD-3`.
2. **A direct child file of `hoard/` defers for every tool**, `Read` included. There is no legacy
   layout to read, so nothing correct targets that shape, which makes it a tripwire with no
   legitimate traffic behind it.
3. **A `Write` or `Edit` whose text looks like it carries a credential is not auto-approved.** On a
   hit the hook declines to decide: the write falls back to the ordinary permission prompt and the
   user chooses. It **refuses auto-approval; it never denies.** Text past the scan cap defers
   unscanned, on the same reasoning as the existing path length cap.

   **Both fields are read and both are scanned** — `content`, which `Write` carries, and
   `new_string`, which `Edit` carries. Reading `content` and merely *falling back* to `new_string`
   when it is empty would be the field-shadowing bypass this file's sibling ADR already records for
   `file_path` (ADR-0002, Amendment AB1): `content` is not a parameter the `Edit` tool reads, so a
   payload carrying a benign one alongside a credential-bearing `new_string` would have had its
   decoy scanned and its real write auto-approved. A field the tool does not read must never
   satisfy a check on the field it does.
4. **The secret scan is scoped to the hoard.** `checkpoints/` is excluded deliberately: rule 14
   rewrites a checkpoint every turn, and a scan there would put a permission prompt in the middle
   of the one write ADR-0002 exists to keep silent.

## What the secret scan does NOT catch

**Stated honestly: this is not a complete secret scanner, and does not claim to be.** It matches
unambiguous shapes — PEM headers, provider token prefixes, and one assignment-shaped rule for
opaque strings that carry no prefix. A credential in a shape it does not know is auto-approved, and
the skill's own instruction not to write one is the only thing in front of it.

Three specific limits, each established by running the hook rather than by reading it. An ADR that
lists what a scan catches and omits what it stops catching is the half-true guarantee this trail
exists to prevent.

**With `grep` absent from `PATH`, the assignment rule drops out.** The PEM and provider-prefix arms
are a pure-shell `case` and still defer. The assignment rule — `api_key = <long opaque string>` — is
the only part that shells out, and with no `grep` the pipeline fails, `-q` reports no match, and
that write is auto-approved. Reproduced against the real hook on a `PATH` holding only `jq` and
`cat`: the PEM header and a `ghp_` prefix both deferred, the identical `api_key` payload that
defers with `grep` present came back `allow`. It degrades safely — no crash, no denial, no wrong
`allow` for a shape the `case` arms know — and it stops catching that class. `tests/test_hooks.sh`
`HOARD-13e` pins all four of those outcomes, so this limit and the code cannot drift apart in
either direction.

**The false positives are broad, and they are ordinary prose.** The provider prefixes are matched
as substrings, unanchored, so any text containing `AKIA`, `AIza`, `sk-ant` or `ghp_` defers — which
means **a memory about this guard itself would defer**, and so would the word `MAKIAVELIAN`, whose
fourth through seventh letters are `AKIA`. A hex SHA following `token:` satisfies the assignment
rule too. Ordinary prose is clean: "never commit without running the test suite" is auto-approved.
Each false positive costs exactly one permission prompt, never a denial. `HOARD-13f` asserts all
five of those cases, the clean one included.

**The scan cap bounds a range of byte counts, not a single one.** What `${#var}` counts is decided
by the locale, and not uniformly by every `sh` either. Measured on a 6-byte, 4-character string:
`/bin/sh`, bash 3.2.57, zsh 5.9 and dash 0.5.13.5 each return **6** under `LC_ALL=C` and **4** under
`pt_BR.UTF-8`, while Apple's `/bin/dash` returns 6 under both. So `${#var}` counts characters under
a multibyte locale and bytes under C/POSIX, with at least one build that counts bytes regardless.
The hook runs under whatever locale it inherits, on whatever `/bin/sh` the machine provides, so the
65536 cap admits **between 65536 bytes and roughly four times that many**. It is a loose bound
rather than an exact one. It is still a fixed bound at either end, and it still never grows with
attacker input, which is the property the cap exists for; tightening it would mean an external
command on the hot path of every hoard write, which is the wrong trade for what it buys.

## Consequences

The asymmetry above is the design. A false positive costs one permission prompt on one write. A
false negative writes a credential into a store re-read in every future session. Those two costs
are not comparable, so the scan is tuned to catch the clear cases with certainty rather than to
catch every case with judgement.

The `jq` requirement is inherited unchanged: without `jq`, no `allow` is reachable for either root,
and every hoard write falls back to a prompt. Note the two tool dependencies pull in opposite
directions and are not the same kind of thing — `jq` missing makes the hook *more* conservative
(nothing is auto-approved), `grep` missing makes one rule *less* so.

**The message the user sees names both directories.** The `allow` branch emits one
`permissionDecisionReason`, and until this ADR it said the operation "targets its own checkpoint
directory (ADR-0002)" — for a hoard write as well, which is not where that write was going. It now
names both governed directories and both ADRs. The JSON's *shape* is unchanged, which matters:
ADR-0002's Amendment (v0.3.1) froze that shape after a live probe, and the freeze is about the keys
and their order, not about the sentence inside one of them. There is still exactly one `allow`
emission in the file and no branch on which root matched — one string cannot drift out of sync with
another one. `HOARD-13` pins the whole line byte for byte, asserts a hoard `allow` and a checkpoint
`allow` emit the identical line, and asserts the file carries exactly one such emission. Nothing
pinned any of that before.

**This script's name now names only one of the two roots it governs.** That mismatch is known and
deliberate: renaming it touches `hooks/hooks.json` and, in `tests/test_hooks.sh`, 103 occurrences
of the literal filename plus 136 uses of the variable built from it — counted against the
8300-line file this ADR was written beside, because the "roughly forty" the note it replaces
claimed was neither counted nor close. Doing that in the same change that widens a security
boundary braids two risky edits together. The rename is deferred to the phase that rewrites this
file's ADR trail.

## Two independent layers around the injected context, and why both

`/squirrel:dig` reads the search script's absolute path off a line `scripts/load-profile.sh`
injects, and acting on that line runs a command. The user's own `profile.md` is quoted into the
same context, above those lines, and `/squirrel:tune` writes `profile.md` from user-dictated text —
so "the profile is trusted" was never available as an answer.

**The hook layer.** `neutralise_forged_lines` in `scripts/load-profile.sh` marks any line of the
quoted profile body that begins with one of squirrel-mode's own injected prefixes, putting
`[profile] ` in front of it, so such a line no longer reaches the model beginning that way. Nothing
is deleted: the user's text is still there, still readable, and still theirs — it simply no longer
impersonates the hook.

**The reading layer.** The rules in `skills/dig/SKILL.md` and `skills/pickup/SKILL.md` are exactly
as strict as they were before that function existed: position relative to the last `Session
off-token:` line, a shape test per line, last-wins among lines that already qualify, and single-quoted
values on the command line.

**Either alone is sufficient, and neither is allowed to justify weakening the other.**
`neutralise_forged_lines` fails open by design — an `awk` that is absent, fails, or prints nothing
returns the body unchanged — and on that path the reading rules are all that is left. In the other
direction, a model can misapply a reading rule, and the hook layer is what holds when it does. The
same statement is recorded in ADR-0002's Amendment (PICKUP-LIST), for the checkpoint list block the
identical mechanism protects; the two ADRs say it the same way on purpose.

**The bound on a successful forgery, as measured rather than as first assumed.** Single-quoting
every value limits a forged search-command line to running one file that already exists, at an
absolute path of the forger's choosing ending in `/scripts/hoard-search.sh`, with no arguments and
no shell syntax anywhere. That file **needs only to exist at a predictable absolute path** —
`/tmp/anything/scripts/hoard-search.sh` satisfies every rule — and an unpacked archive or a
downloaded artifact puts a file there with nothing ever executing to place it. A script sitting at
such a path can print result rows indistinguishable from real ones. An earlier draft claimed the
attack needed someone who could already write files on the machine; that was disproved by running
it, and is not restated anywhere.
