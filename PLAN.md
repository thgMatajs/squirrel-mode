# Build Plan: `squirrel-mode` — ADHD-Friendly AI Responses for Claude Code, Codex, and Cursor

> **How to use this file:** Open Claude Code in this repository and say:
> *"Read PLAN.md and build it exactly as specified. Work through the Build Steps in order."*
>
> Read [CONTEXT.md](./CONTEXT.md) for the vocabulary and [docs/adr/](./docs/adr/) for why the
> architecture looks the way it does. The five ADRs record decisions a reader would otherwise
> assume were oversights and try to "fix".

---

## 1. CONTEXT — What we are building

`squirrel-mode` reshapes how an AI coding assistant communicates, so that people with ADHD (and
anyone who prefers direct, structured answers) can actually process the output. It changes response
*shape*, never response *content*.

It installs into three **targets** — Claude Code, Codex, Cursor — and has five parts:

1. **The base rules** — response-formatting constraints that apply to every answer: answer first,
   numbered steps, no preamble, no tangents, hard length limits. Each rule traces to a specific
   research finding. This is the product; everything else delivers or adapts it.
2. **Calibration** (`/squirrel:init`) — a guided interview (7 multiple-choice questions, one per
   message) that writes a personal **profile**. The rules adapt to the individual.
3. **Adjustment** (`/squirrel:tune`) — change any profile field later without redoing the interview.
4. **Input restructuring** (`/squirrel:digest`, `/squirrel:plan`) — apply the same rules to content
   the user *received* (a rambling ticket, a wall-of-text email) and to raw idea dumps.
5. **Interruption recovery** (`/squirrel:pickup` + automatic **checkpoints**) — a tiny per-project
   record of what we're doing, what's next, and open decisions, plus a **Done log** of recent wins.

Everything is **user-scoped**: it installs to the user's machine, applies across all projects, and
never writes inside a project repository.

All plugin code, commands, and instructions are written in **English** (this is a public repo). The
user's **response language is a profile field**, chosen during `/squirrel:init`.

### Prior art (study these, don't copy them)

- **Caveman** (`github.com/JuliusBrussee/caveman`) — persona-based compression; good session-flag
  architecture; zero telemetry. We borrow the flag-file pattern, inverted, for the off switch.
- **i-have-adhd** (marketplace skill by ayghri) — ~10 fixed markdown rules. We borrow the rule style
  and add what it lacks: per-user calibration.

Our differentiator: neither adapts to the individual. ADHD presentation varies between people and
day to day. `squirrel-mode` calibrates.

---

## 2. WHY — Research foundation

Every rule must trace to a finding below. `docs/RESEARCH.md` carries the full version.

**Citation policy — non-negotiable.** Every citation is verified against the primary source before it
enters the repo, and every finding is tagged with the **population it was measured in**:
`ADHD` / `general working memory` / `borrowed from adjacent accessibility work`. The repo's entire
claim is "evidence-based, not aesthetic"; a reader who checks one citation and finds it wrong
discounts everything. Three errors already found and corrected during planning are marked ⚠ below.
If a search yields nothing solid, the claim comes out — no filler citations.

**Working memory capacity is the bottleneck.** `general working memory`
Working memory holds ~3–5 chunks and abandons content when new stimuli arrive (Baddeley & Hitch;
Cowan, 2010, *The Magical Mystery Four*; Sweller, Cognitive Load Theory). Adults with ADHD show
reduced working-memory accuracy across all load conditions, degrading further as load increases
(Karalunas et al., *Constraints on Information Processing Capacity in Adults with ADHD* — verify
PMC6996017 before citing). `ADHD`
→ **Rules:** max 3–5 items per list; one concept per paragraph; never more than one decision at a time.

**Incremental presentation and external cues reduce load.** `ADHD`
External storage, cues, and incrementally added information reduce working-memory load (Salari et
al., *Neural basis of working memory in ADHD: Load versus complexity*, NeuroImage: Clinical, 2021;
Martinussen et al., 2005 meta-analysis).
→ **Rules:** numbered steps (the numbers *are* the external cues); progress restated across turns;
checklists over prose.

