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
| Cursor | plugin `.mdc`, `alwaysApply: true` | **10** Agent Skills `/squirrel-<name>` | `sessionStart` + profile projection + `preCompact` | `preToolUse` Write/Read | `stash` + `dig` |

## Which commands port, and why Codex still lacks six

| Command | Claude Code | Codex | Cursor | Reason |
| :-- | :-- | :-- | :-- | :-- |
| `digest` | ✅ | ✅ | ✅ | Pure prose transformation. Needs nothing from the target. |
| `plan` | ✅ | ✅ | ✅ | Same. |
| `init` | ✅ | ✅ | ✅ | Writes `~/.squirrel/profile.md`. Codex can run shell commands. Cursor writes the same file through `/squirrel-init`, then a **new chat** for the profile to apply. |
| `tune` | ✅ | ✅ | ✅ | Same as `init`. |
| `pickup` | ✅ | ❌ | ✅ | Needs the checkpoint path injected by a hook. Recomputing the slug is forbidden — that is the drift failure ADR-0003 and the S5 review both hit. Cursor `sessionStart` injects that path; Codex has no hook to. |
| `off` / `on` | ✅ | ❌ | ✅ | The sentinel is claimed by a `UserPromptSubmit` / `beforeSubmitPrompt` hook. Codex has neither, so Codex users edit `AGENTS.md`. Cursor `/squirrel-off` and `/squirrel-on` take effect this turn and write PENDING/CLEAR sentinels for the next prompt's off check, if it runs. |
| `stash` | ✅ | ❌ | ✅ | Built for Cursor as `/squirrel-stash`; Codex still has no port in phase 1, and porting it is a rewrite rather than a copy. It writes a memory with Claude Code's `Write` tool, which it names explicitly because that is what the `PreToolUse` hook auto-approves — the memory *write* therefore costs no permission prompt there, though the command still costs one for the `date` stamp it builds, which is a `Bash` call: squirrel-mode registers its `PreToolUse` hook for `Write|Edit|Read` only, so none of its hooks runs on that call — a choice of this plugin's configuration, not a limit of Claude Code, as README.md sets out. Cursor auto-allow is `Write`/`Read`, not `StrReplace`. Codex has neither that tool name nor that auto-approval, so every sentence resting on the mechanism has to be rewritten for what Codex actually does. The files themselves are plain markdown under `~/.squirrel/hoard/`, so a memory written on Claude Code or Cursor is readable from anywhere. |
| `dig` | ✅ | ❌ | ✅ | Same, plus one more reason: its rules for telling squirrel-mode's own injected lines from a profile that copies them are about lines a Claude Code `SessionStart` / Cursor `sessionStart` hook puts in context, and Codex has no lifecycle hook to put them there. It also names the `Read` tool for the same auto-approval reason `stash` names `Write`. |
| `rules` | ✅ | ❌ | ✅ | Pulls the base rules back into one conversation. Cursor `/squirrel-rules` loads the 15 always-on rules this turn from the plugin `.mdc`. Codex has no output style to recover from: the rules are a block in `AGENTS.md`, restored by editing the file, not by a command. |

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
- **The hoard commands.** No `stash`, no `dig`. Cursor ships both as Agent Skills; Codex still
  does not. What is *not* lost is the data: memories are plain markdown files under
  `~/.squirrel/hoard/`, so anything recorded from Claude Code or Cursor can be read on Codex by
  asking it to read the file. The port table above says why copying the two skills across would not
  work as written.
