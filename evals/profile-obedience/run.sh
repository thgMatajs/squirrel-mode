#!/bin/sh
# Profile-obedience eval runner.
#
# Answers one question the test suite cannot: does the model actually CHANGE
# ITS BEHAVIOUR when ~/.squirrel/profile.md sets a field, or does it just read
# the file? The suite checks that rule text is present; it never checks that
# any of it is followed.
#
# Arms:
#   A  bare claude, no plugin                      (is this just what Claude does anyway?)
#   B  --plugin-dir <repo>, profile ABSENT         (the control: base-rule defaults)
#   C  --plugin-dir <repo>, profile PRESENT        (the thing under test)
#
# Arm B can only be measured while no profile exists. Once ~/.squirrel/profile.md
# is there, this script cannot remove it -- it never writes to ~/.squirrel at all.
# Capture B first, or accept that C has no control.
#
# TWO RUNNER FACTS THAT COST A WHOLE DISCARDED PILOT EACH:
#
#   1. `claude -p` READS STDIN. In a `while read` loop each invocation swallows
#      the remaining prompts and the run is silently garbage. Every call below
#      gets `</dev/null`, and prompts are indexed with `sed -n "${i}p"`.
#   2. Prompts 8 and 9 need two messages: rule 8's recap only fires mid-task and
#      rule 10's gate needs open work. Turn 1 is sent, `session_id` is read out
#      of its JSON, and turn 2 goes through `claude -p --resume <session_id>`.
#      A single-shot probe of either field measures nothing.
#
# Rule 8 fired in 1 of 10 runs when measured this way, so a single repetition
# of a stateful field proves nothing: pass REPS.
#
# Usage:  sh run.sh <ARM> <OUTPUT_DIR> [REPS]
#   ARM         A | B | C
#   OUTPUT_DIR  written fresh; raw per-call JSON lands here as arm<ARM>-p<N>[-turn2][-r<K>].json
#   REPS        default 1. Use ~10 for the stateful fields (8, 9).
#
# Then: python3 grade.py [--profile ~/.squirrel/profile.md] <OUTPUT_DIR> A B C
#
# Costs real money and needs an authenticated `claude`. Deliberately NOT wired
# into tests/run.sh or CI for exactly that reason.
set -u

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

arm=${1:-}
out=${2:-}
reps=${3:-1}
model=${MODEL:-sonnet}

if [ -z "$arm" ] || [ -z "$out" ]; then
  printf 'usage: sh run.sh <A|B|C> <output_dir> [reps]\n' >&2
  exit 64
fi
case "$arm" in
  A | B | C) ;;
  *) printf 'run.sh: arm must be A, B or C (got "%s")\n' "$arm" >&2; exit 64 ;;
esac

# Turn-2 messages for the two stateful probes. Kept here rather than in
# prompts.txt because that file is index-matched one line per field.
msg2_p8="What's a good recipe for banana bread?"
msg2_p9="Continue to step 2: extract the first responsibility into its own function."

# PRECONDITION PROBE. A runner that exits 0 having produced nothing is the
# vacuous green this project has been bitten by before: fail loudly instead.
if ! command -v claude >/dev/null 2>&1; then
  printf "run.sh: the claude CLI is not on PATH -- nothing was run.\n" >&2
  exit 69
fi
probe=$(claude -p 'Reply with exactly: OK' --model "$model" --output-format json </dev/null 2>/dev/null || true)
case "$probe" in
  *'"is_error":true'* | '')
    printf "run.sh: claude -p could not complete a one-token call (not logged in, or no quota) -- nothing was run.\n" >&2
    exit 69
    ;;
esac

# Arm B is only honest while no profile exists; arm C is only honest while one does.
if [ "$arm" = "B" ] && [ -f "$HOME/.squirrel/profile.md" ]; then
  printf 'run.sh: arm B is the no-profile control, but %s/.squirrel/profile.md exists.\n' "$HOME" >&2
  printf 'run.sh: this script will not touch that file. Move it aside yourself, or skip arm B.\n' >&2
  exit 65
fi
if [ "$arm" = "C" ] && [ ! -f "$HOME/.squirrel/profile.md" ]; then
  printf 'run.sh: arm C needs %s/.squirrel/profile.md. Run /squirrel:init first.\n' "$HOME" >&2
  exit 65
fi

mkdir -p "$out" || exit 74
work="$out/.work"
mkdir -p "$work" || exit 74

# A neutral working directory: run from the repo and the model reads the repo,
# which contaminates every answer with this project's own vocabulary.
cd "$work" || exit 74

call() { # $1=output file  $2=prompt   (plugin flag decided by arm)
  if [ "$arm" = "A" ]; then
    timeout 420 claude -p "$2" --model "$model" --output-format json \
      >"$1" 2>"$1.err" </dev/null
  else
    timeout 420 claude -p "$2" --model "$model" --output-format json \
      --plugin-dir "$repo_root" >"$1" 2>"$1.err" </dev/null
  fi
}

resume() { # $1=output file  $2=session id  $3=prompt
  if [ "$arm" = "A" ]; then
    timeout 420 claude -p --resume "$2" "$3" --model "$model" --output-format json \
      >"$1" 2>"$1.err" </dev/null
  else
    timeout 420 claude -p --resume "$2" "$3" --model "$model" --output-format json \
      --plugin-dir "$repo_root" >"$1" 2>"$1.err" </dev/null
  fi
}

session_id_of() {
  python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("session_id") or "")
except Exception:
    print("")' "$1" 2>/dev/null
}

n=$(grep -c . "$here/prompts.txt")
k=1
while [ "$k" -le "$reps" ]; do
  if [ "$reps" = "1" ]; then suffix=""; else suffix="-r$k"; fi
  i=1
  while [ "$i" -le "$n" ]; do
    prompt=$(sed -n "${i}p" "$here/prompts.txt")
    o="$out/arm${arm}-p${i}${suffix}.json"
    printf 'arm=%s rep=%s p=%s\n' "$arm" "$k" "$i" >&2
    call "$o" "$prompt"

    if [ "$i" = "8" ] || [ "$i" = "9" ]; then
      if [ "$i" = "8" ]; then m2=$msg2_p8; else m2=$msg2_p9; fi
      sid=$(session_id_of "$o")
      if [ -n "$sid" ]; then
        resume "$out/arm${arm}-p${i}${suffix}-turn2.json" "$sid" "$m2"
      else
        printf '  turn2 SKIPPED for p%s: no session_id in turn 1\n' "$i" >&2
      fi
    fi
    i=$((i + 1))
  done
  k=$((k + 1))
done

printf 'arm %s complete: %s\n' "$arm" "$out" >&2
