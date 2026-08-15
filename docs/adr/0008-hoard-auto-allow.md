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
   rather than a fixed directory, not of a second copy of the check. The full attack matrix runs
   against the hoard shape rather than being assumed to transfer; see `tests/test_hooks.sh`'s
   `HOARD-3` **and `HOARD-3f` through `HOARD-3n`**.

   *Corrected.* This bullet used to cite `HOARD-3` alone as "the full attack matrix". `HOARD-3` held
   four assertions — a `..` component, a prefix escape, a symlink below the root, a symlink at the
   root — while the matrix the checkpoint root is held to also contains field shadowing (AB1), the
   nested decoy (AC1), `jq` absent, `jq` returning `null`, `jq` returning nothing, a malformed
   payload, a `file_path` over the length cap, and `$HOME` unset/empty/`/`/trailing-slash. None had
   ever been run with a hoard path. They have now, they all behave as the checkpoint root does, and
   `HOARD-3f`–`HOARD-3n` are where they live — so the sentence is true because the scenarios exist,
   not because it was narrowed.

2. **A hard link inside a governed root is not auto-approved.** *(Added; this closes a blocker.)*
   Layers 0–2 all reason about the path — its text, its prefix, whether any component is a symlink.
   A hard link is none of those: it is a second directory entry for an inode that already has one
   somewhere else, and it leaves the path completely ordinary. `ln ~/.ssh/id_rsa
   ~/.squirrel/hoard/global/notes.md` produced `allow` for both `Read` and `Write`, in both roots —
   the private key read, and overwritten, with the prompt this hook had just suppressed. The
   symlink spelling of the same attack deferred, which is what made the gap easy to miss.

   The refusal is: an **existing regular file** at the leaf must have a link count of 1. A leaf that
   does not exist yet is not tested (it has no link count, and every first write has that shape); a
   directory is not tested either (directories always carry at least two links, so testing them
   would defer the legitimate `Read` of a checkpoint's per-project directory). Every file either
   root legitimately holds is created by one `Write` from this plugin's own flow and has exactly one
   name, so this is a guard with no correct traffic behind it. `HOARD-14` pins it in both roots for
   `Read`, `Write` and `Edit`, alongside the four "must still allow" shapes.

   **It needs `find`, and without `find` it does not run.** There is no way to read a link count
   from POSIX `sh` without an external command. `find <file> -links +1` is the narrowest one
   available — no output parsing, and no `stat`, whose flags differ between BSD and GNU. It is
   placed **after every other decision in `decide()`**, so it runs only where the answer would
   otherwise already be `allow`: `jq` is already mandatory on that exact path, so one more command
   there costs a path that already pays for one, while every defer — a `..` component, an over-cap
   path, a path outside both roots, a symlink, a credential — still reaches its answer with no
   process spawned at all. With `find` off `PATH` the layer cannot run and the hard link is
   auto-approved again, which is the same shape of degradation `grep` already has for the secret
   scan below. Deferring instead was rejected for the usual reason: it would put a permission prompt
   on every checkpoint write on such a machine, and the hole it would close is the hole that exists
   there today. `HOARD-14e` asserts both directions on a `PATH` holding only `jq`, `cat` and `grep`.

   **What an `allow` therefore means, stated exactly.** It is a statement about the **name**, checked
   at the instant the hook runs. It is not a statement that the bytes reached live inside the root
   (that is the hard-link case, now closed while `find` is present), and it is not a statement about
   what the name refers to a moment later — whatever this script resolves, the filesystem can be
   changed between the decision and the tool call it approved. `scripts/allow-checkpoint.sh`'s header
   said "resolves inside", every reader took it for the stronger claim, and it now says what it
   checks.
3. **A direct child file of `hoard/` defers for every tool**, `Read` included. There is no legacy
   layout to read, so nothing correct targets that shape, which makes it a tripwire with no
   legitimate traffic behind it.
4. **A `Write` or `Edit` whose text looks like it carries a credential is not auto-approved.** On a
   hit the hook declines to decide: the write falls back to the ordinary permission prompt and the
   user chooses. It **refuses auto-approval; it never denies.** Text past the scan cap defers
   unscanned.

   *Corrected.* That last sentence used to end "on the same reasoning as the existing path length
   cap", and the two caps are not the same reasoning. `MAX_FILE_PATH_LEN` bounds a **quadratic**
   cost — the lexical normaliser and the component walk are both `O(segments²)`, which is why a few
   thousand segments already cost seconds. The scan is **linear**. Linear still needs bounding, but
   capping a straight line is not removing a curve, and calling them the same overstated what one of
   them does.

   **The whole payload is capped too, and that cap is the one that was missing.** `MAX_SCAN_LEN`
   bounds what is *scanned*, never what was *parsed* to produce it: `${#written}` cannot exist until
   `written` does, and producing it runs `jq` over the entire payload — as does reading `tool_name`
   and `file_path`, on every call this hook sees, before any cap was consulted. Measured on one
   32 MB payload: 8.22 s and 407 MB peak RSS for a hoard write, and 2.91 s / 237 MB for a checkpoint
   write, which never scans at all. `MAX_PAYLOAD_LEN` (1 MiB, sixteen times the scan cap) is now
   tested with `${#input}` — a shell expansion, so it adds no command to any path — before the first
   `jq` runs; the same payloads then cost 0.71 s and 0.70 s. What it does **not** bound is
   `input=$(cat)` itself, which runs before it and reads whatever the harness delivers; that residue
   is stated in the script rather than papered over. `HOARD-15` pins a discriminating pair (an
   under-cap and an over-cap payload differing only in an `old_string` no scan reads).

   **Both fields are read and both are scanned** — `content`, which `Write` carries, and
   `new_string`, which `Edit` carries. Reading `content` and merely *falling back* to `new_string`
   when it is empty would be the field-shadowing bypass this file's sibling ADR already records for
   `file_path` (ADR-0002, Amendment AB1): `content` is not a parameter the `Edit` tool reads, so a
   payload carrying a benign one alongside a credential-bearing `new_string` would have had its
   decoy scanned and its real write auto-approved. A field the tool does not read must never
   satisfy a check on the field it does.
5. **The secret scan is scoped to the hoard.** `checkpoints/` is excluded deliberately: rule 14
   rewrites a checkpoint every turn, and a scan there would put a permission prompt in the middle
   of the one write ADR-0002 exists to keep silent.

## What the secret scan does NOT catch

**Stated honestly: this is not a complete secret scanner, and does not claim to be.** It matches
unambiguous shapes — PEM private-key delimiters, provider token prefixes, and one assignment-shaped
rule for opaque strings that carry no prefix. A credential in a shape it does not know is
auto-approved, and the skill's own instruction not to write one is the only thing in front of it.

### What it started catching, and what that cost (audit fixes)

Three shapes it claimed to cover and did not, all reproduced against the shipped hook and all
auto-approved before:

- **Compound key names.** The assignment rule required its keyword to sit *immediately* before the
  `:` or `=`, so `aws_secret_access_key = <40 opaque chars>` was auto-approved while the bare
  `api_key = …` deferred — and an AWS secret access key line *is* "the `api_key = <long opaque
  string>` case" the rule's own comment named as its scope. `secret_key = …`,
  `password_hash=…` and `token_value: …` escaped the same way. A `[A-Za-z0-9_-]*` run is now allowed
  between the keyword and the separator, so the keyword may sit anywhere in the name.
- **Values carrying punctuation.** The value class was `[A-Za-z0-9/+_-]{16,}`, which stops at the
  first character outside it: `password = Tr0ub4dor&3xK9!zQmW#pL2vN` was auto-approved because of
  the `&`. **Decision: widen, not document.** The class is now `[^[:space:]]{16,}` — any run of
  sixteen or more non-blank characters. `grep` matches within a line, so a run can never cross a
  line ending.
- **Six whole families with no arm at all:** `sk-proj-` (OpenAI project keys), `sk_live_` /
  `sk_test_` (Stripe), `glpat-` (GitLab), `GOCSPX-` (Google OAuth client secrets), `xapp-1-` (Slack
  app-level tokens), and DSA private keys — the PEM arms named five algorithms explicitly and DSA
  was not one of them. A `PRIVATE KEY-----` arm now catches every PEM private key by its delimiter,
  DSA and anything invented later included; the five algorithm-specific arms are kept beside it
  because they also match a header whose trailing dashes were stripped or reflowed, which the
  delimiter arm cannot.

**Families deliberately left out, and why.** Every prefix is a false-positive surface as well as a
catch, so this list grows on evidence rather than on completeness. `ASIA` (AWS STS session keys) is
excluded because it would defer any memory that mentions the continent — the exact reason `AKIA` is
tolerable and `ASIA` is not. A bare `sk-` is excluded because it is a substring of ordinary words
(`task-force`, `risk-adjusted`). `eyJ` (the base64 opening of a JWT) is excluded because it is also
the base64 opening of `{"`, which any quoted JSON in a memory carries. `SG.` (SendGrid) is excluded
for the same class of collision with ordinary punctuation. Adding any of these is a decision to
trade prompts for coverage, and it should be made with a measurement rather than by reflex.

Four specific limits, each established by running the hook rather than by reading it. An ADR that
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
rule too. The two widenings above buy more of the same, on purpose: a keyword anywhere in the name
means `secretary:` reaches the rule, and a value of any sixteen unbroken characters means
`password: correct-horse-battery-staple` does. Ordinary prose is clean: "never commit without
running the test suite" is auto-approved. Each false positive costs exactly one permission prompt,
never a denial. `HOARD-13f` asserts all five of the original cases, the clean one included, and
`HOARD-16` asserts the two new ones alongside four clean memories that must still be auto-approved.

**With `find` absent from `PATH`, the hard-link refusal drops out.** Same shape as the `grep` limit
above, one layer up: reading a link count needs an external command, `find <file> -links +1` is it,
and with `find` off `PATH` an existing hard link inside a governed root is auto-approved exactly as
it was before that layer existed. Reproduced on a `PATH` holding only `jq`, `cat` and `grep`: an
ordinary new memory still allowed (so the hook was genuinely running), a credential-bearing write to
the same path still deferred (so the rest of the decision was intact), and the hard-linked path came
back `allow`. `HOARD-14e` pins all four of those outcomes.

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

The range is **observable end to end**, not just in a `${#var}` probe: one 40000-character payload of
`€` (three bytes each) defers under `LC_ALL=C` and is auto-approved under `LC_ALL=en_US.UTF-8` — same
hook, same input, same machine. `scripts/allow-checkpoint.sh`'s own comment beside the constant used
to state the character reading without qualification and conclude the cap was *loose*, which is only
the multibyte half: under `C` the same expansion counts bytes and the cap is *tighter*. This ADR had
it right and the script's comment was the copy that fell behind; it now says what this paragraph
says. The same locale slack applies to `MAX_FILE_PATH_LEN` and `MAX_PAYLOAD_LEN`, which are measured
the same way.

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
deliberate: renaming it touches `hooks/hooks.json` and a large, specific number of places in
`tests/test_hooks.sh`. Doing that in the same change that widens a security boundary braids two
risky edits together. The rename is deferred to the phase that rewrites this file's ADR trail.

**The three figures are recorded in `scripts/allow-checkpoint.sh`, not here, and a test re-derives
them.** This ADR used to carry its own copy of them, marked "counted", and both copies were wrong at
the moment they were written — two of the three could not be produced by any counting method, and
the sentence censured the estimate it replaced ("roughly forty") for being an estimate in the same
breath as being incorrect itself. The script's own comment records exactly which figures were
claimed and which were true; that history is written down once, where the numbers live, rather than
twice. One snapshot with a test behind it beats two snapshots without one, so
`tests/test_hooks.sh`'s `RENAME-COUNT` recounts all three from the real file on every run and fails
with the recomputed values when any has drifted. `RENAME-COUNT-b` is what keeps the copy from coming
back here.

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
