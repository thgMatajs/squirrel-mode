---
description: "Resume work on this project after an interruption or at the start of a new session: show recent wins, what was being done, the next action, and open decisions, in that order, then stop. Trigger only on an explicit /squirrel:pickup invocation, or an explicit request to resume or pick up this project's past work at the start of a new session or after a stated interruption. Never trigger on a request to continue the live, current conversation (e.g. 'let's continue' or 'where were we' about what was just discussed in this same session), and never merely because a checkpoint exists."
---

# squirrel-mode pickup

/squirrel:pickup shows what this project's checkpoint remembers, in a fixed order, then stops.

## Find the checkpoint

Your context already contains a line stating the absolute checkpoint path for this project, in the form `Project checkpoint path: <path>`, injected at the start of this session. Read that exact path with the Read tool. Do not attempt to compute, guess, or re-derive the path yourself; it is already given to you, and any path computed independently could disagree with it.

If no such line is present in context (for example, a very old session), tell the user in one line that the checkpoint path is unavailable and that starting a new session will restore it, then stop.

If the path is present but no checkpoint file exists yet at that path, say so in one line, "No checkpoint found for this project yet.", and stop. This is the normal state for a project that has not yet completed a checkpointed unit of work.

If the checkpoint file exists but is empty, or is missing its Doing, Next, or Done log section, do not invent content for what is missing. Produce the fixed output below as usual, and for whichever of Recent wins, You were doing, or Next action has no source content, say so in one line in that section's place instead - for example "No wins recorded yet.", "No Doing entry recorded.", or "No Next entry recorded." - then continue with the rest of the fixed output. This is separate from Open decisions, which is already documented below as normal to omit entirely when the checkpoint lists none; that is not the malformed case this paragraph covers.

## Output, in this exact order

Once the checkpoint is read, produce exactly this, in this order, and then stop:

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

## Respecting the profile

Any list here, Recent wins or Open decisions, respects `max_list_items` if the checkpoint happens to list more entries than that. In practice both stay short by construction, since the checkpoint itself keeps only the last 10 Done log entries and only genuinely unresolved decisions.
