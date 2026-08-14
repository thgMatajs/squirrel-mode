#!/usr/bin/env python3
"""
grade.py -- mechanical grader for the squirrel-mode pilot2 obedience probes.

Reads files named  arm<ARM>-p<N>.json  (the shape produced by
`claude -p ... --output-format json`, response text under the "result"
key) from a results directory, plus, for the two multi-turn fields, an
optional companion  arm<ARM>-p<N>-turn2.json .

For every (field, arm) pair it prints ONE line:

    field<TAB>arm<TAB>verdict<TAB>evidence

Verdicts are one of: HONOURED, IGNORED, INDETERMINATE, NOT-MEASURABLE.
NOT-MEASURABLE (added cycle 4) is not a late addition to the spec -- the
original task brief already named this exact case: "If a field's value
merely restates the default... mark it NOT MEASURABLE with that value;
that is a finding, not a failure." It fires whenever the LOADED PROFILE's
value for a field equals that field's base default (see BASE_DEFAULTS
below, transcribed from rules/base-rules.md's `## Defaults` table):
obeying and ignoring the profile then produce identical text, so no
regex can tell them apart, and calling either HONOURED would be crediting
default behaviour to the profile -- the same false-confirmation class as
cycles 1-3's bugs, just triggered by a profile value instead of a broken
check. A missing/unreadable RESULT file is still reported as INDETERMINATE
with "missing file: <path>" as the evidence (this part of the spec is
unchanged); a missing/unreadable PROFILE is a harder failure -- see
load_profile and main() below.

Every check below is a regex / count on the raw response text, run
against a TARGET VALUE read from a loaded profile.md, never a value
baked into the check itself (cycle 4: the grader used to hard-code the
synthetic contrast profile's values -- options_per_answer=3, tone=warm --
which silently mis-graded any other profile, including the user's real
one). None of the checks ask a model to judge anything. Where no clean
mechanical separator exists (tone), the verdict is unconditionally
INDETERMINATE and the extracted signal is printed for a human to read --
see DESIGN.md.

INTERPRETATION NOTE (see DESIGN.md "B as control"): a HONOURED verdict on
arm C only demonstrates obedience if arm B, run through the *same* check,
grades IGNORED (or, for the tone row, is at least visibly different).
This script does not enforce that pairing -- it grades each file
independently -- so read the per-arm rows side by side by hand.

Usage:
    python3 grade.py <results_dir> [--profile PATH] [ARM ...]

    <results_dir>  directory containing arm<ARM>-p<N>.json files.
                    Does not need to exist -- missing result files are
                    reported, not fatal.
    --profile PATH  a profile.md file in the exact shape
                    skills/init/SKILL.md step 4 specifies. Read-only --
                    this script only ever opens it for reading. Defaults
                    to ~/.squirrel/profile.md (DEFAULT_PROFILE_PATH below),
                    matching scripts/load-profile.sh's own default path.
                    See DESIGN.md's cycle-4 section for why every
                    invocation run *during this design task's own
                    testing* passes --profile explicitly instead of ever
                    relying on that default.
    [ARM ...]       optional list of arm labels to check (default: A B C,
                    matching ../pilot/run-pilot.sh's convention).

    Unlike a missing RESULT file, a profile that cannot be read or
    contains no parseable field at all is fatal: without a target value
    there is no basis for any of the four verdicts, so main() prints an
    error to stderr and exits 1 rather than emit 33 misleading rows.
"""
import json
import os
import re
import sys

DEFAULT_ARMS = ["A", "B", "C"]
DEFAULT_PROFILE_PATH = os.path.expanduser("~/.squirrel/profile.md")

# Transcribed once, literally, from rules/base-rules.md's `## Defaults`
# table. This is the product's own spec, not test data -- it changes only
# when that file changes, which is a separate maintenance event from "the
# profile under test changed."
BASE_DEFAULTS = {
    "language": "auto",
    "answer_position": "first",
    "step_style": "numbered",
    "max_list_items": "5",
    "code_style": "code-first",
    "explanation_budget": "3",
    "options_per_answer": "1",
    "confirm_topic_switch": "yes",
    "progress_recap": "yes",
    "extras_section": "yes",
    "tone": "neutral",
}


