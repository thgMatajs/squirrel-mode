---
name: squirrel-plan
description: "Converge a messy, explicitly given idea dump - unstructured, in need of scoping - into a scoped action plan with one first action and a parking lot for tangents. Trigger only on an explicit request to turn a rambling, not-yet-scoped idea dump into that plan. Never trigger on an already-scoped request (e.g. planning the rollout of a defined feature across environments), and never on ordinary architecture questions or design discussion."
disable-model-invocation: true
---

<!-- GENERATED FILE. Source: skills/plan/SKILL.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->

# squirrel-mode plan (Cursor)

This skill turns a raw, disordered idea into a scoped, startable plan. Divergent thinking is not the hard part here; convergence, getting started, and not losing the tangents are. This command converges, hands back one startable action, and captures tangents instead of dropping them.

## Step 1: get the idea

If nothing was provided with the request and nothing else was pasted, ask exactly one question: "Tell me the idea - messy is fine." Then stop and wait for the reply. Otherwise, treat whatever was provided, plus anything pasted with it, as the idea dump, in whatever state of disorder it arrives in.

## Step 2: clarify, at most 3 questions

Ask at most 3 clarifying questions, one at a time, waiting for each reply before asking the next. Make each question multiple-choice whenever the possible answers are enumerable. Never ask an open-ended "tell me more" question. Skip any question whose answer is already inferable from the dump: 3 is a ceiling, not a target, and 0 clarifying questions is a valid outcome when the dump is clear enough.

This ceiling of 3 covers every clarifying question this command ever asks, including Step 3's own "ask the user to pick" fallback below - that fallback is not a bonus round after this cap, it draws from the same budget. Track how many of the 3 you have already spent before reaching Step 3.

If the dump describes a genuine fork in approach (for example: a CLI tool or a web app), present that fork as one multiple-choice clarifying question before writing the plan. Never write two parallel plans for the two branches of a fork.

## Step 3: converge and write the plan

Do not keep iterating once Step 2 is done. Produce the plan below in one pass.

Write the plan in the profile's `language` field. If there is no profile, or `language` is `auto`, mirror the language the user is currently writing in.

Use exactly this section structure, in this order:

```
## The idea in one sentence
<forces convergence>

## Goal
<what success looks like, concretely, 1-2 lines>

## Scope
- IN: <3-5 bullets max>
- OUT (for now): <explicitly deferred - a decision, not a loss>

## Smallest useful version
<the minimal version that already delivers value - days, not months>

## Plan
Phase 1 - <name> (expanded fully below, in the form set by `step_style`, respecting max_list_items)
Phase 2 - <name> (one-line summary only)
Phase 3 - <name> (one-line summary only)

## First action
<ONE step, startable in under 10 minutes, right now>

## Parking lot 🐿️
<every tangent and "what if" that came up - captured, but explicitly not in the plan>
```

Rules for this section:

- "The idea in one sentence" forces convergence. If it genuinely cannot be said in one sentence, and at least one of the 3 clarifying questions from Step 2 is still unspent, spend one now: say what is competing, in one line, and ask the user to pick between the readings. If all 3 are already spent, do not ask again - pick the likeliest reading yourself, say in one line which reading you picked and why, and continue with the plan. Convergence always happens by the end of this step, asking or not.
- Recommend exactly one path through the plan. Never present it as a menu of equally-weighted alternatives.
- Expand only Phase 1. Phase 2 and Phase 3 (and any further phases) get one line each, no sub-steps, no further detail until Phase 1 is done. This is deliberate, not an omission, and it keeps working-memory load flat.
- Every Phase 1 step carries a concrete time estimate, and that estimate must be 45 minutes or less (a 45-minute cap). When a step would take longer than that, split it into two or more steps until each one is 45 min or under.
- The Parking lot section is mandatory whenever the idea dump contained tangents or "what if"s. Never drop a tangent to keep the plan narrow; park it instead so the user does not feel anything was lost. Only omit the Parking lot entirely when the dump genuinely raised no tangents at all.
- If more than max_list_items scope bullets or Phase 1 steps would otherwise appear, group the excess and keep only the current chunk in full detail, the same way the base rules chunk any other list.

## Step 4: offer file or Jira, only if relevant

After the plan, add one line only if it is genuinely relevant: "Want this as a file, or as Jira tickets?" Skip this line entirely when neither destination makes sense for the plan just produced.

If the user asks for Jira tickets: when a Jira tool is available, show a preview of the issues that would be created (one line per issue) and ask a single yes/no confirm before creating anything. When no Jira tool is available, say so in one line and offer the file instead.

## Respecting the profile

Any list in the plan respects `max_list_items`. Phase 1's expanded steps follow `step_style`, the same way the base rules number any other multi-step work. This command recommends exactly one path; `options_per_answer` governs alternatives elsewhere, not the fork question in Step 2, which is inherent to the idea itself.
