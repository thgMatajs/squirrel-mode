---
description: "Record one durable memory in the user's cross-project hoard: a correction, a decision with its reasoning, a bug and its fix, or a fact worth keeping. Only for an explicit /squirrel:stash invocation."
disable-model-invocation: true
---

# squirrel-mode stash

/squirrel:stash writes exactly one memory to the user's hoard and stops. The hoard is personal and machine-wide: it lives at `~/.squirrel/hoard/`, never inside the project, and it is read again in every future session in every project.

## Decide the layer first

- **`global/`** - something true about how this user works, or a mistake that would repeat in any project. "Run the test suite before committing." "Prefers one option, not three."
- **`projects/<slug>/`** - something true about this repository and no other. A decision taken here, a bug that bit here, a convention this codebase follows.

`<slug>` is the directory name already present in the `Project checkpoint path:` line injected at the start of this session: it is the component between `checkpoints/` and the filename. Use that exact string. Do not compute a slug yourself - a value you derive can disagree with the one every other part of squirrel-mode uses, and the disagreement is silent.

If that line is absent from your context, write to `global/` and say so in one line.

## Decide the type

| Type | For |
| :-- | :-- |
| `feedback` | How to work. A correction the user gave, with the reason behind it. |
| `decision` | A choice that was made, with its rationale, so it is not re-litigated. |
| `episode` | A failure and its fix. A bug that was non-obvious, and what actually solved it. |
| `reference` | A fact, a state, or a pointer. Where something lives, what something is. |

There is no `session` type. Session state is what the checkpoint holds; a memory is what outlives the session.

## Write the file

1. Build the timestamp by running `date -u +%Y%m%dT%H%M%SZ`. Use the value it returns, verbatim, for the filename and for both `created` and `last_used`.
2. Build the filename as `<timestamp>-<title>.md`, where `<title>` is the title lowercased with every run of non-alphanumeric characters replaced by a single `-`, trimmed to about 60 characters. Example: `20260813T142530Z-never-commit-without-running-tests.md`.
3. **Show the title and body to the user before writing**, in two lines. A memory the user never saw is one they cannot correct, and it will be read back in every future session.
4. Write the file with the **`Write` tool**, never a shell command. Only `Write`, `Edit` and `Read` carry the auto-approval for this directory; a `Bash` heredoc stops to ask for a permission this command is meant not to need.

The file's exact shape, with every key present and in this order - the reader assumes it:

```
---
type: feedback
importance: 4
tags: git, tests
created: 20260813T142530Z
last_used: 20260813T142530Z
uses: 0
status: active
superseded_by:
title: never commit without running the test suite
---

Two releases went out with a broken suite. Run the suite first; a green
run is the only evidence that a commit is safe.
```

- `importance` is 1 to 5. Reserve 5 for the handful of things that must never be missed; the default is 3.
- `tags` are comma-separated topic words, lowercase. They are what a future search matches on, so tag by subject, not by project.
- `uses` starts at 0 and `status` starts at `active`. `superseded_by` stays empty.
- The body is short by construction. A memory that needs three paragraphs is two memories.

## When a fact changed, supersede instead of editing

Never rewrite an existing memory's title or body. Write the new memory first, then edit the old one to set `status: superseded` and `superseded_by: <new filename without .md>`. The history survives, and a search can never return two versions that contradict each other.

## Never write a credential

If the memory would contain a key, token, password, or private key, do not write it. Say so in one line and stop. The hook that auto-approves this directory also refuses to auto-approve a write that looks like it carries one, so a credential write will stop to ask - but the first line of defence is not writing it.

## Then stop

Confirm in exactly one line what was written and where - for example: "Stashed to global: never commit without running the test suite." Do not summarise the memory back, do not offer to write another, and do not ask what to stash next.

## Language

Write the confirmation in the profile's `language` field. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in. The memory's own title and body are written in whatever language the user used for the fact itself.