**Slower processing speed compounds the problem.** `ADHD`
Slower processing keeps capacity occupied by ongoing processing (time-based resource-sharing model;
Kofler; *Academic Achievement in Children with ADHD*, Res. Child Adolesc. Psychopathol., 2025).
→ **Rules:** front-load the answer (conclusion first, rationale after, never the reverse); short
sentences; never bury the action item mid-paragraph.

**Extraneous content is not neutral — it destroys held information.** `general working memory` + `borrowed`
Working-memory content is abandoned to make room for new stimuli; extraneous cognitive load directly
harms task performance (Sweller, intrinsic vs. extraneous load). ⚠ The code-presentation
application — Speicher & Chandrasekar, *Theoretical basis for code presentation: A case for cognitive
load*, arXiv:2511.14636 — studies **blind and low-vision developers, not ADHD**. It is sound CLT
reasoning borrowed from an adjacent accessibility population and must be labelled as such.
→ **Rules:** zero tangents, zero "by the way", zero unsolicited alternatives; no preamble or
postamble; one optional `Extra` section at the very end if something genuinely matters.

**Instructional accommodations for ADHD are well-documented.** `ADHD`
Reduce WM demands: one topic at a time, stay goal-oriented, chunk instructions (Martinussen & Major,
2011, *Working Memory Weaknesses in Students With ADHD*; Meltzer & Basho, 2010).
→ **Rules:** the interview asks one multiple-choice question at a time; multi-step tasks always
numbered; each step independently actionable.

**Context switching destroys the mental model; recovery is expensive.** `ADHD`
⚠ Working-memory weaknesses in ADHD manifest as context-switching problems and difficulty
remembering what one was doing — **Liebel, Langlois & Gama**, *Challenges, Strengths, and Strategies
of Software Engineers with ADHD: A Case Study*, ICSE-SEIS 2024, arXiv:2312.05029. (The planning draft
cited this as "Gama et al." three times; Gama is the third author.) ⚠ The ~23-minute
interruption-recovery figure is **Gloria Mark's** work at UC Irvine, not an APA original — cite Mark.
→ **Features:** automatic per-project checkpoints; `/squirrel:pickup`; a one-line "resume available"
notice at session start.

**Hyperfocus has a stopping problem.** `ADHD`
ADHD developers tend toward over-engineering enjoyable tasks and have trouble stopping, tied to
response-inhibition regulation (Liebel et al., arXiv:2312.05029).
→ **Rule:** the scope guard — when the conversation drifts from the declared task, flag it in ONE
line and offer to park it. Never lecture.

**ADHD blurs the memory of one's own accomplishments.** `ADHD` (practitioner + case-study accounts)
Memory issues blur the personal success record, feeding demotivation.
→ **Feature:** the Done log; `/squirrel:pickup` opens with recent wins.

**Time blindness breaks estimation.** `ADHD`
Time-discrimination difficulty affects deadline management and estimation (Liebel et al.).
Practitioner guidance converges on task atomicity: units of ≤45 minutes.
→ **Rules:** every Phase-1 step in `/squirrel:plan` carries a concrete estimate and must be ≤45 min;
concrete time language everywhere.

**Prior academic validation that this tool category works.** `ADHD`
*Tether: A Personalized Support Assistant for Software Engineers with ADHD* — Shah, Magalhaes, Gama &
de Souza Santos, arXiv:2509.01946 (verified) — validates LLMs as personalized support for
neurodivergent developers. It uses local activity monitoring, RAG, and gamification. squirrel-mode
covers the communication layer of the same space with zero infrastructure; link Tether in README as
the heavier, complementary direction.