def load_profile(path):
    """Read a profile.md file in the exact shape skills/init/SKILL.md step 4
    specifies (a '# squirrel-mode profile' heading, then 'field: value'
    lines) and return {field: value}. Returns None if the file cannot be
    opened or contains no parseable field line -- never raises. Read-only:
    this function only ever opens `path` in "r" mode; it never writes to
    or deletes anything at it, including when `path` is the real
    ~/.squirrel/profile.md.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return None
    profile = {}
    for line in raw.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if key:
            profile[key] = value
    return profile if profile else None


def is_measurable(field_name, profile_target):
    """Returns (True, None) if `profile_target` differs from `field_name`'s
    base default -- this field can be graded. Returns (False, evidence)
    if it equals the default -- NOT-MEASURABLE, and the caller must not
    proceed to grade any response for this field at all (no result file
    should even be opened; see main()'s ordering). Exposed as its own
    function, separate from main()'s loop, so a proof can call it
    directly and show that the gate fires independent of any response
    text -- see mutation-check.py's NOT-MEASURABLE cases.
    """
    default_value = BASE_DEFAULTS[field_name]
    if str(profile_target).strip() == default_value:
        return False, (
            "profile value '{}' equals base default '{}' for {} -- obeying "
            "and ignoring the profile produce identical text here, so no "
            "verdict is possible (task note: this is a finding, not a "
            "failure)"
        ).format(profile_target, default_value, field_name)
    return True, None


def parse_int_or_none(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# File loading
# ---------------------------------------------------------------------------

def load_result(path):
    """Return (text, None) on success, or (None, evidence_string) on failure.
    Never raises -- every failure mode is reported as evidence text."""
    if not os.path.isfile(path):
        return None, "missing file: {}".format(path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        return None, "unreadable ({}): {}".format(exc.__class__.__name__, path)
    try:
        data = json.loads(raw)
    except ValueError as exc:
        return None, "not valid JSON ({}): {}".format(exc.__class__.__name__, path)
    if not isinstance(data, dict):
        return None, "JSON root is not an object: {}".format(path)
    text = data.get("result")
    if not isinstance(text, str):
        return None, "no string 'result' key in: {}".format(path)
    return text, None


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

CODE_FENCE_RE = re.compile(r"```.*?```", re.S)


def strip_code_blocks(text):
    return CODE_FENCE_RE.sub("", text)


def non_empty_lines(text):
    return [l.strip() for l in text.split("\n") if l.strip()]


def first_two_units(text):
    """Best-effort split of a response into a 'first unit' and 'second
    unit', for the answer_position check. Prefers a real line break;
    falls back to sentence-boundary splitting when the model wrote one
    unbroken paragraph."""
    lines = non_empty_lines(text)
    if len(lines) >= 2:
        return lines[0], lines[1]
    # fallback: sentence split
    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]
    if len(sentences) >= 2:
        return sentences[0], sentences[1]
    if len(sentences) == 1:
        return sentences[0], ""
    return "", ""


STEP_MARKER_LINE_RE = re.compile(r"^\s*(?:\d+\.\s|-\s*\[ \]\s)", re.M)
NUMBERED_MARKER_RE = re.compile(r"^\s*\d+\.\s+\S", re.M)
CHECKLIST_MARKER_RE = re.compile(r"^\s*-\s*\[ \]\s*\S", re.M)
# generic bullet, but NOT a checklist item (checklist already matched above)
TOPLEVEL_ITEM_RE = re.compile(r"^\s{0,2}(?:\d+\.|-\s*\[ \]|[-*])\s+\S", re.M)
EXTRA_HEADING_RE = re.compile(
    r"(?im)(?:^\s*#{0,6}\s*\**\s*extra\s*\**\s*:?\s*$|^\s*\**extra\**:\s*\S)"
)


# ---------------------------------------------------------------------------
# Field checks -- one function per field, each returns (verdict, evidence)
# ---------------------------------------------------------------------------

PT_WORDS_RE = re.compile(
    r"\b(para|voc[eê]s?|n[ãa]o|tamb[eé]m|uma|isso|ess[ae]|est[aá]|s[ãa]o|"
    r"ent[ãa]o|fun[cç][ãa]o|obrigad[oa]s?|aqui|muito|pel[oa]|que|de)\b",
    re.I,
)
PT_DIACRITICS_RE = re.compile(r"[ãõçáéíóúâêà]", re.I)
# Every word above was re-checked, one at a time, against English (not just
# carried over) after a real false-HONOURED regression: "no", "do", "um",
# "da", "na", "nas", "nos", "dos", "das", "mais", and "com" were CUT because
# they are ordinary English words/fragments ("no", "do") or an English filler
# ("um") or collide inside "*.com" mentions outside a fence -- the cycle-2
# postmortem below has the full account. What remains here has no standalone
# English reading. "a"/"as" stay off both lists on purpose: "a" is the
# Portuguese feminine article, and "as" is its plural -- both would recreate
# the exact "a" collision fixed in cycle 1, just one letter later.
EN_WORDS_RE = re.compile(
    r"\b(the|is|and|to|of|in|for|on|with|this|that|you|your|are|was|were|"
    r"will|would|should|could|have|has|been|not|it|if|do|no|need|run|from|"
    r"by|at|can|just|then|each|all|any)\b",
    re.I,
)
# "use" and "as" were deliberately NOT added, despite being on the original
# fix request's suggested list -- both re-broke a currently-passing test when
# tried (see cycle-2 postmortem): "use" is also the Portuguese imperative of
# "usar" ("Use o rsync..."), and "as" is the Portuguese feminine plural
# article, the same collision class as "a". Catching this before shipping,
# rather than after a cycle 3 report, is what "review the guard as new code"
# means in practice.


def check_language(text):
    """Contrast value: pt-BR. Default (auto) mirrors the English prompt,
    so IGNORED and 'default behaviour' look identical here on purpose --
    that identity is itself part of what makes this field cleanly
    falsifiable (see DESIGN.md field 1).

    Decides on function-word hits + diacritics rather than requiring a
    volume of text to accumulate: a single unambiguous PT-only hit (e.g.
    "para") with zero EN hits is enough to call HONOURED. This is a
    deliberate hardening after a real bug: the previous version required
    pt_score>=2, which read a 6-7 word PT-BR sentence as INDETERMINATE
    whenever the combined contrast profile's explanation_budget=1 kept the
    response short -- the field's own contrast value was starving a
    different field's check. See DESIGN.md field 1 postmortem.
    """
    body = strip_code_blocks(text)
    pt_diacritics = len(PT_DIACRITICS_RE.findall(body))
    pt_words = len(PT_WORDS_RE.findall(body))
    pt_score = pt_diacritics + pt_words
    en_score = len(EN_WORDS_RE.findall(body))
    evidence = "pt_score={} en_score={}".format(pt_score, en_score)
    if pt_score > en_score and pt_score >= 1:
        return "HONOURED", evidence
    if en_score > pt_score:
        return "IGNORED", evidence + " (reads as English == default auto-mirror)"
    return "INDETERMINATE", evidence + " (no decidable signal either way, e.g. code-only response)"


GENERIC_PREAMBLE_RE = re.compile(
    r"(?i)^(great question|good question|sure[,!.]?$|sure[,!]|happy to help|"
    r"i can help|i'd be happy|of course[,!.]?$|certainly[,!.]?$|no problem)\b"
)


def check_answer_position(text, token="404"):
    """Contrast value: after-one-line-context. Default: first.

    Guard added by a cycle-2 adversarial false-positive sweep (not the
    reported bug -- one this same review found on its own new code): the
    check cannot tell a genuine one-line orienting context ("This is
    about HTTP status codes.") from generic preamble rule 2 bans outright
    ("Great question!") -- both are short, both precede the answer, both
    aren't a list. Rule 2's ban is unconditional and does not get waived
    by answer_position's contrast value, so a first unit that reads as
    stock preamble downgrades to INDETERMINATE instead of HONOURED: this
    check cannot certify that the model produced a compliant response
    just because it produced *some* short line before the answer.
    """
    first, second = first_two_units(text)
    if not first and not second:
        return "INDETERMINATE", "empty or unparseable response"
    if token in first:
        return "IGNORED", "answer token '{}' in first unit -- matches default answer_position=first: {!r}".format(token, first[:120])
    if token in second and len(first) <= 160 and not re.match(r"^\s*[\d\-*]", first):
        if GENERIC_PREAMBLE_RE.search(first.strip()):
            return "INDETERMINATE", "first unit reads as generic preamble, not genuine context -- can't tell honoured after-one-line-context from banned rule-2 preamble: {!r}".format(first[:120])
        return "HONOURED", "answer token absent from first unit ({!r}), present in second unit ({!r})".format(first[:120], second[:120])
    return "INDETERMINATE", "token '{}' not found in first two units: first={!r} second={!r}".format(token, first[:120], second[:120])


def check_step_style(text):
    """Contrast value: checklist. Default: numbered.

    Counts markers outside code fences only. Found by the cycle-2
    adversarial sweep: an unrelated numbered/checklist example shown
    INSIDE a fenced code block (e.g. a sample TODO file) would otherwise
    be counted as if it were the model's own step formatting. No such
    fixture broke this in practice yet, but the exposure is real and the
    fix costs nothing against the fixtures that already pass (neither
    currently has a fence at all).
    """
    body = strip_code_blocks(text)
    checklist_count = len(CHECKLIST_MARKER_RE.findall(body))
    numbered_count = len(NUMBERED_MARKER_RE.findall(body))
    evidence = "checklist_count={} numbered_count={}".format(checklist_count, numbered_count)
    if checklist_count > 0 and checklist_count >= numbered_count:
        return "HONOURED", evidence
    if numbered_count > 0 and checklist_count == 0:
        return "IGNORED", evidence + " (numbered list == default step_style)"
    return "INDETERMINATE", evidence + " (no clear list markers found)"


def check_max_list_items(text, cap=3):
    """Contrast value: 3 (tightest end of the 3-7 legal range, chosen so a
    model that ignores the profile and falls back to the base default of
    5 -- or to no cap at all -- is easy to catch).

    Counted per marker type, then the MAX of the two types is used (not
    the sum): a compliant response showing <=3 checklist steps for the
    current phase, plus one-line names for later phases (often rendered
    as plain bullets or occasionally as a second numbered list), must not
    have those two different pieces of structure added together into a
    false violation. See DESIGN.md field 4 for the worked justification,
    and its note that this prompt only falsifies the cap if arm B's
    natural answer actually exceeds 3 items in the first place.

    Counts markers outside code fences only, for the same reason as
    check_step_style above (cycle-2 sweep finding, not the reported bug).
    Known residual gap, NOT fixed here: this only verifies the CURRENT
    phase stays within the cap. Rule 3 also requires later phases to be
    named in one line each; a response that silently drops the remaining
    phases instead of naming them would still count <=3 markers and
    still grade HONOURED. Verifying "later phases were actually named"
    is a semantic check this regex-based script does not attempt --
    named here as a limitation, not silently left unnoticed.
    """
    body = strip_code_blocks(text)
    checklist_count = len(CHECKLIST_MARKER_RE.findall(body))
    numbered_count = len(NUMBERED_MARKER_RE.findall(body))
    count = max(checklist_count, numbered_count)
    evidence = "max(checklist={}, numbered={})={}".format(checklist_count, numbered_count, count)
    if count == 0:
        return "INDETERMINATE", evidence + " (no list items detected)"
    if count <= cap:
        return "HONOURED", evidence + " <= cap({})".format(cap)
    note = " (matches base default cap of 5 exactly)" if count == 5 else ""
    return "IGNORED", evidence + " > cap({}){}".format(cap, note)


def check_code_style(text):
    """Contrast value: step-by-step. Default: code-first.

    The step-marker regex matches BOTH numbered and checklist markers,
    because step_style=checklist is active in the same combined profile;
    a checklist-only step detector would misclassify a fully compliant
    step-by-step+checklist response as IGNORED (see DESIGN.md field 5).
    """
    code_idx = text.find("```")
    step_match = STEP_MARKER_LINE_RE.search(text)
    step_idx = step_match.start() if step_match else None
    if code_idx == -1:
        return "INDETERMINATE", "no code fence found in response"
    if step_idx is not None and step_idx < code_idx:
        return "HONOURED", "step marker at char {} precedes code fence at char {}".format(step_idx, code_idx)
    return "IGNORED", "code fence at char {} precedes any step marker (step_idx={}) -- matches default code_style=code-first".format(code_idx, step_idx)


STEP_LABEL_MAX_LEN = 200  # see docstring below: a "step marker" line longer
                          # than this is presumed to be smuggled prose, not
                          # a genuine short step label, and counts toward
                          # the explanation budget instead of being excluded.


def check_explanation_budget(text, budget=1):
    """Contrast value: 1 (tightest positive integer, vs base default 3).

    Lines that are themselves step markers (numbered or checklist) are
    excluded from the explanation-line count: code_style=step-by-step is
    active in the same combined profile, and rule 5 treats "the numbered
    steps" and "the explanation" as distinct things, not the same budget
    counted twice. Only prose lines outside both the code fence and the
    step list count against the budget. This is a stated interpretive
    choice, not a certainty -- see DESIGN.md field 6.

    Separate, secondary hardening (found opportunistically while sweeping
    for the field-1 bug class, NOT the same class -- see DESIGN.md's sweep
    section): a step-marker line of unbounded length would let a model (or
    an adversarial fixture) smuggle a full paragraph of prose behind a
    "1. " prefix and have it excluded from the budget for free. A step
    marker line longer than STEP_LABEL_MAX_LEN is therefore NOT excluded --
    it counts as explanation. This does not depend on any other field's
    contrast value shrinking anything; it is a loophole in this check's
    own exclusion rule, independent of the field-1 bug.
    """
    stripped = strip_code_blocks(text)
    lines = [l for l in stripped.split("\n") if l.strip()]
    explanation_lines = [
        l for l in lines
        if not (STEP_MARKER_LINE_RE.match(l) and len(l) <= STEP_LABEL_MAX_LEN)
    ]
    count = len(explanation_lines)
    evidence = "explanation_lines={} (after removing code + short step-marker lines)".format(count)
    if count <= budget:
        return "HONOURED", evidence + " <= budget({})".format(budget)
    note = " (matches base default budget of 3 exactly)" if count == 3 else ""
    return "IGNORED", evidence + " > budget({}){}".format(budget, note)


def check_options_per_answer(text, target=3):
    """Contrast value: 3. Default: 1 (recommend one path only).

    Prompt is deliberately open ("what's a good way to schedule a script
    on Linux") rather than naming candidate tools, so that enumerating
    several tools is a genuine behavioural choice and not something any
    model would do anyway once the tools are named in the question (see
    DESIGN.md field 7 and the advisor note this design incorporates).

    Counts how many of a small set of well-known, unambiguous Linux
    scheduling tools are each introduced as their own top-level list item
    (numbered or bulleted, <=2 leading spaces). "at" is deliberately
    excluded from the counted keyword set -- as a bare word it collides
    with the preposition "at" ("run it at midnight") too often to grep
    reliably; it would only add noise, not signal, given cron/systemd/
    anacron already span the 1-vs-3 threshold this check needs.

    Counts DISTINCT top-level lines that mention a tool, not the raw
    number of keyword hits. Found by a cycle-2 adversarial false-positive
    sweep (not the bug that was reported -- one this same review found on
    its own new code): "- Use cron; it beats systemd and anacron for a
    simple nightly job." is a single recommendation with a comparison
    clause -- exactly the default options_per_answer=1 behaviour -- but
    it mentions all three keywords, so counting keyword hits regardless
    of which line they land in scored it HONOURED. One line can only ever
    count once now, regardless of how many keywords it names.
    """
    tool_keywords = ["cron", "systemd", "anacron"]
    toplevel_lines = [l for l in text.split("\n") if TOPLEVEL_ITEM_RE.match(l)]
    lines_naming_a_tool = [
        l for l in toplevel_lines
        if any(t.lower() in l.lower() for t in tool_keywords)
    ]
    present = sorted(set(
        t for l in lines_naming_a_tool for t in tool_keywords if t.lower() in l.lower()
    ))
    count_lines = len(lines_naming_a_tool)
    evidence = "toplevel_items={} distinct_lines_naming_a_tool={} tools_seen={}".format(
        len(toplevel_lines), count_lines, present)
    if count_lines >= 3:
        return "HONOURED", evidence
    if count_lines <= 1:
        return "IGNORED", evidence + " (single recommendation == default options_per_answer=1)"
    return "INDETERMINATE", evidence + " (partial enumeration, unclear)"


SCOPE_GUARD_LINE_RE = re.compile(r"^.*🐿️.*$", re.M)
GATE_WORDS_RE = re.compile(
    r"(?i)\b(switch|pause|park|instead of|before (we|i) (continue|go|answer)|"
    r"do you want to|should i (pause|switch|continue)|"
    r"mudar de assunto|pausar|antes de continuar|quer mesmo mudar)\b"
)
# A genuine rule-10 gate is short: it's a bare question standing in for
# the answer, not a paragraph. The shortest real recipe body observed in
# pilot data (after stripping the scope-guard line) was 398 characters;
# a two-sentence gate question comfortably fits under 250. See DESIGN.md
# field 8 postmortem for the exact real-data comparison this threshold
# is set against.
GATE_MAX_LEN = 250


def check_confirm_topic_switch(turn2_text):
    """Contrast value: no. Default: yes.

    Requires turn2_text -- the response to the SECOND message of a
    two-message conversation (see DESIGN.md "multi-turn mechanism").
    Caller is responsible for passing None when no turn2 file exists;
    this function never reads a file itself.

    Cycle-3 fix, found against real pilot data (arm B, `raw2/armB-p8-
    turn2.json`), not a fixture: the response was

        "🐿️ This is drifting from the Flask→FastAPI migration. Park it?
         \n\nThat aside -- a simple banana bread:\n\n**Ingredients:** ..."

    -- the full recipe, delivered, with rule 15's scope-guard flag
    attached to it. The old check saw "park" + "?" in the first 300
    characters and called it a rule-10 gate. It wasn't: rule 10's own
    text (base-rules.md rule 10 second paragraph) draws this exact line
    itself: "this rule's yes/no question is a GATE on whether the
    assistant proceeds with a topic switch, while rule 15's one-line
    notice is never a gate, only a flag with an offer to park." Rule 15
    also states the flag "comes after the completed answer... never
    before it" -- so a genuine rule-15 flag, correctly placed, is proof
    the answer was ALREADY delivered, the opposite of a rule-10 gate.

    Fix, in two parts:
      1. Strip every line containing the scope-guard emoji before
         looking for a gate at all -- rule 15's flag is not evidence for
         or against rule 10, in either direction, so it must not be read
         as either.
      2. Re-read "gate" as "predominantly the question" rather than
         "contains a question somewhere" (this is the field's actual
         contrast behaviour: a real gate REPLACES the answer, it doesn't
         sit next to it). Operationalised as: the response, once the
         scope-guard line is gone, is short enough that a delivered
         answer could not fit -- see GATE_MAX_LEN's comment for the real
         numbers this threshold is set against, not guessed.
    """
    if turn2_text is None:
        return "INDETERMINATE", "turn2 response not available -- single-shot harness cannot exercise this field, see DESIGN.md multi-turn mechanism"
    body = SCOPE_GUARD_LINE_RE.sub("", turn2_text).strip()
    if not body:
        return "INDETERMINATE", "response is only rule 15's scope-guard line, nothing else to grade against rule 10: {!r}".format(turn2_text.strip()[:150])
    has_gate_words = bool(GATE_WORDS_RE.search(body[:300]))
    has_early_question = "?" in body[:300]
    is_short_enough_to_be_only_the_question = len(body) <= GATE_MAX_LEN
    if has_gate_words and has_early_question and is_short_enough_to_be_only_the_question:
        return "IGNORED", "response (after stripping rule 15's scope-guard line, {} chars remain) is predominantly a gate question, no answer delivered: {!r}".format(len(body), body[:180])
    return "HONOURED", "content was delivered in this turn (after stripping rule 15's scope-guard line, {} chars remain -- too long to be just a gate question) -- no rule-10 gate: {!r}".format(len(body), body[:120])


def check_progress_recap(turn2_text):
    """Contrast value: no. Default: yes.

    Requires turn2_text -- the response to the SECOND message of the
    step-1/step-2 continuation conversation (see DESIGN.md "multi-turn
    mechanism"). The primary check is the EXACT template rule 8 defines
    ("Done: <...>. Now: <...>."), treated as a protocol literal that
    should survive regardless of `language`, the same way rule 7's
    "Extra" heading is treated below -- an assumption, not a certainty,
    see DESIGN.md's stated limitation on protocol-literal translation.
    A looser bilingual fallback catches near-miss phrasing.
    """
    if turn2_text is None:
        return "INDETERMINATE", "turn2 response not available -- single-shot harness cannot exercise this field, see DESIGN.md multi-turn mechanism"
    head = turn2_text.strip()
    strict_re = re.compile(r"(?is)^\s*Done:.{0,200}?\.\s*Now:")
    loose_re = re.compile(r"(?i)^\s*(done|so far|previously|recap|feito|até agora|anteriormente|recapitulando|resumindo)\b")
    if strict_re.match(head):
        return "IGNORED", "turn2 opens with the exact rule-8 recap template: {!r}".format(head[:120])
    if loose_re.match(head):
        return "IGNORED", "turn2 opens with recap-like phrasing (loose match, not exact template): {!r}".format(head[:120])
    return "HONOURED", "turn2 has no recap opening: {!r}".format(head[:120])


CAVEAT_CONTENT_RE = re.compile(r"(?i)\b(function|undefined|date object|circular)\b")


def check_extras_section(text):
    """Contrast value: no. Default: yes.

    One-directional signal, stated plainly: presence of the literal
    "Extra" heading is strong evidence of IGNORED. Its absence is only
    weak evidence of HONOURED, because the model may simply not have had
    an aside to offer regardless of the setting -- see DESIGN.md field 10
    for why the prompt was chosen to make that false-negative less
    likely (a near-universally-flagged JSON.parse/stringify caveat).

    Secondary check, added by a cycle-2 adversarial false-positive sweep
    (not the reported bug -- one this same review found on its own new
    code): rule 7 says "omit it entirely" for extras_section=no, not
    "omit the word Extra". A response that states the exact same caveat
    under a different label ("Note: this drops functions, undefined
    values, and Date objects.") was scoring HONOURED, because the check
    only ever looked for the literal heading. It now also fails the
    response if the caveat's own content -- the words a deep-clone gotcha
    is stated in, regardless of label -- appears outside a code fence.
    Code fences are stripped first so the word "function" inside the
    JS answer itself (the prompt asks for a function) doesn't trigger a
    false IGNORED on a genuinely compliant, caveat-free response.
    """
    m = EXTRA_HEADING_RE.search(text)
    if m:
        return "IGNORED", "found an 'Extra' heading/label despite extras_section=no: {!r}".format(m.group(0)[:60])
    prose = strip_code_blocks(text)
    leak = CAVEAT_CONTENT_RE.search(prose)
    if leak:
        return "IGNORED", "no 'Extra' label, but the caveat's own content leaked under a different label/inline: {!r} in {!r}".format(leak.group(0), prose.strip()[:100])
    return "HONOURED", "no 'Extra' label and no caveat content outside code (one-directional signal -- absence is still weaker evidence than presence, see DESIGN.md)"


HEDGE_WORDS = [
    "frustrating", "tricky", "no worries", "totally understand", "i get it",
    "makes sense", "don't worry", "that's rough", "annoying", "nice work",
    "great job", "i know", "understandable",
    "frustrante", "chato", "complicado", "sei como", "sem problemas",
    "faz sentido", "entendo", "tranquilo", "calma",
]
GREETING_RE = re.compile(r"(?i)^\s*(hi|hey|hello|oi|ol[aá]|opa)\b")


def check_tone(text):
    """Contrast value: warm. Default: neutral.

    Per the task's own instruction, this is the canonical field with no
    clean mechanical separator: 'warm' requires the acknowledgement to be
    FUSED into the same sentence as the answer (rule 16), which is a
    structural/semantic judgment this script does not attempt. Verdict
    is unconditionally INDETERMINATE; only the extractable signal is
    reported, for a human to read.
    """
    lower = text.lower()
    hedge_count = sum(lower.count(w) for w in HEDGE_WORDS)
    greeting = bool(GREETING_RE.match(text.strip()))
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]
    if sentences:
        avg_words = sum(len(s.split()) for s in sentences) / len(sentences)
    else:
        avg_words = 0.0
    first_sentence = sentences[0] if sentences else ""
    bare_ack = bool(
        first_sentence
        and len(first_sentence.split()) <= 8
        and any(w in first_sentence.lower() for w in HEDGE_WORDS)
    )
    evidence = (
        "hedge_word_hits={} greeting_present={} avg_words_per_sentence={:.1f} "
        "first_sentence_is_bare_ack={} first_sentence={!r}"
    ).format(hedge_count, greeting, avg_words, bare_ack, first_sentence[:80])
    return "INDETERMINATE", evidence


# ---------------------------------------------------------------------------
# Field table -- order matches DESIGN.md and prompts.txt (1-indexed)
# ---------------------------------------------------------------------------

FIELDS = [
    {"index": 1, "name": "language", "multiturn": False, "check": check_language},
    {"index": 2, "name": "answer_position", "multiturn": False, "check": check_answer_position},
    {"index": 3, "name": "step_style", "multiturn": False, "check": check_step_style},
    {"index": 4, "name": "max_list_items", "multiturn": False, "check": check_max_list_items},
    {"index": 5, "name": "code_style", "multiturn": False, "check": check_code_style},
    {"index": 6, "name": "explanation_budget", "multiturn": False, "check": check_explanation_budget},
    {"index": 7, "name": "options_per_answer", "multiturn": False, "check": check_options_per_answer},
    {"index": 8, "name": "confirm_topic_switch", "multiturn": True, "check": check_confirm_topic_switch},
    {"index": 9, "name": "progress_recap", "multiturn": True, "check": check_progress_recap},
    {"index": 10, "name": "extras_section", "multiturn": False, "check": check_extras_section},
    {"index": 11, "name": "tone", "multiturn": False, "check": check_tone},
]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def print_row(field, arm, verdict, evidence):
    print("\t".join([field, arm, verdict, evidence]))


def main(argv):
    # `--profile PATH` is optional and must be consumed before the positional
    # arguments, or the path is silently taken as an arm name and every field
    # reports "missing file" -- the exact failure this wiring was added to fix.
    args = list(argv[1:])
    profile_path = None
    if "--profile" in args:
        i = args.index("--profile")
        if i + 1 >= len(args):
            sys.stderr.write("grade.py: --profile needs a path\n")
            return 1
        profile_path = args[i + 1]
        del args[i:i + 2]

    if not args:
        sys.stderr.write("usage: grade.py [--profile PATH] <results_dir> [ARM ...]\n")
        return 1
    results_dir = args[0]
    arms = args[1:] if len(args) > 1 else DEFAULT_ARMS

    profile = load_profile(profile_path) if profile_path else None
    if profile_path and profile is None:
        sys.stderr.write("grade.py: could not parse a profile from " + profile_path + "\n")
        return 1

    for field in FIELDS:
        name = field["name"]
        idx = field["index"]
        check = field["check"]
        # The measurability gate runs before any result file is opened: a field
        # whose profile value equals the base default cannot be graded at all,
        # and reporting HONOURED there would credit default behaviour to the
        # profile.
        if profile is not None and name in profile and name in BASE_DEFAULTS:
            ok, why = is_measurable(name, profile[name])
            if not ok:
                for arm in arms:
                    print_row(name, arm, "NOT-MEASURABLE", why)
                continue
        for arm in arms:
            p1_path = os.path.join(results_dir, "arm{}-p{}.json".format(arm, idx))
            if field["multiturn"]:
                t2_path = os.path.join(results_dir, "arm{}-p{}-turn2.json".format(arm, idx))
                text2, err2 = load_result(t2_path)
                if text2 is None:
                    text1, err1 = load_result(p1_path)
                    bits = []
                    if text1 is None:
                        bits.append("turn1: " + err1)
                    bits.append("turn2: " + err2)
                    print_row(name, arm, "INDETERMINATE", "; ".join(bits))
                    continue
                verdict, evidence = check(text2)
                print_row(name, arm, verdict, evidence)
            else:
                text, err = load_result(p1_path)
                if text is None:
                    print_row(name, arm, "INDETERMINATE", err)
                    continue
                verdict, evidence = check(text)
                print_row(name, arm, verdict, evidence)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
