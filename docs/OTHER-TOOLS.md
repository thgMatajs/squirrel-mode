# squirrel-mode on Codex and Cursor

squirrel-mode's primary home is Claude Code — that is where every feature exists. This document is
for deciding whether to also install it on Codex or Cursor, and for the exact steps to do so. Read
[ADR-0004](./adr/0004-tiered-parity-across-targets.md) for why the three targets cannot offer the same
feature set; this page states the practical consequences plainly, with no hedging.

## Parity at a glance

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | **7** namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | **4** in `~/.agents/skills/<name>/SKILL.md` | instructed file read only, best-effort | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | **2** in `.cursor/commands/*.md`, project-scoped | no | no |

## Which commands port, and why the other three cannot

| Command | Claude Code | Codex | Cursor | Reason |
| :-- | :-- | :-- | :-- | :-- |
| `digest` | ✅ | ✅ | ✅ | Pure prose transformation. Needs nothing from the target. |
| `plan` | ✅ | ✅ | ✅ | Same. |
| `init` | ✅ | ✅ | ❌ | Writes `~/.squirrel/profile.md`. Codex can run shell commands; Cursor's commands are project-scoped, so a user-level install has nowhere to live. |
| `tune` | ✅ | ✅ | ❌ | Same as `init`. |
| `pickup` | ✅ | ❌ | ❌ | Needs the checkpoint path injected by a hook. Recomputing the slug is forbidden — that is the drift failure ADR-0003 and the S5 review both hit. |
| `off` / `on` | ✅ | ❌ | ❌ | The sentinel is claimed by a `UserPromptSubmit` hook. No hook, no claim, and nothing to turn off anyway: Codex users edit `AGENTS.md`, Cursor users flip `alwaysApply` or delete the `.mdc`. |

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
- **A hard block against starting calibration unprompted.** Claude Code's `disable-model-invocation:
  true` is a harness-level guarantee: the model cannot invoke `init` or `tune` on its own, full stop.
  Codex has no equivalent field. Each skill's description says, in prose, never to run unprompted —
  but on Codex nothing hard-blocks the model from starting the interview, or changing a profile field,
  unprompted the way Claude Code's harness does. It is instruction only, not enforcement, and that is
  a smaller guarantee than Claude Code's, worth knowing plainly rather than discovering by surprise.

**Cursor loses everything Codex loses, plus:**

- **No calibration interview at all.** Cursor gets no `init` and no `tune`. You cannot run the
  seven-question interview from inside Cursor, and you cannot hand-tune a single field from inside
  Cursor either — both would need to write `~/.squirrel/profile.md`, and Cursor's commands are
  project-scoped with no user-level install path to put such a thing at.
- **No personalization, period, on Cursor alone.** The `.mdc` rules file applies the same fixed
  defaults to everyone. It cannot read the profile, because Cursor rules cannot execute anything —
  they are static text injected into context, not a skill that can open a file.
- **`digest` and `plan` are project-scoped.** They live in `.cursor/commands/*.md`, which Cursor reads
  per-project, not once for the whole machine. Getting them into a given project means copying two
  files into that project's own `.cursor/commands/` directory (see Install below) — there is no
  "install once, use everywhere" path for these two commands the way there is on Claude Code and
  Codex.

## The one consequence worth knowing before you install anything

All three targets read the **same** file: `~/.squirrel/profile.md`. Nothing about the path
changes per target. This means running `/squirrel:init` **once**, in Claude Code or in Codex,
calibrates every target installed on that machine — Cursor included, even though Cursor cannot run
the interview itself and has no way to read the file automatically. If you want Cursor's fixed
defaults to reflect your own calibration, run `/squirrel:init` in Claude Code or Codex first, then
open `~/.squirrel/profile.md` and use its values to hand-edit `~/.cursor/rules/squirrel-mode.mdc`
yourself — Cursor will never do this for you.

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

### Codex

```sh
targets/codex/install.sh          # dry run - prints what would change
targets/codex/install.sh --yes    # actually install
```

This touches:

- `~/.codex/AGENTS.md` — squirrel-mode's base rules are added as a clearly delimited block (between
  `<!-- BEGIN SQUIRREL-MODE ... -->` and `<!-- END SQUIRREL-MODE -->`). If the file already exists
  with your own instructions in it (it almost certainly does), those are never touched, never
  truncated, and stay exactly where they were — the block is appended below them. Running the
  installer again after editing `AGENTS.md` yourself, outside that block, updates only the block; your
  own edits elsewhere in the file survive untouched.
- `~/.agents/skills/<name>/SKILL.md` for `digest`, `plan`, `init`, and `tune` — one file per command,
  copied in. If Codex was never run on this machine (`~/.codex` does not exist yet), the installer
  reports that and does nothing, without failing.
- `~/.codex/.squirrel-install.lock` — a mutex directory, created immediately before any `AGENTS.md`
  read-then-write work begins and held for the rest of that run — released by the `EXIT` trap on
  every exit path (including the four-skill loop that runs after `AGENTS.md`, a failure, or a caught
  signal), never the instant `AGENTS.md`'s own work ends (see "Concurrency" below). Created **only**
  during a real write (`--yes`); a dry run never creates it.

### Cursor

```sh
targets/cursor/install.sh          # dry run - prints what would change
targets/cursor/install.sh --yes    # actually install
```

This touches:

- `~/.cursor/rules/squirrel-mode.mdc` — the always-on base rules, copied in whole. If `~/.cursor` does
  not exist yet, the installer reports that and does nothing, without failing.
- `~/.cursor/.squirrel-install.lock` — the same lock mechanism as Codex's above, created and removed
  only during a real write (`--yes`); a dry run never creates it.

`/digest` and `/plan` are **not** installed anywhere by this script, because Cursor has no user-level
command location (see "What each target loses" above). The installer prints the two file paths and
the one line you need:

```
Copy these two files into <your-project>/.cursor/commands/:
  targets/cursor/commands/digest.md
  targets/cursor/commands/plan.md
```

Repeat that copy for every project where you want `/digest` and `/plan` available.

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
their now-empty directories). This happens even if `~/.codex` itself was removed since squirrel-mode
was installed: the four skill files live under `~/.agents/skills/`, not under `~/.codex`, so they are
still cleaned up rather than stranded. If the squirrel-mode block was the ONLY content `AGENTS.md` ever
had, uninstall leaves the file in place, empty (0 bytes), rather than deleting it — install cannot tell
"you had an empty `AGENTS.md` before we ever touched it" apart from "we ourselves created this file",
and the safe default is to never delete a user-visible file under `$HOME` it is not certain it created;
delete the empty file by hand if you don't want it. Cursor's uninstall removes `squirrel-mode.mdc`.

### Ownership, and the symlink refusal

Ownership of an existing file at the exact path either installer manages is decided by an **exact,
full-line match** against that specific artifact's own `GENERATED FILE` banner line — read fresh from
the bundled source next to each installer, never a fixed literal, so a change to `scripts/build.sh`'s
banner format cannot desynchronise the installers from what they compare against. A file that merely
*contains* the substring `<!-- GENERATED FILE. Source:` somewhere — for example, a file of your own
that quotes squirrel-mode's own docs — does **not** count as a match: it is foreign, not squirrel-mode's,
and neither installer ever touches a file at that path that does not carry that exact banner line. If
something else already occupies that exact path, the installer reports it and leaves it alone.

If the exact managed path (`~/.codex/AGENTS.md`, an `~/.agents/skills/<name>/SKILL.md`, or
`~/.cursor/rules/squirrel-mode.mdc`) is itself a **symlink**, both installers **refuse** — a loud
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
  entirely, or open `~/.codex/AGENTS.md` yourself and delete everything between the
  `<!-- BEGIN SQUIRREL-MODE -->` / `<!-- END SQUIRREL-MODE -->` markers. Either way takes effect the
  next time Codex reads `AGENTS.md` (its next session).
- **Cursor:** open `~/.cursor/rules/squirrel-mode.mdc` and change `alwaysApply: true` to
  `alwaysApply: false` in the frontmatter (Cursor stops applying it automatically, but you can still
  invoke it manually), or delete the file entirely (`targets/cursor/install.sh --uninstall --yes`), or
  turn it off from Cursor's own Rules settings UI if your version exposes one. Any of the three takes
  effect immediately for new context Cursor builds.

## Privacy

No network calls. No telemetry. Both installers, and every command skill they place, are plain POSIX
shell and Markdown — nothing shipped by squirrel-mode ever phones home, on any of the three targets.
