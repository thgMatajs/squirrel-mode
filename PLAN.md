# Build Plan: `squirrel-mode` — ADHD-Friendly AI Responses for Claude Code, Codex, and Cursor

> **How to use this file:** Open Claude Code in this repository and say:
> *"Read PLAN.md and build it exactly as specified. Work through the Build Steps in order."*
>
> Read [CONTEXT.md](./CONTEXT.md) for the vocabulary and [docs/adr/](./docs/adr/) for why the
> architecture looks the way it does. The six ADRs record decisions a reader would otherwise
> assume were oversights and try to "fix".

---

## 1. CONTEXT — What we are building

`squirrel-mode` reshapes how an AI coding assistant communicates, so that people with ADHD (and
anyone who prefers direct, structured answers) can actually process the output. It changes response
*shape*, never response *content*.

It installs into three **targets** — Claude Code, Codex, Cursor — and has five parts:

1. **The base rules** — response-formatting constraints that apply to every answer: answer first,
   numbered steps, no preamble, no tangents, hard length limits. 10 of the 16 base rules trace to
   a specific research finding; the other 6 rules are stated design decisions, not empirical
   claims (see `docs/RESEARCH.md`). This is the product; everything else delivers or adapts it.
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

Rules in this document are either backed by a finding below, or are instead declared a design
decision in `docs/RESEARCH.md`'s "Rules with no research claim behind them" section — never
neither. `docs/RESEARCH.md` carries the full version, including exactly which of the two groups
each one falls into.

**[`docs/RESEARCH.md`](./docs/RESEARCH.md) is the authoritative citation list.** This section is the
design argument — findings and the rules they justify. Every citation was verified against its primary
source during the S6 build; the verified identities, population tags, links, and a record of the
corrections live in `RESEARCH.md`. Do not add a citation here without adding it there first, or the two
will drift — which is exactly how the errors below got in.

**Citation policy — non-negotiable.** Before a citation enters the repo, verify **all four**:

1. **Identity** — exact title, full author list in order, year, venue, working link.
2. **Support** — that the paper's own abstract or results actually state the thing we attribute to it.
3. **Whose finding it is** — that the sentence we are leaning on is the paper's *own* result, not its
   summary of someone else's. A paper citing a third party is not evidence; cite the third party.
4. **Population** — tag it `ADHD` / `general working memory` /
   `borrowed from adjacent accessibility work`, and never inflate.

**Item 2 is the one that gets skipped, and skipping it is worse than a typo.** The first verification
pass on this section checked identity only and passed five citations that were bibliographically
pristine and substantively wrong — including the opening claim, whose flagship source states in its own
abstract that it found *no* ADHD-specific working-memory-by-load effect. A correctly cited paper used
to support something it does not say is the failure a hostile reader finds first.

If a search yields nothing solid, the claim comes out — no filler citations.

**Five misattributions and three unsourced claims were found in this section's first draft.** The
verification pass was worth more than everything it cost. Corrected inline below and recorded in full
in `RESEARCH.md`.

**Working memory capacity is the bottleneck.** `general working memory`
Concurrent working-memory capacity is small and is exceeded easily (Cowan, 2010, *The Magical
Mystery Four*). ⚠ **The "~3–5 chunks" figure is no longer stated as settled.** Cowan's discrete-slot
account is disputed by continuous-resource models holding no fixed number of items at all (Ma,
Husain & Bays, 2014, *Nature Neuroscience* 17(3)) — a live dispute, not a retraction. Nothing built
here needs the limit to be a count, only to be small. ⚠ The bare "Sweller, Cognitive Load Theory"
citation is gone: the 1988 paper is not about chunk capacity at all, and Baddeley & Hitch is cited
only for working memory having structure, never for the capacity limit itself.
⚠ Adolescents and young adults with ADHD show a **disproportionate** accuracy drop as working-memory
load rises — a significant diagnosis-by-load interaction (Mukherjee et al., 2021, *NeuroImage:
Clinical* 30). The draft credited this to "Karalunas et al." and then, after the first correction, to
Roberts, Milich & Fillmore — whose abstract reports **no** group difference in load-driven disruption
on the working-memory task. Both were wrong; this one was checked against the paper's own result. `ADHD`
→ **Rules:** cap how many steps are shown at once (`max_list_items`); one concept per paragraph;
never more than one decision at a time.

