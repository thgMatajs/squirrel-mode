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

## The ten commands

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
| `/squirrel:stash` | Records one durable memory — a correction, a decision, a bug and its fix — in your cross-project hoard. Costs one permission prompt: the memory write itself is auto-approved, but the `date` command that stamps it is a `Bash` call, and this plugin registers no hook that runs on one. |
| `/squirrel:dig` | Searches that hoard and shows ranked titles, then fetches only the one you open; `--all` also searches superseded memories. Costs one permission prompt for the search and a second for that same `date` stamp when you open a memory — both `Bash` calls, for the same reason. |

All ten exist on Claude Code. Codex gets `digest`, `plan`, `init`, and `tune`. Cursor gets
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

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints | Hoard |
| :-- | :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **10** namespaced skills | `SessionStart` hook | `PreToolUse` hook | `stash` + `dig` |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `~/.cursor/skills/squirrel-<name>/SKILL.md`, machine-wide, explicit invocation only | no | no | no |

The hoard's own files are plain markdown under `~/.squirrel/`, so any target can read them; what
Codex and Cursor lack is the two commands, which is what this phase ships and only for Claude Code.
Porting them is not a copy: both name the `Write` and `Read` tools explicitly because those are what
Claude Code's auto-approval covers, and a Codex or Cursor variant has neither that tool nor that
auto-approval, so those sentences have to be rewritten rather than carried across.

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
- `hoard/global/<id>.md`, `hoard/projects/<slug>/<id>.md` — durable memories. One file per memory.
  `/squirrel:stash` writes them, `/squirrel:dig` reads them, and **both also edit memories that
  already exist**, which is the part of this that is easiest to miss. Opening a memory through
  `/squirrel:dig` adds 1 to its `uses` and sets its `last_used` to now, so a memory you keep
  consulting holds its rank and one nobody opens sinks on its own. Only your opening one counts;
  appearing in a result list does not. And when a fact changes, `/squirrel:stash` writes the new
  memory and then sets `status: superseded` and `superseded_by:` on the old one. Neither path ever
  rewrites a title or a body, and neither deletes anything: the superseded version stays on disk and
  is still findable with `/squirrel:dig --all`. A memory goes to `projects/<slug>/` only when this
  session injected a checkpoint path that qualifies; otherwise it goes to `global/`, and
  `/squirrel:stash` says which in its one-line confirmation. These are the only files squirrel-mode
  writes that are meant to outlive the project they were written in.

Installs from before this location moved have their data at an older path instead — see the note at
the end of this section; squirrel-mode detects that and tells you, once per session, rather than
moving it for you.

**Your `profile.md` is quoted back into the model's context, and one class of line is marked when it
is.** squirrel-mode appends its own lines after that quoted text — the checkpoint path, the hoard
search command, the session off-token — and a line of yours that COULD otherwise begin exactly the
way one of those does gets `[profile] ` put in front of it before the model sees it, so it cannot be
read as squirrel-mode's own ([ADR-0008](./docs/adr/0008-hoard-auto-allow.md)). Nothing is deleted
and nothing is reworded: the marker exists only in the injected copy, and the file on disk stays
byte for byte what `/squirrel:init` and `/squirrel:tune` wrote.

**It also deletes, on its own, at session start.** Three prunes run in `scripts/load-profile.sh`, and
only there — never on an ordinary message:

- Off/on sentinels older than 7 days, and `profile-seen` markers older than 7 days. Both are
  per-session scraps that are worthless once their session ends; 7 days is a deliberately generous
  cushion so no realistically long-lived session loses its own live one.
- Checkpoint files, on a much narrower rule, because losing one loses work you cannot get back: a
  file is deleted only if it is **both** older than 30 days **and** not among the 10 most recently
  modified checkpoints for that project. However long a project lies untouched, its ten newest
  checkpoints always survive. At most 100 candidates are examined per session start, so a huge
  directory cannot stall the hook.