**During the build**, run 2–3 additional searches to enrich `docs/RESEARCH.md` (e.g. "ADHD text
comprehension formatting study", "plain language accessibility neurodivergent readers"). Verify
before citing.

---

## 3. HOW — Architecture

Five decisions shape this and are recorded as ADRs. Read them before changing the layout.

| ADR | Decision |
| :-- | :-- |
| [0001](./docs/adr/0001-output-style-not-skill.md) | Base rules ship as an **output style**, not a skill |
| [0002](./docs/adr/0002-checkpoint-auto-allow.md) | The plugin **auto-approves** writes to its own checkpoint directory |
| [0003](./docs/adr/0003-profile-outside-plugin-data.md) | Profile and checkpoints live in `~/.claude/squirrel/`, not `${CLAUDE_PLUGIN_DATA}` |
| [0004](./docs/adr/0004-tiered-parity-across-targets.md) | Targets get **tiered parity** from one canonical rules file |
| [0005](./docs/adr/0005-session-flag-off-switch.md) | The off switch is a **session flag** plus a per-prompt counter-injection |

### Repository layout (also serves as a plugin marketplace)

```
squirrel-mode/                       # repo name (brand)
├── .claude-plugin/
│   ├── plugin.json                  # name: "squirrel"  ← the command namespace
│   └── marketplace.json             # /plugin marketplace add <user>/squirrel-mode
├── rules/
│   └── base-rules.md                # ◀── CANONICAL. The 16 rules live here and nowhere else.
├── output-styles/
│   └── squirrel-mode.md             # GENERATED — the real mechanism (ADR-0001)
├── skills/
│   ├── rules/SKILL.md               # GENERATED — thin manual fallback (/squirrel:rules)
│   ├── init/SKILL.md                # /squirrel:init
│   ├── tune/SKILL.md                # /squirrel:tune
│   ├── digest/SKILL.md              # /squirrel:digest
│   ├── plan/SKILL.md                # /squirrel:plan
│   ├── pickup/SKILL.md              # /squirrel:pickup
│   ├── off/SKILL.md                 # /squirrel:off
│   └── on/SKILL.md                  # /squirrel:on
├── hooks/
│   └── hooks.json                   # SessionStart, UserPromptSubmit, PreToolUse
├── scripts/
│   ├── load-profile.sh              # SessionStart  → inject profile + resume notice
│   ├── check-off-flag.sh            # UserPromptSubmit → counter-inject when disabled
│   ├── allow-checkpoint.sh          # PreToolUse    → auto-approve checkpoint writes
│   └── build.sh                     # rules/base-rules.md → every generated artifact
├── targets/
│   ├── codex/
│   │   ├── AGENTS.md                # GENERATED — block for ~/.codex/AGENTS.md
│   │   ├── skills/                  # GENERATED — for ~/.agents/skills/
│   │   └── install.sh
│   └── cursor/
│       ├── squirrel-mode.mdc        # GENERATED — for ~/.cursor/rules/
│       ├── commands/                # GENERATED — for .cursor/commands/
│       └── install.sh
├── docs/
│   ├── RESEARCH.md                  # full evidence base, population-tagged
│   ├── OTHER-TOOLS.md               # Codex + Cursor install and what each loses
│   └── adr/0001…0005-*.md
├── CONTEXT.md                       # glossary
├── profile.example.md
├── README.md
└── LICENSE                          # MIT
```

**Naming.** Repo is `squirrel-mode`; `plugin.json` `name` is **`squirrel`**. Plugin skills are always
namespaced, so `skills/init/` becomes `/squirrel:init` — short, and no duplicated word. The
marketplace entry must also be named `squirrel`: the marketplace entry name is what `enabledPlugins`
keys and `/plugin` use. **Changing `name` later breaks existing users' `enabledPlugins`.**

### Generated files are committed

`scripts/build.sh` reads `rules/base-rules.md` and writes every artifact marked GENERATED above.
Those artifacts are committed so users can install without running anything. CI re-runs the build and
fails if the tree is dirty — that is the drift check. Never hand-edit a GENERATED file; edit
`rules/base-rules.md` and rebuild.

### The profile

- Location: `~/.claude/squirrel/profile.md` (ADR-0003). Never inside a repo — document the ignore
  pattern so users don't commit it by accident.
- Plain markdown, human-editable, ~15 lines, 11 fields:

```markdown
# squirrel-mode profile
language: pt-BR            # pt-BR | en | es | auto (mirror the user)
answer_position: first     # first | after-one-line-context
step_style: numbered       # numbered | checklist
max_list_items: 5          # 3–7
code_style: code-first     # code-first | step-by-step
explanation_budget: 3      # max lines of explanation per code block
options_per_answer: 1      # alternatives to offer (1 = just recommend)
confirm_topic_switch: yes  # ask before changing subject
progress_recap: yes        # restate done/next across turns
extras_section: yes        # allow one "Extra" section at the end
tone: neutral              # neutral | warm | terse
```

### Data flow (Claude Code)

1. **SessionStart** runs `load-profile.sh`, which emits
   `hookSpecificOutput.additionalContext` containing the profile, plus one line
   `Resume available — run /squirrel:pickup` if a checkpoint exists for `cwd`. If no profile exists,
   it emits a single line telling Claude to suggest `/squirrel:init` once, briefly. It also prunes
   stale off-flags. Matchers: `startup|resume|clear|compact` — `compact` matters, because it
   re-injects the profile after compaction drops it.
2. **The output style** is already in the system prompt, carrying the base rules and the instruction
   *"a squirrel-mode profile may be present in context; obey its fields. If absent, use these
   defaults."* It cannot interpolate anything (ADR-0001), so the profile path appears literally.
3. **UserPromptSubmit** runs `check-off-flag.sh`: if `~/.claude/squirrel/off/<session_id>` exists,
   inject the counter-instruction (ADR-0005). Otherwise exit silently.
4. **PreToolUse** on `Write` with `if: Write($HOME/.claude/squirrel/checkpoints/**)` runs
   `allow-checkpoint.sh`, which returns `permissionDecision: "allow"` (ADR-0002).

### The base rules (write these into `rules/base-rules.md`)

1. Answer first, per `answer_position`. When `first`, the opening sentence is the answer or the
   immediate next action, before any setup or caveat. When `after-one-line-context`, exactly one
   short orienting line may precede it — one line, never a paragraph.
2. No preamble ("Great question", "Sure, I can help") and no postamble ("Let me know if...").
3. Multi-step work is always enumerated, in the form set by `step_style`: `numbered` gives
   `1.`/`2.`/`3.`, `checklist` gives `- [ ]` items. Either way max `max_list_items` steps visible at
   once; if more, chunk into phases and show only the current phase in detail.
4. One concept per paragraph. Max ~3 lines per paragraph.
5. Code: respect `code_style`. If `code-first`, show the code block, then at most
   `explanation_budget` lines of explanation. If `step-by-step`, state the numbered steps first,
   then the code block, keeping total explanation within `explanation_budget` lines.
6. Offer exactly `options_per_answer` option(s), unprompted. When it is 1, recommend one path and do
   not enumerate alternatives unless the user asks. When it is greater than 1, present that many up
   front; only list alternatives *beyond* that count when the user asks.
7. No tangents. If something adjacent genuinely matters (a security risk, a breaking change), put it
   in a single `Extra` section at the very end — and only if `extras_section: yes`.
8. Across turns in a task, open with a one-line recap — `Done: X. Now: Y.` — if `progress_recap: yes`.
9. If the user's message contains multiple questions, answer them as a numbered list matching their
   order. Never merge them into prose.
10. Before switching topics (if `confirm_topic_switch: yes`), ask a single yes/no question.
11. Time estimates are concrete ("~10 min", "2 commands"), never vague ("shortly", "a few things").
12. Respond in `language` (or mirror the user when `auto`).
13. **Safety override:** these brevity rules never suppress warnings about destructive operations,
    security issues, or data loss. Clarity beats compression there. **This rule takes precedence over
    rules 1–12 and 16 wherever they conflict, explicitly including rule 7's `extras_section: no`
    gate** — a safety warning is never dropped because the Extra section is disabled.
14. **Checkpoint maintenance:** when a meaningful unit of work completes, update
    `~/.claude/squirrel/checkpoints/<project-slug>.md` **with no commentary in the response** — do
    not announce it, do not ask. At most **one write per turn**, and only when `Doing` or `Next`
    actually changed. Append finished items to the Done log, keeping the last 10.
    *Never describe this as happening without the user's knowledge. Tool calls are always visible in
    the transcript; what we promise is no prose about it, not invisibility (ADR-0002).*
15. **Scope guard:** when the conversation drifts from the declared task, flag it in exactly ONE
    line — e.g. `🐿️ This is drifting from <task>. Park it?` — and offer to park the tangent. Never
    lecture. Never refuse an explicit choice to continue. Flag the same drift only once. The rule
    must read correctly on all three targets, so it may not assume a checkpoint exists.
16. **Tone:** match `tone`. `neutral` is plain and unadorned. `warm` permits brief acknowledgement of
    effort or frustration — but **rule 2 wins structurally**: the acknowledgement must be fused into
    the same sentence as the answer or next action, never a sentence of its own preceding it. A warm
    opener that stands alone is preamble, and rule 2 forbids it. `terse` strips every non-essential
    word: fragments over sentences, no transitions. Tone never changes *what* is said, only its
    register, and never overrides rule 13.

### `/squirrel:init` — calibration

Hard requirements, from the research (one topic at a time, chunked, low WM demand):

- Exactly **one question per message**. Never batch.
- Every question is **multiple-choice (2–4 options)**, labeled A/B/C/D, plus "type your own".
- **7 questions maximum.** Show progress: "Question 3 of 7".
- After the last question: show the resulting profile as a compact block, ask a single confirm
  ("Save this? y/n"), write the file, then demonstrate immediately by answering the user's next
  message in the new style.

**Question → field mapping.** 11 fields, 7 questions. Question 2 is a **bundle selector**: it is the
highest-information question per unit of cognitive load, and it sets four soft fields at once. There
is no 1:1 mapping and the spec must not claim one.

| # | Question | Sets |
| :-- | :-- | :-- |
| 1 | Language | `language` |
| 2 | **What breaks your focus most?** (A: long text · B: disorganized · C: too many options) | `step_style`, `explanation_budget`, `extras_section`, `tone` |
| 3 | Where should the answer go? | `answer_position` |
| 4 | Code first, or steps first? | `code_style` |
| 5 | How long a list before it stops helping? | `max_list_items` |
| 6 | One recommendation, or alternatives? | `options_per_answer` |
| 7 | Recap progress and confirm topic switches? | `progress_recap`, `confirm_topic_switch` |

`/squirrel:tune` exposes all 11 fields individually — that is where the long tail is discoverable.

### `/squirrel:tune`

Reads the current profile, shows current values, asks **one** question about what to change, rewrites
the file. Never re-runs the interview. Must be able to edit any of the 11 fields, including the four
that question 2 set as a bundle.

### `/squirrel:off` and `/squirrel:on`

`/squirrel:off` writes `~/.claude/squirrel/off/<session_id>` and confirms in one line.
`/squirrel:on` removes it. Suppression is delivered by the `UserPromptSubmit` hook, not by an
in-conversation instruction (ADR-0005). README documents `/plugin disable squirrel` + `/clear` as the
hard off.

### `/squirrel:digest`

Take any content the user provides and restructure it into an actionable brief. Same rationale as the
base rules: a rambling ticket imposes exactly the extraneous load the rules remove from Claude's own
output, so apply the same treatment inbound.

**Input handling** — all of these:

- Text pasted after the command.
- A file path in the current project: read it first.
- A Jira ticket reference (`PROJ-123` or a URL): if an Atlassian/Jira MCP tool is available, fetch
  summary, description, comments, status, priority, and linked issues. If not, say so in ONE line and
  ask for a paste. Never fail silently.
- No input: ask one question — "Paste the content or give me a file path / ticket ID."

**Output format** (fixed, in the profile `language`):

```
## TL;DR
<2 sentences max: what this is and what it's really asking for>

## Next action
<the SINGLE first thing to do — concrete, startable in under 10 minutes>

## Breakdown
1. <step — independently actionable>
(respect max_list_items; if more, group into phases and expand only phase 1)

## Priority
- NOW: <what blocks everything else>
- NEXT: <what follows>
- CAN WAIT: <genuinely deferrable — be honest, don't put everything in NOW>

## Open questions / blockers
- <ambiguous, missing, or needs another person — with WHO to ask if identifiable>
```

**Rules:** omit empty sections rather than padding them. For Jira, derive Priority from due dates,
blockers, and linked-issue relationships; flag scope ambiguity ("acceptance criteria missing") under
Open questions; never invent requirements. If the input contains multiple independent asks, digest
each under `## Item 1`, `## Item 2` — never merge. End with nothing.

Optional `--for-reply`: additionally produce a short, polite version suitable for sending back to
whoever requested the task (Jira comment, Slack reply), in the profile `language`, copy-paste ready.

### `/squirrel:plan`

Turn a raw, messy idea into a scoped action plan. Divergent thinking is typically abundant in ADHD;
the hard parts are **convergence**, **initiation**, and **not losing the tangents**. This command does
the convergence, hands back a startable first action, and captures tangents instead of suppressing
them.

1. User dumps the idea, in any state of disorder. If empty, ask one question: "Tell me the idea —
   messy is fine."
2. Ask **at most 3 clarifying questions, one at a time, multiple-choice where possible**. Skip
   anything already inferable from the dump. Never ask open-ended "tell me more".
3. Produce the plan. Do not iterate endlessly — converge and deliver.

**Output format** (in the profile `language`):

```
## The idea in one sentence
<forces convergence — if it can't be said in one sentence, say what's competing and ask them to pick>

## Goal
<what success looks like, concretely, 1–2 lines>

## Scope
- IN: <3–5 bullets max>
- OUT (for now): <explicitly deferred — this is a decision, not a loss>

## Smallest useful version
<the minimal version that already delivers value — days, not months>

## Plan
Phase 1 — <name> (expand fully, numbered, respect max_list_items)
Phase 2 — <name> (one-line summary only)
Phase 3 — <name> (one-line summary only)

## First action
<ONE step, startable in under 10 minutes, right now>

## Parking lot 🐿️
<every tangent and "what if" that came up — captured, but explicitly NOT in the plan>
```

**Rules:** the Parking lot is mandatory whenever the dump contains tangents — capturing them is what
lets the plan stay narrow without the user feeling they lost something. Recommend ONE path; if a
genuine fork exists (CLI vs. web app), present it as a single multiple-choice question *before*
writing the plan, never as parallel plans. Never expand past Phase 1 — detail-on-demand keeps WM load
flat. Every Phase-1 step carries a concrete estimate and must be ≤45 min; anything larger is split.
Offer in one line at the end, only if relevant: "Want this as a file, or as Jira tickets?" If yes to
Jira and a Jira tool is available, show a preview, get a single confirm, then create the issues.

### Checkpoints and `/squirrel:pickup`

- Location: `~/.claude/squirrel/checkpoints/<project-slug>.md`, slug derived from the project
  directory path. Never inside the project repo.
- Max ~15 lines:

```markdown
# checkpoint: <project name>
updated: <ISO timestamp>
## Doing
<current task, one line>
## Next
<the single next step>
## Open decisions
- <unresolved choices, if any>
## Done log (last 10)
- <date>: <one-line win>
```

Written per base rule 14, auto-approved per ADR-0002.

**`/squirrel:pickup` output** (in the profile `language`):

```
## Recent wins 🐿️
- <last 2–3 Done log entries — shown FIRST, on purpose>

## You were doing
<one line>

## Next action
<the single next step, startable now>

## Open decisions
- <only if any exist>
```

Then stop. No suggestions, no "shall we continue?" — the user decides.

### Codex and Cursor (ADR-0004)

| Target | Always-on rules | Commands | Auto profile | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | 7 namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | `.cursor/commands/*.md`, project-scoped | no | no |

Facts the older draft got wrong: Codex skills live in **`~/.agents/skills/`**, not `~/.codex/skills/`,
and Codex **custom prompts are deprecated** in favour of skills. Codex loads `AGENTS.md` in layers
from `~/.codex/` down to cwd, each as a separate user message, later overriding earlier.

`docs/OTHER-TOOLS.md` states plainly what each target loses. `targets/*/install.sh` copies the
generated artifacts into place and is idempotent.

---

## 4. BUILD STEPS — in order

1. **Scaffold** the layout above. `plugin.json`: `name: "squirrel"`, `version: "0.1.0"`,
   `description: "ADHD-friendly AI responses: answer first, zero fluff. 🐿️"` — keep the word
   "ADHD" in every public description for discoverability. `marketplace.json` lists the entry as
   `squirrel`.
2. **Write `rules/base-rules.md`** — all 16 rules, the single source of truth.
3. **Write `scripts/build.sh`** — generates `output-styles/squirrel-mode.md`
   (`keep-coding-instructions: true`, `force-for-plugin: true`), the thin
   `skills/rules/SKILL.md`, `targets/codex/`, and `targets/cursor/`. Run it; commit the output.
4. **Write the 7 command skills.** Set `disable-model-invocation: true` on `init`, `tune`, `off`,
   `on` — the model must never start an interview or flip the plugin's state on its own. Leave
   `digest`, `plan`, `pickup` model-invocable, with descriptions tight enough not to hijack ordinary
   requests.
5. **Write `hooks/hooks.json` + the three scripts.** POSIX sh, no network calls, no telemetry — state
   this explicitly in README. `load-profile.sh` must handle a missing profile, a missing checkpoint,
   and prune stale off-flags without ever exiting non-zero.
6. **Write `docs/RESEARCH.md`** — full citations, population tags, the three corrections from
   Section 2, plus the additional searches. Verify every citation against its primary source.
7. **Write `targets/*/install.sh`** and `docs/OTHER-TOOLS.md`.
8. **Write `README.md`** — what/why in 2 paragraphs using the plugin's own formatting rules (eat the
   dog food), install per target, the 7 commands, the parity table, the privacy note (zero
   phone-home **and** an explicit statement that the plugin auto-approves writes to its own
   checkpoint directory), research link, license.
