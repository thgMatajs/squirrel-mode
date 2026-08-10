# Profile and checkpoints live in ~/.claude/squirrel/, not the plugin data directory

Claude Code provides `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/{id}/`) as the official per-plugin persistent store, and we deliberately do not use it. Two properties make it wrong for this data. It is deleted when the plugin is uninstalled from its last scope — `--keep-data` is opt-in — so uninstalling would destroy the Done log, which is the least disposable thing the plugin holds — it is the only record the plugin accumulates that a user cannot reconstruct. Its path also embeds the marketplace id, so reinstalling from a different marketplace silently yields a fresh, empty profile. We use `~/.claude/squirrel/` instead: a fixed, memorable, hand-editable path that survives uninstall and is indifferent to install source.

## Consequences

- The plugin writes outside its own directory, which is unusual and is why this ADR exists. A future reader looking at `${CLAUDE_PLUGIN_DATA}` in the docs will assume we simply missed it.
- Uninstalling leaves `~/.claude/squirrel/` behind. This is intended — reinstalling restores the user's calibration and their whole history — but README says so, so nobody thinks the uninstall was incomplete.
- The profile is plain markdown a user can open and edit, which `/squirrel:tune` complements rather than replaces.
- Because the path is fixed and not interpolated, it can be referenced literally from the output style, which cannot resolve placeholders ([ADR-0001](./0001-output-style-not-skill.md)), and from Codex and Cursor, which have no equivalent of `${CLAUDE_PLUGIN_DATA}` at all ([ADR-0004](./0004-tiered-parity-across-targets.md)). One path works for all three targets.
- Checkpoints are keyed by a slug derived from the project directory, never written inside the project repository.

## Amendment (S11) — the location moved to `~/.squirrel/`: `.claude` is a protected path

This ADR's own reasoning above is still correct: this data must live somewhere that survives plugin
uninstall and does not depend on install source, and `${CLAUDE_PLUGIN_DATA}` still fails both tests
for the same reasons stated above. What was wrong was the specific directory chosen to satisfy that
reasoning — `~/.claude/squirrel/` (today, `~/.squirrel/`), inside Claude Code's own config directory
— because ADR-0002's
whole auto-approval mechanism depends on writing there without a permission prompt, and that turned
out to be structurally impossible at that location, discovered by direct experiment (S10-2, recorded
in full in [ADR-0002](./0002-checkpoint-auto-allow.md)'s own Amendment (S11)): Claude Code treats
`~/.claude` as a **protected path**, a safety check that runs *before* any hook's `allow` decision is
even considered, and the documentation states plainly that hooks "can tighten restrictions but not
loosen them past what permission rules allow." No hook script, however correctly written, can make a
write inside `~/.claude` skip a permission prompt. ADR-0002 and this ADR had, between them, made two
decisions that could not both hold: put the data somewhere `PreToolUse` cannot auto-approve, and rely
on `PreToolUse` to auto-approve writing to it.

**The fix: `~/.squirrel/`.** Outside `.claude` entirely, at the top level of `$HOME`. The same S10-2
experiment that found the `.claude` problem also directly tested this shape (a path outside the
working directory and outside `.claude`) and confirmed a hook's `allow` is honoured there. Every
runtime path this plugin reads or writes — `profile.md`, `checkpoints/`, `off/` — moved from
`$HOME/.claude/squirrel/...` to `$HOME/.squirrel/...`, with no other change to what lives under it or
how it is organized. This ADR's original rationale (a fixed, memorable, hand-editable path that
survives uninstall and is indifferent to install source) holds exactly as well at the new location as
the old one — nothing about *why* this data lives outside plugin-managed storage changed, only
*where* outside it.

**The symlink trust boundary, re-decided at the new depth.** `~/.claude` was a trusted symlink target
before this move: dotfile managers (chezmoi, stow, yadm) routinely symlink a user's whole
`~/.claude` directory into a dotfiles repository, a legitimate and common setup that
`scripts/allow-checkpoint.sh` deliberately did not reject (see that script's own header comment on
"WHERE THE TRUST BOUNDARY SITS"). `~/.claude/squirrel` beneath it received the identical trust, for
the identical reason — a user or a dotfile manager might reasonably symlink either the whole `.claude`
tree or just the `squirrel` subdirectory within it. Only `checkpoints/`, which the plugin itself
creates, was untrusted: a symlink there or below is never legitimate, because nothing outside the
plugin has a reason to control that specific directory's identity, and rejecting it defeats the one
attack (redirecting an auto-approved write) this boundary exists to stop. The question below is what
becomes of that same trust now that the plugin's data lives at `~/.squirrel/` instead.

That same reasoning transfers directly to the new, shallower layout. **A symlinked `~/.squirrel` is
trusted**, for exactly the reason a symlinked `~/.claude` (or `~/.claude/squirrel`) was: it is
ordinary user configuration this plugin did not create, and a dotfile manager symlinking a whole
per-tool config directory into a managed repository is normal, not an attack. **A symlink at
`checkpoints/` or anywhere below it is still rejected**, unchanged: that directory's identity is still
never legitimately anyone's to redirect but the plugin's own first write or `/squirrel:init`. Moving
the data out from under `.claude` collapses two trusted ancestor directories into one (`~/.claude` and
`~/.claude/squirrel` before; `~/.squirrel` alone now) without changing which side of the boundary
either kind of path falls on. `scripts/allow-checkpoint.sh`'s `component_walk_has_symlink` still
starts its walk at `checkpoints_dir` and never inspects anything above it — the same design, one level
shallower, not a new one.

**Migration: detect and tell, never move automatically.** Anyone upgrading from a build that used
`~/.claude/squirrel/` has real data sitting at that old path, not at today's `~/.squirrel/` — a
profile, and possibly checkpoints with a Done log, the "least disposable thing the plugin holds" this
ADR's own opening paragraph names.
`scripts/load-profile.sh` checks for that directory on every session start and, if it still exists,
injects one line asking the model to tell the user, briefly: where their data used to live, where it
lives now, and that they should move whatever they want to keep and remove the old directory
themselves. It never runs `mv`, `cp`, or `rm` against that directory itself. An automatic move at
session start is exactly the kind of unattended action that goes wrong in a way that cannot be undone
— a partial move racing a concurrent session in another window, or a destination that already has its
own newer `profile.md` silently overwritten by an older one — and the cost of getting it wrong (a
user's calibration or Done log lost) is worse than the cost of asking them to run one command
themselves. The notice repeats every session for as long as the old directory exists and stops the
moment it is gone, with no separate "already told them" state to track.
