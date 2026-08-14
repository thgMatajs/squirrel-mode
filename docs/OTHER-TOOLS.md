# squirrel-mode on Codex and Cursor

squirrel-mode's primary home is Claude Code — that is where every feature exists. This document is
for deciding whether to also install it on Codex or Cursor, and for the exact steps to do so. Read
[ADR-0004](./adr/0004-tiered-parity-across-targets.md) for why the three targets cannot offer the same
feature set; this page states the practical consequences plainly, with no hedging.

## Parity at a glance

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints | Hoard |
| :-- | :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **10** namespaced skills | `SessionStart` hook | `PreToolUse` hook | `stash` + `dig` |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `~/.cursor/skills/squirrel-<name>/SKILL.md`, machine-wide, explicit invocation only | no | no | no |

## Which commands port, and why the other six cannot

| Command | Claude Code | Codex | Cursor | Reason |
| :-- | :-- | :-- | :-- | :-- |
| `digest` | ✅ | ✅ | ✅ | Pure prose transformation. Needs nothing from the target. |
| `plan` | ✅ | ✅ | ✅ | Same. |
| `init` | ✅ | ✅ | ❌ | Writes `~/.squirrel/profile.md`. Codex can run shell commands. No Cursor artifact is built for this one: the reason recorded when the port set was settled — Cursor had no user-level place to install a command — stopped being true when Agent Skills landed, since `~/.cursor/skills/` is exactly that. What has *not* been established is whether a Cursor Agent Skill can write that file at all, so it stays unported rather than shipped on an assumption. |
| `tune` | ✅ | ✅ | ❌ | Same as `init`. |
| `pickup` | ✅ | ❌ | ❌ | Needs the checkpoint path injected by a hook. Recomputing the slug is forbidden — that is the drift failure ADR-0003 and the S5 review both hit. |
| `off` / `on` | ✅ | ❌ | ❌ | The sentinel is claimed by a `UserPromptSubmit` hook. No hook, no claim, and nothing to turn off anyway: Codex users edit `AGENTS.md`, Cursor users flip `alwaysApply` or delete the `.mdc`. |
| `stash` | ✅ | ❌ | ❌ | Not built for either target in phase 1 of the hoard, and porting it is a rewrite rather than a copy. It writes a memory with Claude Code's `Write` tool, which it names explicitly because that is what the `PreToolUse` hook auto-approves — a memory write therefore costs no permission prompt there. Neither other target has that tool name or that auto-approval, so every sentence resting on the mechanism has to be rewritten for what the target actually does. The files themselves are plain markdown under `~/.squirrel/hoard/`, so a memory written on Claude Code is readable from anywhere. |
| `dig` | ✅ | ❌ | ❌ | Same, plus one more reason: its rules for telling squirrel-mode's own injected lines from a profile that copies them are about lines a Claude Code `SessionStart` hook puts in context, and neither other target has a lifecycle hook to put them there. It also names the `Read` tool for the same auto-approval reason `stash` names `Write`. |
| `rules` | ✅ | ❌ | ❌ | Pulls the base rules back into one conversation after Claude Code's forced output style has been turned off. Neither other target has an output style to turn off, so there is nothing for this to recover from: on Codex the rules are a block in `AGENTS.md`, on Cursor a `.mdc` rules file, and both are re-applied by restoring the file rather than by a command. |

## What each target loses, explicitly

**Codex loses:**

- **Automatic profile injection.** Nothing reads `~/.squirrel/profile.md` for you. The
  `AGENTS.md` block instructs Codex to read that file if it exists, but there is no lifecycle hook to
  guarantee the read happens — it is best-effort, every session, with no verification.
- **Automatic checkpoints.** Nothing writes to `~/.squirrel/checkpoints/`. There is no
  `pickup` skill on Codex, because there is no hook to hand it the checkpoint's absolute path, and
  recomputing that path independently is exactly the drift failure this project has already hit once
  (ADR-0003) — it is not implemented rather than implemented unsafely.
- **The off switch.** No `/squirrel:off`, no `/squirrel:on`, no session-scoped suppression. See
  "Turning the rules off" below for what Codex has instead.
- **The calibration interview's automatic follow-through.** `init` and `tune` both run as skills, but
  nothing on Codex reminds you they exist the way Claude Code's `SessionStart` hook does when no
  profile is found yet.
- **The hoard commands.** No `stash`, no `dig`. Phase 1 of the hoard builds them for Claude Code
  only. What is *not* lost is the data: memories are plain markdown files under
  `~/.squirrel/hoard/`, so anything recorded from Claude Code can be read on Codex by asking it to
  read the file. The port table above says why copying the two skills across would not work as
  written.
