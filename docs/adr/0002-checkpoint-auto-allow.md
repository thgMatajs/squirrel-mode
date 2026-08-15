# The plugin auto-approves writes to its own checkpoint directory

Checkpoints only pay off if they are already written when an interruption arrives, which means Claude has to update them as work completes rather than when asked. Every such update is a `Write` tool call, and a permission prompt per completed step would make an anti-interruption plugin the loudest source of interruptions in the session. Plugins cannot pre-grant permissions — a plugin's `settings.json` accepts only `agent` and `subagentStatusLine` — so we use a `PreToolUse` hook whose `if` field matches `Write($HOME/.claude/squirrel/checkpoints/**)` and returns `permissionDecision: "allow"`. The `if` field uses permission-rule syntax, so the path gate is declarative and evaluated before our script runs. — **Superseded on both counts; kept as first written, this ADR's convention for every statement its amendments overtake.** No `if` field was ever shipped: `hooks/hooks.json` matches broadly on `Write|Edit|Read` and the gate lives in `scripts/allow-checkpoint.sh`, as the first Consequences bullet below already says in as many words. And the path it guards is `~/.squirrel/checkpoints/`, not the one named above — see Amendment (S11) below, and [ADR-0003](./0003-profile-outside-plugin-data.md)'s own Amendment (S11) for the move.

## Consequences