**Memories are never pruned.** Nothing under `hoard/` is deleted by squirrel-mode, on any schedule,
at any age. Losing a memory loses something that cannot be reconstructed, and a memory that has lost
its relevance already stops appearing in results by its own score — which is reversible, and deletion
is not.

**Search reads every memory file on each run, with no index.** Measured on the author's machine, a
query costs about 44 ms at 500 memories, 79 ms at 1000, and 155 ms at 2000. Re-measured
independently on that machine, those totals hold — 42, 81 and 159 ms — but the split this paragraph
used to publish does not. At the 2000-memory size the `awk` pass over every file's frontmatter is
about half of the run, not the 71% the old 110-of-155 figure implied; most of the rest is the shell
enumerating the files and checking them one stat at a time.

**That half is the whole of what survived re-measurement, and a finer breakdown has been withdrawn
rather than corrected.** A per-phase split used to be published here. It was taken against a fixture
whose path length was never written down, and path length is exactly the parameter
`scripts/hoard-search.sh` already records as moving its own timings by a large factor — the same 2000
files cost 14.67 s under paths of 176 bytes and 24.08 s under paths of 292. Without that number
stated, nobody else can reproduce a split, so none is claimed. And even the half is a fact about one
machine's toolchain rather than about the design: swapping in a different `awk` on the same fixture
moves it far enough in both directions to change whether that pass is most of a search or a minority
of it. [docs/specs/2026-08-13-hoard-design.md](./docs/specs/2026-08-13-hoard-design.md) §5.1 carries
the method, and says which figures it stands behind and which it withdrew.

The cost of a search did not start out this low. The same query cost 12.08 s at 2000 until the list of
files handed to `awk` stopped being assembled one file at a time: appending a file to that list
rebuilds the whole list, so building it cost O(n²) rather than O(n). Assembling each layer's files in
one step instead took that phase from 12.05 s to 42 ms and left the results byte-identical. Three
sizes on one machine say where the cost sits at those sizes, not how far it goes; if search ever
starts to feel slow, these are the numbers to compare against.

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
one of those three skips the prompt. `hooks/hooks.json` registers this plugin's `PreToolUse` hook for
those three names and nothing else, so no hook of this plugin's is ever invoked for a `Bash` call and
none of them can auto-approve one — a checkpoint written with a heredoc instead goes through the
normal permission flow, a prompt, in an interactive session.

**That is this plugin's own configuration, and not a limit of Claude Code.** A `PreToolUse` hook may
match `Bash` and may answer `permissionDecision: "allow"`; squirrel-mode declines to register one,
because auto-approving `Bash` means approving a tool whose argument is an arbitrary command string,
while everything that makes this hook defensible rests on normalising one field,
`tool_input.file_path`, against one directory this plugin owns
([ADR-0002](./docs/adr/0002-checkpoint-auto-allow.md)). Every prompt count on this page follows from
that choice rather than from something Claude Code makes impossible.

`/squirrel:pickup` names the `Read` tool explicitly; the base
rule that keeps a checkpoint current names the `Read` and `Write` tools and rules out a shell command
in as many words. Neither is worded tool-agnostically any more.

**That is an instruction, not enforcement, and the difference is worth stating.** The matcher decides
which tool calls are auto-approved, never which tool gets called: nothing in the harness stops a model
from reaching for a `Bash` heredoc against the checkpoint anyway, and this plugin has registered no
hook that would run on it if it did. What has been watched live is the tool-agnostic wording, not this one — `/squirrel:init`,
`/squirrel:tune`, `/squirrel:off` and `/squirrel:on` still say "write" or "create" without naming a
tool, and a live run recorded the model reaching for a `Bash` heredoc first there, then retrying with
`Write` and saying so in one line (`docs/ACCEPTANCE.md`, Live-sweep finding 3 — observed on those
four, never on the checkpoint rule itself). Should a checkpoint write ever go that way, the cost is
the same as it was there: one permission prompt and one extra line of report, not a lost checkpoint.

