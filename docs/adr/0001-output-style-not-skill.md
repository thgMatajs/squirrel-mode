# Base rules ship as an output style, not a skill

The base rules must apply to every response, and skills are model-invoked — Claude decides per turn whether a skill is relevant, so no `description` wording makes one fire reliably every time. Intermittent formatting is the worst possible outcome here: a user who cannot trust the shape of the output has to read defensively, which is the cost the plugin exists to remove. Output styles modify the system prompt directly and apply to every turn, and `force-for-plugin: true` applies ours automatically whenever the plugin is enabled, with no `/config` step. We ship `output-styles/squirrel-mode.md` as the real mechanism and keep a thin `skills/squirrel-mode/SKILL.md` carrying the same rules for users who disable the forced style and want to invoke it by hand.

## Consequences

- **`keep-coding-instructions: true` is mandatory.** Without it, an output style *replaces* Claude Code's built-in software-engineering instructions. squirrel-mode changes how Claude talks, not how it codes.
- **No placeholder interpolation.** Claude Code resolves `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}` and `${user_config.*}` in skill and agent content only — output styles are not in that table. The output style must be literal text, which is why the profile arrives through a `SessionStart` hook instead of being interpolated in. It also rules out `userConfig` as the profile mechanism.
- **We override the user's `outputStyle` setting.** Someone using Explanatory or Learning loses it while squirrel-mode is enabled. README must say so plainly.
- **Turning it off needs its own mechanism.** See [ADR-0005](./0005-session-flag-off-switch.md) — an in-conversation "ignore the rules" instruction cannot beat a system prompt that is re-asserted by output-style reminders.
- **Subagents are unaffected.** Output styles apply to the main conversation only; a subagent runs its own system prompt. Work delegated to subagents comes back unshaped.
