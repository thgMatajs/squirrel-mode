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

Run Codex at least once first — it creates `~/.codex` on first run, and the installer needs that
directory to exist. Then clone this repository; the installer reads its sources from a checkout.

```sh
git clone https://github.com/thgMatajs/squirrel-mode
cd squirrel-mode
targets/codex/install.sh          # dry run - shows what would change
targets/codex/install.sh --yes    # actually install
```

Adds a delimited block to `~/.codex/AGENTS.md` and four skills under `~/.agents/skills/`. Dry-run
by default, POSIX `sh`, never touches a project repository. `targets/codex/install.sh --uninstall`
reverses it, on the same dry-run-by-default terms. Full detail, and what Codex loses
compared to Claude Code, in [docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md).

### Cursor

Open Cursor at least once first — it creates `~/.cursor` on first run, and the installer needs that
directory to exist. Then clone this repository; the installer reads its sources from a checkout.

```sh
git clone https://github.com/thgMatajs/squirrel-mode
cd squirrel-mode
targets/cursor/install.sh          # dry run
targets/cursor/install.sh --yes    # actually install
```

Adds `~/.cursor/rules/squirrel-mode.mdc` (the always-on base rules) and two Cursor Agent Skills at
`~/.cursor/skills/squirrel-digest/SKILL.md` and `~/.cursor/skills/squirrel-plan/SKILL.md`, invoked as
`/squirrel-digest` and `/squirrel-plan` in every project on the machine.
`targets/cursor/install.sh --uninstall` removes all three again, on the same dry-run-by-default
terms. Cursor's project-scoped `/digest` and `/plan` commands are a separate mechanism and still have
to be copied into a project's own `.cursor/commands/` if you want them there too —
[docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md) has the two file paths.

## The eight commands

| Command | What it does |
| :-- | :-- |
| `/squirrel:init` | Runs the seven-question calibration interview and writes your profile. |
| `/squirrel:tune` | Changes one profile field without repeating the interview. |
| `/squirrel:digest` | Restructures a rambling ticket, email, pasted note, file, or Jira issue into a fixed TL;DR, Next action, Breakdown, Priority, and Open questions / blockers brief; `--for-reply` adds a copy-paste reply. |
| `/squirrel:plan` | Converges a messy idea dump into a scoped plan with one first action and a parking lot for tangents. |
| `/squirrel:pickup` | Shows recent wins, what you were doing, the next action, and open decisions from this project's checkpoint, then stops. |
| `/squirrel:off` | Turns the base rules off for the rest of the current session. |
| `/squirrel:on` | Turns them back on in the current session. |
| `/squirrel:rules` | Pulls the base rules into the current conversation by hand. A recovery path only — see below. |

All eight exist on Claude Code. Codex gets `digest`, `plan`, `init`, and `tune`. Cursor gets
`digest` and `plan` only — see the parity table below for why. On Cursor they are `/squirrel-digest`
and `/squirrel-plan`: Cursor has no command namespace, so the prefix is part of the name.

**`/squirrel:rules` is a recovery path, not part of the normal flow.** The base rules are already in
the system prompt on every turn, carried by the forced output style
([ADR-0001](./docs/adr/0001-output-style-not-skill.md)) — so there is normally nothing to load. This
command exists for the case where that style has been turned off and you want the rules back in one
conversation without turning it on again. Typed while the style is still active, it loads a second
copy of the same ~12 KB of rules and tells Claude nothing it did not already have. It never fires on
its own: `disable-model-invocation: true` stops Claude from reaching for it, so it runs only when you
type it.

## Parity across targets

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **8** namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `~/.cursor/skills/squirrel-<name>/SKILL.md`, machine-wide, explicit invocation only | no | no |

