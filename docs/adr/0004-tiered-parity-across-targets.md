# Targets get tiered parity from one canonical rules file

squirrel-mode installs into Claude Code, Codex, and Cursor, but the three cannot offer the same feature set: everything that makes the profile and checkpoints automatic depends on lifecycle hooks, and only Claude Code has them. Rather than pretend at parity or cut two targets, each gets the deepest integration its host actually supports, and the README says explicitly what each one loses. The base rules — the actual product — live in a single canonical file, and a build script generates each target's artifact from it. Three hand-maintained copies of the rule set would diverge on the first edit, and divergence here means the plugin behaves differently depending on which editor you opened, which is the failure mode it exists to prevent.

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | 10 namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | skills in `~/.agents/skills/` | instructed file read only | no |
| Cursor | plugin `.mdc`, `alwaysApply: true` | 10 Agent Skills `/squirrel-<name>` | `sessionStart` + profile projection | `preToolUse` Write/Read |

## Consequences

- A build step and a CI drift check are now part of the repo. The generated files are committed so users can install without running anything.
- Codex reads `AGENTS.md` as a user message every session, so a "read the profile file if it exists" instruction is always present — but nothing guarantees the read happens. Codex calibration is best-effort, and README says so.
- Cursor has two command locations and only one of them is user-level. `.cursor/commands/*.md` is project-scoped and cannot be installed once for every project; Agent Skills from the local plugin copy under `~/.cursor/plugins/local/squirrel-mode/` are read for every project on the machine and can. squirrel-mode installs all ten commands as Agent Skills there and ships the project-scoped `digest` and `plan` copies alongside, for anyone who also wants them inside one repository. Agent Skills are never always-on — there is no `alwaysApply` for one — so they cannot carry the base rules; that stays the plugin `.mdc` rules file's job.
- Codex skills live in `~/.agents/skills/`, not `~/.codex/skills/`, and Codex custom prompts are deprecated in favour of skills. Anything written against the older layout is wrong.
- Adding a fourth target means one generator, not one more copy of the rules.

## Amendment (hoard phase 1) — the command count in the table above was corrected in place

Phase 1 of the hoard added `/squirrel:stash` and `/squirrel:dig`
([ADR-0008](./0008-hoard-auto-allow.md), `docs/specs/2026-08-13-hoard-design.md`), so the Claude
Code row's command count went from 8 to **10**, edited in the table itself rather than left standing
with a note beside it. That is the one part of this rendering the repository keeps in step by hand:
`tests/test_targets.sh` scenario 33 records why, and the reasoning is that the rest of the
divergence here is a design-history rendering (unbolded counts, generic skill paths, no Hoard
column, and no `, best-effort` qualifier) while a count that disagrees with the three pinned tables
is a plain factual error about how many commands ship. The three tables it must agree with are in
`README.md`, `docs/OTHER-TOOLS.md` and `PLAN.md`, and those three are pinned to each other, line for
line, by that scenario.

The tiering decision itself is unchanged, and the two new commands are an instance of it rather than
an exception: both are Claude Code only in phase 1, for exactly the reason this ADR gives — they rest
on lifecycle hooks (the `PreToolUse` auto-approval that makes a memory write silent, and the
`SessionStart` injection `dig` reads its search path from), and only Claude Code has them. Porting
them is a rewrite of the sentences that name those mechanisms, not a copy; `docs/OTHER-TOOLS.md`'s
port table and §8 of the hoard spec both record that where a porter will find it.

## Amendment (cursor native plugin) — native plugin hooks and 10 Agent Skills

Cursor now has native plugin hooks and 10 Agent Skills from the local plugin copy at
`~/.cursor/plugins/local/squirrel-mode/`, not Agent Skills under `~/.cursor/skills/`. The Cursor row
in the table above was edited in place for the same reason the hoard-phase-1 count was: a row that
still said hooks `no` / checkpoints `no` / skills only under `~/.cursor/skills/` would be a factual
error about how many Cursor commands ship, and would disagree with the three pinned tables in
`README.md`, `docs/OTHER-TOOLS.md` and `PLAN.md`.

What Cursor has: plugin `.mdc` with `alwaysApply: true`; `/squirrel-<name>` for all ten commands
(init and tune write `~/.squirrel/profile.md`, then a new chat; pickup; stash and dig; off and on
this turn plus sentinels; rules loads the 15 Cursor rules this turn); `sessionStart` plus the
`squirrel-profile.mdc` projection; `preToolUse` on `Write`/`Read`.

What Cursor still does not have: Cloud Agent loading of that local copy; `beforeSubmitPrompt` does
not inject; auto-allow is `Write`/`Read` not `StrReplace`; `sessionStart` injection is best-effort
(the projection `.mdc` mitigates). Codex is unchanged: still no lifecycle hooks, still the four
skills under `~/.agents/skills/`, still no stash/dig/pickup/off/on/rules.

The opening thesis that "only Claude Code has them" is therefore false for Cursor after this
amendment; it remains true for Codex.