**Incremental presentation and external cues reduce load.** `general working memory`
⚠ **Retagged, and its ADHD sourcing withdrawn.** No ADHD study tests cues or incremental presentation
directly. Mukherjee's sentence to that effect is in his *Introduction*, attributed to unspecified
"earlier work" — not his result — and Martinussen et al. (2005) is a diagnostic meta-analysis that
never mentions cues. This is inference from general cognitive-load reasoning, labelled as such.
→ **Rules:** numbered steps (the numbers *are* the external cues); progress restated across turns;
checklists over prose.

**Working memory and processing speed are separable, and the load runs memory → speed.** `ADHD`
⚠ **The mechanism this finding used to assert is retired — it was the reverse of its own source.**
The draft read "slower processing keeps capacity occupied by ongoing processing" and cited a
"time-based resource-sharing model" title from memory. Kofler et al. (2020), *Working memory and
information processing in ADHD: Evidence for directionality of effects*, tested exactly that
direction and reports the opposite: increasing working-memory demand significantly slowed
information processing, while experimentally slowing processing did **not** change working-memory
performance. The unconfirmed title is gone; the directly verified paper stands in its place.
⚠ *Academic Achievement in Children with ADHD* (Res. Child Adolesc. Psychopathol., 2025) was
credited to "Kofler"; it is **Hulsbosch, Van der Oord & Tripp**, and it supports only that both
functions track academic outcomes. The two papers disagree about the direction between them, and
`RESEARCH.md` records that disagreement rather than settling it.
→ **Rules:** front-load the answer (conclusion first, rationale after, never the reverse); short
sentences; never bury the action item mid-paragraph. The step from these lab results to answer
position is an **inference**, not a measured effect, and `RESEARCH.md` labels it as one.

**Extraneous content is not neutral — it destroys held information.** `general working memory` + `borrowed`
Working-memory content is abandoned to make room for new stimuli; extraneous cognitive load directly
harms task performance (**Sweller & Chandler**, 1994, *Cognition and Instruction* 12(3) — ⚠ the draft
cited a bare "Sweller"; the 1988 paper does not contain the words "intrinsic" or "extraneous" and was
removed repo-wide). ⚠ The code-presentation
application — Speicher & Chandrasekar, *Theoretical basis for code presentation: A case for cognitive
load*, arXiv:2511.14636 — **studies nobody**: it has no participants, recruits and tests no one, and
proposes design recommendations *for* **blind and low-vision developers, not ADHD**. Calling it a
study of that population was wrong twice over. It is sound CLT reasoning borrowed from an adjacent
accessibility population, one inferential step further out than the tag alone suggests, and must be
labelled as such.
→ **Rules:** zero tangents, zero "by the way", zero unsolicited alternatives; no preamble or
postamble; one optional `Extra` section at the very end if something genuinely matters.

**Chunking instructions is ordinary classroom guidance.** `general working memory`
⚠ **Retagged, and two of its three recommendations retired.** Only chunking survives, in the source's
own words — "Information should be broken down into manageable chunks or steps" (Meltzer & Basho,
2010) — and that chapter is general-education: it addresses "All students", and "ADHD" occurs in it
zero times, so the old `ADHD` tag rested on a source that never mentions the population. "One topic
at a time" appears nowhere in the chapter and is retired outright; "goal-oriented" is there, but
describes the classroom *environment*, not instructional sequencing. Martinussen & Major (2011),
*Working Memory Weaknesses in Students With ADHD*, genuinely is about students with ADHD — but it is
a paywalled review whose abstract carries none of the three recommendations, so it cannot carry them
either.
→ **Rules:** multi-step tasks are always numbered and chunked; each step independently actionable.
The interview's one-question-per-message shape is a **design choice**, not this finding's: "one topic
at a time" is precisely the recommendation retired above.

