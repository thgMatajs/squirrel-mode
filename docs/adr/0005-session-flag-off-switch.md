# The off switch is a session flag plus a per-prompt counter-injection

Because the base rules live in the system prompt ([ADR-0001](./0001-output-style-not-skill.md)) and Claude Code periodically reminds Claude to adhere to the active output style, `/squirrel:off` cannot work the way such commands usually do — a single in-conversation instruction to ignore the rules is one message competing against a system prompt that gets re-asserted for the rest of the session, so the formatting drifts back on within a few turns. Instead `/squirrel:off` writes a flag file keyed by `session_id`, and a `UserPromptSubmit` hook injects a counter-instruction on every prompt while that flag exists. The suppression then arrives at the same cadence as the thing it is suppressing. `/squirrel:on` removes the flag.

## The skill cannot learn its own session id, so the hook binds the flag

A running skill has no access to its `session_id` — Claude Code exposes it to hooks on stdin, but not to a session as an environment variable or otherwise. So `/squirrel:off` cannot name the file it needs to write.

The first implementation inferred the id by scanning `~/.claude/projects/<escaped-cwd>/*.jsonl` for the most recently modified transcript. That was rejected: it depends on undocumented internals whose path shape and escaping rule can change without notice, and with two sessions open on the same project it disables whichever one wrote last — quite possibly not the one the user typed in.

Instead the two halves cooperate. `/squirrel:off` writes a sentinel named `PENDING.<random>` in `~/.squirrel/off/`, whose contents are the current working directory. On the next prompt the `UserPromptSubmit` hook — which does receive both `session_id` and `cwd` — globs for `PENDING.*`, and claims the one whose recorded directory matches its own `cwd` by renaming it to `<session_id>`. From that point the flag is session-scoped exactly as before.

`/squirrel:on` has the identical problem and gets the mirror solution: it writes `CLEAR.<random>`, also containing the current directory. The hook claims a matching `CLEAR.*` by deleting both `off/<session_id>` and the sentinel itself. Without this, `on` would be stuck with the same rejected transcript scan and only half the feature would work.

The random suffix matters. A single fixed sentinel name is one file for the whole machine, so running `/squirrel:off` in project A and then in project B before either sends a prompt would silently discard A's request — A having already told the user it worked. The suffix gives each request its own file, and the `cwd` in the contents is what decides who claims it.

Nothing depends on Claude Code internals, and the binding is done by the only participant that legitimately knows the answer.

## Consequences

- A hook runs on every prompt for the lifetime of the plugin, not only when disabled. It is a short shell script, but it is on the hot path of every message.
- **The sentinel handoff has a narrow race.** Two sessions in the *same directory*, one running `/squirrel:off`, and the other submitting a prompt first: the other session claims the flag. The `cwd` guard reduces this from "any concurrent session" to "a concurrent session in the same directory", and the window is one prompt wide. Accepted, and documented for the user in README rather than hidden.
- **A sentinel that is never claimed is inert but visible.** If the user runs `/squirrel:off` and then never submits another prompt in that directory, the sentinel survives until pruning. The next session in that directory claims it and starts disabled — surprising, but it is also arguably what the user asked for, and `/squirrel:on` fixes it in one command.
- **Neither skill can confirm the effect took hold**, because the binding happens on the *next* prompt. Both must tell the user the change starts with their next message rather than claiming it already applies.
- **The skills read `cwd` from injected context, never from `pwd`.** The `SessionStart` hook emits the literal working directory alongside the checkpoint path, and the skills use that exact string. This is the same discipline `/squirrel:pickup` already follows for the checkpoint path, and for the same reason: a value the model computes itself can disagree with the value the hook compares against — a symlinked project path or a trailing slash is enough — and the failure is silent. The sentinel simply never matches, the user is told the change takes effect next message, and it never does.
- **When a matching `PENDING` and `CLEAR` both exist, the newer one wins**, resolved with `find -newer`. Claiming them in a fixed order would mean whichever the code happens to check last overrides the user's actual most recent action: already off, then `/squirrel:on` followed by `/squirrel:off` before any prompt, and a fixed order silently lands on *on*. On an exact mtime tie, `PENDING` wins — a user asking to turn squirrel-mode off is reporting that the formatting is actively in their way, and that reading deserves priority over the reverse.
- The flag is keyed by session, so it does not leak into other sessions or other projects — matching the "session only" scope the feature promises.
- Flag files accumulate. The `SessionStart` hook prunes any older than **7 days**. The threshold is
  arbitrary and deliberately generous: a flag outliving its session is inert, since the file is keyed
  by `session_id` and no future session will ever match it, so the only cost of keeping one too long
  is a stray file. Pruning too eagerly, on the other hand, could re-enable squirrel-mode underneath a
  user who is still in the session that disabled it. Pruning never fails the hook.
