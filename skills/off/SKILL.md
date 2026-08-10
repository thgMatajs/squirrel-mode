---
description: "Turn squirrel-mode's formatting off for the rest of the current session only. Only for an explicit /squirrel:off invocation."
disable-model-invocation: true
---

# squirrel-mode off

/squirrel:off suppresses squirrel-mode's base rules for the rest of the current session only. It does not touch any other session, and it does not change the profile.

## Why this cannot flip a flag directly (ADR-0005)

A running skill has no way to learn this session's own session id - Claude Code hands that value to hooks on every prompt, never to a skill. So this skill cannot name the one file that would suppress this exact session; it can only leave a note for the hook that runs on the next prompt, and let that hook - which does see the real session id - claim it.

## Find the session off-token and working directory first

Your context already contains two lines, injected at the start of this session:

- `Session off-token: <token>` - the opaque token this skill embeds in the sentinel filename. Copy that exact string. Do not invent a token, do not shorten it, do not substitute a random suffix of your own: the `UserPromptSubmit` hook recomputes the same value from the session id it receives on stdin, and a token you invent is one it cannot match.
- `Session working directory: <value>` - the exact value written into the sentinel's contents (legacy dual-match / cwd path). Never determine this yourself by running a command, inspecting your own state, or any other means: a value you determine yourself can disagree with the one the claiming hook compares against on the legacy path (a symlinked project path, a trailing slash, a different shell context), and the mismatch is silent.

If the off-token line is missing entirely, or present but empty after the colon, tell the user in one line that the session off-token cannot be determined and stop. Do not write a sentinel in that case.

If the working-directory line is missing entirely, or present but empty after the colon, tell the user in one line that the session's working directory cannot be determined and stop. Do not write a sentinel in that case: a sentinel that can never be claimed on the legacy path, and whose token binding you also cannot confirm, is worse than none at all.

## Turning off

1. Create `~/.squirrel/off/` if it does not exist yet.
2. Inside it, create one new sentinel file named `PENDING.` followed immediately by the exact value from the injected `Session off-token:` line - no extra characters, no second random suffix. The token IS the filename suffix. Never reuse a fixed name unrelated to that token: a fixed name would let a second `/squirrel:off` run, in a different session, silently overwrite the first one's request before either reaches a hook that can claim it.
3. Write the exact value from the injected `Session working directory:` line, and nothing else, as that file's entire contents, verbatim - not a re-typed copy, not a normalized form, the exact string. A single trailing newline in the write is fine; anything else in the file's contents is not.
4. Confirm in exactly one line that the change starts with the user's next message - for example: "squirrel-mode will turn off starting with your next message." Do not say it is already off: the flag only takes effect once a `UserPromptSubmit` hook claims the sentinel on the next prompt, and this skill cannot confirm that happened.

## What this does and does not do

- Nothing changes for the message you are answering right now. Starting with your *next* message in this session, a `UserPromptSubmit` hook claims the sentinel written above (by matching the token to this session's own id) and begins injecting a counter-instruction on every prompt, overriding squirrel-mode's formatting for the rest of this session. `/squirrel:on` reverses it, in this same session only.
- Every other session, and every other project, is unaffected. A token-named sentinel is claimable only by the session whose id equals that token - another session in the same directory cannot steal it.
- This write is a tool call like any other and appears in the transcript the same way every other tool call does.
- This is a soft off: the base rules stay loaded, and a per-prompt check keeps overriding them for the rest of this session once the sentinel is claimed. For a hard off that removes the rules from the system prompt entirely, run `/plugin disable squirrel@squirrel-mode`, then start a new session.

## Language

Write the one-line confirmation in the profile's `language` field, if a profile exists. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.
