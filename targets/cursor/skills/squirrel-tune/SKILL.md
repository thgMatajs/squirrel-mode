---
name: squirrel-tune
description: "Change one field of an existing squirrel-mode profile without repeating the calibration interview. Only run this when the user explicitly asks to change or tune a squirrel-mode profile field. Never change the profile unprompted, and never run it merely because the user mentioned a preference in passing without asking for the change."
disable-model-invocation: true
---

<!-- GENERATED FILE. Source: skills/tune/SKILL.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->

# squirrel-mode tuning (Cursor)

This skill edits one field of the existing profile at `~/.squirrel/profile.md`. It never re-runs the seven-question interview.

This skill writes `~/.squirrel/profile.md`.

## Procedure

1. Read `~/.squirrel/profile.md`. If it does not exist, say so in one line, tell the user to run the squirrel-mode `init` skill first, and stop there.
2. Show the current value of all 11 fields as one compact block: `language`, `answer_position`, `step_style`, `max_list_items`, `code_style`, `explanation_budget`, `options_per_answer`, `confirm_topic_switch`, `progress_recap`, `extras_section`, `tone`. If the file exists but a given field's line is missing entirely, or is malformed - not in the exact `field: value` shape, or carrying a value outside that field's allowed values - show that field as unset (for example, `tone: (unset)`) rather than guessing a value, and treat it as the default for that field shown in the defaults table in `~/.cursor/rules/squirrel-mode.mdc` until the user sets it explicitly through this command. Do not write that default into the file on your own initiative; showing it is not setting it.
3. Ask exactly one question: which field to change, and to what. Offer field-name options as multiple-choice when 4 or fewer are the likely candidates from context; otherwise ask the user to name the field directly.
4. Any of the 11 fields can be changed this way, one at a time, including the four that the squirrel-mode `init` skill question 2 set together as a bundle (`step_style`, `explanation_budget`, `extras_section`, `tone`). Each of the four is independently editable here even though the interview only ever set it alongside the other three.
5. Validate the new value against the allowed values for that field before writing anything:
   - `language`: `pt-BR`, `en`, `es`, or `auto`.
   - `answer_position`: `first` or `after-one-line-context`.
   - `step_style`: `numbered` or `checklist`.
   - `max_list_items`: an integer from 3 to 7.
   - `code_style`: `code-first` or `step-by-step`.
   - `explanation_budget`: a positive integer.
   - `options_per_answer`: a positive integer.
   - `confirm_topic_switch`: `yes` or `no`.
   - `progress_recap`: `yes` or `no`.
   - `extras_section`: `yes` or `no`.
   - `tone`: `neutral`, `warm`, or `terse`.
   If the requested value is not on this list, say so in one line and ask again, for that same field only.
6. Rewrite `~/.squirrel/profile.md` with the new value in place and every other field unchanged, keeping the same `field: value` shape the file already has. Write is non-atomic (ADR-0003 Amendment P3); do not invent an installer-style write script.
7. Confirm the change in one line, naming the field and its new value. Start a new chat for the profile to take effect; this chat will not pick it up. Do not re-show the whole profile unless asked.
8. If the user asks to change more than one field, handle them one at a time: confirm the first change, then repeat the one-question step for the next field. Never ask about two fields in the same message.

## Language

Write questions and confirmations in the profile's own `language` field. If `language` is `auto`, mirror the language the user is currently writing in.

## Respecting the profile while tuning it

Any list this skill shows, such as the field-name options in step 3, respects `max_list_items`. When more than `max_list_items` fields are realistic candidates, name only the most likely ones and let the user type the field name directly for anything else.