Codex and Cursor have no lifecycle hooks, so neither gets automatic checkpoints, session-scoped
off/on, or profile reinjection after a tune — a change elsewhere can leave their view stale until
their own cadence re-reads the file. Claude Code isolates concurrent sessions (one checkpoint file
per session, token-bound off/on) and reinjects an updated profile on the next prompt; see
[ADR-0006](./docs/adr/0006-session-isolation-concurrency.md). Neither Codex nor Cursor can run the
calibration interview at all, so the question of the model starting it unprompted does not arise
there. Codex has no `disable-model-invocation` equivalent of any kind; Cursor's Agent Skills do
support it, and squirrel-mode sets it on both skills it installs, so `/squirrel-digest` and
`/squirrel-plan` never fire on their own. All three targets read the same
`~/.squirrel/profile.md`, so one calibration run — `/squirrel:init` in Claude Code, or asking Codex
in plain language to run squirrel init — calibrates every target on that machine. Full breakdown —
which commands port and why, what each target loses — in
[docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md).

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

The Claude Code plugin's runtime writes to exactly one place — `~/.squirrel/` — and, inside it, to
exactly five kinds of file:

- `profile.md` — your calibration, written by `/squirrel:init` and edited by `/squirrel:tune`.
- `checkpoints/<slug>/<session-id>.md` — one checkpoint file per session
  ([ADR-0006](./docs/adr/0006-session-isolation-concurrency.md)).
- `off/PENDING.<token>`, `off/CLEAR.<token>`, and `off/<session-id>` — the sentinels `/squirrel:off`
  and `/squirrel:on` leave for the next prompt's hook to claim, and the flag a claimed `PENDING`
  becomes. The hook consumes each sentinel as it claims it; claiming a `CLEAR` removes the flag too.
- `profile-seen/<session-id>` — an empty marker whose timestamp is all that matters: it is how a
  session knows whether it has already been shown the current `profile.md`, and it is what makes a
  `/squirrel:tune` in one session reach the others.
- `prune-cursor` — one line naming the last project directory the checkpoint sweep below looked at,
  so the next session start resumes where it stopped instead of always restarting at the same place.
  Nothing reads it but the sweep, and losing it costs nothing.

Installs from before this location moved have their data at an older path instead — see the note at
the end of this section; squirrel-mode detects that and tells you, once per session, rather than
moving it for you.

**It also deletes, on its own, at session start.** The prunes all run in `scripts/load-profile.sh`,
and only there — never on an ordinary message:

- Off/on sentinels older than 7 days, and `profile-seen` markers older than 7 days. Both are
  per-session scraps that are worthless once their session ends; 7 days is a deliberately generous
  cushion so no realistically long-lived session loses its own live one.
- Checkpoint files, on a much narrower rule, because losing one loses work you cannot get back: a
  file is deleted only if it is **both** older than 30 days **and** not among the 10 most recently
  modified checkpoints for that project. However long a project lies untouched, its ten newest
  checkpoints always survive. At most 100 candidates are examined per session start, so a huge
  directory cannot stall the hook.
- The same checkpoint rule, applied to **every** project rather than only the one you are opening.
  Otherwise a project you stop working on keeps every checkpoint it ever had, forever, and
  `~/.squirrel/checkpoints/` grows without bound across abandoned projects. The count that matters
  is always **within one project**: ten newest *per project*, never ten newest overall, so a rarely
  touched project never loses its memory because a busy one has newer files. This sweep is
  deliberately bounded — it looks at no more than 100 project directories and spends no more than
  200 filesystem probes per session start (measured worst case on a Mac: under a second, against
  tens of milliseconds for an ordinary machine), and it resumes where it left off next time rather
  than starting over, so every project is reached within a few sessions without any one session
  start doing all the work.
- Project directories under `checkpoints/` that are **completely empty**, which is the other half of
  the same growth: one directory per project you ever opened, kept forever. Only genuinely empty
  directories are removed, and never one that still holds a checkpoint.

Nothing else in `~/.squirrel/` is ever deleted by squirrel-mode, and `profile.md` never is.

