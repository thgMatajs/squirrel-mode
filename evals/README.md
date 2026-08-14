# evals

The test suite checks that rule text is **present**. It cannot check that any of it is **followed**.
Everything in here measures the second thing, by running the product and grading what comes back.

Nothing here runs in CI. These evals cost money and need an authenticated `claude`, so they are run
by hand and their numbers are written down in the suite that produced them.

## profile-obedience

Does the model actually change its behaviour when `~/.squirrel/profile.md` sets a field, or does it
only read the file? Three arms over the same prompts: bare `claude`, plugin without a profile, and
plugin with one.

```sh
sh evals/profile-obedience/run.sh B /tmp/eval-b          # control: capture BEFORE a profile exists
sh evals/profile-obedience/run.sh C /tmp/eval-c
python3 evals/profile-obedience/grade.py --profile ~/.squirrel/profile.md /tmp/eval-c C
```

`run.sh` never writes to `~/.squirrel`. It refuses arm B when a profile exists and refuses arm C
when one does not, rather than quietly measuring the wrong thing.

`grade.py` grades a field against the value in the profile you point it at. When a profile value
equals its base default, the field is reported `NOT-MEASURABLE` and no response is opened at all:
obeying and ignoring the profile produce identical text there, so a verdict would be a coin toss
dressed as evidence.

`mutation-check.py` proves the grader can still fail. Run it before trusting any verdict; it needs
no API access and no network.

`DESIGN.md` carries the per-field design, what each check can and cannot see, and the residual
limitations that were accepted rather than fixed. Read it before adding a field.

## What has been measured so far

Against a real profile (`pt-BR`, `checklist`, `max_list_items: 5`, `explanation_budget: 1`,
`terse`), 11 prompts per arm, Sonnet:

- Five fields were honoured: `language`, `step_style`, `code_style`, `explanation_budget`,
  `options_per_answer`. The calibration is not decorative.
- Four were `NOT-MEASURABLE`, because that profile happens to match the default on
  `answer_position`, `max_list_items`, `confirm_topic_switch` and `progress_recap`.
- `tone` has no mechanical check and reports `INDETERMINATE` with the raw signals printed.
- `extras_section` graded `IGNORED`, contested: see DESIGN.md. The caveat moved inline instead of
  disappearing, which rule 7 forbids and rule 13 may license. The grader does not know about
  rule 13.

Separately, rule 8's mid-task recap fired in **1 of 10** runs with `progress_recap` at its default
of `yes`. That is a live defect with no fix yet, and the reason `run.sh` takes a repetition count:
one run of a stateful field proves nothing.

## When `claude plugin eval` opens up

The CLI ships a built-in eval runner (`claude plugin eval`) that reads `evals/**/case.yaml` and
`graders/*.md` and can add its own no-plugin baseline arm. It is in early access and refuses to run
here, which is why this directory holds a hand-written runner instead. When it becomes available,
port these cases to that format and delete the runner rather than maintaining both.
