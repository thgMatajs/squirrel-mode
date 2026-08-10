# squirrel-mode profile — reference

This is a reference, not a file to copy. squirrel-mode never reads `profile.example.md` —
the file that matters is `~/.squirrel/profile.md`, and `/squirrel:init` is how you
create it: a seven-question interview, one question per message, writing all 11 fields for
you. Run `/squirrel:tune` afterward to change one field at a time, without repeating the
interview.

## The exact shape

`/squirrel:init` writes this shape to `~/.squirrel/profile.md`. The defaults are shown
below; your own file will hold your own answers instead.

```markdown
# squirrel-mode profile
language: auto
answer_position: first
step_style: numbered
max_list_items: 5
code_style: code-first
explanation_budget: 3
options_per_answer: 1
confirm_topic_switch: yes
progress_recap: yes
extras_section: yes
tone: neutral
```

## Every field, its default, and its allowed values

Canonical source: `rules/base-rules.md`. Change a field with `/squirrel:tune`; never hand-write
a value this table does not list.

| Field | Default | Allowed values |
| :-- | :-- | :-- |
| language | auto | pt-BR, en, es, auto |
| answer_position | first | first, after-one-line-context |
| step_style | numbered | numbered, checklist |
| max_list_items | 5 | 3-7 |
| code_style | code-first | code-first, step-by-step |
| explanation_budget | 3 | positive integer; max lines of explanation per code block |
| options_per_answer | 1 | positive integer; 1 means recommend only |
| confirm_topic_switch | yes | yes, no |
| progress_recap | yes | yes, no |
| extras_section | yes | yes, no |
| tone | neutral | neutral, warm, terse |