The auto-approval decides about the path as a **name**, at the moment the hook is asked, and it
refuses two shapes rather than approving them. The first is a symlink: a symlink at
`checkpoints/` itself, or anywhere below it, is never auto-approved — that write falls back to the
normal permission prompt instead of being silently redirected through the symlink.

The second is a hard link, and it is the reason the sentence above says *name* rather than *resolves
inside that directory*, which is how this paragraph used to put it. An existing file inside
`checkpoints/` that some other name also points at is never auto-approved either — for any tool,
`Read` included — even though nothing about its own path leads anywhere else.
`ln ~/.ssh/id_rsa ~/.squirrel/checkpoints/proj/x.md` gives a private key a second name inside the
directory, and until that refusal landed a read of that name returned the key and a write overwrote
it, both without a prompt. What is tested is the file's link count, only where the answer would
otherwise already be `allow`, and the test needs `find` on `PATH`: with `find` missing, that one
refusal does not run and the hard link is auto-approved again
([ADR-0008](./docs/adr/0008-hoard-auto-allow.md) records that limit).

The same auto-approval covers `~/.squirrel/hoard/`, on the same terms and through the same layers
([ADR-0008](./docs/adr/0008-hoard-auto-allow.md)) — the same `..` rejection, the same length cap,
the same prefix check, the same symlink walk, applied to whichever of the two directories the path
resolved into. A symlink at `hoard/` itself, or anywhere below it, falls back to the normal
permission prompt exactly as one at `checkpoints/` does. Two things are stricter for the hoard, and
both add refusals rather than removing any: a file sitting directly inside `hoard/` rather than one
level down is refused auto-approval for every tool, `Read` included, and a `Write` or `Edit` whose
text looks like it carries a credential is refused too — that write falls back to the normal
permission prompt and you decide, rather than going through without one.

**What that auto-approval does not buy, stated as a number rather than left to be discovered.** It
covers the file operations and nothing else, and both hoard commands need one thing that is not a
file operation: a UTC timestamp, built by running `date -u +%Y%m%dT%H%M%SZ`. That is a `Bash` call,
and the matcher above holds for it unchanged — `Write|Edit|Read` does not name `Bash`, so this
plugin's hook never runs on it — so it goes through the normal permission flow. Both counts below are
therefore facts about how squirrel-mode is configured, not about what Claude Code permits: they would
change if this plugin registered a different hook, which the paragraph above says why it does not. In
an interactive session the true cost is
**one prompt for a `/squirrel:stash`** (the memory write is auto-approved; the stamp is not) and
**two for a `/squirrel:dig` you open a memory from** — one for the search script, which is also a
`Bash` call, and one for the stamp the `uses`/`last_used` edit needs. The read and the edit
themselves are auto-approved. What ADR-0008 buys is that the writes are silent, not that the
commands are.

That credential check matches unambiguous shapes only — private-key headers, a handful of provider
token prefixes, and one `key = <long opaque string>` rule — and **it is not a complete secret
scanner.** It also has the opposite failure: any memory whose text merely mentions one of those
prefixes, including a memory about this feature, will ask for permission it did not need. That
costs one prompt and never a refusal to write, which is the trade it was tuned for. ADR-0008 states
exactly what it does and does not catch, including what stops working when `grep` is missing.

The auto-approval requires `jq` to be installed and on `PATH`. A regex cannot safely parse nested
JSON, so on a machine without `jq` the hook never guesses — every checkpoint and hoard read and
write falls back to the normal permission prompt instead. This is a deliberate, graceful fallback,
not a crash; `jq` is already a hard prerequisite for this project's own test suite.

The base rules that trigger these writes also cap them at one checkpoint write per turn. Those two
directories are the whole of what is auto-approved; full rationale in
[ADR-0002](./docs/adr/0002-checkpoint-auto-allow.md) and
[ADR-0008](./docs/adr/0008-hoard-auto-allow.md).

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
