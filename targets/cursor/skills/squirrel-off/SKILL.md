---
name: squirrel-off
description: "Turn squirrel-mode's formatting off for the rest of the current session only. Only for an explicit /squirrel-off invocation."
disable-model-invocation: true
---

<!-- GENERATED FILE. Source: skills/off/SKILL.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->

# squirrel-mode off (Cursor)

This skill suppresses squirrel-mode's base rules for the rest of the current session only. It does not touch any other session, and it does not change the profile.

## Why this cannot flip a flag directly (ADR-0005)

A running skill has no way to learn this session's own session id. So this skill cannot name the one file that would suppress this exact session; it leaves a PENDING note for the next prompt's off check, if it runs, and that off check - which does see the real session id - can claim it. Independently of that claim, ignore squirrel-mode's base rules from this turn, including this reply.

## Find the session off-token and working directory first

Your context already contains two lines, injected at the start of this session:

- `Session off-token: <token>` - the opaque token this skill embeds in the sentinel filename. Copy that exact string. Do not invent a token, do not shorten it, do not substitute a random suffix of your own: the next prompt's off check, if it runs, recomputes the same value from the session id, and a token you invent is one it cannot match.
- `Session working directory: <value>` - the exact value written into the sentinel's contents (legacy dual-match / cwd path). Never determine this yourself by running a command, inspecting your own state, or any other means: a value you determine yourself can disagree with the one the sentinel claim compares against on the legacy path (a symlinked project path, a trailing slash, a different shell context), and the mismatch is silent.

If the off-token line is missing entirely, or present but empty after the colon, tell the user in one line that the session off-token cannot be determined and stop. Do not write a sentinel in that case.

If the token begins with `anon-`, tell the user in one line that this session cannot be turned off - for example: "This session cannot be turned off: squirrel-mode was not given a session id for it. A new session restores /squirrel-off." - and stop. Do not write a sentinel in that case either. An `anon-` token is what squirrel-mode emits when this session's id was missing or unusable, and it is documentation only: the next prompt's off check, if it runs, recomputes the token from that same session id, so it can never arrive at an `anon-` one. A `PENDING.anon-...` file would sit there unclaimed for the whole session while the user had been told the change was coming - the one outcome worse than saying plainly that it cannot be done.

If the working-directory line is missing entirely, or present but empty after the colon, tell the user in one line that the session's working directory cannot be determined and stop. Do not write a sentinel in that case: a sentinel that can never be claimed on the legacy path, and whose token binding you also cannot confirm, is worse than none at all.

## Turning off

1. Create `~/.squirrel/off/` if it does not exist yet.
2. Inside it, create one new sentinel file named `PENDING.` followed immediately by the exact value from the injected `Session off-token:` line - no extra characters, no second random suffix. The token IS the filename suffix. Never reuse a fixed name unrelated to that token: a fixed name would let a second `/squirrel-off` run, in a different session, silently overwrite the first one's request before either reaches an off check that can claim it.
3. Write the exact value from the injected `Session working directory:` line, and nothing else, as that file's entire contents, verbatim - not a re-typed copy, not a normalized form, the exact string. A single trailing newline in the write is fine; anything else in the file's contents is not.
4. Confirm in exactly one line that squirrel-mode is off from this turn - for example: "squirrel-mode is off from this turn, including this reply." Do not wait for another user message. Still write the PENDING sentinel so the next prompt's off check, if it runs, can claim it; do not depend on that claim for the formatting change.

## What this does and does not do

- From this turn, including this reply, ignore squirrel-mode's base rules. Later replies in this chat stay that way until squirrel-on. The next prompt's off check, if it runs, may still claim the sentinel written above (by matching the token to this session's own id). squirrel-on reverses it, in this same session only.
- Every other session, and every other project, is unaffected. A token-named sentinel is claimable only by the session whose id equals that token - another session in the same directory cannot steal it.
- This write is a tool call like any other and appears in the transcript the same way every other tool call does.
- This is a soft off: the base rules stay loaded, and this chat ignores them from this turn. For a hard off that removes the rules from the system prompt entirely, uninstall the squirrel-mode plugin or turn off its rule in Customize.

## Language

Write the one-line confirmation in the profile's `language` field, if a profile exists. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.
