# squirrel-mode 🐿️

ADHD-friendly AI responses for Claude Code, Codex, and Cursor: answer first, numbered steps, no
filler, calibrated to how you personally process text.

Built for people with ADHD, and for anyone who wants a direct answer over padded prose.

It changes response *shape* — never what the assistant tells you to do, and never its coding
behavior.

## Install

### Claude Code

1. `/plugin marketplace add thgMatajs/squirrel-mode`
2. `/plugin install squirrel@squirrel-mode` — the install summary tells you whether the plugin is
   already active (`Plugin is now active.`) or needs `/reload-plugins` first (`Run /reload-plugins
   to activate.`).
3. Start a new session. The base rules load as an output style with `force-for-plugin: true` — no
   `/config` step — and a new session is the one thing this repo can promise makes that happen.

Testing a local checkout instead of the marketplace: `claude --plugin-dir /path/to/squirrel-mode`.

**First message, fresh install:** with no profile yet, squirrel-mode suggests `/squirrel:init`
once, in one line, then waits — it never starts the interview on its own.

**Checking it's active:** run `/config` — `squirrel-mode` should show as the current output style.
If it doesn't, run `/clear` or start a new session; the style loads at session start, not
mid-conversation, so editing rules first is the wrong place to look.

**Uninstalling:** see [Privacy and what it writes](#privacy-and-what-it-writes) below.

### Codex

```sh
targets/codex/install.sh          # dry run - shows what would change
targets/codex/install.sh --yes    # actually install
```

Adds a delimited block to `~/.codex/AGENTS.md` and four skills under `~/.agents/skills/`. Dry-run
by default, POSIX `sh`, never touches a project repository. Full detail, and what Codex loses
compared to Claude Code, in [docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md).

### Cursor

```sh
targets/cursor/install.sh          # dry run
targets/cursor/install.sh --yes    # actually install
```

Adds `~/.cursor/rules/squirrel-mode.mdc`. `/digest` and `/plan` still need copying by hand into
each project's `.cursor/commands/` — [docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md) has the two
file paths and why Cursor can't install them once for every project.

## The seven commands

| Command | What it does |
| :-- | :-- |
| `/squirrel:init` | Runs the seven-question calibration interview and writes your profile. |
| `/squirrel:tune` | Changes one profile field without repeating the interview. |
| `/squirrel:digest` | Restructures a rambling ticket, email, pasted note, file, or Jira issue into a fixed TL;DR, Next action, Breakdown, Priority, and Open questions / blockers brief; `--for-reply` adds a copy-paste reply. |
| `/squirrel:plan` | Converges a messy idea dump into a scoped plan with one first action and a parking lot for tangents. |
| `/squirrel:pickup` | Shows recent wins, what you were doing, the next action, and open decisions from this project's checkpoint, then stops. |
| `/squirrel:off` | Turns the base rules off for the rest of the current session. |
| `/squirrel:on` | Turns them back on in the current session. |

All seven exist on Claude Code. Codex gets `digest`, `plan`, `init`, and `tune`. Cursor gets
`digest` and `plan` only — see the parity table below for why.

## Parity across targets

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **7** namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `.cursor/commands/*.md`, project-scoped | no | no |

Codex and Cursor have no lifecycle hooks, so neither gets automatic checkpoints, and neither has
a harness-level guarantee against the model starting `/squirrel:init` on its own the way Claude
Code's `disable-model-invocation: true` does. All three targets read the same
`~/.squirrel/profile.md`, so running `/squirrel:init` once, in Claude Code or Codex,
calibrates every target on that machine. Full breakdown — which commands port and why, what each
target loses — in [docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md).

## Why it's shaped this way

10 of the 16 base rules trace to a specific research finding, verified against its own source and
tagged by the population it was actually measured in. The other 6 rules are stated design
decisions — product and ergonomic choices, not empirical claims — named as such in
[docs/RESEARCH.md](./docs/RESEARCH.md#rules-with-no-research-claim-behind-them), which is also the
full evidence base and citation policy.

Four of the findings:

- Working memory holds only a handful of items at once and drops old ones when new information
  arrives. `general working memory` → numbered steps, one concept per paragraph, a capped list
  length.
- Adolescents and young adults with ADHD show a sharper drop in working-memory accuracy as
  demands increase than neurotypical peers do. `ADHD` → never more than one decision offered per
  answer by default — tunable via `options_per_answer`.
- Software engineers with ADHD report losing track of what they were doing after an interruption.
  `ADHD` → automatic checkpoints and `/squirrel:pickup` make resuming cost seconds instead of a
  full reconstruction.
- Separately, higher ADHD-symptom scores in a non-clinical sample were associated with stronger
  recall of negative material than positive. `ADHD` → the Done log opens with recent wins first,
  on purpose, rather than leaving that to happen on its own.

Nothing here restates a finding beyond what its own citation actually supports — see
docs/RESEARCH.md's "Corrections" section for what got cut when a citation didn't hold up.

## Privacy and what it writes

No network calls. No telemetry. Every script squirrel-mode ships is plain POSIX `sh` or Markdown.

The Claude Code plugin's runtime writes to exactly one place: `~/.squirrel/` — your `profile.md`,
and one checkpoint file per session under `checkpoints/<slug>/`. Installs from before this location
moved have their data at an older path instead — see the note at the end of this section;
squirrel-mode detects that and tells you, once per session, rather than moving it for you.

The Codex and Cursor installers are a separate, one-time step: they write to the per-target
directories already listed above (`~/.codex/AGENTS.md`, `~/.agents/skills/`, `~/.cursor/rules/`).
Nothing, on any target, is ever written inside a project repository.

`/plugin uninstall squirrel@squirrel-mode` removes the Claude Code plugin.

Uninstalling — or reinstalling — leaves `~/.squirrel/` alone: your profile and checkpoints
survive independently of the plugin's install state
([ADR-0003](./docs/adr/0003-profile-outside-plugin-data.md)).

One exception to the normal permission flow: a `PreToolUse` hook auto-approves the plugin's own
reads and writes inside `~/.squirrel/checkpoints/` — both the read a checkpoint interaction
starts with (`/squirrel:pickup`, and rule 14's own update path checking what is already logged) and
the write that follows it — so neither one is meant to interrupt the task to ask for permission.
Each is still a tool call like any other and shows up in the transcript the same way every other
tool call does — what's skipped is the permission prompt and any commentary about it in the
response, not the read or write itself.

The auto-approval only covers paths that genuinely resolve inside that directory: a symlink at
`checkpoints/` itself, or anywhere below it, is never auto-approved — that write falls back to the
normal permission prompt instead of being silently redirected through the symlink.

The auto-approval requires `jq` to be installed and on `PATH`. A regex cannot safely parse nested
JSON, so on a machine without `jq` the hook never guesses — every checkpoint read and write falls
back to the normal permission prompt instead. This is a deliberate, graceful fallback, not a crash;
`jq` is already a hard prerequisite for this project's own test suite.

The base rules that trigger these writes also cap them at one checkpoint write per turn. Nothing
else is auto-approved; full rationale in [ADR-0002](./docs/adr/0002-checkpoint-auto-allow.md).

squirrel-mode replaces your Claude Code output style while it's enabled. `keep-coding-instructions:
true` keeps its coding behavior untouched, but Explanatory or Learning mode is overridden for as
long as the plugin is on.

`/squirrel:off` suspends the base rules for one session. `/plugin disable squirrel@squirrel-mode`,
then a new session, removes them from the system prompt entirely — the hard off. `/reload-plugins`
alone does not reliably drop the output style: its documented reload list never names output
styles. (`/plugin disable` opens the plugin panel and leaves it open; press Esc before typing the
next command.)

`/squirrel:off` and `/squirrel:on` take effect starting with your next message, not the one you
just sent: both write a sentinel that a hook claims on the next prompt, not immediately.

Running two Claude Code sessions in the exact same project directory narrows this to a
one-prompt-wide race: whichever session sends the next prompt in that directory claims the
sentinel — and that can be the *other* session, not the one that ran the command.

`/squirrel:on` only clears the claiming session's own suppression flag. A CLEAR sentinel claimed
by the wrong session is consumed — deleted — without effect on the other one, so if a different
session is the one actually suppressed, it stays suppressed until its own next prompt claims a
fresh `/squirrel:on`, or until the flag ages out after 7 days.

**On the data directory having moved.** Versions before this one kept this data inside Claude
Code's own config directory, on the theory that a plugin hook could auto-approve writes there the
same way it does anywhere else. It cannot: Claude Code treats that directory as a protected path,
and that check runs before any hook's `allow` is even considered, so the exact promise this section
makes — a checkpoint update that never stops to ask — could never actually hold at the old location.
`~/.squirrel/` sits outside it, and the same auto-approval mechanism works there for real; see
[ADR-0002](./docs/adr/0002-checkpoint-auto-allow.md)'s and
[ADR-0003](./docs/adr/0003-profile-outside-plugin-data.md)'s S11 amendments for the exact old path,
the experiment that found the problem, and the reasoning behind the move. If your old data is still
there, squirrel-mode notices and tells you once per session; it never moves it for you.

## Related, and out of scope

No background process, no activity monitoring, no nudges or timers — deliberately out of scope,
not a missing feature. For that heavier category:

- [Tether](https://arxiv.org/abs/2509.01946) `ADHD` — an academic prototype combining activity
  monitoring, retrieval-augmented generation, and gamification for developers with ADHD.
- [ravila4/claude-adhd-skills](https://github.com/ravila4/claude-adhd-skills) — nudge- and
  timer-based skills for Claude Code.

## License

MIT — see [LICENSE](./LICENSE).