**Context switching destroys the mental model; recovery is expensive.** `ADHD`
⚠ Working-memory weaknesses in ADHD manifest as context-switching problems and difficulty
remembering what one was doing — **Liebel, Langlois & Gama**, *Challenges, Strengths, and Strategies
of Software Engineers with ADHD: A Case Study*, ICSE-SEIS 2024, arXiv:2312.05029. (The planning draft
cited this as "Gama et al." three times; Gama is the third author.) ⚠ **The "~23 minutes to recover
from an interruption" figure was removed entirely.** It has no primary source — it traces to an
unpublished 2006 interview, and the CHI 2008 paper most often cited for it reports the *opposite*,
that interrupted tasks were completed faster. The claim now rests on Liebel et al. alone, which is
enough: it is ADHD-specific and it is real.
→ **Features:** automatic per-project checkpoints; `/squirrel:pickup`; a one-line "resume available"
notice at session start.

**Starting and finishing is where the difficulty lands.** `ADHD`
⚠ **The "over-engineering enjoyable tasks" claim was retired.** It is Liebel et al. *quoting* Gama &
Lacerda (2023) — someone else's finding — and Gama & Lacerda's own abstract does not contain it. What
is Liebel et al.'s own case-study result, coded from their interviews, is that *Doing Boring Tasks* and
*Starting and Finishing* are the reported challenges, tied to response-inhibition regulation.
→ **Rule:** the scope guard — when the conversation drifts from the declared task, flag it in ONE
line and offer to park it. Never lecture. The step from "difficulty stopping a task" to "drifting off
the declared one" is an **inference**, not a measured result, and `RESEARCH.md` says so.

**Negative memory bias.** `ADHD`
⚠ The draft claimed "ADHD blurs the memory of one's own accomplishments" on the strength of
"practitioner accounts". No source supports that framing. What is supported is narrower and adjacent:
a negative memory bias associated with ADHD symptom severity (Vrijsen et al., 2018, *ADHD* 10(2)) —
measured in a non-clinical, dimensionally scored sample, which `RESEARCH.md` states plainly.
→ **Feature:** the Done log; `/squirrel:pickup` opens with recent wins. The feature stands on the
narrower claim; it did not need the overreach.

**Time blindness breaks estimation.** `ADHD`
Time-discrimination difficulty affects deadline management and estimation (Liebel et al.).
⚠ The ≤45-minute task-atomicity figure has **no** convergent source — published practitioner guidance
ranges from 15 to 60 minutes. It is a **design choice**, labelled as one, not a finding.
→ **Rules:** every Phase-1 step in `/squirrel:plan` carries a concrete estimate and must be ≤45 min;
concrete time language everywhere.

**Related work — the category is explored, not validated.** No population tag, deliberately: nobody
was measured.
⚠ *Tether: A Personalized Support Assistant for Software Engineers with ADHD* — Shah, Magalhaes,
Gama & de Souza Santos, arXiv:2509.01946 (verified) — was described here as **validating** LLMs as
personalized support for neurodivergent developers, under an `ADHD` tag. Its own abstract reports
"preliminary validation through self-use" and states, "While not yet evaluated by target users". A
tool built *for* a population is not a measurement *in* one, so the tag is removed rather than
swapped for a nearer-fitting one. Tether *explores* the category, with local activity monitoring,
RAG, and gamification. squirrel-mode covers the communication layer of the same space with zero
infrastructure; link Tether in README as the heavier, complementary direction. It justifies no rule.