The Codex and Cursor installers are a separate, one-time step: they write to the per-target
directories already listed above (`~/.codex/AGENTS.md`, `~/.agents/skills/`, `~/.cursor/rules/`,
`~/.cursor/skills/`).
Nothing, on any target, is ever written inside a project repository.

`/plugin uninstall squirrel@squirrel-mode` removes the Claude Code plugin.

Uninstalling — or reinstalling — leaves `~/.squirrel/` alone: your profile and checkpoints
survive independently of the plugin's install state
([ADR-0003](./docs/adr/0003-profile-outside-plugin-data.md)). That is a statement about install
state, not about the session-start pruning above, which keeps running for as long as the plugin is
installed.

One exception to the normal permission flow: a `PreToolUse` hook auto-approves the plugin's own
reads and writes inside `~/.squirrel/checkpoints/` — both the read a checkpoint interaction
starts with (`/squirrel:pickup`, and rule 14's own update path checking what is already logged) and
the write that follows it — so neither one is meant to interrupt the task to ask for permission.
Each is still a tool call like any other and shows up in the transcript the same way every other
tool call does — what's skipped is the permission prompt and any commentary about it in the
response, not the read or write itself.

**That guarantee is exactly as wide as the hook's matcher, and every instruction that touches a
checkpoint now names a tool the matcher covers.** The matcher is `Write|Edit|Read`: three exact tool
names, not a pattern that also catches things containing them. A checkpoint read or write made with
one of those three skips the prompt. A `Bash` call cannot be auto-approved by any hook, at any path,
so one that writes a checkpoint file with a heredoc instead goes through the normal permission flow —
a prompt, in an interactive session. `/squirrel:pickup` names the `Read` tool explicitly; the base
rule that keeps a checkpoint current names the `Read` and `Write` tools and rules out a shell command
in as many words. Neither is worded tool-agnostically any more.

**That is an instruction, not enforcement, and the difference is worth stating.** The matcher decides
which tool calls are auto-approved, never which tool gets called: nothing in the harness stops a model
from reaching for a `Bash` heredoc against the checkpoint anyway, and no hook could auto-approve it if
it did. What has been watched live is the tool-agnostic wording, not this one — `/squirrel:init`,
`/squirrel:tune`, `/squirrel:off` and `/squirrel:on` still say "write" or "create" without naming a
tool, and a live run recorded the model reaching for a `Bash` heredoc first there, then retrying with
`Write` and saying so in one line (`docs/ACCEPTANCE.md`, Live-sweep finding 3 — observed on those
four, never on the checkpoint rule itself). Should a checkpoint write ever go that way, the cost is
the same as it was there: one permission prompt and one extra line of report, not a lost checkpoint.

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
alone is not a substitute for that, but not for the reason this paragraph used to give. Claude Code's
plugins reference does name `output-styles/` among the components `/reload-plugins` picks up — so the
old claim that its reload list never mentions output styles was wrong. What that sentence covers is
reloading a component's *content*; it says nothing about deactivating a style already applied to the
running session, and this repo has not tested whether it does. A new session is the trigger that can
actually be promised here, which is why it is the one documented above. (`/plugin disable` opens the
plugin panel and leaves it open; press Esc before typing the next command.)

`/squirrel:off` and `/squirrel:on` take effect starting with your next message, not the one you
just sent: both write a sentinel that a hook claims on the next prompt, not immediately.

Each sentinel is named with an opaque session token injected at session start, so two Claude Code
sessions in the same project directory do not steal each other's off/on request. The claiming hook
matches that token to the session id it receives — not whichever session happens to prompt first
([ADR-0005 Amendment P2](./docs/adr/0005-session-flag-off-switch.md),
[ADR-0006](./docs/adr/0006-session-isolation-concurrency.md)).

`/squirrel:on` only clears this session's own suppression flag. After `/squirrel:tune`, Claude Code
reinjects the updated profile into other open Claude sessions on their next prompt; Codex and Cursor
do not get that reinjection ([docs/OTHER-TOOLS.md](./docs/OTHER-TOOLS.md)).

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
