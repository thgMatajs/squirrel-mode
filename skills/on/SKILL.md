---
description: "Turn squirrel-mode's formatting back on for the current session after /squirrel:off. Only for an explicit /squirrel:on invocation."
disable-model-invocation: true
---

# squirrel-mode on

/squirrel:on reverses `/squirrel:off` for the current session. It is a no-op, confirmed the same way, if the session was never turned off.

## Why this cannot flip a flag directly (ADR-0005)

Exactly the same problem `/squirrel:off` has: this skill has no way to learn this session's own session id, so it cannot name the one file it would need to remove. It leaves a note for the `UserPromptSubmit` hook - which does see the real session id on the next prompt - and lets that hook clear the flag.

## Find the session's working directory first

Your context already contains a line, injected at the start of this session, in the form `Session working directory: <value>`. That exact value - never anything you determine yourself, by running a command, inspecting your own state, or any other means - is what step 3 below writes into the sentinel. A value you determine yourself can disagree with the one the claiming hook compares against (a symlinked project path, a trailing slash, a different shell context), and the mismatch is silent: the sentinel simply never gets claimed, and squirrel-mode never actually turns back on, no matter what this skill told the user.

If that line is missing entirely, or present but empty after the colon, tell the user in one line that the session's working directory cannot be determined and stop. Do not write a sentinel in that case: a sentinel that can never be claimed is worse than none at all, since it sits inert and eventually misleads whoever finds it later.

## Turning back on

1. Create `~/.squirrel/off/` if it does not exist yet.
2. Inside it, create one new sentinel file named `CLEAR.` followed by a fresh random or otherwise unique suffix that you generate right now - the same reasoning as `/squirrel:off`'s `PENDING.` sentinel: a fixed name would let a second request in a different project silently overwrite the first.
3. Write the exact value from the injected `Session working directory:` line, and nothing else, as that file's entire contents, verbatim - not a re-typed copy, not a normalized form, the exact string. A single trailing newline in the write is fine; anything else in the file's contents is not.
4. Confirm in exactly one line that the change starts with the user's next message - for example: "squirrel-mode will turn back on starting with your next message." Say this whether or not the session was actually off; the end state is identical either way. Do not say it is already back on: the clear only takes effect once a `UserPromptSubmit` hook claims this sentinel on the next prompt, and this skill cannot confirm that happened.

## What this does and does not do

- Nothing changes for the message you are answering right now. Starting with your *next* message in this session, a `UserPromptSubmit` hook claims the sentinel written above, removes this session's suppression flag if one exists, and squirrel-mode's rules resume.
- This only ever affects this one session, once a hook confirms the sentinel was written from that session's own working directory. It never touches other sessions or other projects.
- The hard off is `/plugin disable squirrel@squirrel-mode`, then a new session. Running `/plugin enable squirrel@squirrel-mode`, then a new session, restores squirrel-mode from that state; `/squirrel:on` is unrelated to that path and only ever matters after a `/squirrel:off` in the same session.

## Language

Write the one-line confirmation in the profile's `language` field, if a profile exists. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.
