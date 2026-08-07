# squirrel-mode

A cross-platform AI coding-assistant extension that reshapes how the assistant communicates, so that people with ADHD can process the output. It changes response *shape*, never response *content*.

## Language

### The product

**squirrel-mode**:
The project and its brand. The repository name.
_Avoid_: squirrel mode (two words), Squirrel Mode

**squirrel**:
The installed plugin's identifier, and therefore the command namespace (`/squirrel:init`). Distinct from the project name on purpose: the namespace is typed dozens of times a day, the brand is read once.
_Avoid_: plugin name, package name

**Target**:
One of the three assistants squirrel-mode installs into: Claude Code, Codex, Cursor. Each target supports a different subset of the feature set.
_Avoid_: platform, host, client, IDE

### What shapes the output

**Base rules**:
The formatting constraints that apply to every response — answer first, numbered steps, no preamble, no tangents. Each one traces to a specific research finding. They are the product; everything else exists to deliver or adapt them.
_Avoid_: formatting rules, style rules, the skill, instructions

**Profile**:
A user's personal calibration of the base rules — their language, tolerance for list length, how much explanation they want per code block. One profile per person, shared across all their projects. Its existence is what separates squirrel-mode from a fixed rule list.
_Avoid_: config, settings, preferences, user config

**Calibration**:
The guided interview that produces a profile: one multiple-choice question per message, seven maximum. The interview's shape obeys the base rules it is configuring.
_Avoid_: onboarding, setup, wizard, init

### What survives interruption

**Checkpoint**:
A per-project record of the current mental model: what is being worked on, the single next step, and unresolved decisions. Exists so that returning after an interruption costs seconds instead of the usual recovery tax.
_Avoid_: state file, session file, memory, context file

**Done log**:
The accumulated list of completed work inside a checkpoint. Its purpose is emotional, not operational: ADHD blurs the memory of one's own accomplishments, so the record is shown back to the user first.
_Avoid_: history, changelog, completed tasks

**Parking lot**:
Tangent ideas captured explicitly and excluded from the plan in the same gesture. Capturing them is what makes narrowing the plan feel like a decision rather than a loss.
_Avoid_: backlog, icebox, TODO, notes

**Scope guard**:
The single-line flag raised when the conversation drifts from the declared task. It offers to park the tangent and never argues.
_Avoid_: drift detection, focus check, nag

### What restructures input

**Digest**:
The act of taking messy inbound content — a rambling ticket, a wall-of-text email, unstructured notes — and reshaping it into an actionable brief. Applies the base rules to content the user received rather than to the assistant's own output.
_Avoid_: summary, TL;DR, brief, parse