- **A plugin auto-approves its own file reads and writes.** This is the kind of thing a security reviewer must find documented rather than discover in `hooks.json`, so README states it under privacy alongside the no-telemetry claim. The scope is one directory the plugin owns; nothing else is auto-approved. — **Widened, not superseded, by [ADR-0008](./0008-hoard-auto-allow.md); this bullet is kept as first written, this ADR's convention.** The scope is now TWO directories the plugin owns, `~/.squirrel/checkpoints/` and `~/.squirrel/hoard/`, sharing one gate, one set of layers and one `allow` emission. "Nothing else is auto-approved" still holds; "one directory" stopped holding when the hoard landed. ADR-0008 states what the second root adds — a stricter direct-child rule and a refusal of auto-approval for a write that looks like it carries a credential — and both of those add refusals rather than removing any.
- **The gate lives in the script, not in the hook's `if` field.** `PreToolUse` accepts an `if` using permission-rule syntax, but the plugin cannot know the user's `$HOME` at build time and it is unverified whether that syntax expands `~` or `$HOME`. So `hooks.json` matches broadly on `Write|Edit|Read` and `scripts/allow-checkpoint.sh` reads `tool_input.file_path` and decides. That makes the script a security boundary, and a testable one — an `if` expression is not. This is the settled, current design, not the one first shipped: the original script preferred a top-level `file_path` over `tool_input.file_path`, which a crafted payload could exploit (see the AB1 amendment below), and until the AC1 amendment below, the field was recovered by a sed fallback when `jq` was absent, which could not parse a nested `tool_input` correctly either. Both are recorded, not scrubbed, because a security boundary's history of what it used to get wrong is part of its documentation, not an embarrassment to edit away.
- **The script either auto-approves or declines to decide, never denies.** Refusing a write is not this plugin's business; declining hands the decision back to the normal permission flow. Declining is expressed by exiting 0 with **empty stdout** — see the Amendment (v0.3.1) below, which corrects this bullet's original wording ("returns `allow` or `defer`") and the mechanism it described.
- **Symlink trust boundary.** A symlink at `checkpoints/` or anywhere below it is rejected: the only mechanism that ever creates that directory is a plain file write through this plugin's own flow, and a plain file write never produces a symlink — so a symlink there is never legitimate and would silently redirect every auto-approved write. (**Corrected, cycle 2 of the hard-link audit.** This bullet used to justify the rejection by asserting that the plugin creates the directory. Nothing does. `grep -rn mkdir` over this repo is the whole disproof: no shipped script, skill or rule creates `~/.squirrel/checkpoints/` or `~/.squirrel/hoard/`; `/squirrel:init` creates `~/.squirrel/` and writes `profile.md` into it, nothing deeper; and both governed roots come into existence implicitly, as the parent directory the model's first `Write` to a path inside them creates. `scripts/allow-checkpoint.sh` was corrected on exactly this point in the cycle that added the hard-link layer, and its correction was pinned by needle — but that pin's scope was one file, so this copy of the same false claim survived intact in the document a reader of the ADR trail reaches first. The conclusion is unchanged and the reasoning is now one that holds. The stale phrasing is deliberately not restated here, so `tests/test_repo_invariants.sh`'s invariant 16 can forbid it by needle across **every tracked file outside `tests/`** — the widening that closes the gap this correction is about — without this correction being the thing its needle finds.) A symlink at `~/.claude` or `~/.claude/squirrel` is trusted, because `chezmoi`, `stow` and `yadm` routinely make those symlinks and rejecting them would break checkpoint writes for every dotfile-manager user. (Superseded by the move recorded in Amendment (S11) below: the trusted symlink today is `~/.squirrel/` itself, and [ADR-0003](./0003-profile-outside-plugin-data.md)'s Amendment (S11) re-derives that boundary for the shallower layout. The reason is unchanged — a dotfile manager symlinking a whole per-target config directory is normal, not an attack.) The check is a component walk using the `[ -L ]` shell builtin, so it holds on a system with neither `realpath` nor `readlink`. An earlier revision compared `realpath` of the target against `realpath` of the checkpoint directory; that can never detect a symlink at or above the shared prefix, because both sides resolve through it and always compare equal. That code was removed rather than relabelled — dead code that reads as protection is worse than none.
- **`file_path` is capped at 4096 bytes before any per-segment work.** It arrives as an arbitrary JSON string, not a real path, so no `PATH_MAX` bounds it, and the normalisation is quadratic in segment count: 3000 segments cost over six seconds on the author's machine, paid on every `Write` and `Edit` in the session. A path just under the cap still costs about two seconds in the worst case — bounded, and judged acceptable.
- **The spec's "silently update the checkpoint" was corrected wherever it described our own writes.** Tool calls are always visible in the transcript. What we can guarantee is no prose about it in the response, not invisibility, and promising otherwise would have been a promise we cannot keep. The narrow rule the repo enforces: no shipped instruction or user-facing document may claim these writes are hidden from the user. Describing an *error* path as failing quietly is an unrelated and legitimate use, and stays.
- **Write frequency is capped** at one checkpoint update per turn, and only when `Doing` or `Next` actually changed. Without a cap, "whenever a meaningful unit of work completes" becomes a write per step.
- Users who never want this can delete the hook from the installed plugin, at the cost of a permission prompt per checkpoint update.

## Amendment (S10-1) — the original matcher covered writes, not the read every interaction starts with

Every checkpoint interaction actually begins with a `Read`, not a `Write`: `/squirrel:pickup` reads
the checkpoint file before it can show anything, and rule 14's own update path has to read the
current Done log to know which entries are the last 10 before it can write the new one. The original
version of this decision covered only `Write` and `Edit` — `hooks.json`'s matcher was `Write|Edit`,
and `scripts/allow-checkpoint.sh` returned `defer` for `tool_name: "Read"` on the identical path it
happily returned `allow` for on a `Write`. This was missed during the original build: every automated
scenario in `tests/test_hooks.sh` asked the script about `Write`, so the gap was invisible to the
suite. A live, headless probe (S10, probe F) caught it directly — the model reported that reading the
checkpoint path required approval — which is what a static test asking only about `Write` structurally
cannot surface.

The fix extends the matcher to `Write|Edit|Read` and extends `scripts/allow-checkpoint.sh`'s decision
to return `allow` for `Read` too, under the identical path validation already applied to `Write`/`Edit`:
the same lexical traversal/prefix-escape checks, the same component-walk symlink defence (including at
`checkpoints_dir` itself), the same 4096-byte `file_path` cap, and the same dotfile-manager exemption
for a symlinked `~/.claude`. A read is strictly narrower in risk than a write — it cannot plant or
redirect anything — so widening the boundary to include it does not loosen what the boundary rejects;
every path that defers for a `Write` still defers, identically, for a `Read`. `Bash` and every other
tool name still fall through to `defer` unconditionally; the matcher was not widened beyond what this
fix required.

This amendment records the gap rather than silently closing it: the original text above still
describes the mechanism as it was designed and shipped, missing the read, because that is what
actually happened and the record is more useful for saying so than for reading as though it were
always right.

## Amendment (S10 review cycle 1, AB1) — a benign top-level field could shadow the real one

The path validated by `scripts/allow-checkpoint.sh` used to come from a helper that preferred a
TOP-LEVEL `file_path` over `tool_input.file_path` if both were present — `(.[$k] //
.tool_input[$k] // empty)` in the `jq` path, and an unscoped, greedy, effectively last-match-wins
scan of the whole raw JSON text in the `sed` fallback. The real PreToolUse payload carries the
tool's own parameters under `tool_input`, never at the top level; the top-level fallback was never
part of that contract. A payload carrying a BENIGN top-level `file_path` (something that resolves
inside `checkpoints/`) alongside a MALICIOUS `tool_input.file_path` (something that does not) made
this script validate the field the operation never reads and `allow` the operation on the field it
actually does — reproduced for `Read`, `Write`, and `Edit` alike, and independently in both the
`jq` path and the `sed` fallback (the `sed` bug was order-dependent rather than
preference-dependent: reordering the same payload's keys flipped which field's value it returned).

Fixed by splitting the single field-reading helper into two: `extract_field`, kept top-level-only
and used only for `tool_name` (which legitimately lives there, a sibling of `tool_input`, in the
real contract); and a new `extract_tool_input_field`, which reads `file_path` from *inside*
`tool_input` ONLY, in both the `jq` path and its `sed` fallback, never a sibling top-level field of
the same name. `tool_name` staying top-level-only was a deliberate choice, argued and confirmed
against the real PreToolUse contract, not an oversight left unexamined: there is no legitimate
payload shape in which the operation's own `file_path` lives anywhere but `tool_input.file_path`.

## Amendment (S10 review cycle 2, AC1) — the sed fallback could not parse nested JSON, so it was removed

AB1's fix scoped the `sed` fallback to `tool_input`'s own text, but the mechanism it used to find
that text — capture everything between `tool_input`'s opening `{` and the FIRST literal `}` after
it — cannot tell "the first `}` that closes `tool_input`" apart from "the first `}` that closes an
object NESTED inside `tool_input`", because a regex matches text shapes and does not track brace
depth. A payload carrying a nested decoy object with its own `file_path` defeated it:

```
{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd",
 "decoy":{"file_path":"$HOME/.claude/squirrel/checkpoints/legit.md"}}}
```

The nested decoy's own closing brace is the FIRST one in `tool_input`'s text, so the old isolation
regex captured only up to it, and the greedy key search inside that truncated capture returned the
decoy's legitimate-looking `checkpoints/` path instead of the real, dangerous
`tool_input.file_path` (`/etc/passwd`) the `Write` tool actually operates on. With `jq` present the
script parsed the real nested structure correctly and deferred; with `jq` stripped from `PATH`, it
fell to the broken `sed` fallback and wrongly allowed the write that targets `/etc/passwd`.

No narrower isolation regex closes this: each pattern tried only shrinks the set of nested shapes
that defeat it, never eliminates the set, because the underlying problem — matching text without
tracking structure — does not go away by writing a more specific match. This ADR's earlier
amendments already record two instances of that exact trap for the symlink defence ("Layer 3 was
removed, not relabelled") and for `check_no_claude_only_syntax`'s word-boundary logic; AB1's own
`sed` fix, six months earlier by build time, was itself one narrowing of a fallback that ultimately
had to be removed outright rather than narrowed a second time.

**The fix is removal, not another narrowing.** `extract_tool_input_field`'s `sed` fallback for
`file_path` is gone. Without `jq` on `PATH`, the function returns nothing, `file_path` resolves
empty, and `decide()`'s own existing empty-`file_path` handling defers — no special-casing for "jq
absent" was needed, because an empty value already took the safe branch. `extract_field`'s own
`sed` fallback (used only for `tool_name`, a flat top-level field with no nested object of its own
to be confused with) was deliberately left in place: `decide()` never calls it for `file_path`, the
one field this vulnerability class implicates, and removing it anyway was tried and reverted after
it broke unrelated failure-proof fixtures (`tests/test_hooks.sh` scenarios 16/17) that rely on its
existing, unscoped behaviour to simulate a different, older, already-fixed bug shape. Scope stayed
precisely on the function actually implicated.

**The cost, stated plainly.** On a machine without `jq`, every checkpoint `Write`, `Edit`, and
`Read` — including a perfectly legitimate one — now falls back to the normal permission prompt
instead of being auto-approved. This is worse, in the single dimension of convenience on a jq-less
machine, than the behaviour it replaces. It is accepted anyway: a wrong `allow` on this boundary is
unrecoverable (the operation already happened by the time anyone could object), while a wrong
decline merely costs one permission prompt on a machine that was already missing a tool this
project's own test suite treats as a hard prerequisite (`tests/run.sh`). That "merely costs one
permission prompt" reading became true only with the Amendment (v0.3.1) below: at the time this
amendment was written the decline was emitted as `permissionDecision: "defer"`, which does not cost
a prompt — it parks the tool call and stops the turn. The sentence above describes the behaviour as
it is now, and this note records that it did not describe the behaviour as it then was. `README.md` and
`docs/ACCEPTANCE.md`'s criterion 12 both state this cost explicitly, alongside the auto-approval
mechanism itself, rather than leaving it implicit in this ADR alone.

`tests/test_hooks.sh` scenario 60 pins the nested-decoy payload as a permanent assertion, for
`Read`, `Write`, and `Edit`, with `jq` present (must defer — unaffected, `jq` parses real nesting
correctly) and absent (must defer — the fix); a companion assertion pins that an otherwise
legitimate, non-nested payload still allows with `jq` present and now defers with `jq` absent; and
a failure-proof mutant reintroduces the removed `sed` fallback into a scratch copy of the current
script and confirms it reproduces the exact `allow` this amendment fixes, with `jq` stripped from
`PATH` — proving the new `defer` assertions are not vacuous.

## Amendment (S10 review cycle 3 final gate, AD1) — the "always exits 0" claim did not hold for a wedged `jq`

`scripts/allow-checkpoint.sh`'s own header claimed "the final `case` below always emits exactly one
well-formed JSON decision and this script always exits 0" — stated with no qualification. That is
false for one input this script cannot bound: a `jq` that is present on `PATH` but WEDGED — stopped,
deadlocked, or otherwise never returns. Reproduced directly: a `jq` shim that loops forever left the
script still running, with zero bytes of stdout, two seconds in — at which point the process was
killed externally to end the reproduction, not because the script itself ever returned. The
`if decision=$(decide 2>/dev/null); then ... fi` wrapper catches `decide()` **failing** (a non-zero
exit); it cannot catch `decide()` never **finishing**, because the shell has to wait for that command
substitution's subshell — itself blocked inside `jq` — to return before the `if` can even be
evaluated. No POSIX `sh` construct interrupts a command substitution already in flight.

**The fix is the honest claim, not a `timeout` wrapper.** `timeout(1)` is GNU coreutils, not POSIX,
and is absent from stock macOS — wrapping the `jq` calls in `extract_field`/`extract_tool_input_field`
with it would add a dependency to a security hook to cover a pathological system state (a wedged
system binary), which is the wrong trade for what it buys. The corrected header now states precisely
what the contract covers: every input, and every command **failure** this script depends on — `jq`
exiting non-zero, `jq` exiting 0 with no output, and `jq` printing the literal string `null` are all
reproduced (this fix) to defer correctly in well under a second (112–272ms, measured on the author's
machine — stated as machine-specific data, not a portable performance guarantee). It does not cover an
invoked command that is never given the chance to fail or succeed because it never returns at all;
that gap is bounded only by the harness's own hook timeout (Claude Code kills a hook process that
overruns its configured or default timeout), never by anything in this script.

Checked for the same absolute claim elsewhere (this ADR, `README.md`, `docs/ACCEPTANCE.md`,
`PLAN.md`): none of the other three restate it — this ADR's own text above never claimed the script
"always exits 0" unqualified, only that it "returns `allow` or `defer`, never `deny`". `scripts/
load-profile.sh` carries an analogous unqualified "must NEVER exit non-zero... no matter how broken
its input" claim in its own header, scoped to malformed/missing *input and filesystem state*, not to
an external command that never returns — a real, if narrower, instance of the same class, and reported
here rather than fixed: it is a different script, out of this fix's scope, and `load-profile.sh`'s own
`jq` usage is explicitly PREFERRED-not-REQUIRED with an `awk` fallback for every call, which changes
the analysis enough that it deserves its own look rather than a drive-by edit.

## Amendment (S11) — the mechanism was sound; it was pointed at a location where it structurally could not work

Every amendment above (S10-1, AB1, AC1, AD1) fixed a real defect in *this script's own logic* — the
matcher, the field extraction, the JSON parsing, the exit-code claim. All four fixes held. None of
them could have fixed what this amendment records, because the problem was never in this script at
all: it was one layer up, in Claude Code itself, and no amount of correctness inside
`scripts/allow-checkpoint.sh` could reach it.

**The experiment (S10-2).** Criterion 12 ("checkpoints are written... with no permission prompt")
stayed `manual` after every fix above, and probe F (S10) reported, unprompted, that a checkpoint
write was denied and needed the user's approval — the opposite of what this ADR promises. Resolving
that doubt meant instrumenting the actual runtime, not reading the script again:

1. A wrapper around the shipped, unmodified hook script logged every invocation. The `PreToolUse`
   hook **is** invoked for both `Read` and `Write` on the checkpoint path, with the real payload
   shape (`tool_input.file_path`), exactly as the amendments above assumed.

2. The wrapper's logged decision **is** `permissionDecision: "allow"`, exit 0, well-formed JSON — for
   both tool names. The script was doing its job correctly.

3. **The write was still denied** — creating `~/.claude/squirrel/checkpoints/` (this ADR's location
   before the fix below moved everything to `~/.squirrel/checkpoints/`) by hand first did not help.

4. A hook rewritten to `allow` **everything**, tested with the working directory set to a scratch
   directory, against three target shapes:

   | target | result |
   | :-- | :-- |
   | inside the cwd | **wrote** |
   | outside the cwd, outside `.claude` | **wrote** |
   | inside `~/.claude/` | **denied** |

A hook's `allow` **is** honoured, and it **does** cross the working-directory boundary — rows 1 and 2
prove the mechanism this whole ADR describes is real and works exactly as designed, for the large
majority of the filesystem. Row 3 is the only failure, and it isolates the cause completely: `.claude`
itself. Claude Code treats it as a **protected path**, with a safety check that runs *before* any
hook's `allow` is even consulted, matching the documented rule that hooks "can tighten restrictions
but not loosen them past what permission rules allow." No hook script, however correct, can make a
write inside `.claude` skip a permission prompt — the auto-approval this ADR designs is categorically
inapplicable there, not merely buggy there.

**Why this survived four rounds of fixes and every static test.** Every automated scenario in
`tests/test_hooks.sh` checks what THIS SCRIPT returns for a given input, run directly — `sh
scripts/allow-checkpoint.sh < payload.json` — never through the actual Claude Code permission
pipeline the real hook runs inside. That is the correct way to test a security boundary this script
owns (fast, deterministic, no dependency on a live harness), and it is also structurally blind to a
safety check that lives entirely *above* this script, in code this repository does not contain and
cannot invoke from a test. Four rounds of review made the script's own decision logic provably
correct. None of them could have found this, because the script was never where the problem was.

**Consequence.** ADR-0003 chose `~/.claude/squirrel/` (now `~/.squirrel/`, per that ADR's own S11
amendment) so this data would survive plugin uninstall. This ADR then designed the auto-approval
mechanism around writing there without a prompt. Those two decisions were incompatible from the
start, and nothing in either ADR's own reasoning, read on its own, revealed that — each was locally
sound. **The fix is ADR-0003's, not this one's**: move the data to `~/.squirrel/`, outside `.claude`
entirely, the exact shape row 2 above proves works. This ADR's
mechanism is unchanged by that move — the matcher, the field extraction, the path validation, the
symlink defence, the `jq` requirement all stay exactly as amended above — because the fix was never
"make this script smarter." It was already correct. The fix was making sure it gets asked about a
path that Claude Code allows a hook to decide on at all. See
[ADR-0003](./0003-profile-outside-plugin-data.md)'s own Amendment (S11) for the new location, the
symlink trust boundary re-derived for it, and the migration notice for anyone still on the old path.

## Amendment (v0.3.1) — "defer" is a real value that pauses the session; it was never "no opinion"

Every amendment above fixed a defect in *which decision* the script reaches. This one is about *how
the decision is spoken*, and it is the more serious class: the decision logic was right and the
emission made it harmful.

`scripts/allow-checkpoint.sh` ended with a two-armed `case`. The `allow` arm printed the
auto-approval JSON. Every other arm printed:

```
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}
```

and this ADR, `README.md`, and the script's own header all described that as handing the decision
back to the normal permission flow "exactly as if this hook did not exist."

**That was false.** `permissionDecision: "defer"` is a real Claude Code value, but it does not mean
"this hook has no opinion." It means *defer this tool call for later*: the session pauses, the tool
never executes, and a headless run terminates with `stop_reason: "tool_deferred"`. The documented way
for a `PreToolUse` hook to express "no opinion, use the normal permission flow" is to **exit 0 with
empty stdout**. Confirmed twice over — by live testing and against the official documentation —
before any code was changed.

**What it cost.** Measured with the real `claude` CLI (v2.1.227), same prompt and project, only the
plugin varying:

| scenario | no plugin | plugin as shipped | plugin with the `defer` emission removed |
| :-- | :-- | :-- | :-- |
| default mode, `Read` a file in cwd | `end_turn`, correct answer | `tool_deferred`, EMPTY response | `end_turn`, correct answer |
| `--permission-mode bypassPermissions`, `Write` a file | `end_turn`, file created | `tool_deferred`, no file | `end_turn`, file created |
| default mode, write own checkpoint | n/a | allowed, no prompt | allowed, no prompt (unchanged) |

So installing this plugin broke ordinary file operations for every user, on every path this hook's
matcher (`Write|Edit|Read`) touches — which is nearly all of them, because the matcher is broad by
design (see the second Consequence bullet above). It also explains, retroactively, why
`/squirrel:off`, `/squirrel:init` and `/squirrel:tune` returned completely empty responses in live
runs: the first tool call each of them makes was being parked rather than permitted, and there was
nothing after it.

**The fix is the emission, and only the emission.** The non-`allow` arm now prints nothing and exits
0. The `allow` arm is byte-for-byte unchanged — row 3 of the table above is the point: the
auto-approval this whole ADR exists to design was working, and still works. `decide()` still returns
the two internal tokens `allow` and `defer`; "defer" remains the correct word for the *concept* (this
hook declines to decide) and is still used that way throughout the script, this ADR, and `README.md`.
What changed is what the process writes when that concept applies.

**Why every static test missed it, again, and what changed so the next one will not.** This is the
same structural blind spot Amendment (S11) records, in a different place: every scenario in
`tests/test_hooks.sh` asserted on the *content of a JSON decision this script printed*, so a script
that printed a syntactically perfect, semantically catastrophic decision passed all of them. The
suite could see the value; it could not see what the value meant one layer up. The assertions are now
rewritten to the shape the fix actually requires — for a no-opinion outcome the suite asserts **empty
stdout AND exit status 0**, as a conjunction, in a single helper (`assert_no_opinion`), specifically
so no future call site can assert only the empty-stdout half that a *crashed* script would also
satisfy. Reverting this fix by hand in a scratch copy of the repository turns 77 assertions red.

`README.md`'s description of the fallback ("that write falls back to the normal permission prompt")
needed no change: it always described the intended concept, and this fix is what finally made it
true.

## Amendment (PICKUP-LIST) — the promise held for the write and broke on the read, the moment a project's memory became a directory

This ADR promises that an ordinary checkpoint interaction never costs a permission prompt, and
Amendment (S10-1) above already widened the matcher to `Read` on the grounds that every such
interaction *begins* with one. Both statements stayed true for `Write`. Neither survived
[ADR-0006](./0006-session-isolation-concurrency.md).

**What changed underneath this ADR.** v0.3.0 split a project's memory from one flat file into one
file per session inside a per-project directory. Rule 14's write is unaffected — it writes the single
path it was handed. `/squirrel:pickup` is not: folding every past session's file into one answer
means **enumerating that directory**, which is a thing this ADR's mechanism structurally cannot
cover. `hooks/hooks.json`'s `PreToolUse` matcher is `Write|Edit|Read`; enumeration is none of those.
On a harness exposing only Read, Write, Edit and Bash, the one tool left that can list a directory is
Bash, and `scripts/allow-checkpoint.sh` never sees a Bash call. Recorded when the fix was written: an
ordinary `/squirrel:pickup` under default permissions stopped and asked for approval to list the
directory — the exact interaction the first paragraph of this ADR says never costs one.

**The fix is not a wider matcher, and deliberately so.** Auto-approving `Bash` would mean returning
`permissionDecision: "allow"` for a tool whose argument is an arbitrary command string. Everything
that makes the auto-approval in this ADR defensible — one field, `tool_input.file_path`, normalised
and checked against one directory this plugin owns — evaporates there. So the enumeration is removed
instead of permitted: `scripts/load-profile.sh` hands the model the answer at `SessionStart`, as a
block of absolute checkpoint paths, newest first. This is the same move tech-lead Decision 1 already
makes for the checkpoint path itself (the model cannot compute the project-slug algorithm, so it is
given the result rather than the means), applied one level further out. With the list in context,
`/squirrel:pickup` needs only `Read` on paths this hook already auto-approves.

**Two properties keep the new line from becoming its own surface.**

1. **The block's header carries this session's off-token.** `build_context` quotes `profile.md` into
   the same `additionalContext` FIRST, so profile text COULD otherwise spell any of these lines
   exactly, including a perfect copy of the header followed by paths of an attacker's choosing — and
   `/squirrel:tune` writes `profile.md` from user-dictated text, so "the profile is trusted" was
   never available as an answer. The token is derived from the `session_id` this hook was handed on
   stdin, so a `profile.md` written before this session started cannot contain it. It rides on the
   incompleteness marker below for the sharper version of the same reason: a marker is an
   *instruction to go enumerate*, and unbound it would be a way for profile text to spend a
   permission prompt.

   **Amended (task 7b).** The quoting is no longer bare: `neutralise_forged_lines` in
   `scripts/load-profile.sh` marks any body line that begins with one of squirrel-mode's own
   injected prefixes — the header's and the marker's included — so such a line no longer reaches the
   model beginning that way. Nothing above is relaxed on the strength of it, and the token stays
   exactly as load-bearing as it was: that step fails open, and the token is what holds when it
   does. Two independent layers, either sufficient alone.
2. **A block that left something out says so.** It closes with
   `(more checkpoint files exist in that directory than are listed here - session <token>)` on
   exactly two conditions — the `CHECKPOINT_LIST_MAX_FILES` cap, and a real checkpoint whose filename
   falls outside the character class the hook writes. The absence of that line is therefore a
   positive guarantee that the list is whole, which is what lets `skills/pickup/SKILL.md` forbid
   enumeration in the common case without ever making memory unreachable.

**What this amendment does not change.** `scripts/allow-checkpoint.sh` is untouched, byte for byte.
No new tool is auto-approved, and the set of auto-approved paths is unchanged. Enumeration still
costs one permission prompt in the two cases where it genuinely has to happen — a marked block whose
unnamed files the user's request actually needs, and no block at all — and `skills/pickup/SKILL.md`
tells the model to ask for it plainly rather than work around it.

**Evidence, and what remains unobserved.** Suite at 2021 assertions, 0 failures. Against a copy of
the repository, neutralising the hook's call site turns **42** assertions in `tests/test_hooks.sh`
red; removing the session token from the block header turns **34** red; weakening the completeness
clause in `skills/pickup/SKILL.md` turns **1** red in `tests/test_skills.sh`. Driven directly against
the real hook under a scratch `HOME`: fourteen eligible files yield exactly ten, newest first, plus
the marker, with all fourteen still on disk; exactly ten yield no marker; a `café.md` newer than the
ASCII files under `LC_ALL=pt_BR.UTF-8` yields a block naming only the ASCII file, the marker, and
`Resume available` unchanged; a symlinked slug directory yields no block and no resume banner; a
newline in `$HOME` yields no block, valid JSON and exit 0; a failing `ls` yields no block with
`Resume available` intact, so pickup falls back to enumerating. A `profile.md` spelling the header
and `/etc/passwd` yields two headers in one context, of which only the hook's carries the token, and
the hook's is both last and below the last `Session off-token:` line.

What none of that observes is the half that lives in the model: that `/squirrel:pickup` now reads the
handed-over list instead of shelling out. That needs a live authenticated session, which is
unavailable under the scratch `HOME` every probe here requires, and it is the same reason
`docs/ACCEPTANCE.md` criterion 12 stays `manual`.
