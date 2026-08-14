#!/usr/bin/env python3
"""
mutation-check.py -- proves the field-1 (`language`) fix, in BOTH error
directions, against hand-built cases. Not a live model run: these are
literal Python strings fed straight into grade.py's check_language,
exactly the same function grade.py itself calls.

Two review cycles found a bug in each direction of this one check, which
is why both are now permanent, not just the one most recently reported:

  - cycle 1: a short PT-BR reply read as INDETERMINATE (false negative on
    obedience) because the check needed volume to accumulate and the
    combined profile's explanation_budget=1 denies it that volume.
  - cycle 2: after fixing cycle 1, short ENGLISH replies read as HONOURED
    (false positive on obedience) because the widened PT word list
    included ordinary English words ("no", "do") with zero English-side
    counterweight. This is the worse failure of the two: it reports the
    product's central feature as working when the evidence says the
    opposite, and it does so silently (no visible INDETERMINATE flag).

The EN_SENTENCES block exists specifically to keep testing the direction
that broke second. Do not remove it when this check next changes -- it
is the only thing in this repo that would have caught cycle 2 before a
human had to.

Required outcomes:
    1. a short pt-BR sentence   -> HONOURED
    2. a short English sentence -> IGNORED
    3. a bare code fence, no prose -> INDETERMINATE (must NOT become a
       verdict -- a fabricated verdict here would mean the instrument
       broke, not that it measured something)
    4. four more short English sentences (the exact cycle-2 regression
       fixtures) -> IGNORED, every one

Run: python3 mutation-check.py
"""
import sys

sys.path.insert(0, ".")
from grade import check_language  # noqa: E402

CASES = [
    ("short pt-BR sentence", "Use o rsync para copiar a pasta.", "HONOURED"),
    ("short English sentence", "Use rsync to copy the folder.", "IGNORED"),
    ("code-only, no prose", "```bash\nrsync -a /src/ /dst/\n```", "INDETERMINATE"),
]

# Cycle-2 regression fixtures, verbatim from pilot2/myfix3/ (armE1-armE4).
# All four are plain, unambiguous English. Every one must grade IGNORED.
EN_SENTENCES = [
    ("cycle-2 regression E1", "No, do it manually.", "IGNORED"),
    ("cycle-2 regression E2", "No need. Do that once.", "IGNORED"),
    ("cycle-2 regression E3", "Do not do this.", "IGNORED"),
    ("cycle-2 regression E4", "Use rsync. No cron needed.", "IGNORED"),
]
CASES = CASES + EN_SENTENCES

ok = True
for label, text, expected in CASES:
    verdict, evidence = check_language(text)
    status = "PASS" if verdict == expected else "FAIL"
    if verdict != expected:
        ok = False
    print("{:<26} -> {:<14} {}   [{}, expected {}]".format(
        label, verdict, evidence, status, expected))

print()
print("ALL PASS" if ok else "SOME FAILED")
sys.exit(0 if ok else 1)
