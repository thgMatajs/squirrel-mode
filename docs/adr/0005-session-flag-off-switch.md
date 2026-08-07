# The off switch is a session flag plus a per-prompt counter-injection

Because the base rules live in the system prompt ([ADR-0001](./0001-output-style-not-skill.md)) and Claude Code periodically reminds Claude to adhere to the active output style, `/squirrel:off` cannot work the way such commands usually do — a single in-conversation instruction to ignore the rules is one message competing against a system prompt that gets re-asserted for the rest of the session, so the formatting drifts back on within a few turns. Instead `/squirrel:off` writes a flag file keyed by `session_id`, and a `UserPromptSubmit` hook injects a counter-instruction on every prompt while that flag exists. The suppression then arrives at the same cadence as the thing it is suppressing. `/squirrel:on` removes the flag.

## Consequences

- A hook runs on every prompt for the lifetime of the plugin, not only when disabled. It is a short shell script, but it is on the hot path of every message.
- The flag is keyed by session, so it does not leak into other sessions or other projects — matching the "session only" scope the feature promises.
- Flag files accumulate. The `SessionStart` hook prunes stale ones.
- `/plugin disable squirrel` plus `/clear` remains the hard off, and README documents it as such: it is the only path that truly removes the rules from the system prompt.
