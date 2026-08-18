---
name: squirrel-on
description: "Turn squirrel-mode's formatting back on for the current session after /squirrel-off. Only for an explicit /squirrel-on invocation."
disable-model-invocation: true
---

<!-- GENERATED FILE. Source: skills/on/SKILL.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->

# squirrel-mode on (Cursor)

This skill reverses squirrel-off for the current session. It is a no-op, confirmed the same way, if the session was never turned off.

## Why this cannot flip a flag directly (ADR-0005)

Exactly the same problem squirrel-off has: this skill has no way to learn this session's own session id, so it cannot name the one file it would need to remove. It leaves a CLEAR note for the next prompt's off check, if it runs - which does see the real session id - and lets that off check clear the flag. Independently of that claim, follow squirrel-mode's base rules from this turn, including this reply.

## Find the session off-token and working directory first

Your context already contains two lines, injected at the start of this session:

- `Session off-token: <token>` - the opaque token this skill embeds in the sentinel filename. Copy that exact string. Do not invent a token, do not shorten it, do not substitute a random suffix of your own: the next prompt's off check, if it runs, recomputes the same value from the session id, and a token you invent is one it cannot match.
- `Session working directory: <value>` - the exact value written into the sentinel's contents (legacy dual-match / cwd path). Never determine this yourself by running a command, inspecting your own state, or any other means: a value you determine yourself can disagree with the one the sentinel claim compares against on the legacy path (a symlinked project path, a trailing slash, a different shell context), and the mismatch is silent.

If the off-token line is missing entirely, or present but empty after the colon, tell the user in one line that the session off-token cannot be determined and stop. Do not write a sentinel in that case.

If the token begins with `anon-`, tell the user in one line that this session cannot be turned back on - for example: "This session cannot be turned back on: squirrel-mode was not given a session id for it. A new session restores /squirrel-on." - and stop. Do not write a sentinel in that case either. An `anon-` token is what squirrel-mode emits when this session's id was missing or unusable, and it is documentation only: the next prompt's off check, if it runs, recomputes the token from that same session id, so it can never arrive at an `anon-` one. A `CLEAR.anon-...` file would sit there unclaimed for the whole session while the user had been told the change was coming. Such a session cannot have been turned off by squirrel-off either, for exactly the same reason, so there is nothing to reverse.

If the working-directory line is missing entirely, or present but empty after the colon, tell the user in one line that the session's working directory cannot be determined and stop. Do not write a sentinel in that case: a sentinel that can never be claimed on the legacy path, and whose token binding you also cannot confirm, is worse than none at all.

## Turning back on

1. Create `~/.squirrel/off/` if it does not exist yet.
2. Inside it, create one new sentinel file named `CLEAR.` followed immediately by the exact value from the injected `Session off-token:` line - no extra characters, no second random suffix. The token IS the filename suffix. Never reuse a fixed name unrelated to that token: a fixed name would let a second request in a different session silently overwrite the first.
3. Write the exact value from the injected `Session working directory:` line, and nothing else, as that file's entire contents, verbatim - not a re-typed copy, not a normalized form, the exact string. A single trailing newline in the write is fine; anything else in the file's contents is not.
4. Confirm in exactly one line that squirrel-mode is on from this turn - for example: "squirrel-mode is on from this turn, including this reply." Say this whether or not the session was actually off; the end state is identical either way. Do not wait for another user message. Still write the CLEAR sentinel so the next prompt's off check, if it runs, can claim it; do not depend on that claim for the formatting change.

## What this does and does not do

- From this turn, including this reply, follow squirrel-mode's base rules again. The next prompt's off check, if it runs, may still claim the sentinel written above (by matching the token to this session's own id) and remove this session's suppression flag if one exists.
- This only ever affects this one session. A token-named sentinel is claimable only by the session whose id equals that token - another session in the same directory cannot steal it. It never touches other sessions or other projects.
- The hard off is to uninstall the squirrel-mode plugin or turn off its rule in Customize. Installing the plugin or turning its rule back on in Customize restores squirrel-mode from that state; squirrel-on is unrelated to that path and only ever matters after squirrel-off in the same session.

## Language

Write the one-line confirmation in the profile's `language` field, if a profile exists. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.