- `/plugin disable squirrel@squirrel-mode`, then a new session, remains the hard off, and README documents it as such: it is the only path that truly removes the rules from the system prompt. `/reload-plugins` alone is not enough — its documented reload list (plugins, skills, agents, hooks, plugin MCP servers, plugin LSP servers) never names output styles, so it does not reliably drop a `force-for-plugin` style on its own.

## Amendment (P2) — bind the sentinel by session token, not by cwd alone

**Status:** Accepted
**Date:** 2026-08-10

The original Consequences bullet that accepted a one-prompt-wide same-directory race is superseded for the token-named path described here. The historical decision text above is preserved deliberately; this section records what changed and why.

### Context

The original design wrote `PENDING.<random>` / `CLEAR.<random>` with cwd as contents, and `UserPromptSubmit` claimed the first sentinel whose contents matched its own cwd. That is correct when two sessions have different directories. It is wrong when they share one: the first session in that cwd to fire `UserPromptSubmit` claims the sentinel — which can silence the session that did not run `/squirrel:off`.

### Decision

1. `SessionStart` (`load-profile.sh`) always injects `Session off-token: <token>`. When `session_id` survives the same `sanitize_session_id` used elsewhere, the token **is** that sanitised value. Otherwise it is `anon-<random>` (exclusive to that SessionStart context, parallel to anonymous checkpoint names).
2. `/squirrel:off` writes `PENDING.<token>`; `/squirrel:on` writes `CLEAR.<token>`. The token is the filename suffix — the skill copies the injected line verbatim and must not invent a different suffix.
3. `UserPromptSubmit` (`check-off-flag.sh`) does not receive SessionStart context. It sanitises the `session_id` on its own stdin and claims only `PENDING.<that>` / `CLEAR.<that>`. Same value, two channels.
4. **Tech-lead D3 — dual path:**
   - **Token path:** suffix sanitises and equals this session's id → claim by token only; contents/cwd are optional (a cwd mismatch must not block).
   - **Foreign token-shaped:** suffix sanitises but is not this session's id → leave untouched. Falling back to cwd here would re-open the race.
   - **Legacy tokenless:** suffix fails sanitise (not a valid session_id shape) → claim-by-cwd as in the original decision, contents still compared byte-for-byte after trimming at most one trailing newline.
5. Sentinel contents remain the injected cwd string so the legacy path keeps working for any pre-P2 or non-token-shaped file still on disk.

### Consequences

- Two sessions in the same directory no longer steal each other's token-named sentinels. The README race paragraph is retired for this path.
- Pre-P2 `PENDING.<sanitize-ok-random>` files left on disk become unclaimable (their suffixes look token-shaped but match no live session's id). They stay inert until the existing 7-day prune. Accepted transition residue; new skills always write `PENDING.<token>`.
- An `anon-*` off-token is still injected when `session_id` is missing, but `UserPromptSubmit` still refuses to touch `off/` when sanitisation fails — so `/squirrel:off` remains non-binding for sessions without a valid session id, as before. The anon token is exclusivity/documentation, not a second claiming channel the hook can recompute.
- The skill must read both injected lines (`Session off-token:` for the name, `Session working directory:` for the contents). Inventing either value locally remains forbidden.