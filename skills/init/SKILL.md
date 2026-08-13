---
description: "Run the squirrel-mode calibration interview: seven one-at-a-time multiple-choice questions that build the user's personal response-formatting profile. Only for an explicit /squirrel:init invocation."
disable-model-invocation: true
---

# squirrel-mode calibration

/squirrel:init builds the user's personal squirrel-mode profile through a seven-question interview. Follow this procedure exactly, in every session it runs in.

## Rules for the whole interview

1. Ask exactly one question per message. Never combine two questions in the same message, and never ask a follow-up question in the same message as the question itself.
2. Every question is multiple-choice, with two to four options labeled A, B, C, D (only as many as the question needs, never more than four), plus a final line offering "or type your own answer". When the reply is a free-form answer rather than a lettered option, map it to the closest listed option by meaning, and state which one you mapped it to in one line, before continuing. This applies to every question in this interview, not only question 2 - question 2's own mapping table below is the one case detailed enough to need its own worked example, not a special case.
3. Show progress on every question in the exact form `Question N of 7` (for example `Question 3 of 7`), where N is the number of the current question.
4. Wait for the user's reply before asking the next question.
5. If a reply matches neither a lettered option nor a plausible free-form answer, ask the same question again once, still showing the same `Question N of 7` line.
6. Before the profile exists, mirror the language the user is currently writing in for the questions and the confirmation. This interview is what creates `language`; it cannot yet read a value that does not exist.
7. If the user goes off-script mid-interview - asks something unrelated, reports a problem, or otherwise does not answer the current question - address what they raised first, then ask whether to resume from the same question you were on before that happened. Do not silently drop the interview, and do not resume without asking.

## The seven questions, in order

### Question 1 of 7: Language

Ask which language responses should use.

A. Portuguese (pt-BR)
B. English (en)
C. Spanish (es)
D. Match whatever language I write in (auto)

Sets: `language`. This question is the one exception to the general free-form-mapping rule above: a free-form answer naming a language NOT among A-C (for example, French) maps to D (`auto`), never to whichever of A-C sounds closest by geography or family - `auto` mirrors the language actually used, which is the closer functional match than guessing a wrong supported language.

### Question 2 of 7: What breaks your focus most? (bundle selector)

This is the single highest-information question in the interview: it sets four fields at once. Ask exactly this question, with exactly these four lettered options, plus "type your own":

A. Long walls of text
B. Answers that jump around or feel disorganized
C. Too many options or choices thrown at me at once
D. Getting stuck or frustrated, and losing momentum

This mapping is authoritative - do not improvise it, and do not infer a different combination even if it seems plausible. Each answer describes a distinct *mode* of overwhelm, and the tech lead has already worked out the combination each mode needs:

| Answer | `step_style` | `explanation_budget` | `extras_section` | `tone` |
| :-- | :-- | :-- | :-- | :-- |
| A - long walls of text | `checklist` | 1 | `no` | `terse` |
| B - jumps around, disorganized | `numbered` | 3 | `yes` | `neutral` |
| C - too many options at once | `numbered` | 2 | `no` | `neutral` |
| D - stuck or frustrated, losing momentum | `numbered` | 3 | `no` | `warm` |

Why these four combinations, so a future edit does not undo it: A is drowning in words, so cut words and drop the Extra section entirely. B can handle content but needs scaffolding, so it keeps a normal budget and gets a clearly labelled Extra - a reader who wants structure tolerates one more labelled section. C is paralysed by choice, so `extras_section` is `no` there too - an Extra section is one more thing to evaluate, which is exactly the load C is reporting; C answering this way also strongly suggests `options_per_answer: 1` at question 6, but question 6 asks that directly and its own answer wins. D is the one mode where the material is not the problem: the content lands and the momentum does not, so structure stays ordinary and `tone` is `warm` - the only field in the profile that can acknowledge the friction at all, and rule 16 keeps that acknowledgement to one clause fused into the answer, never an opener of its own. `extras_section` is `no` for D as well, because an optional extra section is one more thing to come back to for someone already stalled.

`warm` is reachable only here. Answer D is the one path in this interview that sets it, so do not quietly fold D into B: the two differ in `extras_section` and in `tone`, and collapsing them would take a third of `tone`'s value space off the calibration path entirely.

A free-form answer for this question follows the general free-form rule above: map it to the closest of A, B, C, or D by meaning, and name which one in one line before continuing.

This one question sets `step_style`, `explanation_budget`, `extras_section`, and `tone` together. No other question in this interview sets any of these four fields; `/squirrel:tune` is where each of the four can be revisited on its own later.

### Question 3 of 7: Where should the answer go?

A. Straight into the answer, no lead-in
B. One short line of context, then the answer

Sets: `answer_position` (`first` for A, `after-one-line-context` for B).

### Question 4 of 7: Code first, or steps first?

A. Show the code, then explain
B. Explain the steps, then show the code

Sets: `code_style` (`code-first` for A, `step-by-step` for B).

### Question 5 of 7: How long a list before it stops helping?

A. 3 items
B. 5 items
C. 7 items

Sets: `max_list_items` (3, 5, or 7). A free-form or typed-in answer is accepted only if it is a whole number from 3 to 7 inclusive - the same range `rules/base-rules.md` and `/squirrel:tune` both enforce for this field. A number outside that range, or anything that is not a number, is not accepted: say in one line that it must be an integer from 3 to 7, and ask this same question again, still showing `Question 5 of 7`. Do not move on until a valid value is given.

### Question 6 of 7: One recommendation, or alternatives?

A. Just recommend one path
B. Show 2 options up front
C. Show 3 options up front

Sets: `options_per_answer` (1, 2, or 3).

### Question 7 of 7: Recap progress and confirm topic switches?

A. Recap progress across turns, and ask before switching topics
B. Recap progress, but switch topics without asking
C. Do not recap progress, but ask before switching topics
D. Neither

Sets: `progress_recap` and `confirm_topic_switch` together (`yes`/`yes` for A, `yes`/`no` for B, `no`/`yes` for C, `no`/`no` for D).

## After question 7

1. Assemble all 11 fields: `language`, `answer_position`, `step_style`, `max_list_items`, `code_style`, `explanation_budget`, `options_per_answer`, `confirm_topic_switch`, `progress_recap`, `extras_section`, `tone`.
2. Show the resulting profile as one compact fenced code block, one field per line, in the exact shape used in step 4 below.
3. Ask a single confirm question: "Save this? y/n" (or the equivalent in the language just chosen). Wait for the reply before doing anything else.
4. On yes, create `~/.squirrel/` if it does not exist, then write `~/.squirrel/profile.md` with exactly this shape:

```markdown
# squirrel-mode profile
language: <value>
answer_position: <value>
step_style: <value>
max_list_items: <value>
code_style: <value>
explanation_budget: <value>
options_per_answer: <value>
confirm_topic_switch: <value>
progress_recap: <value>
extras_section: <value>
tone: <value>
```

5. On no, ask which single answer to revisit, return to that question, and re-run the confirm step once the answer changes. Do not restart the whole interview.
6. Once the file is written, confirm in one line and immediately answer the user's very next message using the new profile. The demonstration is part of `/squirrel:init` itself, not a separate step the user has to ask for.

## Notes

- Never batch questions. A message containing more than one question defeats the interview's purpose.
- Do not ask the user to repeat information already given earlier in this same interview.
- Once the profile exists partway through this flow, any recommendation this interview itself makes follows `options_per_answer`, and any list it shows respects `max_list_items`.