**During the build**, run 2–3 additional searches to enrich `docs/RESEARCH.md` (e.g. "ADHD text
comprehension formatting study", "plain language accessibility neurodivergent readers"). Verify
before citing.

---

## 3. HOW — Architecture

Six decisions shape this and are recorded as ADRs. Read them before changing the layout.

| ADR | Decision |
| :-- | :-- |
| [0001](./docs/adr/0001-output-style-not-skill.md) | Base rules ship as an **output style**, not a skill |
| [0002](./docs/adr/0002-checkpoint-auto-allow.md) | The plugin **auto-approves** writes to its own checkpoint directory |
| [0003](./docs/adr/0003-profile-outside-plugin-data.md) | Profile and checkpoints live in `~/.squirrel/`, not `${CLAUDE_PLUGIN_DATA}` |
| [0004](./docs/adr/0004-tiered-parity-across-targets.md) | Targets get **tiered parity** from one canonical rules file |
| [0005](./docs/adr/0005-session-flag-off-switch.md) | The off switch is a **session flag** plus a per-prompt counter-injection |
| [0006](./docs/adr/0006-session-isolation-concurrency.md) | Concurrent sessions isolate by **ownership**, not by locking shared state |

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
│   ├── allow-checkpoint.sh          # PreToolUse    → auto-approve checkpoint reads/writes
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
│   ├── ACCEPTANCE.md                # S9 conformance record against Section 5
│   └── adr/0001…0006-*.md
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

- Location: `~/.squirrel/profile.md` (ADR-0003). Never inside a repo — document the ignore
  pattern so users don't commit it by accident.
- Plain markdown, human-editable, ~15 lines, 11 fields.
- **The SessionStart hook caps what it injects at 100 lines / 4 KB**, truncating with a one-line
  notice past that. The documented format is ~15 lines, so the cap is generous by any honest measure.
  Two reasons: an uncapped profile is unbounded context bloat on every session start, and the injected
  text is framed to the model as authoritative field overrides — so anything that can write this file
  gets a persistent, privileged prompt-injection surface. The cap bounds the blast radius without
  making the hook a security boundary it cannot be.

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
   `Resume available - run /squirrel:pickup` if a checkpoint exists for `cwd` (ASCII hyphen, not an em
   dash — injected context stays ASCII). If no profile exists,
   it emits a single line telling Claude to suggest `/squirrel:init` once, briefly. It also prunes
   stale off-flags. Matchers: `startup|resume|clear|compact` — `compact` matters, because it
   re-injects the profile after compaction drops it.
2. **The output style** is already in the system prompt, carrying the base rules and the instruction
   *"a squirrel-mode profile may be present in context; obey its fields. If absent, use these
   defaults."* It cannot interpolate anything (ADR-0001), so the profile path appears literally.
3. **UserPromptSubmit** registers **two** commands in `hooks.json`, in order. First
   `check-off-flag.sh`: if `~/.squirrel/off/<session_id>` exists, inject the counter-instruction
   (ADR-0005); otherwise exit silently. Then `load-profile.sh` again, on its P3 reinjection path:
   if `~/.squirrel/profile.md` is newer than `~/.squirrel/profile-seen/<session_id>` (or that
   marker does not exist yet), reprint the profile framing so a `/squirrel:tune` in another
   session reaches this one without a restart, and touch the marker; otherwise exit silently.
4. **PreToolUse**, matcher `Write|Edit|Read`, runs `allow-checkpoint.sh` on every one. The hook's
   `if` field cannot safely express the path gate itself (ADR-0002: unverified whether it expands
   `~`/`$HOME` at plugin-build time), so the matcher is broad and the script reads
   `tool_input.file_path` and emits `permissionDecision: "allow"` only for a path that genuinely
   resolves inside `$HOME/.squirrel/checkpoints/`; for every other path it emits **nothing at all**
   and exits 0, which is how a `PreToolUse` hook says "no opinion, use the normal permission flow" —
   for a `Read` exactly as for a `Write`/`Edit`, per S10-1's amendment to ADR-0002. Emitting
   `permissionDecision: "defer"` here instead — which this script did until v0.3.1 — does *not* mean
   that: it parks the tool call and stops the turn (see ADR-0002's Amendment (v0.3.1)). This read
   requires `jq`: a regex cannot safely parse `tool_input` when it carries a nested object, so
   without `jq` on `PATH` the script never guesses and always declines (S10 review cycle 2, AC1's
   amendment to ADR-0002).

### The base rules (write these into `rules/base-rules.md`)

1. Answer first, per `answer_position`. When `first`, the opening sentence is the answer or the
   immediate next action, before any setup or caveat. When `after-one-line-context`, exactly one
   short orienting line may precede it — one line, never a paragraph.
2. No preamble ("Great question", "Sure, I can help") and no postamble ("Let me know if..."). None
   of that bans the trailing content another rule expressly licenses. Rule 7 states what may trail
   the answer and in what order; this rule does not restate it. The clearest example is rule 15's
   scope-guard flag: when it fires, its one line follows the completed answer as the final line of
   the response, never before it.
3. Multi-step work is always enumerated, in the form set by `step_style`: `numbered` gives
   `1.`/`2.`/`3.`, `checklist` gives `- [ ]` items. Either way max `max_list_items` steps visible at
   once; if more, chunk into phases and show only the current phase in detail. This cap governs task
   steps only — it does not shrink or delay answers covered by rule 9: every question in a
   multi-question message still gets answered, no matter how many there are. When rule 9 puts
   several sub-answers in one response, this cap applies to each sub-answer on its own, not to the
   response as a whole.
4. One concept per paragraph. Max ~3 lines per paragraph.
5. Code: respect `code_style`. If `code-first`, show the code block, then at most
   `explanation_budget` lines of explanation. If `step-by-step`, state the numbered steps first,
   then the code block, keeping total explanation within `explanation_budget` lines.
6. This rule governs solutions the assistant offers as its own answer; it does not govern the
   lettered choices inside a question the assistant asks the user to resolve scope, intent, or a
   preference first — a clarifying question's own choices are set by whatever rule or skill defines
   it and are not counted against `options_per_answer`. Offer exactly `options_per_answer`
   option(s), unprompted. When it is 1, recommend one path and do not enumerate alternatives unless
   the user asks. When it is greater than 1, present that many up front; only list alternatives
   *beyond* that count when the user asks. When rule 9 puts several sub-answers in one response,
   this cap applies to each sub-answer on its own, not to the response as a whole.
7. No tangents. If something adjacent genuinely matters (a security risk, a breaking change), put it
   in a single `Extra` section, never inline — only if `extras_section: yes`. When `extras_section` is
   no, omit it entirely. This rule states, once, the order that applies on every target: the `Extra`
   section comes first, then whichever other trailing content another rule licenses for this
   response; when rule 15's scope-guard flag also fires in the same response, that flag becomes the
   actual final line, after the Extra section and after any such other trailing content. Rule 2
   defers to this ordering rather than restating it.
8. Across turns in a task, open with a one-line recap — `Done: X. Now: Y.` — if `progress_recap:
   yes`. The recap is the lead line, not a substitute for the answer: the answer or next action that
   rule 1 requires follows immediately after the recap, on the next line, never folded into the same
   sentence.
9. If the user's message contains multiple questions, answer them as a numbered list matching their
   order. Never merge them into prose.
10. Confirm before switching topics (`confirm_topic_switch: yes`) only when the assistant itself is
    introducing the different topic, or the switch would abandon work that is still open and
    unfinished — ask a single yes/no question first. Do not ask when the user has already named the
    new topic themselves, even when that abandons open work: that request is the answer. When
    `confirm_topic_switch` is no, switch without asking either way. This does not remove rule 15's
    flag, which still applies to the same switch on its own terms.
11. Time estimates are concrete ("~10 min", "2 commands"), never vague ("shortly", "a few things").
12. Respond in `language` (or mirror the user when `auto`).
13. **Safety override:** these brevity rules never suppress warnings about destructive operations,
    security issues, or data loss. Clarity beats compression there. **This rule takes precedence over
    rules 1–12 and 16 wherever they conflict, explicitly including rule 7's `extras_section: no`
    gate** — a safety warning is never dropped because the Extra section is disabled.
14. **Checkpoint maintenance:** when a meaningful unit of work completes, update **this session's
    own** checkpoint file — `~/.squirrel/checkpoints/<project-slug>/<session-id>.md`, named for the
    model on the injected `Project checkpoint path:` line, to be used exactly as given and never
    computed, guessed, or re-derived; every other file in that slug directory belongs to another
    session and is left alone — **with no commentary in the response** — do
    not announce it, do not ask. At most **one write per turn**, and only when `Doing` or `Next`
    actually changed. Append finished items to the Done log, keeping the last 10. The file's shape is
    fixed so two sessions produce foldable files: `##` sections in the order `Doing` (one line),
    `Next` (the single startable step), `Open decisions` (only when there are any), `Done` (the
    finished items) — never a heading with nothing under it, omit the section instead. Read and
    written with the `Read` and `Write` tools, never a shell command: the `PreToolUse` matcher is an
    exact-string list (`Write|Edit|Read`), so only those carry the auto-approval, and a `Bash`
    heredoc — what the model reaches for when the rule is tool-agnostic — always prompts (ADR-0002).
    *Never describe this as happening without the user's knowledge. Tool calls are always visible in
    the transcript; what we promise is no prose about it, not invisibility (ADR-0002).* If the read
    or the write fails, say so in one line: a failure is reported, never absorbed silently, and that
    one-line report is not the commentary the paragraph above forbids. This report is the other
    trailing content rule 7's ordering makes room for: it falls after any Extra section rule 7
    produces and before rule 15's scope-guard flag, exactly where rule 7 says other rule-licensed
    trailing content goes. That only matters here, on Claude Code: neither this report nor a
    checkpoint exists on the other two targets.
15. **Scope guard:** when the conversation drifts from the declared task, flag it in exactly ONE
    line — e.g. `🐿️ This is drifting from <task>. Park it?` — and offer to park the tangent. Never
    lecture. Never refuse an explicit choice to continue. Flag the same drift only once. The rule
    must read correctly on all three targets, so it may not assume a checkpoint exists. This still
    applies when the user is the one who named the new topic, the case where rule 10 asks no
    confirmation; the flag rides along with the response to that topic, never delaying it. The flag
    is the final line of the response — an explicit, named exception to rule 2's postamble ban: rule
    2 permits exactly this one trailing line when this rule fires. When rule 7 also produces an
    Extra section in the same response, the flag follows it.
16. **Tone:** match `tone`. `neutral` is plain and unadorned. `warm` permits brief acknowledgement of
    effort or frustration — but **rule 2 wins structurally**: the acknowledgement must be fused into
    the same sentence as the answer or next action, never a sentence of its own preceding it. A warm
    opener that stands alone before the answer is preamble, and rule 2 forbids it regardless of
    `tone`. `terse` strips every non-essential word: fragments over sentences, no transitions. Tone
    never changes *what* is said, only its register, and never overrides rule 13: a safety warning
    keeps its full content regardless of `tone`.

### `/squirrel:init` — calibration

Hard requirements (chunked, low WM demand — Section 2). One question per message is a **design
choice**, not a research finding: "one topic at a time" is the recommendation Section 2 retires.

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
| 2 | **What breaks your focus most?** (see the value mapping below) | `step_style`, `explanation_budget`, `extras_section`, `tone` |
| 3 | Where should the answer go? | `answer_position` |
| 4 | Code first, or steps first? | `code_style` |
| 5 | How long a list before it stops helping? | `max_list_items` |
| 6 | One recommendation, or alternatives? | `options_per_answer` |
| 7 | Recap progress and confirm topic switches? | `progress_recap`, `confirm_topic_switch` |

**Question 2's value mapping is authoritative — do not improvise it.** The four answers describe
different *modes* of overwhelm, and each maps to a distinct combination. If two answers produced the
same values the question would be doing no work.

| Answer | Overwhelm mode | `step_style` | `explanation_budget` | `extras_section` | `tone` |
| :-- | :-- | :-- | :-- | :-- | :-- |
| **A** — long walls of text | volume | `checklist` | 1 | `no` | `terse` |
| **B** — jumps around, disorganized | structure | `numbered` | 3 | `yes` | `neutral` |
| **C** — too many options at once | decision load | `numbered` | 2 | `no` | `neutral` |
| **D** — stuck or frustrated, losing momentum | momentum | `numbered` | 3 | `no` | `warm` |

The reasoning, so a future edit does not undo it: A is drowning in words, so cut words and drop the
Extra section. B can handle content but needs scaffolding, so keep a normal budget and allow a clearly
labelled Extra — a reader who wants structure tolerates one more *labelled* section. C is paralysed by
choice, so `extras_section: no` — an Extra section is one more thing to evaluate, which is exactly the
load C is reporting. Answering C also strongly suggests `options_per_answer: 1` at question 6, but
question 6 asks that directly and its answer wins. D is the one mode where the material is not the
problem — the content lands, the momentum does not — so structure stays ordinary and `tone` is
`warm`, the only field that can acknowledge the friction; `extras_section: no` for the same reason as
C. **D is the only path to `warm` in the interview**: without it a third of `tone`'s value space
would be reachable through `/squirrel:tune` alone, which is not calibration.

`/squirrel:tune` exposes all 11 fields individually — that is where the long tail is discoverable.

### `/squirrel:tune`

Reads the current profile, shows current values, asks **one** question about what to change, rewrites
the file. Never re-runs the interview. Must be able to edit any of the 11 fields, including the four
that question 2 set as a bundle.

### `/squirrel:off` and `/squirrel:on`

`/squirrel:off` cannot learn its own session id, so it writes `~/.squirrel/off/PENDING.<token>` —
`<token>` being the opaque off-token injected at session start — and confirms in one line; the
`UserPromptSubmit` hook recomputes that token from the `session_id` it receives and renames the
sentinel to `~/.squirrel/off/<session_id>` on the next prompt. `/squirrel:on` writes the mirror,
`off/CLEAR.<token>`, which the same hook claims to remove the flag (ADR-0005 Amendment P2).
Suppression is delivered by the `UserPromptSubmit` hook, not by an
in-conversation instruction (ADR-0005). README documents `/plugin disable squirrel@squirrel-mode`,
then a new session, as the hard off.

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
<steps in the form set by `step_style` — `numbered` gives 1./2./3., `checklist` gives - [ ] items —
 each one independently actionable>
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
Phase 1 — <name> (expand fully, in the form set by `step_style`, respect max_list_items)
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

- Location: `~/.squirrel/checkpoints/<project-slug>/<session-id>.md` — one file per session inside
  a per-project slug directory, slug derived from the project directory path. Never inside the
  project repo.
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
## Done
- <date>: <one-line win>   (last 10 kept)
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

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **8** namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `~/.cursor/skills/squirrel-<name>/SKILL.md`, machine-wide, explicit invocation only | no | no |

**Which commands port, and why the other four cannot.**

| Command | Claude Code | Codex | Cursor | Reason |
| :-- | :-- | :-- | :-- | :-- |
| `digest` | ✅ | ✅ | ✅ | Pure prose transformation. Needs nothing from the host. |
| `plan` | ✅ | ✅ | ✅ | Same. |
| `init` | ✅ | ✅ | ❌ | Writes `~/.squirrel/profile.md`. Codex can run shell commands; Cursor's commands are project-scoped, so a user-level install has nowhere to live. |
| `tune` | ✅ | ✅ | ❌ | Same as `init`. |
| `pickup` | ✅ | ❌ | ❌ | Needs the checkpoint path injected by a hook. Recomputing the slug is forbidden — that is the drift failure ADR-0003 and the S5 review both hit. |
| `off` / `on` | ✅ | ❌ | ❌ | The sentinel is claimed by a `UserPromptSubmit` hook. No hook, no claim, and nothing to turn off anyway: Codex users edit `AGENTS.md`, Cursor users flip `alwaysApply` or delete the `.mdc`. |
| `rules` | ✅ | ❌ | ❌ | Pulls the base rules back into one conversation after the forced output style has been turned off. Neither other target has an output style to turn off, so there is nothing to recover from: the rules are a block in `AGENTS.md` or a `.mdc` file, restored by editing the file, not by a command. |

One consequence worth stating plainly in `docs/OTHER-TOOLS.md`: because all three targets read the
**same** `~/.squirrel/profile.md`, running `/squirrel:init` once in Claude Code or Codex
calibrates every target on that machine — including Cursor, which cannot run the interview itself.

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
      to `~/.squirrel/profile.md`. Question 2 sets four fields.
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
- [ ] Checkpoints are written to `~/.squirrel/checkpoints/` with **no permission prompt and no
      prose in the response**, at most once per turn. `/squirrel:pickup` opens with recent wins, then
      Doing/Next/Open decisions, then stops.
- [ ] Uninstalling the plugin leaves `~/.squirrel/` intact; reinstalling restores the profile
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
- [ ] Parallel Claude Code sessions in the same project do not lose each other's checkpoint Done-log
      entries (per-session checkpoint files).
- [ ] `/squirrel:off` in one session does not suppress a different session sharing the same cwd
      (token-bound pending claim).
- [ ] A `/squirrel:tune` that finishes writing `~/.squirrel/profile.md` becomes visible to another
      already-open Claude Code session on a later UserPromptSubmit without restart.

## 6. NON-GOALS (v0.1)

- No timers, alarms, activity monitoring, or nudge systems — anything requiring a background process
  is out (see ravila4/claude-adhd-skills and the Tether paper for that niche; link both in README as
  complementary). Checkpoints are passive markdown files, not a task manager.
- No per-project profile overrides.
- No shaping of subagent output — output styles apply to the main conversation only (ADR-0001).
- No GUI. Markdown and commands only.
