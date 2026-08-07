# The off switch is a session flag plus a per-prompt counter-injection

Because the base rules live in the system prompt ([ADR-0001](./0001-output-style-not-skill.md)) and Claude Code periodically reminds Claude to adhere to the active output style, `/squirrel:off` cannot work the way such commands usually do — a single in-conversation instruction to ignore the rules is one message competing against a system prompt that gets re-asserted for the rest of the session, so the formatting drifts back on within a few turns. Instead `/squirrel:off` writes a flag file keyed by `session_id`, and a `UserPromptSubmit` hook injects a counter-instruction on every prompt while that flag exists. The suppression then arrives at the same cadence as the thing it is suppressing. `/squirrel:on` removes the flag.

## The skill cannot learn its own session id, so the hook binds the flag

A running skill has no access to its `session_id` — Claude Code exposes it to hooks on stdin, but not to a session as an environment variable or otherwise. So `/squirrel:off` cannot name the file it needs to write.

The first implementation inferred the id by scanning `~/.claude/projects/<escaped-cwd>/*.jsonl` for the most recently modified transcript. That was rejected: it depends on undocumented internals whose path shape and escaping rule can change without notice, and with two sessions open on the same project it disables whichever one wrote last — quite possibly not the one the user typed in.

Instead the two halves cooperate. `/squirrel:off` writes a sentinel named `PENDING.<random>` in `~/.claude/squirrel/off/`, whose contents are the current working directory. On the next prompt the `UserPromptSubmit` hook — which does receive both `session_id` and `cwd` — globs for `PENDING.*`, and claims the one whose recorded directory matches its own `cwd` by renaming it to `<session_id>`. From that point the flag is session-scoped exactly as before.

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
- `/plugin disable squirrel` plus `/clear` remains the hard off, and README documents it as such: it is the only path that truly removes the rules from the system prompt.