9. **Validate:** `claude plugin validate .` must pass. Then `claude --plugin-dir .` and run the
   acceptance criteria below end to end.
10. **Iterate:** if the output style is not taking effect, check `/config` and remember it needs
    `/clear` or a new session — do not start editing rules first.

## 5. ACCEPTANCE CRITERIA

- [ ] `claude plugin validate .` passes.
- [ ] Installs user-scoped; zero files written inside any project repository.
- [ ] The base rules apply on the **first** message of a fresh session, with no manual step beyond
      enabling the plugin, and on **every** message after — verified over a 10-turn session.
- [ ] Claude's coding behaviour is unchanged (`keep-coding-instructions: true` is set and working).
- [ ] Fresh install with no profile → Claude suggests `/squirrel:init` exactly once, in one line.
- [ ] `/squirrel:init` asks one multiple-choice question at a time, 7 total, and writes all 11 fields
      to `~/.claude/squirrel/profile.md`. Question 2 sets four fields.
- [ ] Responses obey the profile: answer-first, numbered steps, list/length limits, chosen language.
- [ ] `/squirrel:tune` edits a single field, including a bundle-set one, without redoing the interview.
- [ ] `/squirrel:off` suppresses the rules for the rest of the session and **stays** suppressed for
      at least 10 turns. `/squirrel:on` restores them. Neither leaks into another session.
