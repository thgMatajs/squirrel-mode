# Targets get tiered parity from one canonical rules file

squirrel-mode installs into Claude Code, Codex, and Cursor, but the three cannot offer the same feature set: everything that makes the profile and checkpoints automatic depends on lifecycle hooks, and only Claude Code has them. Rather than pretend at parity or cut two targets, each gets the deepest integration its host actually supports, and the README says explicitly what each one loses. The base rules — the actual product — live in a single canonical file, and a build script generates each target's artifact from it. Three hand-maintained copies of the rule set would diverge on the first edit, and divergence here means the plugin behaves differently depending on which editor you opened, which is the failure mode it exists to prevent.

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | 10 namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | skills in `~/.agents/skills/` | instructed file read only | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | Agent Skills in `~/.cursor/skills/` | no | no |

## Consequences

- A build step and a CI drift check are now part of the repo. The generated files are committed so users can install without running anything.
- Codex reads `AGENTS.md` as a user message every session, so a "read the profile file if it exists" instruction is always present — but nothing guarantees the read happens. Codex calibration is best-effort, and README says so.
- Cursor has two command locations and only one of them is user-level. `.cursor/commands/*.md` is project-scoped and cannot be installed once for every project; Agent Skills under `~/.cursor/skills/` are read for every project on the machine and can. squirrel-mode installs `digest` and `plan` as Agent Skills and ships the project-scoped copies alongside, for anyone who also wants them inside one repository. Agent Skills are never always-on — there is no `alwaysApply` for one — so they cannot carry the base rules; that stays the `.mdc` rules file's job.
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
