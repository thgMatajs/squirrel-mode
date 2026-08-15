# The hoard — durable cross-project memory for squirrel-mode

Status: phase 1 implemented (§12, phase 1 — the storage layout, `scripts/hoard-search.sh`,
`/squirrel:stash`, `/squirrel:dig` and ADR-0008's auto-approval), Claude Code only;
phases 2-4 are not started.
What they still owe: the session-start brief with both its caps and the `memory`
profile field (§7.2, §7.5); automatic correction capture, the inbox, `seen`, repetition and
`/squirrel:hoard` (§6.1-§6.3, §7.1); base rule 17, the trailing-line ordering and ADR-0007 (§7.3,
§7.4, and item 1 of §10); and the whole-file temp-then-`mv` writer §6.7 describes, with the
torn-file test §11 pairs with it — phase 1's only writers are the harness's `Write` and `Edit`
tools, so it guarantees nothing about a torn file. Anything below that describes one of those is a
design, not a description of shipped behaviour.
Date: 2026-08-13.
Supersedes nothing. Amends: `CONTEXT.md`, `README.md`, `ADR-0002`, base rule 15.

---

## 1. What this is for

squirrel-mode already survives an interruption **inside one project**: the checkpoint records
Doing / Next / Open decisions per session, and `/squirrel:pickup` folds them back. What it does not
survive is the interruption between projects and between weeks — the lesson learned in one
repository in June is not available in another repository in August, and the correction the user
gave three times is given a fourth time.

The hoard is the layer that outlives both. It holds what was learned, not what was in progress:

- what breaks repeatedly, so the assistant stops re-breaking it,
- decisions already taken with their reasoning, so they are not re-litigated,
- corrections the user gave, so they do not have to be given again,
- how this particular user works, carried into every project on the machine.

The user's own framing, which the rest of this document is accountable to: *"ele sempre irá se
lembrar o que foi feito, erros/acertos; algo que sempre se repete ele irá lembrar — o humano não vai
precisar ficar lembrando."*

## 2. What it is not

Not in v1, and each is a decision rather than an omission:

- **Not team memory.** Nothing is committed to a repository, shared between developers, or reviewed
  in a PR. Team memory is a different product (§13), and building it here would mean writing inside
  a project directory — which squirrel-mode promises it never does.
- **No reactive injection on file edits.** It is the heaviest machinery in the design space this
  borrows from, needs telemetry to calibrate, and injecting mid-task is precisely what costs
  attention when it is calibrated wrong.
- **No derived index, no embeddings, no database.** §5 states the scale limit this accepts.
- **No session memory.** The checkpoint already covers the "what was I doing" question, and covers
  it with machinery a memory store would have to duplicate worse (auto-approved writes, one file
  per session, `/squirrel:pickup` folding them back).
- **No background process, no timers, no activity monitoring.** Unchanged from the current README.

## 3. Naming

**hoard** — the store as a whole. Squirrels practise *scatter-hoarding*: they bury hundreds of nuts
across a territory and recover them from memory. The name of the animal behaviour is already the
name of the product.

| Term | Meaning | Avoid |
| :-- | :-- | :-- |
| **hoard** | The whole store of durable memories, both layers. | memory bank, knowledge base |
| **memory** | One atomic unit: a title, a short body, and its frontmatter. | note, entry, fact, record |
| **layer** | `global` (the user) or `project` (one repository). Every memory is in exactly one. | shared, namespace |
| **candidate** | An automatically captured item in the inbox. Not yet a memory. | draft, suggestion, proposal |
| **brief** | The budgeted block of memories injected at session start. | dump, context, digest |

`digest` is already taken by the command that restructures inbound content; the brief is the opposite
direction and never borrows that word.

**Two `Avoid` columns changed after phase 1, and are recorded rather than quietly swapped.** "store"
came off the hoard's list: this document's own next sentence calls the hoard "the store as a whole",
so the entry contradicted its own definition, and the word is ordinary English in every other
context this repository uses it in. "scope" came off the layer's list for the same reason —
`CONTEXT.md` defines a **Scope guard** and the README has an "out of scope" section, so reserving
the bare word would have made the glossary disagree with two shipped documents on its first day.
"shared" was added in its place, because that is the drift that actually happened: `skills/dig/
SKILL.md` shipped one sentence calling the global layer the "shared" layer, which is the exact thing
this table exists to catch. `CONTEXT.md`'s own entries, added by task 8, agree with this table where
they overlap, which is not everywhere and is worth stating exactly rather than in one word. **hoard**
and **memory** carry the same `Avoid` lists in both documents. **Layer** does not: `CONTEXT.md`
reserves only `namespace` on its `_Avoid_` line and rules "shared" out in the entry's own prose
instead, so the two documents agree on the substance and differ on where they put it. **candidate**
and **brief** have no `CONTEXT.md` entry at all, and should not: they name things phases 2 and 3
build, and a glossary entry for a term nothing on disk uses would be the same overstatement the
status line above was corrected for.

## 4. Storage

```
~/.squirrel/hoard/
  global/<id>.md              # the user: how they work, what breaks everywhere
  projects/<slug>/<id>.md     # one repository: its decisions and episodes
  inbox/<id>.md               # candidates awaiting triage
```

`<slug>` is `project_slug()` from `scripts/load-profile.sh` — `basename-hash` of the cwd, the exact
function the checkpoint directories already use. A project's checkpoint and its memories sort under
the same slug, and no new path-derivation code exists to disagree with the old one.

`<id>` is `<UTC timestamp>-<slugified title>`, for example
`20260813T142530Z-never-commit-without-running-tests.md`. It is sortable by time, readable without
opening the file, and generatable identically by the model (`date -u +%Y%m%dT%H%M%SZ` plus the same
`tr -c 'A-Za-z0-9._-' '-'` idiom `project_slug()` already uses) and by a shell hook. Two writes in
the same second with the same title are the same memory; the collision is the correct outcome.

### 4.1 One memory

```markdown
---
type: feedback
importance: 4
tags: git, tests
created: 20260813T142530Z
last_used: 20260813T142530Z
uses: 0
status: active
superseded_by:
title: never commit without running the test suite
---

Two releases went out with a broken suite because `git commit` ran before `tests/run.sh`.
Run the suite first; a green run is the only evidence that a commit is safe.
```

- `title` lives in the frontmatter, not as an `#` heading, so one `awk 'FNR<=12'` pass over every
  file collects everything the brief and the ranking need without ever reading a body.
- `type` is one of `feedback` (how to work), `decision` (a choice with its reasoning), `episode` (a
  failure and its fix), `reference` (a fact or pointer). There is no `session` type; the checkpoint
  covers that.
- `status` is `active` or `superseded`. Nothing is ever `archived`, because nothing is ever pruned
  (§6.6).
- `superseded_by` holds an `<id>` or is empty.
- Timestamps are compact ISO-8601 UTC, parsed arithmetically in awk (§5); there is no dependency on
  GNU `date`.

Bodies are short by construction. A memory that needs three paragraphs is two memories.

## 5. Ranking

Every memory carries a score. With no query (the brief):

```
score = (importance / 5)
      × exp(-lambda × days_since_last_used)
      × (1 + 0.2 × log(1 + uses))

lambda = 0.16 × (1 - importance × 0.8 / 5)
```

Important memories decay more slowly; a memory that has actually been used holds its place. `exp()`
and `log()` are in POSIX awk, so this is one awk expression and no external process.

With a query (`/squirrel:dig`), the score above is multiplied by a relevance term: the fraction of
query tokens (lowercased, stopwords dropped) that appear in `title` or `tags`. A memory matching no
query token is not a result.

`days_since_last_used` is computed inside awk with a days-from-civil conversion over the timestamp's
digits — roughly six lines, fully deterministic, no `date` arithmetic and no GNU extensions. Bucketed
tiers ("used in the last 30 days") were considered and rejected: the tiers are not less code, and
they make two memories a day apart rank identically for a month.

**These weights are a starting point, not a finding.** They are conventional choices for this shape
of scoring function, never measured against this corpus, at this scale, for this user. They belong
in `docs/RESEARCH.md`'s *"rules with no research claim behind them"* section, named as a design
decision — and they should be revisited once there is real usage to calibrate against.

### 5.1 The scale limit, stated

There is no index. The brief and `dig` read the frontmatter of every file in one awk process. This
is the whole reason the implementation is small: no rebuild, no staleness detection, no schema
migration, no divergence between a file and its index. Every one of those is a failure mode that
exists only because the index exists.

The cost is a ceiling, and phase 1 measured where it sits. On the author's machine a query costs
about 44 ms at 500 memories, 79 ms at 1000, and 155 ms at 2000.

**The split inside that total was published wrong, and this is the correction.** This section used to
say that at 2000, 110 ms of the 155 ms was the awk frontmatter pass, and concluded from it that the
scan this section defends is most of what a search spends. Re-measured independently on the same
machine — the real `scripts/hoard-search.sh` run whole, and again cut short after the two `set --`,
after the prescan, and after awk, so every phase is timed inside one run, in one locale, against one
fixture — the totals reproduce and the attribution does not. The totals came back 42, 81 and 159 ms
at the three sizes. At the 2000-memory size the awk pass is **about half** of the run rather than the
71% the old 110-of-155 figure implied, and the shell's own enumeration — the two glob expansions plus
the prescan that keeps a FIFO or a broken symlink away from awk — is most of the other half. The
trailing `sort | head | awk` formatter is a rounding error beside either of them.

**The per-phase split that stood here has been withdrawn, and it is not replaced.** This paragraph
used to give a millisecond figure for each of those four phases. An independent re-run of the same
cuts, on the same machine, did not reproduce them: it put the prescan consistently *above* the glob
expansion at every size tried, where the published figures had it comfortably below. The two runs
cannot be reconciled from what was written down, because this section never recorded the parameter
that separates them — the length of the fixture's paths. `scripts/hoard-search.sh`'s own measurement
block states that dependence in as many words for the timings it publishes there: the same 2000
files and the same loop cost 14.67 s under a directory making each path 176 bytes and 24.08 s at 292.
Neither the glob expansion nor the prescan is any less sensitive to it than that loop was. A split a
third party cannot reproduce from the method as published is not a measurement, so this section now
publishes the one ratio two independent runs agree on — awk is about half — and stops there. The same
gap bounds how far the totals above travel, which is why they are stated as one machine's numbers at
three sizes and never as a property of the design.

**Half is not a property of the design either.** Which awk the machine ships decides that share more
than anything in the design does. Swapping the system awk for `mawk` and for `gawk` on the same
fixture moves the pass in both directions, and far enough to cross the halfway line: both runs that
tried it agree that under `mawk` the frontmatter pass is a minority of a search and under `gawk` it is
the majority of one. No millisecond figures are published for those two, for the same reason the
split above is not. (Locale moves it too, in one identified place: the glob expansion is
locale-collated, so `LC_ALL=C` makes it markedly cheaper, and whatever it saves there raises awk's
share of what is left. The totals above are from the ambient `pt_BR.UTF-8`, which is the condition
they were taken in, with the awk macOS ships — version 20200816. An earlier draft of this parenthesis
put the `LC_ALL=C` total at about 112 ms and awk's share at about 85%; those two do not agree with
each other — the 84 ms that draft gave for awk is 75% of its own 112 ms — and an independent re-run
reproduced neither, so both are withdrawn rather than adjusted.) What *is* a
property of the design is that every search reads every file, so both the enumeration and the parse
grow with the number of memories.

The paragraph below is the same kind of correction one level up, and the two are worth reading
together: the first measurement corrected which *component* dominated, this one corrects the split
inside what was left. A number nobody re-ran is not a measurement.

That is a correction, not just a number, and the sequence matters. This section originally attributed
the cost of a search to the no-index scan described above, without having measured either. The first
measurement, 12.47 s at 2000 memories, showed the attribution was wrong; re-measured here, the
pre-fix reader cost 12.08 s at the same size. The time was going into `scripts/hoard-search.sh`
assembling awk's file-list argument one file at a time,
where each append rebuilds the whole list and the assembly therefore costs O(n²); the awk scan it was
feeding was never the expensive half. Assembling each layer's files in a single step took that phase
from 12.05 s to 42 ms and changed no output at any size. `tests/test_hoard.sh` scenario 14 pins the
construction rather than a stopwatch, because the regression is behaviour-preserving — a reverted
copy returns byte-identical results — so no comparison of search output could catch it coming back.

One thing the reader still pays for per file, deliberately. A `*.md` entry that is not a regular file
is not a memory, and awk does not merely skip one: a FIFO blocks it forever, and a broken symlink
makes it exit mid-list, dropping the memory it had parsed but not yet emitted — a complete-looking
answer, quietly missing an entry. So the list is checked once before awk sees it, and rebuilt the
slow way only when that check finds something. The check costs about 19 ms at 2000 memories; the
rebuild costs what the whole reader used to, and runs only for a hoard that already contains
something which is not a memory. Scenario 16 holds all three cases, including the one that used to
hang.

Measured during phase 1; see README.md. The phase-1 subject is `scripts/hoard-search.sh`, not the
brief, because the brief does not exist until phase 2. Three sizes on one machine locate the cost at
those sizes, not the ceiling. If the ceiling is ever reached, an index is a backward-compatible
addition, because the files remain the source of truth either way — and what such an index would
have to beat is the **whole per-search cost**, not the awk pass alone. An index replaces the
enumeration and the prescan as well as the parse, and on the numbers above those two are about 44%
of the run at 2000. Naming the awk pass as the thing to beat, as this section did before the split
was re-measured, would have set the bar at roughly half the real one.

## 6. Lifecycle

### 6.1 Three ways in

1. **The user says so** — `/squirrel:stash`. Writes straight to the hoard, because the decision was
   the user's. With no argument, it stashes what just happened in the conversation, showing the
   title and body it is about to write.
2. **The user corrects the assistant** — a `UserPromptSubmit` hook matches anchored multi-word
   correction idioms and files a **candidate in the inbox**. Never the hoard.
3. **Repetition** — §6.3.

### 6.2 Why the inbox exists

Automatic capture never becomes truth on its own. A wrong lesson written automatically contaminates
every later session in every later project, and by the time it does damage nobody can tell where it
came from. Promotion is always per-item, with the user reading the text.

The correction matcher is calibrated for *precision before recall*, and the reason is structural:
the inbox is human triage, and a matcher that cries wolf destroys the user's willingness to triage
long before it destroys the store. A bare word like `"wrong"` or `"errado"` does not fire, because it matches `"what's wrong
here?"`; only anchored multi-word idioms count (`"não era isso"`, `"refaça isso"`, `"that's not what
I meant"`, `"redo that"`). A matched phrase appearing **inside quotes** — a reference to UI text
rather than an assertion by the user — does not fire either. Each candidate records the pattern that
matched it and the exact text span, so triage never has to guess why something was captured.

### 6.3 Repetition — the mechanism the request is actually about

When a new candidate's title tokens overlap an existing candidate's by ≥ 0.6 (Jaccard over
lowercased tokens with stopwords dropped), no second file is created: `seen` is incremented on the
one that exists, and the new text span is appended to its body as further evidence.

At `seen >= 3`, the next session's brief carries exactly one line, as its last line (§7.2) — the
position closest to the conversation, and therefore the most salient one in an injected block:

```
🐿️ This came up 3×: "use Read/Write on the checkpoint, never a heredoc". Stash it?
```

A "yes" promotes it. It never promotes itself — but the user never has to keep the count either.
The 0.6 threshold and the count of 3 are starting points, tunable in one place, and named as design
decisions rather than findings.

### 6.4 Reinforcement

`uses` and `last_used` are updated **only** on explicit consultation — `/squirrel:dig`, or the user
acting on a memory. Automatic injection never counts. Without that rule the brief feeds itself and
the same five memories rise forever: injection raises `uses`, a higher `uses` raises the score, and
a higher score wins the next injection. Reinforcement has to measure the user's behaviour, never the
system's own.

### 6.5 Supersede, never edit

This governs the **fact**, not the bookkeeping. A memory's `title` and body are never rewritten in
place by any path, automatic or otherwise. Its counters — `uses`, `last_used`, `seen`, `status`,
`superseded_by` — are mutated in place by design, and §6.7 covers what happens when two sessions do
that at once.

A fact that changed produces a **new** memory; the old one gets `status: superseded` and
`superseded_by: <new id>`. Superseded memories leave the brief immediately and remain findable via
`dig --all`. The history is preserved, and the brief can never show two versions that contradict
each other.

### 6.6 Forgetting

Nothing in `global/` or `projects/` is ever deleted automatically. Losing a memory loses work that
cannot be reconstructed, and a memory that has lost its relevance already disappears from the brief
by score alone — which is sufficient, and reversible.

Only untriaged **candidates** expire, after 30 days, in the session-start prune that already exists
in `load-profile.sh`. It examines at most 100 candidates per session start, the same cap the
checkpoint prune uses, so a large inbox cannot stall the hook.

### 6.7 Concurrency

The hoard is shared mutable state across concurrent sessions, which is the exact problem
[ADR-0006](../adr/0006-session-isolation-concurrency.md) exists for and the reason checkpoints are
one file per session. Memories cannot take that escape: a memory shared across projects is shared
across the sessions in them by definition.

Three races are reachable, and **all three are accepted as last-write-wins**, because the cost of
losing one is bounded and the cost of a locking protocol in POSIX `sh` is not:

1. **`uses` / `last_used`** — two sessions consulting the same memory, both rewriting the file. A
   lost increment costs one ranking nudge on a score that is already a heuristic. Nothing is lost
   that was not an approximation to begin with.
2. **`seen` on a candidate** — two correction hooks incrementing the same candidate. A lost
   increment delays a promotion offer by one occurrence; the count is not a measurement, and the
   offer is not time-critical.
3. **Two `stash`es in the same second with the same title** — they resolve to the same filename, and
   §4 already states that this collision is the correct outcome: they are the same memory.

What is **not** accepted is a torn file — and phase 1 does not prevent one. Phase 1 has no writer of
its own: every write goes through the harness's `Write` and `Edit` tools, and `skills/dig/SKILL.md`
has the model make a **targeted `Edit`** to bump `uses` and `last_used`, which is by definition not a
whole-file write. Whatever those tools do on an interrupted write is what happens; this phase
neither implements that behaviour nor is in a position to guarantee it.

A writer of squirrel-mode's own — whole-file and atomic, writing to a temporary file in the same
directory and then `mv`-ing it, so that a concurrent reader sees either the old memory or the new one
and never half of either — is the design that would close this, and it is owed by a later phase
rather than shipped by this one. It is the discipline a database would give for free, without the
database; phase 1 simply does not have it yet.

The body of a memory is never mutated by an automatic path (§6.5), so no race can lose text a human
wrote — only counters, and only by one.

## 7. Surface

### 7.1 Three commands, taking the total from 8 to 11

| Command | What it does |
| :-- | :-- |
| `/squirrel:stash` | Writes a memory now. With no argument, stashes what just happened. |
| `/squirrel:dig` | Searches the hoard: ranked titles only, then the body of what the user opens. |
| `/squirrel:hoard` | Hoard status plus inbox triage: promote, reject, or do nothing. |

`dig` is deliberately two-step: ~100 tokens to **discover**, ~300 only for what **matters**. A search that returns bodies would make the memory into the problem it exists to solve.

All three are explicit-invocation only (`disable-model-invocation: true` where the target supports
it), like every other squirrel-mode command.

### 7.2 The brief

The `SessionStart` hook that already injects the profile also injects, in this order:

1. Top-scoring `global` memories — how the user works, what breaks everywhere.
2. Top-scoring memories for the current project, when inside one.
3. At most one pending repetition line (§6.3).

The block is capped **twice**: by the profile's `max_list_items`, and by a character budget of ~1200
(stated as ~300 tokens at the conventional ~4 chars/token approximation — the budget is enforced in
characters, because counting tokens in POSIX sh is not possible and pretending otherwise would be a
false promise). An unbounded memory dump would contradict the working-memory rationale the other 16
rules rest on; the cap is coherence, not economy.

The brief is injected at `SessionStart` only, never on `UserPromptSubmit`. `load-profile.sh` runs on
both, so this distinction is load-bearing: paying the brief's cost on every prompt would be a
per-message tax for a per-session fact.

### 7.3 Base rule 17

```
### 17. Surface a memory before repeating a known mistake

<!-- targets: all -->

When a memory already present in this conversation's context records that the action about to be
taken failed before, or was corrected before, state it in exactly one line and then continue. Never
lecture, never withhold the action to ask a question first, and flag the same memory only once per
conversation.

This rule never triggers a search. It fires only from memories already in context — from the
session-start brief, or from a `/squirrel:dig` the user ran. An assistant that has no memory in
context has nothing to flag.
```

Example output: `🐿️ You already recorded: a heredoc on the checkpoint asks for permission. Using
Write.`

The "already in context" constraint is what makes this cheap and honest: it costs zero extra tokens,
it cannot invent a memory it never saw, and it is not a gate. That is also the argument for why it
is not the nudge the README rules out — it is the shape of rule 15, not the shape of a timer.

### 7.4 Ordering of trailing lines

Rule 15 currently promises the scope-guard flag is always the final line. Rule 17 produces a
trailing line too, so the order must be stated or that promise stops being true:

```
Extra (rule 7) → checkpoint failure report (rule 14) → memory flag (17) → scope guard (15)
```

The scope guard remains last. Rule 15 needs a one-sentence amendment naming rule 17 among the
trailing content it follows, in the same form it already uses for rule 7 and rule 14.

### 7.5 The twelfth profile field

```
| memory | on | on, off |
```

`off` disables the automatic layer entirely: no brief, no correction capture, no rule 17. Explicitly
typed commands still work — `/squirrel:dig` is the user asking, and an off switch on the automatic
layer never disables an explicit request. Same posture as `/squirrel:off`.

**Two switches, and they are not the same one.** `memory: off` is durable and machine-wide: the
automatic layer stays off until `/squirrel:tune` turns it back on. `/squirrel:off` is
session-scoped, and it suppresses the memory layer along with the base rules — the brief rides
`load-profile.sh` and rule 17 rides the output style, so both go quiet for exactly as long as the
rules do, and `/squirrel:on` brings both back. Neither switch touches an explicitly typed command.

It does **not** become an eighth interview question. `CONTEXT.md` states the calibration is always
exactly seven questions and assembles 11 fields; the seven survives, the 11 becomes 12, and
`CONTEXT.md` is amended to say so. `/squirrel:tune` is how it changes.

Touchpoints: `rules/base-rules.md` Defaults table, `skills/init/SKILL.md`, `skills/tune/SKILL.md`,
`profile.example.md`, and every generated target artifact via `scripts/build.sh`.

## 8. Cross-target parity

**This table is the feature's end state, not what phase 1 ships.** Phase 1 ships `stash` and `dig`
on **Claude Code only**: no Codex skill and no Cursor skill for either command is built, and the
README's parity table says so. The table below is what the four phases together are aiming at.

Pull is cross-tool; push is Claude Code only — the same posture squirrel-mode already has for
checkpoints, and forced by the same fact: Claude Code is the only target with lifecycle hooks.

| Target | Brief | Repetition capture | `stash` / `dig` |
| :-- | :-- | :-- | :-- |
| Claude Code | yes (hook) | yes (hook) | yes |
| Codex | no | no | yes, manual skills |
| Cursor | no | no | `dig`, manual skill |

The hoard is plain markdown under `~/.squirrel/`, so all three targets read the same content. What
Codex and Cursor lose is the automation, never the data — exactly what already happens with the
profile. The parity table in the README gains a column rather than a footnote.

**Porting either command is a rewrite of some of its sentences, not a copy.** Both name the `Write`
and `Read` tools explicitly, and they do that because those two are what Claude Code's
`PreToolUse` auto-approval covers — naming them is how a hoard write or a memory read avoids a
permission prompt. A Codex variant **cannot reuse that wording**: Codex has neither those tool names
nor any auto-approval to earn by using them, so every sentence resting on that mechanism has to be
rewritten for what Codex actually does. `dig`'s four forgery rules rest on the same footing and need
the same treatment: they are about lines a Claude Code `SessionStart` hook injects, and Codex has no
lifecycle hook to inject them. Recorded here rather than in the skills themselves because it is
whoever ports them who needs it, and `docs/OTHER-TOOLS.md`'s port table says the same thing where a
porter will look first.

## 9. Security

1. **Secret filter, enforced at the hook.** The agent writes memories with the `Write` tool, so an
   instruction inside a skill is not enforcement. The `PreToolUse` hook that already parses the tool
   input with `jq` refuses **auto-approval** for a hoard write whose body matches secret patterns.
   Refusing is not blocking: it falls back to the normal permission prompt and the user decides.
   Fail-closed on automatic approval, fail-open on the work.
2. **Symlinks.** A symlink at `hoard/` or anywhere below it is never auto-approved, identical to the
   guard `checkpoints/` already has.
3. **Persistent poisoning — the new risk, stated plainly.** A memory returns to context in *every*
   future session, in every project. A hostile repository that could get the assistant to write a
   memory would gain cross-project persistence. That is the reason automatic capture reaches only
   the inbox and promotion is always per-item with the user reading the text. It is a mitigation,
   not an elimination, and the README says so.
4. **Unchanged:** no network, no telemetry, nothing written inside a project repository.

### 9.1 How the injected context is delivered

`/squirrel:dig` and `/squirrel:pickup` both decide which lines in their context are squirrel-mode's
by where those lines sit. That reasoning depends on facts that live in `hooks/hooks.json` and in one
function of `scripts/load-profile.sh` and nowhere else, and this plan has already shipped a rule
whose premise `hooks.json` had falsified. The facts, stated here so the next reader has them:

- **`SessionStart` is registered for `startup|resume|clear|compact`**, and the hook branches on
  `hook_event_name`, never on which of those four sources fired — so
  **all four emit a full context block**.
  A single conversation therefore carries several genuine blocks, and a later one is not
  suspect for being later. A rule reading "the block, once, at the top of the conversation" would
  reject a genuine line whenever a session is cleared or compacted.
- **A separate channel re-shows the profile body alone.** When `profile.md` has changed since this
  session last saw it, the `UserPromptSubmit` path re-emits the same framing sentence and the same
  body, and **none** of squirrel-mode's own session lines after it — no off-token line, no checkpoint
  lines, no search-command line, no resume banner.
- **That difference is the discriminator both commands rely on**: squirrel-mode's own
  **session lines appended after the quoted profile**, or not.
  Text with none of them is profile text end to
  end, however perfectly a line inside it satisfies a position rule read against that text alone.

### 9.2 Two independent layers, and the forgery bound as measured

The quoted profile sits above squirrel-mode's own lines in the same context, and `/squirrel:tune`
writes `profile.md` from user-dictated text, so a body COULD otherwise spell a line exactly like one
of squirrel-mode's — and acting on the search-command line runs a command. Two layers stand between
that and a command running, and they are independent:

- **At the hook.** `neutralise_forged_lines` in `scripts/load-profile.sh` marks any body line
  beginning with one of squirrel-mode's own injected prefixes, so it no longer reaches the model
  beginning that way. Nothing is deleted; the user's text stays theirs and stays readable.
- **At the reader.** The rules in `skills/dig/SKILL.md` and `skills/pickup/SKILL.md` are exactly as
  strict as they were before that function existed.

**Either alone is sufficient, and neither is allowed to justify weakening the other.** The hook step
fails open by design, and on that path the reading rules are the whole defence; a model can misapply
a reading rule, and the hook step is what holds when it does. [ADR-0008](../adr/0008-hoard-auto-allow.md)
and [ADR-0002](../adr/0002-checkpoint-auto-allow.md)'s task-7b amendment record the same statement.

**The bound on a successful forgery, measured rather than assumed.** Single-quoting every value on
`dig`'s command line limits a forged search-command line to running one file that already exists, at
an absolute path of the forger's choosing ending in `/scripts/hoard-search.sh`, with no arguments and
no shell syntax anywhere. That file **needs only to exist at a predictable absolute path** — an
unpacked archive or a downloaded artifact puts one there with nothing ever executing to place it —
and a script sitting at such a path can print result rows indistinguishable from real ones. What
quoting removes is the ability to build an arbitrary command; it does not remove the risk of running
the wrong file. An earlier draft put the bound higher than that, and running it proved otherwise.

## 10. Promises that must be amended

Each of these is a public statement that stops being true. Each gets an explicit amendment, not a
silent contradiction — this repository's culture is that its documentation matches its behaviour.

1. **`CONTEXT.md`: "changes response *shape*, never response *content*."** Injected memory is
   content. New ADR-0007 draws the replacement boundary: the hoard returns only what the user chose
   to record, never the model's own opinion, and the assistant's advice on a subject is unchanged by
   its presence.
2. **`README`: "exactly four kinds of file"** in `~/.squirrel/` → five, with `hoard/` described in
   the same detail as the other four.
3. **`README`: "No nudges or timers — deliberately out of scope."** Narrowed, with rule 17's
   "already in context" constraint as the boundary, and the timer/monitoring half left intact.
4. **`ADR-0002` (checkpoint auto-approval)** → new ADR-0008 extends auto-approval to `hoard/`, adds
   the secret-pattern refusal, and inherits the symlink guard and the `jq` dependency verbatim.
5. **`README` pruning section:** memories are never pruned; only candidates expire, at 30 days.
6. **Base rule 15's "always the final line"** → amended per §7.4.
7. **`CONTEXT.md`: 11 profile fields** → 12, seven interview questions unchanged.

## 11. What the tests must prove

A new `tests/test_hoard.sh`, in the style of the ten suites that already exist, plus additions to
`tests/test_manifests.sh` and `tests/test_targets.sh` for the new command surface.

1. **No write path lands inside a repository**, under any cwd, including when `~/.squirrel` is a
   symlink and when the project slug collides.
2. **The brief respects both caps** — `max_list_items` and the character budget — and injects at
   `SessionStart` only, never on `UserPromptSubmit`.
3. **A repeated candidate increments `seen`** instead of creating a second file, and the promotion
   line appears at exactly 3, once.
4. **A supersede removes the old memory from the brief** and keeps it findable via `dig --all`.
5. **A secret in the body defeats auto-approval** (falls back to the prompt, does not silently
   write), **a memory is never pruned**, and **a candidate expires at 30 days**.

Concurrency (§6.7) gives phase 1 nothing to test. Phase 1 writes through the harness's tools and
promises nothing about a torn file, so there is no property of its own to assert; a test would be
asserting the harness's behaviour rather than this repository's. The torn-file test — a write
interrupted mid-way leaving either the old memory or the new one and never half of either — is owed
together with the temp-then-`mv` writer that would earn it. The three lost-update races are **not**
tested in any phase, because they are accepted rather than prevented — the spec states that, and a
test asserting a bounded loss would only encode the acceptance twice.

Each guard must be proven by mutation against the current text — a test that cannot fail for its own
target is not a test. `docs/ACCEPTANCE.md` gains a live-sweep entry for the brief actually appearing
in a fresh session, because a green suite that never ran the product proves nothing about it.

## 12. Sequencing

Phases are separable and each leaves the repository releasable:

1. **Storage and `stash`/`dig`** — the files, the awk ranking, two commands. ADR-0008's auto-approval
   lands here too, because without it every `stash` stops to ask for permission *on the write itself*
   and the command is not usable in practice. What it does not remove is the timestamp. Both commands
   build one by running `date -u +%Y%m%dT%H%M%SZ`, which is a `Bash` call, and `hooks/hooks.json`
   registers the `PreToolUse` hook for `Write|Edit|Read` only — no hook is invoked for a `Bash` call,
   so none can auto-approve one. As shipped, a `/squirrel:stash` therefore costs one permission
   prompt and a `/squirrel:dig` that opens a memory costs two: the search script, which is also a
   `Bash` call, and the stamp the reinforcement edit needs. The auto-approval makes the writes
   silent; it does not make the commands silent, and `README.md` publishes both numbers.
2. **The brief** — `SessionStart` injection, both caps, the `memory` profile field.
3. **Capture and repetition** — the correction matcher, the inbox, `seen`, `/squirrel:hoard`.
4. **Rule 17 and the amendments** — the rule, the trailing-line ordering, ADR-0007, and the README
   and `CONTEXT.md` edits. ADR-0008 is not here; it lands in phase 1 with the writes it governs.

Phase 4's documentation amendments for phases 1–3 land with those phases, not deferred to the end;
only rule 17 itself waits for the brief to exist, since it has nothing to fire from until then.

## 13. Provenance

The mechanisms here are re-derived from prior art in project memory for code agents, none of it
original to this project: atomic typed memories, importance × recency × reinforcement scoring,
supersede-never-edit, a secret filter on write, an inbox with per-item triage, a budgeted
session-start brief, the two-step search/hydrate split, and the rule that automatic injection must
never count as reinforcement.

**No code is copied, from any source.** Every mechanism above is written from scratch in POSIX `sh`
and Markdown, which is the stack this repository promises and not the stack that prior art is
usually built in — project-memory tools reach for SQLite and full-text search, and §5.1 explains why
this one does not.

The design deliberately occupies the opposite quadrant from that prior art. Project memory is
repository-scoped, team-shared and committed to git, and its value is that a colleague benefits from
what you learned. The hoard is personal, cross-project and local, and its value is that *you* benefit
tomorrow from what you learned today. The two do not compete, and both can be installed in the same
repository without overlapping.

Left out on purpose, because they belong to the other quadrant: committed per-author data files, a
pull-request quality gate, per-repository vendoring of the tool, cross-developer sharing, a derived
search index, and reactive injection on file edits.
