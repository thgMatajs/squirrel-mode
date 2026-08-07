---
description: "Change one field of an existing squirrel-mode profile without repeating the calibration interview. Only for an explicit /squirrel:tune invocation."
disable-model-invocation: true
---

# squirrel-mode tuning

/squirrel:tune edits one field of the existing profile at `~/.claude/squirrel/profile.md`. It never re-runs the seven-question interview.

## Procedure

1. Read `~/.claude/squirrel/profile.md`. If it does not exist, say so in one line, tell the user to run `/squirrel:init` first, and stop there.
2. Show the current value of all 11 fields as one compact block: `language`, `answer_position`, `step_style`, `max_list_items`, `code_style`, `explanation_budget`, `options_per_answer`, `confirm_topic_switch`, `progress_recap`, `extras_section`, `tone`. If the file exists but a given field's line is missing entirely, or is malformed - not in the exact `field: value` shape, or carrying a value outside that field's allowed values - show that field as unset (for example, `tone: (unset)`) rather than guessing a value, and treat it as the `rules/base-rules.md` default for that field until the user sets it explicitly through this command. Do not write that default into the file on your own initiative; showing it is not setting it.
3. Ask exactly one question: which field to change, and to what. Offer field-name options as multiple-choice when 4 or fewer are the likely candidates from context; otherwise ask the user to name the field directly.
4. Any of the 11 fields can be changed this way, one at a time, including the four that `/squirrel:init` question 2 set together as a bundle (`step_style`, `explanation_budget`, `extras_section`, `tone`). Each of the four is independently editable here even though the interview only ever set it alongside the other three.
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
6. Rewrite `~/.claude/squirrel/profile.md` with the new value in place and every other field unchanged, keeping the same `field: value` shape the file already has.
7. Confirm the change in one line, naming the field and its new value. Do not re-show the whole profile unless asked.
8. If the user asks to change more than one field, handle them one at a time: confirm the first change, then repeat the one-question step for the next field. Never ask about two fields in the same message.

## Language

Write questions and confirmations in the profile's own `language` field. If `language` is `auto`, mirror the language the user is currently writing in.

## Respecting the profile while tuning it

Any list `/squirrel:tune` shows, such as the field-name options in step 3, respects `max_list_items`. When more than `max_list_items` fields are realistic candidates, name only the most likely ones and let the user type the field name directly for anything else.