- **A hard block against starting calibration unprompted.** Claude Code's `disable-model-invocation:
  true` is a harness-level guarantee: the model cannot invoke `init` or `tune` on its own, full stop.
  Codex has no equivalent field. Each skill's description says, in prose, never to run unprompted —
  but on Codex nothing hard-blocks the model from starting the interview, or changing a profile field,
  unprompted the way Claude Code's harness does. It is instruction only, not enforcement, and that is
  a smaller guarantee than Claude Code's, worth knowing plainly rather than discovering by surprise.

**Cursor loses everything Codex loses, plus:**

- **No calibration interview at all.** Cursor gets no `init` and no `tune`. You cannot run the
  seven-question interview from inside Cursor, and you cannot hand-tune a single field from inside
  Cursor either — both would need to write `~/.squirrel/profile.md`, and squirrel-mode builds no
  Cursor artifact that does. The port table above states what is and is not known about why.
- **No personalization, period, on Cursor alone.** The `.mdc` rules file applies the same fixed
  defaults to everyone. It cannot read the profile, because Cursor rules cannot execute anything —
  they are static text injected into context, not a skill that can open a file.
- **`digest` and `plan` never fire on their own.** They install once, machine-wide, as Cursor
  **Agent Skills** at `~/.cursor/skills/squirrel-digest/` and `~/.cursor/skills/squirrel-plan/`,
  invoked explicitly as `/squirrel-digest` and `/squirrel-plan`. Both carry
  `disable-model-invocation: true`, so Cursor never applies them on its own the way Claude Code's
  model-invocable `digest` still can — where "still can" is itself narrow, and worth stating as it
  ships: there, an ordinary-language "what should I do with this?" fires `digest` unprompted **only**
  when what was pasted alongside is recognisably a ticket, an email, or a written note, and never
  when it is code, a stack trace, a log, a diff, a config, or command output. Narrow or not, that is
  a mode Cursor does not have at all: Cursor Agent Skills have no `alwaysApply` equivalent, so
  explicit invocation is the only mode available; each one's "Trigger on…" description therefore
  describes when *you* should reach for the command, not something Cursor will act on by itself. The
  project-scoped `.cursor/commands/*.md` copies still exist for anyone who also wants `/digest` and
  `/plan` inside one specific repository.

## The one consequence worth knowing before you install anything

All three targets read the **same** file: `~/.squirrel/profile.md`. Nothing about the path
changes per target. This means **one** calibration run — `/squirrel:init` in Claude Code, or asking
Codex in plain language to run squirrel init (Codex's skills are flat-named and invoked that way,
not as `/squirrel:`-namespaced commands) — calibrates every target installed on that machine —
Cursor included, even though Cursor cannot run the interview itself and has no way to read the file
automatically. If you want Cursor's fixed defaults to reflect your own calibration, calibrate in
Claude Code or Codex first, then open `~/.squirrel/profile.md` and use its values to hand-edit
`~/.cursor/rules/squirrel-mode.mdc` yourself — Cursor will never do this for you.

Claude Code reinjects an updated `profile.md` into already-open sessions on the next prompt
(`UserPromptSubmit` mtime check). Cursor and Codex do not get that reinjection: a tune (or hand
edit) elsewhere can leave their view stale until their own cadence re-reads the file or the user
restarts — there is no cross-tool hook to engineer.

## Install

Both installers are POSIX `sh`, make no network calls, send no telemetry, and are **dry-run by
default**: run them with no flags to see exactly what would change; a dry run creates **nothing at all
under `$HOME`** — not even the lock directory described below — and nothing is written until you pass
`--yes`. Each also uses a short-lived, self-cleaning staging directory under `$TMPDIR` on **every**
invocation, including a dry run (removed on every exit path, including a caught signal); that staging
directory is never under `$HOME`. Neither installer ever writes inside a project repository. If a
destination path is itself a symlink, the installer **refuses** — fails loudly, changes nothing —
instead of writing through it; see "Ownership, and the symlink refusal" under Uninstall below.

Three flags exist in total, the same three on both installers: `--yes` (or `-y`) to write for real,
`--uninstall` to reverse an install (see Uninstall below — it obeys the same dry-run-by-default
rule), and `--help` (or `-h`) to print the full list and exit without touching anything. Any other
argument is rejected with an error and the same list. Neither installer has a flag that skips the
dry run's own checks or writes outside `$HOME`.

Both installers resolve the files they copy relative to their own location in this repository, so
each of the two sections below starts by cloning it. Run the target's app once first as well: each
installer keys off that app's own config directory under `$HOME`, which the app itself creates on
first run.

### Codex

Run Codex at least once before this — it creates `~/.codex` on first run.

```sh
git clone https://github.com/thgMatajs/squirrel-mode
cd squirrel-mode
targets/codex/install.sh          # dry run - prints what would change
targets/codex/install.sh --yes    # actually install
```

This touches:

- `~/.codex/AGENTS.md` — squirrel-mode's base rules are added as a clearly delimited block (between
  `<!-- BEGIN SQUIRREL-MODE ... -->` and `<!-- END SQUIRREL-MODE -->`). If the file already exists
  with your own instructions in it (it almost certainly does), those are never touched, never
  truncated, and stay exactly where they were — the block is appended below them. Running the
  installer again after editing `AGENTS.md` yourself, outside that block, updates only the block; your
  own edits elsewhere in the file survive untouched. Two refusals guard that block, and both change
  nothing when they fire. If a matching marker pair is already there but what sits **between** them
  does not carry squirrel-mode's own generated banner line — someone pasted the markers around
  content this installer never wrote — install and uninstall both stop and tell you to remove the two
  marker lines by hand, keeping whatever is between them. And before writing anything at all, the
  installer wraps its **own** bundled block in those markers and re-scans the result with the same
  marker scan every other decision here uses: unless that comes out as exactly one findable block, it
  fails, because installing a block that no later run could find again would wedge your `AGENTS.md`
  permanently.
- `~/.agents/skills/<name>/SKILL.md` for `digest`, `plan`, `init`, and `tune` — one file per command,
  copied in. If Codex has not been run on this machine yet, `~/.codex` does not exist, and the
  installer reports exactly that and does nothing, without failing — run Codex once, then re-run the
  installer.
- `~/.codex/.squirrel-install.lock` — a mutex directory, created immediately before any `AGENTS.md`
  read-then-write work begins and held for the rest of that run — released by the `EXIT` trap on
  every exit path (including the four-skill loop that runs after `AGENTS.md`, a failure, or a caught
  signal), never the instant `AGENTS.md`'s own work ends (see "Concurrency" below). Created **only**
  during a real write (`--yes`); a dry run never creates it.

### Cursor

Open Cursor at least once before this — it creates `~/.cursor` on first run.

```sh
git clone https://github.com/thgMatajs/squirrel-mode
cd squirrel-mode
targets/cursor/install.sh          # dry run - prints what would change
targets/cursor/install.sh --yes    # actually install
```

This touches:

- `~/.cursor/rules/squirrel-mode.mdc` — the always-on base rules, copied in whole. If Cursor has not
  been run on this machine yet, `~/.cursor` does not exist, and the installer reports exactly that
  and does nothing, without failing — open Cursor once, then re-run the installer.
- `~/.cursor/skills/squirrel-digest/SKILL.md` and `~/.cursor/skills/squirrel-plan/SKILL.md` — Cursor
  **Agent Skills**, auto-discovered from `~/.cursor/skills/` for every project on this machine. The
  folder names carry a `squirrel-` prefix because Cursor has no command namespace; each one's
  frontmatter `name` must match its folder exactly, and `scripts/build.sh` generates both from one
  expression so they cannot drift apart.
- `~/.cursor/.squirrel-install.lock` — the same lock mechanism as Codex's above, created and removed
  only during a real write (`--yes`); a dry run never creates it.

Cursor's **project-scoped** commands are a separate mechanism and are still not installed by this
script — they live in a project's own `.cursor/commands/` directory, and writing them there would
mean guessing which project. The Agent Skills above are what covers every project. Every **install**
run — dry run included, but never an `--uninstall` run — ends by naming the two command files, as
absolute paths inside the checkout you ran it from, for anyone who also wants them in one specific
repository:

```
The two skills above are Cursor AGENT SKILLS: Cursor auto-discovers $HOME/.cursor/skills/ for every project on this machine, so /squirrel-digest and /squirrel-plan work everywhere once, with nothing to copy per project.
Cursor's PROJECT-scoped commands are a separate mechanism and are not installed here. If you also want /digest and /plan as project commands in one specific repository, copy these two files into that project's .cursor/commands/ directory:
  <your-checkout>/targets/cursor/commands/digest.md
  <your-checkout>/targets/cursor/commands/plan.md
```

Repeat that copy for every project where you want the project-scoped `/digest` and `/plan` as well.

### One honest caveat about `~/.cursor/rules/`

Cursor's own documentation describes `.mdc` rule files at **project** level only — project rules live
in `.cursor/rules` as `.mdc` files — and describes user-level rules only as global preferences set in
Customize → Rules, a screen with no documented filesystem path. The **user-level** directory
`~/.cursor/rules/`, where squirrel-mode installs `squirrel-mode.mdc`, appears nowhere in those docs.

That is absence from the documentation, not a documented denial. It works today, and it is the only
mechanism on Cursor that applies squirrel-mode's base rules to every turn without being asked.
Cursor's documented user-level file mechanism is Agent Skills (`~/.cursor/skills/`), which
squirrel-mode also installs — but Agent Skills are never always-on: they are applied when the agent
judges them relevant, or, with `disable-model-invocation: true`, only when you type their slash
command. There is no `alwaysApply` for an Agent Skill, so Agent Skills cannot carry the base rules.

squirrel-mode therefore ships both: the documented mechanism for the two commands, and the
undocumented-but-working one for the always-on rules. If a future Cursor release stops reading
`~/.cursor/rules/`, the symptom is that the base rules quietly stop applying while `/squirrel-digest`
and `/squirrel-plan` keep working. The fallback is to paste the contents of
`~/.cursor/rules/squirrel-mode.mdc` into Cursor's Customize → Rules screen by hand.

## Concurrency

A second `install.sh` (any action) started with `--yes` while one is already writing against the same
`$HOME` fails loudly, naming the lock path, instead of racing the first one's read-then-write sequence:

```
install.sh: ERROR: another squirrel-mode Codex install/uninstall appears to be running (lock directory
exists at /home/you/.codex/.squirrel-install.lock). ...
```

The lock is acquired **only** for a real write (`--yes`) — a dry run changes nothing under `$HOME`, so
it needs no mutex and never takes the lock; two concurrent dry runs, or a dry run running alongside a
real install, never contend with each other. The lock directory named in the message above is created
and removed within the same run; if you see this message and are certain no other run is actually in
progress (for example, a previous run crashed before cleaning up), remove that directory by hand and
re-run. A *different* failure — most commonly a read-only `~/.codex` or `~/.cursor` — is reported
separately, naming the parent directory and the underlying error, rather than being described as
contention with a lock directory that was never created.

## Uninstall

Both installers accept `--uninstall`, with the same dry-run-by-default / `--yes` discipline:

```sh
targets/codex/install.sh --uninstall          # dry run
targets/codex/install.sh --uninstall --yes    # actually remove

targets/cursor/install.sh --uninstall          # dry run
targets/cursor/install.sh --uninstall --yes    # actually remove
```

Codex's uninstall removes exactly the delimited block from `AGENTS.md` — the rest of the file is left
byte-for-byte as it was before squirrel-mode was ever installed — and removes the four skill files (and
their now-empty directories: each `~/.agents/skills/<name>`, then `~/.agents/skills`, then `~/.agents`
itself, which install's own `mkdir -p` created). Each of those is a plain, non-recursive `rmdir` that
is allowed to fail, and none of them runs unless that same run really did remove one of
squirrel-mode's own skill files — so an `~/.agents` or `~/.agents/skills` you made yourself, and
squirrel-mode never installed into, survives an uninstall, and one still holding anything else of
yours is left exactly where it is. That skill-file cleanup happens even if `~/.codex` itself was
removed since squirrel-mode was installed: the four files live under `~/.agents/skills/`, not under
`~/.codex`, so they are still cleaned up rather than stranded. If the squirrel-mode block was the ONLY content `AGENTS.md` ever
had, uninstall leaves the file in place, empty (0 bytes), rather than deleting it — install cannot tell
"you had an empty `AGENTS.md` before we ever touched it" apart from "we ourselves created this file",
and the safe default is to never delete a user-visible file under `$HOME` it is not certain it created;
delete the empty file by hand if you don't want it.

Cursor's uninstall removes `squirrel-mode.mdc` **and** both `~/.cursor/skills/squirrel-*/SKILL.md`
files, plus the directories install created for them — `~/.cursor/rules`, each
`~/.cursor/skills/<name>`, and `~/.cursor/skills` itself. Every one of those is a plain,
non-recursive `rmdir` that is allowed to fail, so a directory still holding anything else survives
untouched, and every one of them runs **only** when that same run actually removed one of
squirrel-mode's own files from it — so a `~/.cursor/skills` you made yourself and squirrel-mode never
installed into is never deleted. `~/.cursor` itself is never removed: Cursor creates it, and this
installer refuses to run at all when it is missing.

### Ownership, and the symlink refusal

Ownership of an existing file at the exact path either installer manages is decided by an **exact,
full-line match** against that specific artifact's own `GENERATED FILE` banner line — read fresh from
the bundled source next to each installer, never a fixed literal, so a change to `scripts/build.sh`'s
banner format cannot desynchronise the installers from what they compare against. A file that merely
*contains* the substring `<!-- GENERATED FILE. Source:` somewhere — for example, a file of your own
that quotes squirrel-mode's own docs — does **not** count as a match: it is foreign, not squirrel-mode's,
and neither installer ever touches a file at that path that does not carry that exact banner line. If
something else already occupies that exact path, the installer reports it and leaves it alone.

If the exact managed path (`~/.codex/AGENTS.md`, an `~/.agents/skills/<name>/SKILL.md`,
`~/.cursor/rules/squirrel-mode.mdc`, or a `~/.cursor/skills/<name>/SKILL.md`) is itself a
**symlink**, both installers **refuse** — a loud
`fail()`, changing nothing — on both install and uninstall, rather than write through it. Either
installer replaces a destination atomically via `mv` (`rename(2)`), which replaces the *directory
entry* at that path; if that entry is a symlink, the rename severs it instead of writing through it,
silently leaving whatever it pointed to stale forever. This matters because symlinking one of these
exact paths out of a dotfiles repository (chezmoi, stow, yadm) is a common, legitimate setup — the
refusal is deliberate, matching the same trust boundary `scripts/allow-checkpoint.sh` and
[ADR-0002](./adr/0002-checkpoint-auto-allow.md) apply to their own checkpoint directory: a symlink AT
the exact path a script owns is never silently followed. The error message tells you to remove the
symlink (or point the installer at the real file) and re-run. Note that a symlinked **ancestor
directory** — `~/.cursor/rules` itself, or `~/.codex` — is unaffected by this and continues to work
normally; only a symlink at the exact managed leaf path is refused.

The same "refuses, changes nothing" guarantee also applies if the exact managed path is a
**directory**, or any other non-regular file, instead of a symlink — both installers check every
managed path for both of these conditions in one pass, before writing anything at all anywhere, for
either install or uninstall, so a problem found at one path (say, a directory sitting where one of the
four Codex skill files belongs) can never let an earlier path (say, `AGENTS.md`) already have been
written by the time the installer reports it and stops.

Uninstalling either one does **not** touch `~/.squirrel/` — your profile and checkpoints are
Claude Code's concern (ADR-0003) and survive independently of any target's install state.

## Turning the rules off

Claude Code has `/squirrel:off` and `/squirrel:on` — a per-session flag, described in
[ADR-0005](./adr/0005-session-flag-off-switch.md). Neither exists on Codex or Cursor, because both
depend on a `UserPromptSubmit` hook that only Claude Code has. There is nothing to turn off
automatically there — turn it off by removing or disabling the thing that is actually applying it:

- **Codex:** run `targets/codex/install.sh --uninstall --yes` to remove the block from `AGENTS.md`
  entirely, or open `~/.codex/AGENTS.md` yourself and delete these two lines *and* everything between
  them:

  ```
  <!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
  <!-- END SQUIRREL-MODE -->
  ```

  The BEGIN line is that whole string, parenthetical included — searching for a bare
  `<!-- BEGIN SQUIRREL-MODE -->` finds nothing. Delete the marker lines themselves, not only the text
  between them: a marker pair left sitting around content squirrel-mode did not write is exactly what
  the installer refuses to touch afterwards. Either way takes effect the next time Codex reads
  `AGENTS.md` (its next session).
- **Cursor:** open `~/.cursor/rules/squirrel-mode.mdc` and change `alwaysApply: true` to
  `alwaysApply: false` in the frontmatter (Cursor stops applying it automatically, but you can still
  invoke it manually), or delete the file entirely (`targets/cursor/install.sh --uninstall --yes`), or
  turn it off from Cursor's own Rules settings UI if your version exposes one. Any of the three takes
  effect immediately for new context Cursor builds. The two Agent Skills are unaffected by any of
  this — they only ever run when you type `/squirrel-digest` or `/squirrel-plan`, so there is nothing
  to turn off there; delete their folders, or run the uninstall, if you want them gone.

## Privacy

No network calls. No telemetry. Both installers, and every command skill they place, are plain POSIX
shell and Markdown — nothing shipped by squirrel-mode ever phones home, on any of the three targets.
