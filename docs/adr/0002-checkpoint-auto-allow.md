# The plugin auto-approves writes to its own checkpoint directory

Checkpoints only pay off if they are already written when an interruption arrives, which means Claude has to update them as work completes rather than when asked. Every such update is a `Write` tool call, and a permission prompt per completed step would make an anti-interruption plugin the loudest source of interruptions in the session. Plugins cannot pre-grant permissions — a plugin's `settings.json` accepts only `agent` and `subagentStatusLine` — so we use a `PreToolUse` hook whose `if` field matches `Write($HOME/.claude/squirrel/checkpoints/**)` and returns `permissionDecision: "allow"`. The `if` field uses permission-rule syntax, so the path gate is declarative and evaluated before our script runs.

## Consequences

- **A plugin auto-approves its own file reads and writes.** This is the kind of thing a security reviewer must find documented rather than discover in `hooks.json`, so README states it under privacy alongside the no-telemetry claim. The scope is one directory the plugin owns; nothing else is auto-approved.
- **The gate lives in the script, not in the hook's `if` field.** `PreToolUse` accepts an `if` using permission-rule syntax, but the plugin cannot know the user's `$HOME` at build time and it is unverified whether that syntax expands `~` or `$HOME`. So `hooks.json` matches broadly on `Write|Edit|Read` and `scripts/allow-checkpoint.sh` reads `tool_input.file_path` and decides. That makes the script a security boundary, and a testable one — an `if` expression is not. This is the settled, current design, not the one first shipped: the original script preferred a top-level `file_path` over `tool_input.file_path`, which a crafted payload could exploit (see the AB1 amendment below), and until the AC1 amendment below, the field was recovered by a sed fallback when `jq` was absent, which could not parse a nested `tool_input` correctly either. Both are recorded, not scrubbed, because a security boundary's history of what it used to get wrong is part of its documentation, not an embarrassment to edit away.
- **The script returns `allow` or `defer`, never `deny`.** Refusing a write is not this plugin's business; `defer` hands the decision back to the normal permission flow.
- **Symlink trust boundary.** A symlink at `checkpoints/` or anywhere below it is rejected: only the plugin creates that directory, so a symlink there is never legitimate and would silently redirect every auto-approved write. A symlink at `~/.claude` or `~/.claude/squirrel` is trusted, because `chezmoi`, `stow` and `yadm` routinely make those symlinks and rejecting them would break checkpoint writes for every dotfile-manager user. The check is a component walk using the `[ -L ]` shell builtin, so it holds on a system with neither `realpath` nor `readlink`. An earlier revision compared `realpath` of the target against `realpath` of the checkpoint directory; that can never detect a symlink at or above the shared prefix, because both sides resolve through it and always compare equal. That code was removed rather than relabelled — dead code that reads as protection is worse than none.
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
`defer` merely costs one permission prompt on a machine that was already missing a tool this
project's own test suite treats as a hard prerequisite (`tests/run.sh`). `README.md` and
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