- **A hard block against starting calibration unprompted.** Claude Code's `disable-model-invocation:
  true` is a harness-level guarantee: the model cannot invoke `init` or `tune` on its own, full stop.
  Codex has no equivalent field. Each skill's description says, in prose, never to run unprompted —
  but on Codex nothing hard-blocks the model from starting the interview, or changing a profile field,
  unprompted the way Claude Code's harness does. It is instruction only, not enforcement, and that is
  a smaller guarantee than Claude Code's, worth knowing plainly rather than discovering by surprise.

**Cursor still loses these remaining gaps** (it does **not** lose init/tune, pickup, stash/dig, off/on, or rules — those ship as Agent Skills from `~/.cursor/plugins/local/squirrel-mode`):

- **Cloud Agent.** The local plugin copy is for the Cursor app on this machine. A Cloud Agent does not load `~/.cursor/plugins/local/squirrel-mode`.
- **beforeSubmitPrompt does not inject.** The adapter may print a profile reinjection on stdout; Cursor does not apply that as injected context the way Claude Code's `UserPromptSubmit` does. After `/squirrel-tune` or `/squirrel-init`, start a **new chat**. The `squirrel-profile.mdc` projection is what carries field overrides into later chats.
- **Auto-allow is `Write`/`Read`, not `StrReplace`.** Cursor's `preToolUse` matcher is `Write|Read`. A `StrReplace` on a checkpoint or hoard path still goes through the normal permission prompt.
- **`sessionStart` injection is best-effort.** Stdout context can fail to land; the projection `.mdc` (`~/.cursor/rules/squirrel-profile.mdc`, `alwaysApply: true`) mitigates that for the profile. Pickup still needs the injected checkpoint path when `sessionStart` does land.
- **`digest` and `plan` never fire on their own.** They ship as Cursor Agent Skills, invoked explicitly as `/squirrel-digest` and `/squirrel-plan` (and the other eight as `/squirrel-<name>`). Cursor Agent Skills have no `alwaysApply` equivalent, so explicit invocation is the only mode available. Claude Code's model-invocable `digest` still can fire unprompted, and where "still can" is itself narrow, and worth stating as it ships: there, an ordinary-language "what should I do with this?" fires `digest` unprompted **only** when what was pasted alongside is recognisably a ticket, an email, or a written note, and never when it is code, a stack trace, a log, a diff, a config, or command output. Each Cursor skill's "Trigger on…" description therefore describes when *you* should reach for the command, not something Cursor will act on by itself. The project-scoped `.cursor/commands/*.md` copies still exist for anyone who also wants `/digest` and `/plan` inside one specific repository.

## The one consequence worth knowing before you install anything

All three targets read the **same** file: `~/.squirrel/profile.md`. Nothing about the path
changes per target. This means **one** calibration run — `/squirrel:init` in Claude Code,
`/squirrel-init` in Cursor (then a new chat), or asking Codex in plain language to run squirrel
init (Codex's skills are flat-named and invoked that way, not as `/squirrel:`-namespaced
commands) — calibrates every target installed on that machine. Cursor `sessionStart` projects
that file to `~/.cursor/rules/squirrel-profile.mdc` with `alwaysApply: true` so field values
override the plugin defaults; that projection is best-effort, which is why a new chat after
init/tune is the reliable follow-through.

Claude Code reinjects an updated `profile.md` into already-open sessions on the next prompt
(`UserPromptSubmit` mtime check). Cursor `beforeSubmitPrompt` does not inject that reinjection,
and Codex has no hook: a tune (or hand edit) elsewhere can leave their view stale until a new
chat, their own cadence re-reads the file, or the projection is rewritten — there is no
cross-tool hook to engineer.

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

- `~/.cursor/plugins/local/squirrel-mode/` — a repo-shaped **copy** (never a symlink) of the Cursor
  plugin subset: `.cursor-plugin/plugin.json`,
  `scripts/{load-profile,check-off-flag,allow-checkpoint,hoard-search}.sh`, and `targets/cursor/**`.
  After a real install, reload the Cursor window (Reload Window). GitHub shortcut:
  `/add-plugin https://github.com/thgMatajs/squirrel-mode` (pins a commit; the local copy is the
  stable path). If Cursor has not been run on this machine yet, `~/.cursor` does not exist, and the
  installer reports exactly that and does nothing — including not creating `plugins/local` —
  without failing; open Cursor once, then re-run the installer.
- `~/.cursor/.squirrel-install.lock` — the same lock mechanism as Codex's above, created and removed
  only during a real write (`--yes`); a dry run never creates it.

Cursor's **project-scoped** commands are a separate mechanism and are still not installed by this
script — they live in a project's own `.cursor/commands/` directory, and writing them there would
mean guessing which project. The plugin copy above is what covers every project. Every **install**
run — dry run included, but never an `--uninstall` run — ends by naming the two command files, as
absolute paths inside the checkout you ran it from, for anyone who also wants them in one specific
repository:

```
Installed a local Cursor plugin copy at $HOME/.cursor/plugins/local/squirrel-mode. Reload the Cursor window (Reload Window) so Cursor picks it up.
Cursor's PROJECT-scoped commands are a separate mechanism and are not installed here. If you also want /digest and /plan as project commands in one specific repository, copy these two files into that project's .cursor/commands/ directory:
  <your-checkout>/targets/cursor/commands/digest.md
  <your-checkout>/targets/cursor/commands/plan.md
```

Repeat that copy for every project where you want the project-scoped `/digest` and `/plan` as well.

### One honest caveat about `~/.cursor/rules/`

Always-on rules come from the **plugin** `.mdc` inside
`~/.cursor/plugins/local/squirrel-mode/` (loaded after Reload Window), not from installing
`squirrel-mode.mdc` into `~/.cursor/rules/`. What squirrel-mode does write under `~/.cursor/rules/`
is the **projection**: `squirrel-profile.mdc`, with `alwaysApply: true`, so calibrated field values
override the plugin defaults. Hooks write that file; the installer does not.

Cursor's own documentation describes `.mdc` rule files at **project** level only — project rules live
in `.cursor/rules` as `.mdc` files — and describes user-level rules only as global preferences set in
Customize → Rules, a screen with no documented filesystem path. The **user-level** directory
`~/.cursor/rules/` appears nowhere in those docs. Absence from the documentation is not a documented
denial. The projection works today. If a future Cursor release stops reading `~/.cursor/rules/`,
the symptom is that field overrides quietly stop applying while the plugin `.mdc` and
`/squirrel-<name>` skills keep working. The fallback is to paste the projection body into Cursor's
Customize → Rules screen by hand, or to rely on `/squirrel-rules` for the 15 rules this turn.

Cursor Agent Skills are never always-on: they are applied when the agent judges them relevant, or,
with `disable-model-invocation: true`, only when you type their slash command. There is no
`alwaysApply` for an Agent Skill, so Agent Skills cannot carry the base rules; that stays the
plugin `.mdc`'s job.

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

Cursor's uninstall removes only the allowlisted files under
`~/.cursor/plugins/local/squirrel-mode/` when they classify as squirrel-mode's own, then `rmdir`s
empty parents (`squirrel-mode`, `plugins/local`) only when empty. It never removes `~/.cursor`,
`~/.cursor/plugins`, or a sibling plugin. It also removes `~/.cursor/rules/squirrel-profile.mdc` when
that file carries the frozen projection banner as an exact full line, and leftover old-layout files
at `~/.cursor/rules/squirrel-mode.mdc` and `~/.cursor/skills/squirrel-*/SKILL.md` when those classify
as ours (a foreign leftover at those paths is left alone). Every directory removal is a plain,
non-recursive `rmdir` that is allowed to fail, and those `rmdir`s run **only** when that same run
actually removed one of squirrel-mode's own files — so a `plugins/local` you made yourself and
squirrel-mode never installed into is never deleted. `~/.cursor` itself is never removed: Cursor
creates it, and this installer refuses to run at all when it is missing.

### Ownership, and the symlink refusal

Ownership of an existing file at the exact path either installer manages is decided differently
for Codex than for Cursor `--yes`.

**Codex** (and Cursor **uninstall**): an **exact, full-line match** against that specific artifact's
own `GENERATED FILE` banner line — read fresh from the bundled source next to each installer, never
a fixed literal, so a change to `scripts/build.sh`'s banner format cannot desynchronise the
installers from what they compare against. Files with no banner (`plugin.json`, the four scripts,
`install.sh`, `hooks.json`) count as ours on uninstall iff they are byte-identical to the current
bundle. A file that merely *contains* the substring `<!-- GENERATED FILE. Source:` somewhere — for
example, a file of your own that quotes squirrel-mode's own docs — does **not** count as a match: it
is foreign, not squirrel-mode's. Uninstall still deletes only ours (banner or byte-identical). If
something else already occupies that exact path and does not classify as ours, uninstall reports it
and leaves it alone.

**Cursor `--yes`:** overwrites allowlisted regular files in the plugin tree. Absent creates; an
existing regular file at an allowlisted dest is updated to the bundled bytes even when it would
classify as foreign (a newer bundle will not match an older dest). Extra files that are not on the
allowlist are not touched. A symlink or non-regular file at a managed dest is still refused. Codex
`--yes` is unchanged: it still will not overwrite a file that does not carry that exact banner
line.

If the exact managed path (`~/.codex/AGENTS.md`, an `~/.agents/skills/<name>/SKILL.md`, or a file
under `~/.cursor/plugins/local/squirrel-mode/` such as `.cursor-plugin/plugin.json`) is itself a
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
[ADR-0005](./adr/0005-session-flag-off-switch.md). Codex has no off switch: there is no
`UserPromptSubmit` hook to claim a sentinel. Cursor has `/squirrel-off` and `/squirrel-on` (this
turn, plus PENDING/CLEAR sentinels). Codex users turn the rules off by removing or disabling the
block that is actually applying them:

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
- **Cursor:** type `/squirrel-off` to suppress the base rules from this turn in this chat (and
  `/squirrel-on` to restore them). That is the session off switch. For a hard off, run
  `targets/cursor/install.sh --uninstall --yes`, or disable the local plugin in Cursor. The
  projection at `~/.cursor/rules/squirrel-profile.mdc` uses `alwaysApply: true`; deleting that file,
  or changing `alwaysApply` to `false` in its frontmatter, stops field overrides without removing
  the plugin `.mdc`. Agent Skills only run when you type `/squirrel-<name>`.

## Privacy

No network calls. No telemetry. Both installers, and every command skill they place, are plain POSIX
shell and Markdown — nothing shipped by squirrel-mode ever phones home, on any of the three targets.
