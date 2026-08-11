---
description: "Resume work on this project after an interruption or at the start of a new session: show recent wins, what was being done, the next action, and open decisions, in that order, then stop. Trigger only on an explicit /squirrel:pickup invocation, or an explicit request to resume or pick up this project's past work at the start of a new session or after a stated interruption. Never trigger on a request to continue the live, current conversation (e.g. 'let's continue' or 'where were we' about what was just discussed in this same session), and never merely because a checkpoint exists."
---

# squirrel-mode pickup

/squirrel:pickup shows what this project's checkpoint remembers, in a fixed order, then stops.

## Find the checkpoint

This project's memory is spread over several files, one per past session, in a single directory. Your context already names both, injected at the start of this session:

- `Project checkpoint directory: <dir>` - the directory holding every session's checkpoint file for this project. This is what you read.
- `Project checkpoint path: <path>` - the one file inside it that the current session writes to. It may not exist yet.

Read that exact path, and that exact directory, as they are written in context. Do not attempt to compute, guess, or re-derive the path yourself; both are given to you already, and anything worked out independently could disagree with them.

List the directory, then read every checkpoint file in it with the Read tool, most recently modified first. That order is the whole point: it is what makes the newest answer win below.

Context may also carry a third line, `Legacy checkpoint file: <path>`. That file was written before this project's memory was split up per session, so it holds real work. Read it as well, treat it as older than everything in the directory, and say so to the user in one line - for example "Folded in an older checkpoint from the previous single-file layout." Never write to it, move it, or delete it; it stays exactly where it is.

If neither a `Project checkpoint directory:` line nor a `Project checkpoint path:` line is present in context (for example, a very old session), tell the user in one line that the checkpoint path is unavailable and that starting a new session will restore it, then stop.

If those lines are present but the directory holds no checkpoint file and no legacy file was named either, say so in one line, "No checkpoint found for this project yet.", and stop. This is the normal state for a project that has not yet completed a checkpointed unit of work.

## Fold the files into one answer

Read the files newest first and combine them, section by section:

- **You were doing** and **Next action** are single values. Take each from the newest file that actually records it. A file that is empty, or that has no such section, contributes nothing and you move on to the next newest.
- **Recent wins** folds the Done log entries of every file together, newest file first, and within a file newest entry first.
- **Open decisions** folds the same way; drop an entry that repeats one you already have.

If a file is empty, or is missing its Doing, Next, or Done log section, do not invent content for what is missing, and never fill the gap from a file that does not actually say it. If, after folding everything you read, a section still has no source content at all, say so in one line in that section's place instead - for example "No wins recorded yet.", "No Doing entry recorded.", or "No Next entry recorded." - then continue with the rest of the fixed output. This is separate from Open decisions, which is already documented below as normal to omit entirely when nothing lists any; that is not the malformed case this paragraph covers.

## Output, in this exact order

Once the files are read and folded, produce exactly this, in this order, and then stop:

```
## Recent wins 🐿️
- <the last 2-3 Done log entries, shown FIRST, on purpose>

## You were doing
<one line, from the checkpoint's Doing section>

## Next action
<the single next step, from the checkpoint's Next section, startable now>

## Open decisions
- <only if the checkpoint's Open decisions section has any>
```

Write it in the profile's `language` field. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.

Omit the Open decisions section entirely when the checkpoint lists none. Never pad it with "none" or similar filler.

## Then stop

Do not add a suggestion, a question, or a "shall we continue?" after Open decisions. The whole point of showing recent wins first is to hand the decision of what to do next back to the user, not to make it for them. Stop the moment the fixed output above is complete.

This bans only what this command would add on its own. It never suppresses a line the base rules license for this response - a mid-task recap line before Recent wins, an `Extra` section, the one-line checkpoint-failure report, or the scope-guard flag as the final line - each of which keeps the position and order the base rules give it.

## Respecting the profile

Any list here, Recent wins or Open decisions, respects `max_list_items` if the folded result happens to hold more entries than that. The cap matters more now than it did when one file held everything: each checkpoint file keeps only its own last 10 Done log entries, so folding several of them together can produce a long list even though no single file is long. Apply `max_list_items` to the folded list, keeping the newest entries.