- [ ] `/squirrel:digest` restructures pasted text and files into the fixed format; with a Jira tool
      available it digests a ticket by ID; without one it says so in one line; `--for-reply` adds a
      copy-paste reply.
- [ ] `/squirrel:plan` converges a messy dump into the fixed format (≤3 clarifying questions, one at
      a time), always includes First action and Parking lot, expands only Phase 1, and every Phase-1
      step has a concrete estimate ≤45 min.
- [ ] Checkpoints are written to `~/.claude/squirrel/checkpoints/` with **no permission prompt and no
      prose in the response**, at most once per turn. `/squirrel:pickup` opens with recent wins, then
      Doing/Next/Open decisions, then stops.
- [ ] Uninstalling the plugin leaves `~/.claude/squirrel/` intact; reinstalling restores the profile
      and Done log.
- [ ] Scope guard fires as ONE line on task drift, offers to park the tangent, never lectures, never
      repeats for the same drift.
- [ ] `scripts/build.sh` is idempotent; CI fails if generated files drift from `rules/base-rules.md`.
- [ ] Codex and Cursor installs work via `targets/*/install.sh`; `docs/OTHER-TOOLS.md` states what
      each loses.
- [ ] No network calls, no telemetry anywhere. The checkpoint auto-approval is disclosed in README.
- [ ] Every citation in README and RESEARCH.md is verified against its primary source and tagged with
      the population it was measured in.
- [ ] No shipped instruction, skill, output style, or user-facing doc claims that checkpoint writes
      are invisible, unobservable, or hidden from the user. Describing an *error* path as failing
      quietly is a different and legitimate use; promising that our own writes go unseen is not.

## 6. NON-GOALS (v0.1)

- No timers, alarms, activity monitoring, or nudge systems — anything requiring a background process
  is out (see ravila4/claude-adhd-skills and the Tether paper for that niche; link both in README as
  complementary). Checkpoints are passive markdown files, not a task manager.
- No per-project profile overrides.
- No shaping of subagent output — output styles apply to the main conversation only (ADR-0001).
- No GUI. Markdown and commands only.
