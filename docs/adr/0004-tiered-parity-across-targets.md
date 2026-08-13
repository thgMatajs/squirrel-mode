# Targets get tiered parity from one canonical rules file

squirrel-mode installs into Claude Code, Codex, and Cursor, but the three cannot offer the same feature set: everything that makes the profile and checkpoints automatic depends on lifecycle hooks, and only Claude Code has them. Rather than pretend at parity or cut two targets, each gets the deepest integration its host actually supports, and the README says explicitly what each one loses. The base rules — the actual product — live in a single canonical file, and a build script generates each target's artifact from it. Three hand-maintained copies of the rule set would diverge on the first edit, and divergence here means the plugin behaves differently depending on which editor you opened, which is the failure mode it exists to prevent.

| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints |
| :-- | :-- | :-- | :-- | :-- |
| Claude Code | output style, `force-for-plugin` | 8 namespaced skills | `SessionStart` hook | `PreToolUse` hook |
| Codex | `~/.codex/AGENTS.md` global layer | skills in `~/.agents/skills/` | instructed file read only | no |
| Cursor | `~/.cursor/rules/*.mdc`, `alwaysApply: true` | Agent Skills in `~/.cursor/skills/` | no | no |

## Consequences

- A build step and a CI drift check are now part of the repo. The generated files are committed so users can install without running anything.
- Codex reads `AGENTS.md` as a user message every session, so a "read the profile file if it exists" instruction is always present — but nothing guarantees the read happens. Codex calibration is best-effort, and README says so.
- Cursor has two command locations and only one of them is user-level. `.cursor/commands/*.md` is project-scoped and cannot be installed once for every project; Agent Skills under `~/.cursor/skills/` are read for every project on the machine and can. squirrel-mode installs `digest` and `plan` as Agent Skills and ships the project-scoped copies alongside, for anyone who also wants them inside one repository. Agent Skills are never always-on — there is no `alwaysApply` for one — so they cannot carry the base rules; that stays the `.mdc` rules file's job.
- Codex skills live in `~/.agents/skills/`, not `~/.codex/skills/`, and Codex custom prompts are deprecated in favour of skills. Anything written against the older layout is wrong.
- Adding a fourth target means one generator, not one more copy of the rules.
