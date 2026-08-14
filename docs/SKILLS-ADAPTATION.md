# squirrel-mode skill adaptation plan

> **How to use this file:** This is the product plan for adapting skills from
> [mattpocock/skills](https://github.com/mattpocock/skills) into squirrel-mode. It is not a build
> orchestrator — do not implement from it until a later plan names the build steps. Read
> [CONTEXT.md](../CONTEXT.md) for vocabulary, [PLAN.md](../PLAN.md) §6 for non-goals, and
> [rules/base-rules.md](../rules/base-rules.md) for the 16 rules every new command still obeys.

**What this is.** A map of what we take from Matt Pocock's skills, rewritten for ADHD working
memory, and what we refuse. Every entry is a *shape* for a session. None of them change how the
assistant codes (`keep-coding-instructions: true` still holds).

**Source snapshot.** `mattpocock/skills` @ main, 13 Aug 2026. 35 skills read (engineering,
productivity, in-progress, misc). Deprecated bucket empty.

---

## 1. The line that does not move

These constraints are not negotiable. A skill that cannot be rewritten inside them is out, even
if it is useful for typical engineers.

1. **Shape, never content.** The assistant's advice does not change. The packing of that advice
   does — answer first, numbered steps, one concept per paragraph, cap `max_list_items`, parking
   lot for tangents.
2. **Never coding behaviour.** No TDD mandate, no "run `/implement`", no deep-module refactor
   programme. ADR-0001.
3. **User-scoped.** Writes go to `~/.squirrel/` or to the response. Never to the project
   repository. No `CONTEXT.md`, no ADRs, no `.scratch/` tickets, no `lessons/` HTML in the repo.
4. **No timers, nudges, or background processes.** PLAN.md §6. Tether and
   `ravila4/claude-adhd-skills` cover that niche.
5. **Checkpoints are not a task manager.** A new command that becomes Jira-in-`~/.squirrel/` is a
   failed adaptation.
6. **Profile-shaped.** Every new command reads `language`, `step_style`, `max_list_items`,
   `options_per_answer`, `tone`. Interviews are one question per message, multiple-choice, hard
   cap — the `/squirrel:init` rhythm, never Matt's frontier-in-a-round.
7. **English in the repo.** Skill text is English. The user's response language is a profile
   field.

Matt's own docs already admit the sequential opt-out: people who read slowly, work in a second
language, or use one-question-at-a-time as focus scaffolding prefer it. That audience *is*
squirrel-mode. We do not ship his default and patch it with a `CLAUDE.md` line.

---

## 2. Map at a glance

| Kind | Meaning |
| :-- | :-- |
| **Rewrite** | New `/squirrel:*` command. Same job as Matt's skill, ADHD shape. |
| **Adjust** | Existing squirrel command absorbs a Matt idea. No new name. |
| **Steal** | Mechanism only. Lands in the base rules or inside another command. Not user-facing. |
| **Out** | Useful for typical engineers. Wrong product. |

### Rewrite — lote 1 (communication)

Ship these while squirrel-mode is still "how the assistant talks."

| Source | Command | One-line job |
| :-- | :-- | :-- |
| `wait-what` | `/squirrel:wait` | Last message did not land. Re-pitch it in the profile. |
| `grilling` + `grill-me` | `/squirrel:decide` | One isolated decision. One question at a time. Cap. Parking lot. |
| `handoff` | `/squirrel:handoff` | Portable brief for another target, session, or person. |
| `to-questionnaire` | `/squirrel:ask` | Questionnaire for someone else, in the response, not a file in the repo. |
| `ask-matt` | `/squirrel:help` | One question. Recommends one existing command. Stops. |
| `wayfinder` | `/squirrel:map` | Last, optional. One durable effort. One next decision. Fog in the parking lot. |

### Rewrite — lote 2 (productivity + tech)

Ship these only after lote 1, and only if we deliberately widen the product from *communication*
to *ADHD-shaped work sessions*. Still shape, still not a coding methodology.

| Source | Command | One-line job |
| :-- | :-- | :-- |
| `triage` | `/squirrel:inbox` | The pile, not one ticket. One item that needs you now. |
| `wizard` | `/squirrel:walk` | Human-only procedure. One stage visible. Confirm before irreversible. |
| `teach` | `/squirrel:orient` | Land in a repo or stack. One concept, one file, one win. |
| `writing-shape` | `/squirrel:draft` | Produce a PR / email / doc one block at a time. |
| `diagnosing-bugs` | `/squirrel:stuck` | Debug session shape. No hypothesis until a red loop exists. |
| `to-tickets` | `/squirrel:slice` | After `plan`: one startable atom. Rest parked with blockers. |
| `code-review` | `/squirrel:review` | Diff findings as a digest. One next fix. |
| `research` | `/squirrel:look-up` | One question, primary source, brief. No novel in the repo. |

### Adjust — commands we already ship

| Existing | Absorbs | What changes |
| :-- | :-- | :-- |
| `/squirrel:plan` | grilling primitive, ungrillable stop, short spec export | Clarifying questions use the decide format. Hits an ungrillable → stop, do not invent a fourth question. Optional short spec (Problem / Solution / Out of scope / First slice), never Matt's "extremely extensive" user-story wall. |
| `/squirrel:digest` | AGENT-BRIEF durability (no file paths) | Already the inbound reshape. Do not merge `ask` into it. Optional: behavioural wording in Open questions ("who / what is missing"), never a line number. |
| `/squirrel:pickup` | loop-me brief, complementary to handoff | Pickup stays same-user, same project, checkpoint. Opening stays Recent wins. The *body* of Doing/Next should read as a decision-ready brief, not a transcript dump. |
| `/squirrel:init` | grilling primitive as shared format | Init is already the ADHD interview. The primitive is extracted *from* init, then reused by `decide` and `plan`. Init itself does not grow a new question. |
| Base rules | grounding, one-stage human procedure, phase-boundary question | See §5. |

`tune`, `off`, `on`, `rules` take nothing from Matt.

### Steal — not commands

| Source | What we take | Where it lands |
| :-- | :-- | :-- |
| `writing-beats` | A term is unused until it has been grounded | Base rules (candidate rule, or a clause under rule 4). |
| `writing-for-agents` | Pointers, completion criteria, leading words, prompt the positive | How *we* write skills. Not a user command. |
| `loop-me` | Checkpoint presents a brief, not raw output. Push the human question as late as possible, once. | `pickup` + `decide`. Never the scheduler. |
| `grill-me` / `prototype` | Ungrillable: stop interviewing, name that it needs something concrete | `plan` and `decide`. Do not generate throwaway HTML. |
| `to-spec` | Short durable template, no file paths | Optional export from `plan`. |
| `ask-matt` phase boundaries | When the window is full: continue / handoff / stop. One question. | Base rules or a line in `pickup`. Not five options. |
| `triage` AGENT-BRIEF | Behavioural, no paths, explicit out of scope | Format inside `slice`. |
| `resolving-merge-conflicts` | One hunk, recommended resolution, confirm | A mode of `walk`, not its own command. |

---

## 3. Lote 1 — rewrite as commands

Shared implementation notes for every command in this section:

- Skill body in English. Output in the profile `language`.
- `disable-model-invocation: true` unless a row says otherwise.
- Respect `max_list_items`, `step_style`, `options_per_answer`, `tone`.
- Parking lot is mandatory when tangents appear.
- Claude Code first. Pure-prose commands (`wait`, `decide`, `ask`, `help`) port to Codex and
  Cursor the same way `digest` / `plan` do. Commands that write `~/.squirrel/` follow init/tune
  parity (Codex yes, Cursor not until writing that path is proven).

---

### `/squirrel:wait`

| | |
| :-- | :-- |
| Source | `wait-what` |
| Kind | rewrite |
| Writes | nothing |
| Targets | all three |

**Why.** The base rules try to stop a message from failing. They still fail mid-conversation:
jargon pile-up, a premise the user never saw, five acronyms. Matt's leading word is the whole
skill: **wait** names the *listener*, not the output. "Be concise" produces a telegram that loses
the user further. `digest` reshapes inbound prose the user received. `wait` reshapes the
assistant's own last output.

**How we adapt.**

1. User-invoked only. The model must not decide the user is lost.
2. Re-pitch *that* — the agent chooses how far back to go, usually more than one paragraph.
3. Obey the profile: answer first, `max_list_items`, `explanation_budget`, `language`, one
   concept per paragraph. Recap `Done: … Now: …` if `progress_recap: yes`.
4. Add the missing premise. Do not only delete words.
5. Do not invoke ASD-STE100. Do not assume a project `CONTEXT.md`.
6. A second `/squirrel:wait` in a row must not degrade into terseness.

**Does not replace.** Base rules, `digest`, `plan`.

**Example.**

The assistant has just explained a cache invalidation bug in 400 words, three layer names, no
action. The user types `/squirrel:wait`.

```
The bug is two requests both seeing a cache miss and both writing.

Done: identified the race. Now: lock the write.

1. Add a mutex around the cache fill in the user-profile loader. (~10 min)
2. Add a test with two concurrent misses. (~15 min)

Extra: the stale TTL on the edge cache is a separate bug. Park it?
```

---

### `/squirrel:decide`

| | |
| :-- | :-- |
| Source | `grilling` + `grill-me` (grill-me is a one-line wrapper; we do not ship the wrapper) |
| Kind | rewrite |
| Writes | nothing |
| Targets | all three |

**Why.** Matt's mechanism is gold: a design tree, facts are the agent's job, decisions are the
user's, do not act until shared understanding is confirmed. Matt's *format* is hostile: the whole
frontier in one round, no cap, 46 questions as an "ordinary" session. squirrel-mode already
proved the ADHD interview: `/squirrel:init` is 7 questions, one per message, A/B/C/D.
`/squirrel:plan` already clarifies at most 3 times. `decide` covers the gap between those two — a
fork that is not an idea dump (`plan`) and not a profile field (`init`).

**How we adapt.**

1. Extract a **grilling primitive** used by `init` (already matches), `plan` (adjust), and
   `decide`. The primitive is not user-invoked.
2. One question per message. 2–4 lettered options plus "type your own". One recommended option.
   Progress `Question N of C`.
3. Hard cap, a design choice not a finding: **5** for `decide` (init stays 7, plan stays 3).
   Unvisited branches go to the parking lot. The tree is not exhausted.
4. Facts: the agent looks them up. Decisions: wait. Never answer its own decisions.
5. Stop and ask one confirm ("Shared understanding? y/n") before acting.
6. If a question is ungrillable (how should this feel / look), stop. One line: this needs
   something concrete, not another question. Offer to park. Do not start `/prototype`.

**Does not replace.** `plan` (messy dump → scoped plan). `init` (profile only).

**Example.**

User: `/squirrel:decide` keep the Codex installer as a shell script or rewrite it in Go?

```
Question 1 of 5

What is this decision actually for?

A. Ship a fix this week — smallest change that works
B. Make the installer something we can test in CI the same way as the rest
C. I don't know yet — help me pick

Recommended: A. The installer already has a lock-and-rename idiom in POSIX sh; a language
rewrite is a different project.

or type your own answer
```

After at most five answers, one recommended path, parking lot for "rewrite in Go later".

---

### `/squirrel:handoff`

| | |
| :-- | :-- |
| Source | `handoff` |
| Kind | rewrite |
| Writes | `~/.squirrel/handoffs/<slug>.md` |
| Targets | Claude Code and Codex. Cursor unported until a skill there can write that path (same bar as `init`). |

**Why.** `/squirrel:pickup` resumes *this* user, *this* project, *this* checkpoint. It cannot
travel: Claude → Cursor, a colleague, a side task forked mid-phase. Matt writes to `/tmp`, which
vanishes (Codex, reboot). squirrel-mode already has the durable user-scoped directory.

**How we adapt.**

1. Write under `~/.squirrel/handoffs/`, never the project, never temp.
2. Shape of pickup, plus parking lot: Recent wins, You were doing, Next action, Open decisions,
   Parking lot. Suggested next `/squirrel:*` command, one only.
3. Do not copy specs, diffs, or ADRs. Point at paths and URLs.
4. Redact secrets.
5. `$ARGUMENTS` = what the next session is for. Tailor the brief to that, or the *why* dies
   (Matt's own known failure).
6. One file per invocation. Not a second automatic checkpoint. Rule 14 stays Claude-only and
   checkpoint-only.
7. Report the path in one line. Stop. No "shall I open it."

**Does not replace.** `pickup`, checkpoints, `/compact`.

**Example.**

User, in Claude Code, mid-fix on the off-switch: `/squirrel:handoff` continue this in Cursor.

The file at `~/.squirrel/handoffs/off-switch.md` contains:

```
## Recent wins
- Token-bound PENDING/CLEAR sentinels land per session (ADR-0006)

## You were doing
Fix the remaining same-second profile-seen skip on UserPromptSubmit

## Next action
Read scripts/load-profile.sh around the find -newer test and add a not-newer-or-equal probe. (~15 min)

## Open decisions
- Whether equal-mtime should count as "already seen"

## Parking lot
- Codex reinjection (no hook — out of this session)

## Suggested command
/squirrel:stuck if the probe is red and the cause is not obvious
```

The user pastes the path into Cursor and continues.

---

### `/squirrel:ask`

| | |
| :-- | :-- |
| Source | `to-questionnaire` |
| Kind | rewrite |
| Writes | nothing (response only). Optional `--for-paste` still in the response. |
| Targets | all three |

**Why.** ADHD often cannot start the message to the one person who holds the missing fact. Matt
grills the *send* (who, what you need back) — that is the correct interview, two questions, not
the subject. He then writes `to-questionnaire-<slug>.md` in cwd, which squirrel-mode forbids.

**How we adapt.**

1. Two questions, one at a time, multiple-choice where possible: who is it for; what must you
   walk away able to decide.
2. Output in the response: Purpose, From / To, How to answer (deadline + concrete effort),
   questions most-important-first, one idea each, "I don't know" is a valid stub, catch-all at
   the end.
3. Cap questions at `max_list_items`. Extra questions in a parked "If there is time" list.
4. Never write a file in the project. `--for-paste` is a copy-ready block in the same response.
5. Do not merge into `digest --for-reply`. That is the *outbound reply to whoever asked for
   work*. `ask` is the inverse: extract what only someone else has.

**Does not replace.** `digest`, `digest --for-reply`.

**Example.**

User: `/squirrel:ask` I need to know from Ana whether we can drop API v1 in September.

```
Question 1 of 2

Who is Ana to this decision?

A. Owns the API, can say yes/no
B. Uses the API, can report breakage
C. Adjacent — she will know who owns it
```

Then the questionnaire, ready to paste:

```
# Can we drop API v1 in September?

Purpose: decide whether the September release deletes the v1 routes.
From: Thiago — To: Ana — How answers will be used: one go/no-go in the release plan.

## How to answer
~10 min. "I don't know" is useful. Flag guesses.

## Decision
### Are any production clients still on v1?
_Why this matters: if yes, September is a migration, not a deletion._

>
```

---

### `/squirrel:help`

| | |
| :-- | :-- |
| Source | `ask-matt` |
| Kind | rewrite |
| Writes | nothing |
| Targets | all three |

**Why.** Matt's router maps a whole engineering pipeline (grill → spec → tickets → tdd). We have
eight commands today and will have more; ADHD forgets they exist. A router that teaches Matt's
pipeline would be a product change. A router that names *one* squirrel command is cheap and on
strategy.

**How we adapt.**

1. One multiple-choice question: what are you trying to do. Options map onto shipped commands
   only — never onto a Matt flow we refused.
2. Recommend exactly one command (`options_per_answer` does not apply to this question; the
   command *is* the one option). One line why. Stop.
3. If nothing fits, say so in one line and point at `digest` or `plan` as the default reshape.
4. Keep the skill's own description tight so it never hijacks ordinary questions. User-invoked
   only.
5. Update this command whenever a command is added, renamed, or removed — a router that lies is
   worse than none (Matt's rule for `ask-matt`, kept).

**Does not replace.** README command table. It is the in-session "I forgot the name."

**Example.**

User: `/squirrel:help`

```
What are you trying to do?

A. A message, ticket, or email I received is a wall of text
B. I have a messy idea and need a first action
C. I got lost in this conversation — re-pitch the last answer
D. I am coming back after an interruption

Recommended: if A → /squirrel:digest. If you meant C, that is /squirrel:wait.
```

(The real skill lists every shipped command, grouped, still one question.)

---

### `/squirrel:map`

| | |
| :-- | :-- |
| Source | `wayfinder` |
| Kind | rewrite — **lote 1 last, or lote 2.** Do not build before `wait`, `decide`, and `handoff` exist and still hurt. Prefer extending `plan` + checkpoint first. |
| Writes | `~/.squirrel/maps/<slug>.md` |
| Targets | Claude Code first |

**Why.** The concept is the most ADHD-native in Matt's repo: work too big for one session, fog of
war, **one resolution per session**, destination named, out of scope as a decision. His
implementation is the opposite: issue tracker, 100k-token tickets, batch grilling, "the most
cognitively demanding flow." PLAN.md says checkpoints are not a task manager. `map` sits on that
line.

**How we adapt.**

1. One file per effort in `~/.squirrel/maps/`. Sections: Destination (1–2 lines), Next decision
   (exactly one), Fog (parking lot), Out of scope, Decisions so far (one line each).
2. Never an issue tracker. Never more than one decision visible.
3. `/squirrel:pickup` may offer a map in one line when one exists for this project ("Resume
   available — run /squirrel:pickup or open the map"). It does not dump the map.
4. Charting a map is one session. Working it is later sessions, one decision each.
5. If the way is already clear in one session, do not create a map. Say so and offer `plan`.

**Does not replace.** `plan`, checkpoints. If `plan` + checkpoint + `handoff` already cover
multi-session work, **do not ship `map`.**

**Example.**

User: `/squirrel:map` we need Codex and Cursor to get pickup somehow.

```
## Destination
A way to resume work on Codex and Cursor that does not recompute the checkpoint slug.

## Next decision
Is the answer "handoff files the human pastes" or "a Codex-readable pointer in AGENTS.md"? Pick
one this session.

A. Handoff files only — Cursor/Codex have no hooks; do not fake them
B. Best-effort AGENTS.md "read this path" plus handoff
C. Park the whole effort — Claude Code pickup is enough for v0.x

Recommended: A. Recomputing the slug is the failure ADR-0003 already recorded.

## Fog
- Whether Cursor Agent Skills can write ~/.squirrel/ at all
- Session identity on Codex

## Out of scope
- Building lifecycle hooks that Codex/Cursor do not have
```

---

## 4. Lote 2 — productivity and tech

Widen the product only on purpose. These commands structure *sessions of work* the user is
already in. They still do not tell the assistant how to write tests or modules.

Do not start lote 2 until lote 1's `wait` and `decide` have been used for real. Sequence inside
lote 2: `inbox` and `stuck` first (pile and rabbit hole), then `slice` and `review`. `walk`,
`orient`, `draft`, `look-up` are the productivity band.

---

### `/squirrel:inbox`

| | |
| :-- | :-- |
| Source | `triage` |
| Kind | rewrite |
| Writes | nothing, unless the user confirms a tracker write |

**Why.** `digest` restructures one item. ADHD failure is the *pile*: forty issues, none of them
"what needs me now." Matt's three buckets (oldest first) are the right view. His state machine of
labels and auto-posted agent briefs is a tracker product.

**How we adapt.**

1. Three buckets in digest Priority shape: NOW (needs you), NEEDS YOU TO ANSWER (blocked on a
   person), CAN WAIT.
2. Expand only NOW. Cap at `max_list_items`. Everything else is named, not opened.
3. One next item, startable in under 10 minutes. Stop.
4. Do not transition labels unprompted. Do not post comments unprompted.
5. If a tracker MCP is missing, say so in one line and ask for a paste of the list.

**Does not replace.** `digest` (one item). `plan` (idea dump).

**Example.**

User: `/squirrel:inbox`

```
NOW
1. PROJ-882 — missing acceptance criteria on the off-switch bug. Next: ask Ana one question
   (use /squirrel:ask). (~5 min)

NEEDS YOU TO ANSWER
- PROJ-901 — reporter asked whether v1 can go. Parked until 882 moves.

CAN WAIT
- 11 other open issues. Not listed. Say "expand can wait" if you want the names.
```

---

### `/squirrel:walk`

| | |
| :-- | :-- |
| Source | `wizard` (lote 1 steal, lote 2 command). Absorbs `resolving-merge-conflicts` as a hunk mode. |
| Kind | rewrite |
| Writes | nothing |

**Why.** Human-only procedures explode working memory: ten steps, three URLs, an irreversible
action in the middle. Matt's wizard clears the screen each stage — that is the mechanism. His
skill then generates bash and writes `.env`, which is coding/setup behaviour.

**How we adapt.**

1. One stage visible. `Stage N of T`. What to open, what to copy, what this stage produces.
2. Confirm before irreversible. Rule 13 still wins: safety warnings are never compressed.
3. Next stage only after the user replies.
4. If the agent can do the step itself, it does — `walk` is HITL only.
5. Merge-conflict mode: one hunk, recommended resolution by intent, confirm, next hunk. Never
   `--abort` unless the user asks.
6. No generated script. No `.env` writes by this command.

**Does not replace.** Ordinary numbered steps in the base rules. `walk` is for procedures only a
human can perform.

**Example.**

User: `/squirrel:walk` I need to add the GitHub marketplace listing screenshot.

```
Stage 1 of 3 — open the listing

Open: https://github.com/marketplace (your publisher account)

Copy nothing yet. Click the squirrel listing → Edit.

Reply "done" for stage 2 (upload the 1220×640 image from docs/).
```

---

### `/squirrel:orient`

| | |
| :-- | :-- |
| Source | `teach` |
| Kind | rewrite |
| Writes | optional notes under `~/.squirrel/orient/<slug>.md`, never `./lessons/` in the project |

**Why.** `teach` is explicit about working memory: short lesson, one win, zone of proximal
development. It then becomes an HTML course product (quizzes, communities, `MISSION.md` in cwd).
The ADHD job in *this* product is landing in an unfamiliar repo or stack without drowning.
`explanation_budget` already covers a passing explanation. `orient` is the standing session.

**How we adapt.**

1. One question first: what do you need to *do* in this repo this week. That is the mission.
   Without it, lessons drift abstract (Matt's own failure mode).
2. One concept, grounded before it is used. One file to open. One tangible win. Recap
   Done/Now.
3. Parking lot for rabbit holes. Scope guard still fires.
4. No HTML, no quiz widgets, no spaced-repetition schedule.
5. State, if any, in `~/.squirrel/`. The folder is continuity, not the conversation — same
   idea as teach's workspace, without giving the project over to a course.

**Does not replace.** Asking "what does this function do" in an ordinary turn. `wait` when a
single explanation failed.

**Example.**

User: `/squirrel:orient` I need to change the Cursor installer this week.

```
Done: nothing yet. Now: the Cursor install path.

The Cursor target copies three things onto the machine: a .mdc rule, two Agent Skills, and
optional project commands. The installer is targets/cursor/install.sh. It is dry-run by
default.

Open: targets/cursor/install.sh — the header comment lists every destination path.

Win for this session: tell me which of those three you are changing. Then we open that file
only.
```

---

### `/squirrel:draft`

| | |
| :-- | :-- |
| Source | `writing-shape` (grounding also stolen from `writing-beats` into the base rules) |
| Kind | rewrite |
| Writes | nothing, unless the user names a path *outside* the project or asks for a paste |

**Why.** `digest --for-reply` reshapes existing prose. The hole is *starting* a PR description,
a long email, a short RFC. `writing-shape` is one block, ground concepts, confirm, next.
`writing-fragments` is more divergence — ADHD already has that; we do not ship it.

**How we adapt.**

1. One question: destination (PR / email / doc) and who reads it.
2. Ground what the reader already knows. Then write **one** block. Stop.
3. Offer at most `options_per_answer` next-block directions (default: recommend one).
4. Parking lot for sentences that do not belong yet.
5. User says when it is done. No article workspace.

**Does not replace.** `digest --for-reply`, `ask`.

**Example.**

User: `/squirrel:draft` PR description for the checkpoint prune fix.

```
Block 1 — what changed, for the reviewer who already knows ADR-0002.

Prune now refuses to follow a symlink at checkpoints/<slug>/, matching
allow-checkpoint's existing deferral. Adds a test that a symlink-as-slug cannot
delete files outside ~/.squirrel.

Next block (recommended): Test plan, three checkboxes. Parked: the no-jq sed note
(separate PR).
```

---

### `/squirrel:stuck`

| | |
| :-- | :-- |
| Source | `diagnosing-bugs` |
| Kind | rewrite |
| Writes | nothing |
| Invocation | user-invoked. Tight trigger if we ever allow model invocation: only when the user says they are stuck on a *reproducing* bug, never on "this looks wrong" architecture talk. |

**Why.** Liebel et al.: starting/finishing and context-switching are the reported ADHD
engineering challenges. Debug is where both hit. Matt's gate is the steal: **no hypothesis until
a loop exists that goes red on this bug.** His dump is the refuse: ten ways to build the loop,
3–5 hypotheses to rank, six phases on screen. We keep the gate. We show one phase.

**How we adapt.**

1. Phase 1 only, until one command has been *run* and gone red on the user's exact symptom.
   Do not list ten methods. Pick one, try it, if it fails try the next.
2. Then minimise, still one visible phase.
3. Hypotheses: recommend one (`options_per_answer`). The rest go to the parking lot, ranked,
   not presented as a menu unless the profile asks for more than one option.
4. One variable at a time. Scope guard if the session turns into a refactor.
5. Do not mandate a regression test as TDD religion. If a correct seam exists, say so in the
   Extra section. If it does not, that is a finding, not a cue to run Matt's architecture
   skill.
6. Content of the diagnosis is still the model's. This command only shapes the conversation.

**Does not replace.** Ordinary debugging in a normal turn. Base-rule numbered steps.

**Example.**

User: `/squirrel:stuck` pickup shows the wrong session's Done log.

```
Done: nothing. Now: a red loop for this symptom.

I will run one command that should print this session's checkpoint path and the
other session's path, and fail if they match.

Proposed: Read the two files under ~/.squirrel/checkpoints/<slug>/ and diff the
`updated:` lines.

Reply "run it" or name a different loop. No hypotheses until that output is red.
```

---

### `/squirrel:slice`

| | |
| :-- | :-- |
| Source | `to-tickets` + AGENT-BRIEF format from `triage` |
| Kind | rewrite |
| Writes | nothing by default. Tracker create only after preview + one confirm, same as `plan`'s Jira offer. |

**Why.** `plan` already chunks Phase 1 to ≤45 min. The hole is publishing twelve tickets at once
(decision load) or one ticket the size of the feature (cannot start). Matt's vertical slice +
blocking edges are the right *size*. His batch publish is the wrong *move*.

**How we adapt.**

1. Input: the current `plan` output, or the conversation. Not a blank slate — if there is no
   plan, offer `/squirrel:plan` in one line.
2. Emit **one** frontier ticket: what it delivers (user-visible), blocked by, testable
   acceptance criteria, estimate ≤45 min. AGENT-BRIEF rules: behavioural, no file paths, explicit
   out of scope.
3. Remaining slices named in the parking lot with their blocking edges, not opened.
4. Preview. One y/n. Create one. Never twelve.
5. Do not close or edit a parent issue.

**Does not replace.** `plan`. `inbox` (incoming pile vs outgoing slice).

**Example.**

User, after a plan: `/squirrel:slice`

```
## Slice 1 of the frontier (can start now)

What to build: prune refuses symlink-as-slug the same way allow-checkpoint already defers.
Blocked by: none.
Estimate: ~25 min.

Acceptance
- [ ] A symlink at checkpoints/<slug>/ does not delete files outside ~/.squirrel
- [ ] allow-checkpoint still defers that write (existing behaviour)

Out of scope
- The no-jq sed parser (separate slice, parked)

Create this issue? y/n
```

---

### `/squirrel:review`

| | |
| :-- | :-- |
| Source | `code-review` |
| Kind | rewrite |
| Writes | nothing |

**Why.** A review dump is a wall: twenty nits mixed with three blockers plus a smell catalogue.
Matt's split (Standards vs Spec) is worth keeping as *axes*, not as two parallel subagent
novels. squirrel-mode already has a digest shape for inbound judgement.

**How we adapt.**

1. Pin the fixed point (the user names a commit/branch, or we ask once). Empty diff fails here.
2. Output as digest: TL;DR, NOW (merge blockers), NEXT (the single fix to do now), CAN WAIT
   (nits), Open questions.
3. If the diff is large, one axis per invocation — Spec first (did we build what was asked).
   Standards only if the user asks or NOW is empty.
4. Cap each list at `max_list_items`. Extra nits parked.
5. Repo-documented standards win. Do not dump Fowler. Do not invent a smell the repo does not
   care about.
6. Do not commit. Do not run TDD. This is the report.

**Does not replace.** Human review. `stuck` (debug vs review).

**Example.**

User: `/squirrel:review` since main

```
## TL;DR
The symlink prune fix matches ADR-0002. One missing test on the equal-mtime profile-seen skip.

## NEXT
Add the equal-mtime probe in tests/test_hooks.sh. (~10 min)

## CAN WAIT
- Comment in load-profile.sh restates ADR-0005; not wrong, not needed.

## Open questions
- None. No spec issue found.
```

---

### `/squirrel:look-up`

| | |
| :-- | :-- |
| Source | `research` |
| Kind | rewrite |
| Writes | nothing by default. A file only if the user names `~/.squirrel/` or an explicit path. Never a surprise file in the repo. |

**Why.** Reading docs is the classic rabbit hole. Matt is right about primary sources and
citations — squirrel-mode's own RESEARCH.md citation policy is the same discipline. He then
writes a long markdown via a background agent into the repo. The user-facing version is a digest
of *one* question.

**How we adapt.**

1. One question. Primary source (docs, spec, paper, first-party API), not a blog about it.
2. Digest: TL;DR of what the source *says*; what it does *not* say; one next source.
3. Unread tabs go to the parking lot.
4. No background agent. No citation that fails RESEARCH.md's four checks if we are claiming a
   finding — for API/docs look-ups, quote the page and link it.
5. This is not the plugin's internal research log. That stays `docs/RESEARCH.md`.

**Does not replace.** `digest` (prose the user already has). `stuck` (runtime evidence).

**Example.**

User: `/squirrel:look-up` does Claude Code PreToolUse `if` expand `~` in plugin hooks?

```
## TL;DR
We do not know from a primary source in this repo. ADR-0002 already recorded that `if` expanding
~ / $HOME at plugin-build time is unverified, which is why allow-checkpoint.sh gates on the
resolved path instead.

## What the source does not say
No Claude Code docs page cited in ADR-0002 states the expansion rules.

## Next source
The current Claude Code hooks reference. One page. Parked: asking in a Discord.

I can fetch that page if you want. y/n
```

---

## 5. Steal — land in the base rules or inside a command

These do not get a `/squirrel:*` name. If a steal grows a name, it has been rewritten in §3 or
§4 instead.

### Grounding (`writing-beats`)

**Why.** A message that uses a term the user has not met is the failure `/squirrel:wait`
repairs after the fact. Rule 4 (one concept per paragraph) almost says this and does not.

**How.** Candidate clause on rule 4, or a new design-decision rule with no research claim:
do not use a project-specific term until this response has grounded it in one short clause.
Does not apply to terms in the profile or in CONTEXT.md for *this* repo when the user is
working in squirrel-mode itself.

**Example.** Instead of "the materialization cascade failed", write "the step that writes a
lesson file onto disk (we call that materialization) failed."

### Writing for agents (`writing-for-agents`)

**Why.** Our skills are already long and precise. Matt's levers (completion criteria per step,
leading words, prompt the positive, pointers instead of inlining) are how we keep them from
becoming sediment.

**How.** Authoring convention when adding a skill: every step ends on a checkable done-line;
descriptions front-load the trigger word; do not steer by prohibition unless it is a hard
guardrail paired with the positive target. Not shipped to users.

### Brief and push-right (`loop-me`)

**Why.** A checkpoint that dumps the transcript is unread. A human asked three times mid-task
loses the thread.

**How.** `pickup` Doing/Next is a brief: what was produced, why, the one next action. `decide`
and `stuck` ask the human once, late, with options prepared. We do **not** take triggers,
schedules, or `workflows/*.md`.

### Ungrillable (`grill-me` + `prototype`)

**Why.** Talking through "how should this feel" balloons the session. Matt: stop grilling, make
something to look at. We cannot ship a prototype generator without violating coding-behaviour.

**How.** `plan` and `decide`: if the next question is ungrillable, one line, park, offer to
stop. The user decides whether to go make a sketch. We do not generate the HTML.

### Short spec (`to-spec`)

**Why.** Sometimes `plan` needs to be handed to a person or an AFK agent. Matt's template asks
for an "extremely extensive" user-story list — a wall.

**How.** Optional last line of `plan`, already sketched as "Want this as a file, or as Jira
tickets?": if file, the file is Problem / Solution / Out of scope / First slice. No paths. No
forty user stories. User-scoped or paste, not `.scratch/` in the repo unless they insist.

### Phase boundary (`ask-matt`)

**Why.** A full context window is the dumb zone. Five options (continue / clear / handoff /
subagent / compact) is decision load.

**How.** When the assistant can tell the thread is huge, one question: continue / write a
handoff / stop. Default recommend continue if the current phase is not finished. Do not
explain the five-option tree.

### HITL vs AFK (wayfinder ticket types, compressed)

**Why.** ADHD needs to know "this needs you" vs "I can do this while you look away."

**How.** One line on `plan` First action and on `walk` stages: `Needs you` or `I can run this`.
Not a label taxonomy.

---

## 6. Adjust — existing commands, concrete deltas

### `/squirrel:plan`

1. Clarifying questions use the decide primitive (lettered options, one recommended, one per
   message). Cap stays 3.
2. Ungrillable stop (see §5).
3. Optional short spec export (see §5). `slice` is the follow-on command in lote 2, not a new
   section inside `plan`.

### `/squirrel:digest`

No new flag required. Keep `--for-reply`. Do not add `--for-ask`; that is `/squirrel:ask`.
When Open questions name a person, one line may offer `ask`.

### `/squirrel:pickup`

Doing/Next written as a brief (loop-me steal). Still opens with Recent wins. Still stops. One
optional line if a `handoff` file was written this session, or if a `map` exists — not both,
not a menu.

### `/squirrel:init`

No new questions. The grilling primitive is documented as matching init's existing rules so
`decide` cannot drift into rounds.

---

## 7. Out — do not adapt

| Source | Why it stays out |
| :-- | :-- |
| `tdd` | Mandates red-green-refactor. Coding behaviour. |
| `implement` | Owns grill → spec → tickets → tdd → review → commit. GSD-shaped. Matt built his skills to *avoid* that ownership; we do not become it. |
| `prototype` as generator | Throwaway HTML/UI. Coding behaviour. Ungrillable *stop* is the steal. |
| `codebase-design` | Deep-module vocabulary for how to shape code. |
| `improve-codebase-architecture` | Architecture survey + HTML report. GUI non-goal + coding behaviour. |
| `grill-with-docs` | Writes `CONTEXT.md` and ADRs in the project. |
| `domain-modeling` | Same write. Ubiquitous language is useful; the profile is the personal language, not a per-repo glossary. |
| `setup-matt-pocock-skills` | Per-repo config for his plugin. |
| `setup-ts-deep-modules`, `setup-pre-commit`, `migrate-to-shoehorn`, `scaffold-exercises` | TypeScript/git/course tooling. |
| `git-guardrails-claude-code` | Blocks git at the hook. Rule 13 already refuses to compress safety warnings. Not our product. |
| `claude-handoff` | `claude --bg`. Claude-only + background process. File `handoff` is what ports. |
| `writing-fragments` | More divergence. `plan` and `draft` converge. |
| `loop-me` as product | Triggers, schedules, workflow specs. Tether / ravila4. |
| `triage` as state machine | Labels, wontfix, agent-ready briefs posted to GitHub. `inbox` is the view; the machine is not. |

---

## 8. Sequence

Do not build lote 2 because this file lists it. Build because lote 1 is in use and still
hurts.

**Lote 1, in order**

1. `/squirrel:wait` — smallest, pure shape, unblocks mid-conversation.
2. Grilling primitive + `/squirrel:decide` — unblocks forks without a full `plan`.
3. `/squirrel:handoff` — unblocks Claude → Cursor and interruption that pickup cannot travel.
4. `/squirrel:ask` and `/squirrel:help` — cheap. Help can even ship with wait (it is a table).
5. `/squirrel:map` — only if plan + checkpoint + handoff still fail on a multi-session effort.

**Steals into current product, any time, without a new command**

- Grounding clause on rule 4.
- Ungrillable stop in `plan`.
- Brief-shaped Doing/Next in `pickup`.
- Phase-boundary one question when the thread is huge.
- writing-for-agents as the authoring checklist for whoever writes the next `SKILL.md`.

**Lote 2, in order, after lote 1 is real**

1. `/squirrel:inbox` and `/squirrel:stuck` — pile and rabbit hole.
2. `/squirrel:slice` and `/squirrel:review`.
3. `/squirrel:walk`, `/squirrel:orient`, `/squirrel:draft`, `/squirrel:look-up`.

**Parity reminder.** Each new command needs an ADR-0004 row: Claude Code / Codex / Cursor, and
*why* the missing ones cannot port. Pure prose ports. `~/.squirrel/` writes follow init/tune.
Anything that needs a hook does not leave Claude Code.

---

## 9. What a later build plan must still decide

This file chooses *what* and *why*. It does not choose:

- Version number or which lote ships in which release.
- Whether `map` is cut.
- Exact cap for `decide` (5 is the design default; it can move after live use).
- Whether grounding is a 17th base rule or a clause on rule 4 (a 17th rule needs the
  research-or-design-decision treatment in RESEARCH.md).
- Test and acceptance criteria. Those belong in a PLAN.md-style build plan, not here.

Until that build plan exists, do not implement these skills.
