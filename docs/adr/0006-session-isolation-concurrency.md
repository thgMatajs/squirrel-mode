# Concurrent sessions isolate by ownership, not by locking shared state

Two Claude Code sessions on the same project must not lose each other's checkpoint entries or silence the wrong session. The v0.3 concurrency model does that by giving each session exclusive ownership of its mutable cells — not by locking a shared file.

**Checkpoints.** Each session writes only `~/.squirrel/checkpoints/<slug>/<session-id>.md`. `SessionStart` injects that absolute path; the model never invents the slug or the session id. `/squirrel:pickup` folds the per-project directory by mtime. The previous layout was one flat `<slug>.md` shared by every session in that project — concurrent writes lost updates.

**Off/on.** Sentinels are named with an opaque session token and claimed only by the matching session id. That binding is the decision in [ADR-0005 Amendment (P2)](./0005-session-flag-off-switch.md); this ADR does not restate it. The earlier cwd-claimed pending flag could hand `/squirrel:off` to a different session in the same directory.

**Profile.** `~/.squirrel/profile.md` remains the one intentionally shared file. A torn read during `/squirrel:tune`'s Write is accepted ([ADR-0003 Amendment (P3)](./0003-profile-outside-plugin-data.md)). Propagation inside Claude Code is a `UserPromptSubmit` mtime reinjection with per-session markers under `~/.squirrel/profile-seen/`. Cross-tool staleness — Codex and Cursor have no hooks — stays documented only ([docs/OTHER-TOOLS.md](../OTHER-TOOLS.md)).

**Rejected alternative: lock shared mutable state** (one checkpoint file per project, or a cwd-claimed off flag). Lost updates and wrong-session off are exactly the failure modes those locks were meant to prevent and did not. The model cannot hold a lock across turns, and hooks must stay fail-open (never exit non-zero), so a contended lock would either drop work or break the hot path. Ownership per session removes the shared cell instead.

## Consequences

- Checkpoint paths are nested (`checkpoints/<slug>/<session-id>.md`). The `PreToolUse` allowlist and rule 14's per-file Done-log cap are scoped to that layout; a flat shared file is not coming back.
- `/squirrel:pickup` reads a directory, not one file. Folding is best-effort by mtime; consolidating into a canonical history inside a fail-open hook is out of scope.
- Off/on correctness for concurrent same-directory sessions depends on the token path in ADR-0005 Amendment (P2). Legacy tokenless sentinels still claim by cwd.
- Profile torn-reads stay possible and accepted. Claude sessions see a fresh profile on the next prompt after a tune elsewhere; Codex/Cursor do not get that reinjection.
- Installers may still use short-lived `mkdir` locks for their own one-shot `$HOME` writes. That is a different problem (atomic install, not multi-turn session state) and is not a precedent for locking checkpoint or off state.
