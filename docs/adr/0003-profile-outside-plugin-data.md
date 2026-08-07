# Profile and checkpoints live in ~/.claude/squirrel/, not the plugin data directory

Claude Code provides `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/{id}/`) as the official per-plugin persistent store, and we deliberately do not use it. Two properties make it wrong for this data. It is deleted when the plugin is uninstalled from its last scope — `--keep-data` is opt-in — so uninstalling would destroy the Done log, and that log exists precisely because ADHD blurs the memory of one's own accomplishments; it is the least disposable thing the plugin holds. Its path also embeds the marketplace id, so reinstalling from a different marketplace silently yields a fresh, empty profile. We use `~/.claude/squirrel/` instead: a fixed, memorable, hand-editable path that survives uninstall and is indifferent to install source.

## Consequences

- The plugin writes outside its own directory, which is unusual and is why this ADR exists. A future reader looking at `${CLAUDE_PLUGIN_DATA}` in the docs will assume we simply missed it.
- Uninstalling leaves `~/.claude/squirrel/` behind. This is intended — reinstalling restores the user's calibration and their whole history — but README says so, so nobody thinks the uninstall was incomplete.
- The profile is plain markdown a user can open and edit, which `/squirrel:tune` complements rather than replaces.
- Because the path is fixed and not interpolated, it can be referenced literally from the output style, which cannot resolve placeholders ([ADR-0001](./0001-output-style-not-skill.md)), and from Codex and Cursor, which have no equivalent of `${CLAUDE_PLUGIN_DATA}` at all ([ADR-0004](./0004-tiered-parity-across-targets.md)). One path works for all three targets.
- Checkpoints are keyed by a slug derived from the project directory, never written inside the project repository.
