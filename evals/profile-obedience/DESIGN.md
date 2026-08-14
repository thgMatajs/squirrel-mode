# pilot2 design: does the model obey the profile, not just receive it?

Pilot 1 proved injection: the profile text reaches the model's context.
This pilot asks a different question: for each of the 11 fields, when the
profile's value demands behaviour the base rules do **not** already
produce by default, does the model's response actually change?

`profile-contrast.md` sets every field to the value furthest from
`rules/base-rules.md`'s default, so an ignored profile is maximally
visible. Three arms (reusing `../pilot/run-pilot.sh`'s convention):

- **A** = bare `claude`, no plugin.
- **B** = `--plugin-dir squirrel-mode`, no `~/.squirrel/profile.md`. Gets
  the base rules' defaults with no profile field to obey or ignore.
- **C** = `--plugin-dir squirrel-mode`, with `profile-contrast.md` in
  place as `~/.squirrel/profile.md`.

## Reading the results: B is the control, not a spare data point

Every check below asks one question of a response: does it match the
**contrast** value (verdict HONOURED) or does it match the **default**
value (verdict IGNORED)? That check runs identically on every arm's file
for the same prompt — the verdict just reports which side of the line
that particular response landed on.

That means a HONOURED verdict on arm C proves obedience **only if arm B,
graded by the same check on the same prompt, comes back IGNORED.** If B
also grades HONOURED, the prompt itself pulls models toward that
behaviour regardless of any profile — the contrast value was never
actually a contrast for this prompt, and C's HONOURED is worthless. Read
every field's B and C rows side by side, never C alone.

This matters most for the three fields whose contrast value is "no" /
absence-based (`confirm_topic_switch`, `progress_recap`, `extras_section`):
there is no positive marker HONOURED can point to, only the *lack* of one.
For those three, B carries essentially all the evidential weight — C's
"nothing here" only means something once B's "something here, using the
base-rule default's own template" is confirmed on the same turn. **The
two-message flow for fields 8 and 9 must therefore be run on arm B as
well as arm C**, not only on C; grade.py already grades whatever
`arm<X>-p<N>-turn2.json` files exist, so this is a data-collection
requirement on the runner, not a code change.

## Field-by-field

### 1. `language` — contrast: `pt-BR` (default: `auto`)

**Falsifiable.** All prompts are in English, so default `auto` mirrors
English — behaviourally indistinguishable from simply not switching
language. Setting `pt-BR` demands a response in a language the prompt
never used, something the default state genuinely cannot produce.

- Prompt (line 1): "Why is it worth backing up a folder on Linux
  regularly, instead of only occasionally?" — a "why" question, chosen
  specifically so the natural answer is a sentence or two of reasoning,
  not a one-line command plus a code block. See the postmortem below for
  why that specific shape mattered.
- HONOURED: response is in Portuguese (diacritics, `não`/`você`/`para`/...).
- IGNORED: response is in English — which is also exactly what `auto`
  produces on this prompt, so IGNORED and "did nothing" look identical.
  That identity is the point: it's what makes this field cleanly
  falsifiable rather than restating a default.
- Mechanical check: count Portuguese function-word/diacritic hits vs a
  curated English stopword list (code blocks stripped first). `pt_score
  > en_score` and `pt_score >= 1` → HONOURED. `en_score > pt_score` →
  IGNORED. Otherwise INDETERMINATE. A single unambiguous PT-only hit with
  zero EN hits is enough to call HONOURED — the check no longer needs
  volume to accumulate. See the postmortem for why that changed.

**Postmortem (orchestrator-caught defect, fixed here).** The original
prompt was "What is a good way to back up a folder on Linux?", which
invites exactly the one-line-command-plus-fenced-code answer the same
combined profile's `explanation_budget: 1` demands. That collided with
the original `check_language`, which required `pt_score >= 2` to call
HONOURED and counted the bare word `a` as an English marker. `a` is
simultaneously the English indefinite article and the Portuguese
feminine article/direct-object pronoun — a genuine orthographic overlap,
not a typo — so a short, unambiguously-Portuguese reply such as `"Use o
rsync para copiar a pasta."` scored `pt_score=1, en_score=1` (the lone
`para` hit against the lone `a` hit) and fell to INDETERMINATE, even
though a human reads it as Portuguese without hesitation. Reproduced with
the orchestrator's own fixtures at `pilot2/myfix/armC-p1.json` and
`pilot2/myfix2/armD-p1.json`.

The field's own contrast value (`pt-BR`) was fine; a *different* field's
contrast value (`explanation_budget: 1`, active in the same combined
profile) was starving the language check's signal by forcing short
replies — the same cross-field-interaction class already documented for
`code_style`/`step_style` and `explanation_budget`/`code_style` above,
just not caught for this field the first time. Two independent fixes,
both applied: (1) the prompt no longer invites a code-block answer at
all, so `explanation_budget` has nothing to compress here; (2) the
checker was hardened to decide on a single high-signal hit rather than
requiring volume — see "mutation proof" below. `check_language`'s
English-marker list also now excludes the bare word `a` outright, since
that collision would recreate the same failure on *any* short Portuguese
reply, independent of which prompt provoked the short reply.

**Mutation proof** (run against hand-built fixtures, not live model
output — see `pilot2/mutation-check.py` for the exact script, which now
carries all seven cases below as a permanent regression suite, not a
one-time proof):

```
short pt-BR sentence  ("Use o rsync para copiar a pasta.")        -> HONOURED       pt_score=1 en_score=0
short English sentence ("Use rsync to copy the folder.")          -> IGNORED        pt_score=0 en_score=2
code-only, no prose    ("```bash\nrsync -a /src/ /dst/\n```")     -> INDETERMINATE  pt_score=0 en_score=0
```

The third case is required to stay INDETERMINATE, not become a verdict —
there is no language signal in a bare code fence, and forcing one would
be exactly the kind of fabricated verdict this whole grader is built to
refuse.

**Cycle-2 postmortem: the cycle-1 fix introduced a worse defect.** A
second, independent review built four short English fixtures
(`pilot2/myfix3/armE1-p1.json` … `armE4-p1.json`) and all four graded
HONOURED — clean English read as "the model honoured `language: pt-BR`."
This is a more severe failure than cycle 1's: cycle 1 produced a visibly
inconclusive INDETERMINATE; this one produced confident, silent, *wrong*
confirmation of the product's central feature.

Cause: cycle 1's widened PT word list included `no`, `do`, `um`, `da`,
`na`, `nas`, `nos`, `dos`, `das`, `mais`, and `com` — the first two are
ordinary English words, `um` is a common English filler ("um, I don't
know"), and none of them had an EN-side counterweight, so a single stray
`do`/`no` in an all-English reply was enough to tip `pt_score` above
`en_score=0` under the loosened `pt_score>=1` threshold. `com` carried
its own separate risk (any bare `.com` mention outside a fenced block).
Fixed by re-evaluating every PT-list token individually against English
rather than trusting the earlier list, and cutting every one that had a
standalone English reading: `para, você(s), não, também, uma, isso,
esse/essa, está, são, então, função, obrigado, aqui, muito, pelo/pela,
que, de` is what survived that pass, plus the accent chord. `do` and `no`
moved to the EN list instead (see EN_WORDS_RE's own comment for the
accepted residual tradeoff on genuine PT `do`/`no` contractions).

The EN list was also widened per the same fix request (`not, it, if, do,
no, need, run, from, by, at, can, just, then, each, all, any`), but two
of the originally-suggested additions were caught and dropped before
shipping, not after a third report: **`as`** is the Portuguese feminine
plural article — adding it would recreate the exact `a` collision fixed
in cycle 1, one letter later. **`use`** is also the Portuguese imperative
of `usar` ("Use o rsync…" — the standard short-PT-BR fixture itself
starts with it); adding it turned the required "short pt-BR → HONOURED"
case into a tie (`pt_score=1, en_score=1` → INDETERMINATE), which would
have silently broken an already-passing test. Both are documented in
`EN_WORDS_RE`'s comment in `grade.py` rather than silently omitted.

**Mutation proof, cycle 2** (added to `pilot2/mutation-check.py`
permanently, not just run once — see that file's own comment for why):

```
E1 "No, do it manually."           -> IGNORED   pt_score=0 en_score=3
E2 "No need. Do that once."        -> IGNORED   pt_score=0 en_score=4
E3 "Do not do this."               -> IGNORED   pt_score=0 en_score=4
E4 "Use rsync. No cron needed."    -> IGNORED   pt_score=0 en_score=1
```

All four re-verified against the original cycle-1 fixtures too
(`myfix/armC-p1.json` → still HONOURED, `myfix2/armD-p1.json` → still
HONOURED, `myfix2/armC-p1.json` long PT paragraph → still HONOURED) —
the fix does not just move the failure from one direction to the other.

### 2. `answer_position` — contrast: `after-one-line-context` (default: `first`)

**Falsifiable**, with a caveat on how cleanly "one line of context" is
detected. Default already forbids preamble and demands the answer up
front; the contrast value demands the opposite of that — exactly one
short orienting line before the answer, never zero, never a paragraph.

- Prompt (line 2): "Which HTTP status code means 'Not Found'?" — answer
  token `404` is short, literal, and unambiguous.
- HONOURED: `404` is absent from the first line/sentence, present in the
  second, and the first unit reads as a short orienting line, not a list
  or heading.
- IGNORED: `404` is in the very first line/sentence (matches default).
- Mechanical check: split into "units" (newline-delimited, falling back
  to sentence-split if the model wrote one unbroken paragraph); check
  which unit contains the token. Caveat: a model that fuses context and
  answer into one sentence with no clean break falls to INDETERMINATE
  rather than a forced guess — a deliberate refusal to fabricate a
  verdict the text doesn't support.
- **Cycle-2 false-positive fix**: the check could not tell a genuine
  one-line orienting context from generic preamble rule 2 bans outright
  ("Great question!\n404 is the code for Not Found." graded HONOURED
  before the fix — confirmed with a fixture, not just reasoned about). A
  first unit matching a short blocklist of stock openers (`great
  question`, `sure`, `happy to help`, `of course`, `certainly`, `no
  problem`, …) now downgrades to INDETERMINATE instead: this check has no
  way to certify the model's one-line context was genuine rather than
  banned filler, so it no longer claims to.

### 3. `step_style` — contrast: `checklist` (default: `numbered`)

**Falsifiable.** Default renders multi-step work as `1. 2. 3.`; the
contrast value demands `- [ ]` checklist markers instead — a different,
grep-able literal syntax, not a restatement.

- Prompt (line 3): "Explain how to create a new Git repository and make
  the first commit."
- HONOURED: `- [ ]` markers present, count ≥ any numbered markers.
- IGNORED: numbered markers present, no checklist markers.
- Mechanical check: regex count of `^\s*-\s*\[ \]` vs `^\s*\d+\.\s`.

### 4. `max_list_items` — contrast: `3` (default: `5`)

**Falsifiable**, chosen deliberately at the tight end of the legal 3–7
range rather than the loose end (`7`). A `7` cap is so loose that a
model ignoring the profile and following the base default of 5 — or no
cap at all — would still happen to satisfy it, proving nothing. `3` is
tight enough that the base default (5) visibly fails it.

- Prompt (line 4): "List the main steps to set up a new CI pipeline from
  scratch, from checking out code to deploying to production." — chosen
  because a natural full breakdown (checkout, install, lint, test,
  build, deploy) is expected to run past 3 items on its own, so the cap
  actually has something to constrain.
- **This expectation is a design-time assumption, not a guarantee**: if
  arm B's actual response happens to list ≤3 items anyway, this row is
  vacuous by the same B-as-control logic above, and should be flagged as
  such when real data comes in, not silently trusted.
- HONOURED: current-phase items shown ≤3, remaining phases (if any)
  named in one line each per rule 3, not broken down further.
- IGNORED: more than 3 items shown at once.
- Mechanical check: count checklist-marker lines and numbered-marker
  lines separately, then take the **max of the two counts**, not the
  sum. Rationale: a compliant response under this same contrast profile
  shows ≤3 checklist steps for the current phase *plus* one-line names
  for later phases, which the model may render as plain bullets or an
  unrelated second list — summing distinct marker types would count
  that second, non-step content against the cap and produce a false
  IGNORED. Count ≤3 → HONOURED; >3 → IGNORED (evidence notes when the
  count lands exactly on 5, the base default, as a hint of what leaked
  through).

### 5. `code_style` — contrast: `step-by-step` (default: `code-first`)

**Falsifiable.** Default shows code before any explanation; the
contrast value demands steps stated first, code block after — a
detectable ordering inversion.

- Prompt (line 5): "Write a bash command to find all files larger than
  100MB in the current directory."
- HONOURED: a step marker line precedes the first ` ``` ` fence.
- IGNORED: the fence appears at/near the start, before any step marker.
- Mechanical check: compare character offsets of the first ` ``` ` and
  the first step-marker line. The step-marker regex matches **both**
  numbered and checklist markers — `step_style: checklist` is active in
  this same combined profile, so a detector that only looked for `\d+\.`
  would misclassify a fully compliant checklist-then-code response as
  IGNORED. This cross-field interaction is exactly the kind of thing a
  single combined profile can hide if the checks aren't built to expect
  it (see "Known limitations" below).

### 6. `explanation_budget` — contrast: `1` (default: `3`)

**Falsifiable**, chosen at the tight end (the field is an unbounded
positive integer) for the same reason as field 4: a loose budget would
be satisfied by accident.

- Prompt (line 6): "Write a Python function that checks if a number is
  prime."
- HONOURED: at most 1 line of explanation outside the code block.
- IGNORED: more (evidence flags exactly-3 as a likely default leak).
- Mechanical check: strip code fences, then **also exclude any line that
  is itself a step marker** (numbered or checklist) before counting the
  remaining prose lines. Rationale, stated as an interpretive choice
  rather than a certainty: `code_style: step-by-step` is active in the
  same combined profile, and rule 5's own wording ("state the numbered
  steps first... and keep the total explanation within budget") treats
  the step list and "the explanation" as two different things, not one
  budget counted twice. Without this exclusion, every compliant
  step-by-step response would blow a budget of 1 on its mandatory steps
  alone, producing spurious IGNORED verdicts that reflect a bug in the
  check, not a real ignored profile.

### 7. `options_per_answer` — contrast: `3` (default: `1`)

**Falsifiable, with a real trap avoided on purpose.** An earlier draft
of this prompt named three candidate tools directly ("cron, systemd
timers, or anacron — which is best?"). That's the exact failure mode
this whole pilot exists to catch: naming the candidates invites *any*
model to compare all three unprompted, options_per_answer or not, so the
check would stop discriminating. The prompt below stays open so that
enumerating alternatives is a genuine behavioural choice.

- Prompt (line 7): "What's a good way to schedule a script to run every
  night on Linux?"
- HONOURED: ≥3 of {cron, systemd, anacron} each introduced as their own
  top-level list item, unprompted.
- IGNORED: one tool recommended, in prose, no enumerated alternatives
  (matches default "recommend one path").
- Mechanical check: regex for top-level list markers (≤2 leading
  spaces), then count **distinct top-level lines that each name a tool**
  — not the raw number of keyword hits. `count≥3` → HONOURED, `count≤1`
  → IGNORED, `count==2` → INDETERMINATE. `at` was deliberately dropped
  from the keyword set: as a bare word it collides with the preposition
  ("run it **at** midnight") too often to grep reliably, and
  cron/systemd/anacron alone already span the threshold this check
  needs — adding it would add noise, not signal.
- **Cycle-2 false-positive fix**: the original version counted *keyword
  hits anywhere in the qualifying lines*, not lines. `"- Use cron; it
  beats systemd and anacron for a simple nightly job."` is a single
  recommendation with a comparison clause — exactly default
  `options_per_answer=1` behaviour — but it names all three tools in one
  bullet, and the old count (3 keyword hits) graded it HONOURED.
  Confirmed with a fixture before fixing. Now each top-level line can
  only ever contribute once, however many tool names it mentions.

### 8. `confirm_topic_switch` — contrast: `no` (default: `yes`) — MULTI-TURN

**Falsifiable only under a specific, narrower reading — flagged here
adversarially rather than assumed.** Rule 10's own text says the
confirmation fires "only when the assistant itself is the one
introducing the different topic, or when the switch would abandon a
task that is still open and unfinished" — but then carves out "Do not
ask when the user has already named the new topic themselves... an
explicit request to switch is the answer to that question." Read
broadly, almost any new question the user asks "names" its own topic,
which would make the confirmation gate nearly unreachable from ordinary
user prompting regardless of `confirm_topic_switch`'s value — the gate
would only ever fire when the *assistant* spontaneously introduces a
tangent, which rule 7 ("No tangents") separately forbids. That reading
would make this field close to **NOT MEASURABLE** by prompting alone.

The design below takes the narrower, defensible reading instead: an
**implicit** drift (the user just asks something unrelated, with no
"let's switch" framing) is not the same as an "explicit request to
switch," so it still falls under "task open and unfinished" rather than
the carve-out. This is the best-effort probe, not a certainty; a null
result on this field should be read against both readings, not treated
as proof the model ignored the setting.

Requires two messages — `claude -p` is single-shot. Mechanism: run turn
1, capture `session_id` from its `--output-format json` output, then run
turn 2 with `--resume <session_id>`. Concrete messages (verbatim, so a
future runner invents nothing):

- Turn 1 (prompts.txt line 8): "I'm going to walk you through migrating
  a small Flask app to FastAPI, one step at a time. Let's start with
  step 1: what's the first thing I should change?" — declares an open,
  unfinished, multi-step task.
- Turn 2 (not in prompts.txt — see "why only turn 1 is in prompts.txt"
  below): "What's a good recipe for banana bread?" — a fully unrelated
  question, deliberately **not** framed as "let's switch" or "forget
  that," to avoid tripping rule 10's explicit-request carve-out.

- HONOURED (`no`): turn 2's response just answers the banana bread
  question, no confirmation gate.
- IGNORED (behaves like default `yes`): turn 2 opens with a yes/no gate
  about pausing/switching before (or instead of) answering.
- Mechanical check (revised — see cycle-3 postmortem below): strip any
  line containing rule 15's scope-guard emoji (🐿️) first, then check
  whether what remains is *predominantly* a gate question rather than an
  answer — operationalised as "short enough that a delivered answer
  could not fit," not "contains a question mark somewhere." See
  `GATE_MAX_LEN`'s comment in `grade.py` for the exact threshold and the
  real numbers it's set against.
- Recall the control-arm requirement above: this only means something
  if arm B's turn 2 (default `confirm_topic_switch: yes`) actually shows
  the gate. Run this two-message flow on B as well as C.

**Cycle-3 postmortem: the check was reading rule 15's flag as rule 10's
gate.** Live pilot data (arms A and B, 26 calls, zero errors — the first
real-model run this design has had) surfaced this on `raw2/armB-p8-
turn2.json`, arm B, `confirm_topic_switch` at its base default (`yes`):

```
🐿️ This is drifting from the Flask→FastAPI migration. Park it?

That aside — a simple banana bread:

**Ingredients:** 3 ripe bananas mashed, 1/3 cup melted butter, ...
**Steps:**
1. Mash bananas, mix in melted butter.
...
```

The full recipe was delivered. There was no gate — nothing was withheld
pending a reply — yet the old check read "Park it?" plus the `?` in the
first 300 characters as a rule-10 confirmation gate and graded IGNORED.
This is wrong on the rule's own terms. `rules/base-rules.md` rule 10's
second paragraph draws exactly this line, in so many words:

> "This rule and rule 15's scope guard govern different acts, not
> competing ones: this rule's yes/no question is a **gate** on whether
> the assistant proceeds with a topic switch, while rule 15's one-line
> notice is **never a gate**, only a flag with an offer to park."

Rule 15 itself adds the other half of the proof: "The flag is the final
line of the response: it comes after the completed answer or action for
that topic, never before it." A correctly-placed rule-15 flag is
*evidence the answer was already delivered* — the opposite of a rule-10
gate, not a variant of one.

**The fix has two parts.** First, strip every line containing 🐿️ before
looking for anything — rule 15's flag is not evidence for or against
rule 10 in either direction, so it must not be read as either (this also
means a *correctly-placed* flag, which `raw/armB-p8-turn2.json` shows
appearing as the literal final line, is handled the same way as the
misplaced one in `raw2/`; the check does not need to know which position
is correct to get the verdict right). Second, and more load-bearing:
"gate" was re-read as "the response is predominantly the question, not
one that merely contains a question." A real rule-10 gate *replaces* the
answer — that's what "gate" means in the rule's own paragraph quoted
above, something the assistant's next action depends on. It cannot also
contain a full delivered recipe. Operationalised as a length check: after
stripping the scope-guard line, is what remains short enough that it
could only be the question, not the question plus a delivered answer?
`GATE_MAX_LEN = 250` is not a guess — it's set against the actual data:
the shortest real recipe body observed across all four turn-2 responses
in `raw/` and `raw2/` (arms A and B, after stripping any scope-guard
line) is 398 characters; a two-sentence gate question comfortably fits
under 250 with margin to spare.

**Proof, against real data first, then synthetic:**

```
raw2/armB-p8-turn2.json (the reported case)  -> HONOURED  (398 chars remain, no gate)
raw/armB-p8-turn2.json  (flag correctly at the end) -> HONOURED  (572 chars remain, no gate)
raw/armA-p8-turn2.json  (no plugin, no flag at all) -> HONOURED  (940 chars remain, no gate)
raw2/armA-p8-turn2.json (no plugin, no flag at all) -> HONOURED  (1099 chars remain, no gate)
```

Synthetic genuine-gate cases (`pilot2/gate-sweep/`), built to prove the
fix didn't just stop looking for gates altogether:

```
armGATE-p8-turn2.json  ("Do you want to pause... or should I finish the
                         migration step first?", no recipe at all)
                         -> IGNORED (182 chars remain, predominantly the question)

armGATE2-p8-turn2.json (the SAME gate question, but with a scope-guard
                         line attached in front of it, to prove stripping
                         the flag doesn't launder a real gate into a
                         false HONOURED)
                         -> IGNORED (102 chars remain, predominantly the question)
```

**Real-data observation, incorporated here because it bears directly on
this field's validity going forward:** across arm B's 13 real responses
(11 single-turn + 2 turn-2's), rule 15's scope-guard flag fired exactly
3 times, and all three are correct fires, not misfires: two are the
"no squirrel profile yet, run `/squirrel:init`" notice (`raw/armB-
p2.json`, `raw/armB-p10.json` — unrelated to scope drift, a different
squirrel-mode notice that happens to share the same 🐿️ emoji), and one
is the genuine Flask→FastAPI-to-banana-bread drift this field's own
probe is built to provoke. Arm A (no plugin) shows zero flags across its
13 responses, as expected — rule 15 doesn't exist without the plugin.
No misfire was found in this data. This is encouraging for rule 15's own
reliability, but it is a different question from this field's: the fix
above is about not *misreading* the flag as something it isn't, not
about whether the flag itself fires correctly (it did, both times it
mattered).

One more thing worth naming, found in this same data but out of scope for
this fix: `raw2/armB-p8-turn2.json` places the flag *before* the recipe,
which is itself a rule-15 positioning slip (rule 15 requires it as the
final line). `raw/armB-p8-turn2.json`, a separate real call, places it
correctly at the end. This is a model-consistency question about rule 15,
not about `confirm_topic_switch` — noted here because the data surfaced
it, not folded into this field's verdict.

### 9. `progress_recap` — contrast: `no` (default: `yes`) — MULTI-TURN

**Falsifiable**, and the cleanest of the two multi-turn fields — rule 8
gives an exact, literal template (`Done: <...>. Now: <...>.`), which is
about as strong a mechanical signature as this whole design gets.

Also requires two messages, for the same reason: rule 8 only fires
"mid-task," which needs an established task from a prior turn.

- Turn 1 (prompts.txt line 9): "Let's refactor a large function step by
  step. Step 1: identify the responsibilities inside the function. Go
  ahead and do step 1 now, then stop and wait for me."
- Turn 2 (verbatim, not in prompts.txt): "Continue to step 2: extract
  the first responsibility into its own function." — a true
  continuation of the same open task, not a topic change, to keep this
  field's probe independent of field 8's topic-switch dynamics.

- HONOURED (`no`): turn 2 goes straight into step 2, no recap line.
- IGNORED (behaves like default `yes`): turn 2 opens with `Done: ...
  Now: ...` (or an obvious paraphrase).
- Mechanical check: regex `^Done:.{0,200}?\.\s*Now:` (case-insensitive,
  anchored at the start) on turn 2's response. A looser bilingual
  fallback (`so far`, `previously`, `recap`, `feito`, `até agora`, ...)
  also counts as IGNORED, since any recap-style opener is a rule-8 leak
  even if it misses the exact template. Absence of both → HONOURED.
- **Stated assumption**: the exact `Done:`/`Now:` template is treated as
  a protocol literal that should appear regardless of `language`, the
  same way rule 14's checkpoint-file headings are clearly
  machine-oriented and not user-facing prose. This is an assumption, not
  a certainty — if a model instead translates the template into
  Portuguese (since `language: pt-BR` is active in the same combined
  profile), the strict check would miss it; the bilingual loose fallback
  exists specifically to reduce that risk, not eliminate it.
- Same B-as-control requirement as field 8: run on arm B too.

**Why only turn 1 is in `prompts.txt` for fields 8 and 9:** `prompts.txt`
is index-matched to `DESIGN.md`'s 11 rows, one line each, and
`../pilot/run-pilot.sh`'s loop only issues single, independent `-p`
calls — it has no `--resume` chaining. Turn 1 is what that existing
loop *can* produce today; turn 2 needs a new, small runner (sketched
below) that this design step does not execute. `grade.py` looks for an
optional `arm<X>-p<N>-turn2.json` and reports INDETERMINATE with an
explicit "turn2 not available" message when it's missing, rather than
grading turn 1 as if it were the whole probe.

Sketch of the turn-2 runner (POSIX `sh`, not executed here — flag
existence of `--resume` with `claude --help` first, never with `-p`):

```sh
#!/bin/sh
set -u
REPO=/Users/thg.inchurch/Documents/squirrel-mode
OUT=/path/to/results
MODEL=haiku
ARM=$1     # A | B | C
N=$2       # 8 | 9
MSG1=$3
MSG2=$4

t1="$OUT/arm${ARM}-p${N}.json"
t2="$OUT/arm${ARM}-p${N}-turn2.json"

if [ "$ARM" = "A" ]; then
  timeout 300 claude -p "$MSG1" --model "$MODEL" --output-format json \
    >"$t1" 2>"$OUT/arm${ARM}-p${N}.err" </dev/null
else
  timeout 300 claude -p "$MSG1" --model "$MODEL" --output-format json \
    --plugin-dir "$REPO" >"$t1" 2>"$OUT/arm${ARM}-p${N}.err" </dev/null
fi

sid=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    print(json.load(fh).get('session_id', ''))
" "$t1")

if [ -n "$sid" ]; then
  if [ "$ARM" = "A" ]; then
    timeout 300 claude -p --resume "$sid" "$MSG2" --model "$MODEL" \
      --output-format json >"$t2" 2>"$OUT/arm${ARM}-p${N}-turn2.err" </dev/null
  else
    timeout 300 claude -p --resume "$sid" "$MSG2" --model "$MODEL" \
      --output-format json --plugin-dir "$REPO" \
      >"$t2" 2>"$OUT/arm${ARM}-p${N}-turn2.err" </dev/null
  fi
fi
```

### 10. `extras_section` — contrast: `no` (default: `yes`)

**Falsifiable, but one-directional — stated plainly, not glossed over.**
Rule 7 gives a literal label ("a single `Extra` section") when the
setting is `yes` and something adjacent is worth flagging; `no` means
omit it entirely. The label's *presence* despite `no` is strong evidence
of IGNORED. Its *absence* is only weak evidence of HONOURED, because the
model may simply not have generated an aside worth flagging at all,
independent of the setting — an absence-based test can't tell "correctly
suppressed" apart from "never occurred to it."

To reduce (not eliminate) that ambiguity, the prompt is chosen to make
an aside highly likely under default behaviour: a near-universally
flagged JavaScript gotcha.

- Prompt (line 10): "Write a JavaScript function that deep-clones an
  object using JSON.parse(JSON.stringify(obj))." — the caveat that this
  method loses functions, `undefined`, `Date` objects, and circular
  references is one of the most commonly volunteered asides for this
  exact idiom.
- HONOURED: no `Extra` heading/label anywhere in the response.
- IGNORED: an `Extra` heading/label is present.
- Mechanical check: regex for a line that is (or starts) `Extra` as a
  heading/label, case-insensitive, with optional markdown heading/bold
  markup. Note also rule 13's safety override does **not** confound this
  prompt: the JSON.parse/stringify caveat is a correctness gotcha, not a
  destructive-operation/security/data-loss warning, so it isn't forced
  through regardless of `extras_section` the way a `rm -rf` warning
  would be — that's a bullet dodged by prompt choice, not by the check.
- **Cycle-2 false-positive fix**: the label check alone missed a response
  that states the exact same caveat under a different label —
  `"...\nNote: this drops functions, undefined values, and Date
  objects."` graded HONOURED before the fix, because "Extra" never
  appeared. Rule 7 says omit the *content* when `extras_section` is no,
  not "omit the specific word Extra". A secondary check now also fails
  the response if the caveat's own content (`function`, `undefined`,
  `date object`, `circular`, matched outside code fences) appears
  anywhere, regardless of label. Code fences are stripped first so the
  word `function` inside the JS answer itself — the prompt asks for a
  function — doesn't trip a false IGNORED on a genuinely clean response.

### 11. `tone` — contrast: `warm` (default: `neutral`) — always INDETERMINATE

**Not mechanically falsifiable, by design and by the task's own example.**
`warm` requires a brief acknowledgement **fused into the same sentence**
as the answer (rule 16) — never a standalone opener, which rule 2 would
then classify as banned preamble regardless of `tone`. Telling "fused
into one sentence" apart from "a separate sentence that merely precedes
the answer" is a structural/semantic judgment, not a regex.

- Prompt (line 11): "My tests keep failing and I don't understand why.
  Can you help me write a function to validate an email address?" — a
  mild-frustration cue, chosen to give a `warm` response something
  natural to acknowledge.
- grade.py's verdict for this row is unconditionally INDETERMINATE. It
  prints, for a human to read: hedge/empathy-word hit count (bilingual
  word list, since `language: pt-BR` is active in the same profile),
  whether the response opens with a greeting, average words per
  sentence, and whether the first sentence is a short standalone
  acknowledgement (which would itself be a rule-2/rule-16 violation if
  `warm` were genuinely intended). No verdict is fabricated from these
  numbers.

## Summary table

| # | field | contrast value | falsifiable? | turns |
|---|---|---|---|---|
| 1 | language | pt-BR | yes | 1 |
| 2 | answer_position | after-one-line-context | yes | 1 |
| 3 | step_style | checklist | yes | 1 |
| 4 | max_list_items | 3 | yes (assumes B's natural answer exceeds 3) | 1 |
| 5 | code_style | step-by-step | yes | 1 |
| 6 | explanation_budget | 1 | yes (assumes step-marker exclusion) | 1 |
| 7 | options_per_answer | 3 | yes | 1 |
| 8 | confirm_topic_switch | no | yes, under the narrow reading only — see field 8 | 2 (--resume) |
| 9 | progress_recap | no | yes | 2 (--resume) |
| 10 | extras_section | no | yes, one-directional (absence is weak evidence) | 1 |
| 11 | tone | warm | **no** — INDETERMINATE by construction | 1 |

No field's contrast value merely restates the default: every one of the
11 fields was set to a value the base rules do not already produce
un-prompted, so there is no "NOT MEASURABLE because it's already the
default" case here (unlike, say, leaving `code_style` at `code-first` or
`options_per_answer` at `1` would have been). The measurability gaps that
do exist are of a different kind: no clean mechanical separator exists
at all (`tone`), the separator only works in one direction
(`extras_section`), or the separator's very trigger condition is
contested by the rule's own text (`confirm_topic_switch`).

## Sweep for the field-1 bug class (orchestrator fix request)

The field-1 postmortem above is one instance of a general class:
**a check whose verdict needs a volume of matches to accumulate, paired
with another field in the same combined profile that systematically
shrinks the response for that field's own prompt.** After fixing field 1,
every one of the other 10 checks was walked through against two
questions: (a) does this check's verdict require several hits to cross a
threshold, or does one hit already decide it; and (b) if it needs volume,
does any other field's contrast value suppress that volume for that
field's specific prompt?

| field | needs accumulated volume to decide? | starved by another field on its own prompt? |
|---|---|---|
| answer_position | no — one token, one of two units | n/a |
| step_style | no — one checklist item with zero numbered items already decides | n/a |
| max_list_items | no — the cap check passes at count=1 already | no; prompt 4 doesn't invite a code block for `explanation_budget` to compress |
| code_style | no — positional (index of first fence vs. first step marker), not a count | n/a |
| explanation_budget | this field IS the pressure, deliberately set to the tight end; it isn't the victim here | n/a |
| options_per_answer | needs 3 distinct keyword hits, but they're proper nouns a model states directly, not prose that needs room to breathe | no; prompt 7 doesn't naturally invite a code block either |
| confirm_topic_switch | no — one hit inside a fixed ~300-char window | no; turn-2 replies (banana bread / step 2) aren't code, so `explanation_budget` doesn't apply |
| progress_recap | no — one hit at the very start of the reply | same as above |
| extras_section | no — presence of one literal label | n/a |
| tone | yes, its printed signal is volume-sensitive (hedge-word count, average sentence length) | **doesn't matter** — verdict is unconditionally INDETERMINATE regardless of signal quality, so a low-volume reply can only make the printed evidence sparser, never produce a wrong verdict |

**Result: no second instance of the reported class was found.** The
common reason is structural, not luck: every other check decides on the
*presence, position, or a low fixed count* of a marker (a token, a list
marker, a heading, an opening pattern), not on words accumulating past a
threshold across a whole response — `language` was the one check built
on raw word-frequency scoring across the full response body, which is
exactly why it was the one this class of bug could reach.

One additional weakness was found during this same sweep, but it is a
**different class** and is called out as such rather than folded into
the above: `check_explanation_budget`'s own step-marker-line exclusion
had no length bound, so a line of any length starting with `1. ` or
`- [ ] ` was excluded from the explanation count regardless of how much
prose it actually smuggled behind that prefix. This isn't one field
starving another's signal — it's a loophole in this one check's own
exclusion rule, exploitable independent of any other field's value.
Fixed anyway (`STEP_LABEL_MAX_LEN = 200`; a step-marker line longer than
that now counts as explanation, not as an excluded step label), and
documented in `check_explanation_budget`'s docstring and in field 6
above, kept separate from the field-1 writeup so the two are not
conflated.

## False-positive sweep, cycle 2 (orchestrator fix request, redone)

The cycle-1 sweep above asked "does this check need volume that another
field starves?" and concluded no second instance existed. That
conclusion was reached against code that has since changed, and the very
fix that changed it (the widened `language` word lists) is what produced
cycle 2's worse regression. Per the project rule this cycle opened with —
**a fix that adds a guard is new surface, reviewed against what the code
now says, not against the finding that motivated it** — the sweep is
redone here from a different, harder question, asked of *every* check
including the ones just edited in this same cycle:

> **What input makes this check say HONOURED when the truth is IGNORED?**

False positives, not false negatives. Each row below reports what was
found, whether it was reproduced with an actual fixture (not just
reasoned about), and what was done about it.

| field | false-positive vector found | reproduced with a fixture? | outcome |
|---|---|---|---|
| `language` | see the cycle-2 postmortem above (own field, found by the orchestrator) | yes — `myfix3/armE1..E4` | fixed: PT/EN lists rebuilt word-by-word; both suggested additions (`use`, `as`) that would have caused a *new* collision were caught and dropped before shipping |
| `answer_position` | first unit is generic preamble ("Great question!") rather than genuine context — indistinguishable to a regex, and rule 2 bans the former outright regardless of `answer_position` | yes — `fp-sweep/fp-answerpos.json` | fixed: preamble-pattern match now downgrades HONOURED to INDETERMINATE |
| `step_style` | a checklist/numbered example shown *inside* a fenced code block (unrelated sample, not the model's own formatting) would be counted as if it were | no fixture built; no realistic prompt in this pilot produces such a fence | fixed anyway (strip code fences before counting) — cheap, and confirmed to not change either currently-passing fixture's verdict |
| `max_list_items` | same code-fence exposure as `step_style` | no | fixed anyway, same reasoning. **Separate, NOT fixed**: the check only verifies the current phase stays ≤3 items; a response that silently drops the remaining phases instead of naming them in one line each (rule 3's other requirement) still counts ≤3 markers and still grades HONOURED. Verifying "later phases were actually named" is a semantic read this script does not attempt |
| `code_style` | a numbered aside unrelated to the actual task, positioned before an unrelated illustrative code fence, could satisfy the ordering check without being genuine "state the steps, then the real code" | not reproduced — needs a two-code-block response this pilot's prompt is unlikely to produce | **not fixed**, documented: the check only compares the *first* fence to the *first* step marker, not the holistic structure |
| `explanation_budget` | many short lines, each individually ≤`STEP_LABEL_MAX_LEN` and each disguised with a step-marker prefix, would each be excluded with no cap on how many — a "salami-sliced" version of the bug fixed last cycle | not reproduced — requires an adversarial, not merely non-compliant, response | **not fixed**, documented: `max_list_items` (a different check, different prompt) would likely catch a model that actually produces ten fake "steps," but that safety net does not apply within this same check's own prompt/response |
| `options_per_answer` | one bullet naming all three tools while recommending only one — options_per_answer=1 behaviour with a comparison clause | yes — `fp-sweep/fp-options.json` | fixed: counts distinct top-level *lines* naming a tool, not raw keyword hits |
| `confirm_topic_switch` | a genuine confirmation gate phrased outside the keyword list (e.g. "Mind if I finish the migration first?") would slip past the regex and grade HONOURED | not reproduced — would require enumerating natural-language paraphrases, which is unbounded | **not fixed** (inherently unfixable by a fixed keyword list): this is a completeness gap in any regex-based paraphrase detector, named as a limitation rather than closed |
| `progress_recap` | same paraphrase-completeness gap: a recap phrased as "Having finished identifying the responsibilities, let's now extract the first one." matches neither the strict template nor the loose opener list | not reproduced, same reason as above | **not fixed**, same reasoning — named, not closed |
| `extras_section` | the caveat restated under a different label ("Note: …") instead of being omitted | yes — `fp-sweep/fp-extras.json` | fixed: a secondary content-leak check now fires on the caveat's own wording (outside code fences) even without the literal "Extra" label |
| `tone` | n/a — verdict is unconditionally INDETERMINATE by construction, so there is no HONOURED for a false input to produce | n/a | immune by construction, not by accident |

**How this sweep was conducted**, so the method is checkable and not
just the conclusion: for each check, the actual response text that check
operates on was inspected for what it does NOT verify — i.e., what a
model could produce that satisfies the regex/count while failing the
rule it's supposed to detect. Three of the ten candidates were turned
into concrete fixtures and confirmed to reproduce a real HONOURED-for-a-
truly-IGNORED-input before any fix was written (`fp-sweep/fp-answerpos.
json`, `fp-sweep/fp-options.json`, `fp-sweep/fp-extras.json`), the same
discipline cycle 2's own report used. The other candidates are real but
lower-probability or fundamentally unfixable by regex (open-ended
paraphrase); those are named above rather than either silently ignored
or force-fixed with a patch that hasn't been tested against its own
adversarial input. `pilot2/fp-sweep/` is kept, alongside `myfix/`,
`myfix2/`, and `myfix3/`, as evidence for this sweep.

**On the checks fixed in this same cycle** (`options_per_answer`,
`extras_section`, `answer_position`, plus the code-stripping change to
`step_style`/`max_list_items`): each was re-run against the fixture that
motivated it (now passing) and against every fixture that was already
passing before this cycle (`myfix/`, `myfix2/`, `myfix3/`, and a rebuilt
local regression set covering `answer_position`, `code_style`, both
multi-turn fields, and `tone`) to confirm none of those regressed. None
did. This is the same "review new code against the current text, verify
against old fixtures too" loop the project rule asks for, applied to
this cycle's own edits before calling them done — not assumed safe
because the reasoning sounded right.

## Sweep for the same misattribution, cycle 3 (against real data, not fixtures)

Cycle 3's bug is a third distinct class, named plainly rather than
folded into the first two: **a check reading a different rule's output
as if it were the signal for the field it measures.** `confirm_topic_
switch`'s check was reading rule 15's scope-guard flag as rule 10's
gate. The obvious next question — could any other check be doing the
same thing with a different rule's output? — was answered empirically,
against the actual response text in `pilot2/raw/` and `pilot2/raw2/`
(the only two directories with a real, live scope-guard occurrence: 3
lines across arm B's 13 responses, found by a full grep for 🐿️ across
both directories, not a sample), rather than by reasoning about it in
the abstract:

**Method**: for each field with a real file containing the scope-guard
line (`answer_position` — `raw/armB-p2.json`; `extras_section` —
`raw/armB-p10.json`; `confirm_topic_switch` — the one already fixed
above), and for every other field's real arm-B file as a control, each
check was run twice: once on the file as-is, once on the same text with
every 🐿️ line stripped out first. A check that is silently reading the
flag as its own field's signal would disagree between the two runs. None
did, `confirm_topic_switch` aside:

| field | real file checked | flag present? | verdict with flag | verdict with flag stripped | contaminated? |
|---|---|---|---|---|---|
| `language` | `raw/armB-p1.json` | no | IGNORED | IGNORED | no (no flag in this file to begin with) |
| `answer_position` | `raw/armB-p2.json` | **yes** | IGNORED | IGNORED | **no** — the answer token `404` sits in the first line, resolved before the flag (on its own line two) is ever inspected |
| `step_style` | `raw/armB-p3.json` | no | IGNORED | IGNORED | no |
| `max_list_items` | `raw/armB-p4.json` | no | IGNORED | IGNORED | no |
| `code_style` | `raw/armB-p5.json` | no | IGNORED | IGNORED | no |
| `explanation_budget` | `raw/armB-p6.json` | no | IGNORED | IGNORED | no |
| `options_per_answer` | `raw/armB-p7.json` | no | IGNORED | IGNORED | no |
| `confirm_topic_switch` | `raw2/armB-p8-turn2.json` | **yes** | **was IGNORED, now HONOURED after the fix above** | HONOURED | **yes — this was the reported bug** |
| `extras_section` | `raw/armB-p10.json` | **yes** | IGNORED | IGNORED | **no** — the obvious candidate the fix request named, checked specifically: the caveat-content leak fires on `undefined`/`function`/`circular` in the model's own genuine caveat sentence ("Loses `undefined`, functions, `Date`, `Map`/`Set`, and circular refs..."), not on the flag line, which contains none of those words. Confirmed on both arms — `raw/armA-p10.json` (no flag, same IGNORED verdict for the same content reason) rules out the flag mattering either way |
| `tone` | `raw/armB-p11.json` | no | INDETERMINATE | INDETERMINATE | no (immune by construction regardless) |
| `progress_recap` | n/a | no file in `raw/`, `raw2/`, or `raw3/` carries the flag for p9/p9-turn2 | — | — | no exposure found in this data; the check's own reliance on the literal `Done:`/`Now:` template makes it structurally unlikely to confuse rule 15's flag for rule 8's recap either way, since neither word appears in the flag text |

**Result: no second contaminated field was found**, `extras_section`
included, checked specifically because the fix request named it as the
obvious candidate. The reason `extras_section` survives is not luck: its
two signals (the literal `Extra` heading, and the caveat's own content
words) are both about the *deep-clone caveat specifically*, and rule 15's
flag text never contains any of `extra`, `function`, `undefined`, `date
object`, or `circular` — there's no shared vocabulary for it to leak
through, unlike rule 10 and rule 15 which share the surface form (a
short line ending in `?`) that caused the actual bug.

This sweep is real-data-only by design (per the fix request), which
means its coverage is bounded by what arm B's 13 responses happened to
produce: three flag occurrences, all in `p2`/`p8-turn2`/`p10`. If a
future run surfaces the flag in a `p9`/`p9-turn2` (`progress_recap`) or a
`p1` (`language`) response, this table should be re-run against that
file specifically rather than assumed to still hold — the empirical
method above costs nothing to re-apply and is exactly how the one real
contamination here was found in the first place.

## Known limitations

- **Single combined profile, not eleven isolated ones.** Every arm-C
  response is generated under all 11 contrast values simultaneously,
  because that mirrors how squirrel-mode is actually used — one profile,
  not eleven. This is a deliberate simplification, not an oversight, but
  it means every field's check has to survive the other ten fields being
  active too. Two places where that interaction was caught and fixed
  during design: `code_style`'s step-detector had to accept checklist
  markers (not just numbered) because `step_style: checklist` is active
  in the same profile; `explanation_budget`'s line-count had to exclude
  step-marker lines because `code_style: step-by-step` is active in the
  same profile. Any future edit to the contrast profile's values should
  re-check both.
- **Protocol-literal assumption.** Rule 7's `Extra` heading and rule 8's
  `Done:`/`Now:` template are treated as fixed-format labels that survive
  translation, the same way rule 14's checkpoint headings clearly do.
  This is stated as an assumption, not verified: if a model translates
  these literals into Portuguese (since `language: pt-BR` is active
  throughout), the strict checks would under-fire. Bilingual fallbacks
  exist for fields 8, 9, and 11 to reduce this risk; field 10 relies on
  "extra" also being a common Portuguese loanword.
- **`options_per_answer`'s distinct-line-count check is still a proxy,
  not a semantic reading**, even after the cycle-2 fix (counting lines
  that name a tool, not raw keyword hits — see the false-positive sweep
  above). A model that lists three genuine *steps* of a single approach
  on three separate top-level lines, each of which happens to also name
  a different tool in passing, would still be miscounted as three
  options. Mitigated, not eliminated, by picking an open prompt where
  "steps of one approach" and "three tools" don't naturally overlap.
- **`confirm_topic_switch` and `progress_recap` are keyword/template
  checks over an unbounded paraphrase space.** The cycle-2 false-positive
  sweep names concrete phrasings (a confirmation gate or a recap opener
  worded outside the checked list) that would slip through as a false
  HONOURED. This is not something a fixed word list can close completely;
  it is a ceiling on how much confidence either field's verdict can
  carry, not a bug still waiting to be fixed.
- **`answer_position`'s unit-splitting is best-effort.** A response that
  fuses context and answer into one unbroken sentence with no detectable
  boundary falls to INDETERMINATE rather than a forced verdict.
- **This pilot does not re-verify pilot 1's injection claim.** It
  assumes the profile reaches context (confirmed by reading
  `scripts/load-profile.sh`, which injects `~/.squirrel/profile.md`
  verbatim via `cat`) and asks only whether the model then acts on it.
- **Haiku-specific, not a claim about all models.** `../pilot/run-pilot.sh`
  pins `--model haiku`. Obedience results here describe that one model;
  they should not be read as a claim about squirrel-mode's target model
  mix in general without re-running against others.

## Files in this directory

- `profile-contrast.md` — the arm-C profile, in the exact shape
  `skills/init/SKILL.md` step 4 specifies (raw file, no fence markers —
  confirmed against `scripts/load-profile.sh`, which injects it verbatim
  via `cat`).
- `prompts.txt` — 11 lines, English, index-matched 1:1 to the table
  above. Lines 8 and 9 are turn-1 messages only; turn-2 messages are
  quoted verbatim in this file (fields 8 and 9 above) and are not in
  `prompts.txt` because the existing `run-pilot.sh` loop cannot issue
  them (no `--resume` chaining).
- `grade.py` — mechanical grader; see its own docstring for the exact
  file-naming contract (`arm<ARM>-p<N>.json`, optional
  `arm<ARM>-p<N>-turn2.json`) and verdict semantics.
