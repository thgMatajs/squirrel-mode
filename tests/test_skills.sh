#!/bin/sh
# Coverage for S5: the seven command skills under skills/ (init, tune,
# off, on, digest, plan, pickup). Structural and contract coverage only
# - this harness cannot verify a MODEL actually follows the instructions
# in a SKILL.md, only that the instructions exist, are well-formed, and
# say the right things. See the S5 report for what stays unverifiable.
#
# skills/rules/SKILL.md is GENERATED (S3) and out of scope here - S3's
# own test_build.sh already covers it in full.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion: every assert_* helper always returns 0, and
# only assert_report (called once, at the end) turns a failure into a
# non-zero exit code.
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# shellcheck source=lib/assert.sh
. "$script_dir/lib/assert.sh"

skills_dir="$repo_root/skills"

# --- Cleanup ------------------------------------------------------------
#
# Scratch mutant files (failure-proof scenarios only, see the bottom of
# this file) accumulate here and are removed by a single EXIT trap - the
# same technique tests/test_hooks.sh uses for its own scratch scripts.
cleanup_paths=""
trap 'rm -rf $cleanup_paths' EXIT

skill_scratch() {
  # skill_scratch <src> - copies <src> into a throwaway scratch file and
  # returns its path. The real, shipped skill file is never touched.
  src=$1
  scratch=$(mktemp "${TMPDIR:-/tmp}/squirrel-skill-mutant.XXXXXX")
  cleanup_paths="$cleanup_paths $scratch"
  cp "$src" "$scratch"
  printf '%s' "$scratch"
}

section_between() {
  # section_between <file> <start_pattern> <end_pattern> - prints every
  # line from the first line matching <start_pattern> (inclusive) up to
  # (but excluding) the first later line matching <end_pattern>. Used to
  # bind an assertion to one specific section of a skill file instead of
  # scanning the whole document, where a phrase used as a worked example
  # elsewhere could otherwise make the check vacuously pass.
  # <end_pattern> may be the empty string, meaning "no end - run to EOF"
  # (used for a section that is the last one in its file, where there is
  # no following heading to bound against).
  file=$1
  start_pattern=$2
  end_pattern=$3
  awk -v start="$start_pattern" -v end="$end_pattern" '
    end != "" && $0 ~ end { exit }
    $0 ~ start { flag = 1 }
    flag { print }
  ' "$file"
}

first_byte_offset_in_string() {
  # first_byte_offset_in_string <haystack> <phrase> - byte offset of the
  # first occurrence of <phrase> in <haystack> (a string, not a file), or
  # a large sentinel if absent. Same contract as first_byte_offset below,
  # for callers that already extracted a substring of a file into a
  # shell variable rather than working with the file directly.
  haystack=$1
  phrase=$2
  off=$(printf '%s' "$haystack" | grep -a -b -o -m 1 -- "$phrase" 2>/dev/null | head -n 1 | cut -d: -f1) || off=""
  if [ -n "$off" ]; then
    printf '%s' "$off"
  else
    printf '999999999'
  fi
}

# The seven new command skills. Order matches PLAN.md Section 3.
new_skill_names="init tune digest plan pickup off on"

# Skills that must carry disable-model-invocation: true - the model must
# never start these on its own initiative (calibration interview, tuning,
# or flipping the plugin's own on/off state).
disabled_invocation_names="init tune off on"
# Skills that must NOT carry that key at all - they stay model-invocable,
# with descriptions tight enough not to hijack ordinary requests.
model_invocable_names="digest plan pickup"

# Files permitted to contain the squirrel emoji (the only non-ASCII byte
# sequence allowed anywhere in these skills) - matches PLAN.md's own
# fixed output formats for /squirrel:pickup ("## Recent wins <emoji>")
# and /squirrel:plan ("## Parking lot <emoji>"). No other command's
# output format specifies it.
emoji_permitted_names="pickup plan"

read_file() {
  # read_file <path> - prints file content, or empty string if missing.
  # Never fails the whole test file on a missing skill; the missing
  # file itself is caught by the assert_file_exists calls in scenario 1.
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf ''
  fi
}

skill_file_for() {
  # skill_file_for <name> - prints the absolute path to that skill's
  # SKILL.md, new-skill or not (also used for the generated skills/rules/
  # in scenario 17's directory-listing check).
  printf '%s/%s/SKILL.md' "$skills_dir" "$1"
}

# --- Frontmatter helpers (same technique tests/test_build.sh uses) ------

extract_frontmatter_line() {
  # extract_frontmatter_line <file> <key> - prints the raw line for <key>
  # inside the frontmatter block (between the first two "---" lines), or
  # nothing if <key> is not present there.
  awk -v key="$2" '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && $0 ~ ("^" key ":") { print; exit }
  ' "$1"
}

frontmatter_delims_ok() {
  # frontmatter_delims_ok <file> - "yes" iff the file's very first line is
  # "---" and a second "---" line closes the block somewhere after it.
  f=$1
  first_line=$(head -n 1 "$f" 2>/dev/null) || first_line=""
  second_delim_line=$(awk '/^---$/ { c++; if (c == 2) { print NR; exit } }' "$f" 2>/dev/null)
  if [ "$first_line" = "---" ] && [ -n "$second_delim_line" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# ==========================================================================
# 1. All seven skill directories exist, each with exactly a SKILL.md.
# ==========================================================================
for name in $new_skill_names; do
  dir="$skills_dir/$name"
  if [ -d "$dir" ]; then
    dir_status=yes
  else
    dir_status=no
  fi
  assert_eq "yes" "$dir_status" "skills/$name/ must exist as a directory"

  if [ -d "$dir" ]; then
    entries=""
    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
      if [ -e "$entry" ]; then
        entries="$entries $(basename "$entry")"
      fi
    done
    listing=$(printf '%s\n' "$entries" | tr -s ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ *$//')
  else
    listing="<directory missing>"
  fi
  assert_eq "SKILL.md" "$listing" "skills/$name/ must contain exactly SKILL.md, nothing else"
done

# ==========================================================================
# 2. Every SKILL.md has valid YAML frontmatter with a non-empty
#    description. Structural delimiter check always runs; a full
#    python3+PyYAML parse runs additionally when available (same
#    belt-and-suspenders approach as tests/test_build.sh).
# ==========================================================================
have_yaml_parser=no
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" >/dev/null 2>&1; then
    have_yaml_parser=yes
  fi
fi

yaml_parses_with_description() {
  # yaml_parses_with_description <path> - prints "yes" iff the frontmatter
  # parses as a YAML mapping and its "description" value is a non-empty
  # string. Only called when have_yaml_parser=yes.
  python3 - "$1" <<'PYEOF'
import sys, re, yaml

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    print("no")
    sys.exit(0)
try:
    data = yaml.safe_load(m.group(1))
except Exception:
    print("no")
    sys.exit(0)
if not isinstance(data, dict):
    print("no")
    sys.exit(0)
desc = data.get("description")
print("yes" if isinstance(desc, str) and len(desc.strip()) > 0 else "no")
PYEOF
}

for name in $new_skill_names; do
  f=$(skill_file_for "$name")

  assert_eq "yes" "$(frontmatter_delims_ok "$f")" "skills/$name/SKILL.md must open with a '---' frontmatter block closed by a second '---'"

  desc_line=$(extract_frontmatter_line "$f" "description")
  desc_val=$(printf '%s\n' "$desc_line" | sed -n 's/^description: "\(.*\)"$/\1/p')
  if [ -n "$desc_val" ]; then
    desc_nonempty=yes
  else
    desc_nonempty=no
  fi
  assert_eq "yes" "$desc_nonempty" "skills/$name/SKILL.md frontmatter must have a non-empty, double-quoted description"

  if [ "$have_yaml_parser" = "yes" ]; then
    assert_eq "yes" "$(yaml_parses_with_description "$f")" "skills/$name/SKILL.md frontmatter must parse as YAML with a non-empty string description"
  fi
done

# ==========================================================================
# 3. disable-model-invocation: true is present on EXACTLY init, tune, off,
#    on, and ABSENT on digest, plan, pickup. Both directions asserted.
# ==========================================================================
for name in $disabled_invocation_names; do
  f=$(skill_file_for "$name")
  line=$(extract_frontmatter_line "$f" "disable-model-invocation")
  assert_eq "disable-model-invocation: true" "$line" "skills/$name/SKILL.md must set disable-model-invocation: true"
done

for name in $model_invocable_names; do
  f=$(skill_file_for "$name")
  line=$(extract_frontmatter_line "$f" "disable-model-invocation")
  assert_eq "" "$line" "skills/$name/SKILL.md must NOT set disable-model-invocation (it stays model-invocable)"
done

# ==========================================================================
# 4. No skill body contains "${" other than "$ARGUMENTS". Since
#    "$ARGUMENTS" itself (the only supported placeholder) never produces
#    the substring "${", the sole tolerated exception is a literal
#    "${ARGUMENTS}" spelling - stripped out before the scan so a future
#    edit using that brace form is not penalised, while any OTHER "${...}"
#    placeholder still fails loudly.
# ==========================================================================
for name in $new_skill_names; do
  f=$(skill_file_for "$name")
  content=$(read_file "$f")
  # shellcheck disable=SC2016 # single-quoted deliberately: this is a
  # literal sed pattern to match in the file's text, not an expression to
  # expand in THIS shell.
  sanitized=$(printf '%s' "$content" | sed 's/\${ARGUMENTS}//g')
  # shellcheck disable=SC2016 # single-quoted deliberately: '${' is the
  # literal needle assert_not_contains searches for, not an expansion.
  assert_not_contains "$sanitized" '${' "skills/$name/SKILL.md must contain no \${...} placeholder syntax other than \$ARGUMENTS (which needs no braces)"
done

# ==========================================================================
# 5. No skill claims a write is invisible/unobservable/hidden from the
#    user. tests/test_repo_invariants.sh already scans every tracked file
#    repo-wide for this (skills/ is not on its path denylist), so this is
#    intentionally redundant with it - explicit, skill-scoped coverage
#    with its own failure message, not a replacement.
# ==========================================================================
VISIBILITY_REGEX="invisible|unobservable|hidden from (the )?user|without (the )?user[^A-Za-z0-9_ ]{1,3}s knowledge"
for name in $new_skill_names; do
  f=$(skill_file_for "$name")
  if grep -qiE "$VISIBILITY_REGEX" "$f" 2>/dev/null; then
    visibility_status="CLAIMS INVISIBILITY"
  else
    visibility_status="clean"
  fi
  assert_eq "clean" "$visibility_status" "skills/$name/SKILL.md must not claim any write is invisible/unobservable/hidden from the user"
done

# ==========================================================================
# 6. Non-ASCII limited to the squirrel emoji, and only in the files
#    permitted to carry it (pickup, plan). Every other skill must contain
#    ZERO non-ASCII bytes, including the emoji itself.
# ==========================================================================
squirrel_emoji='🐿️'
for name in $new_skill_names; do
  f=$(skill_file_for "$name")
  case " $emoji_permitted_names " in
    *" $name "*)
      permitted=yes
      ;;
    *)
      permitted=no
      ;;
  esac

  if [ -f "$f" ]; then
    if [ "$permitted" = "yes" ]; then
      scan_content=$(sed "s/$squirrel_emoji//g" "$f")
    else
      scan_content=$(cat "$f")
    fi
    non_ascii_lines=$(printf '%s\n' "$scan_content" | LC_ALL=C grep -n '[^ -~]' || true)
  else
    non_ascii_lines="<file missing: $f>"
  fi

  if [ -n "$non_ascii_lines" ]; then
    non_ascii_status="found non-ASCII: $non_ascii_lines"
  else
    non_ascii_status="clean"
  fi
  if [ "$permitted" = "yes" ]; then
    assert_eq "clean" "$non_ascii_status" "skills/$name/SKILL.md must contain no non-ASCII byte other than the permitted squirrel emoji"
  else
    assert_eq "clean" "$non_ascii_status" "skills/$name/SKILL.md must contain no non-ASCII byte at all (not on the emoji-permitted list)"
  fi
done

# ==========================================================================
# 7. init mentions all 11 profile field names, contains 7 numbered
#    questions, and shows progress in the "Question N of 7" form.
# ==========================================================================
init_file=$(skill_file_for "init")
init_body=$(read_file "$init_file")

# The 11 field names, derived from PLAN.md's own profile example (see
# scenario 16 below for the shared parse) - duplicated here as a plain
# list literal only for readability of this scenario's loop; the
# authoritative, non-hardcoded comparison lives in scenario 16.
for field in language answer_position step_style max_list_items code_style explanation_budget options_per_answer confirm_topic_switch progress_recap extras_section tone; do
  assert_contains "$init_body" "$field" "init must mention the '$field' field"
done

question_heading_count=$(grep -c '^### Question [0-9] of 7' "$init_file" 2>/dev/null || true)
assert_eq "7" "$question_heading_count" "init must contain exactly 7 'Question N of 7' headings"

for n in 1 2 3 4 5 6 7; do
  # NIT fix: bound to the actual "### Question N of 7" HEADING line, not
  # merely to the phrase appearing anywhere in the file. Rule 3's own
  # worked example ("for example `Question 3 of 7`") is deliberately
  # NOT a heading, so it can no longer make this vacuously pass if the
  # real heading for that N were ever deleted.
  assert_contains "$init_body" "### Question $n of 7" "init must show progress as 'Question $n of 7' in an actual heading (not merely as a passing textual mention, e.g. a worked example)"
done

# ==========================================================================
# 8. init's question 2 names all four fields it sets as a bundle.
# ==========================================================================
q2_section=$(awk '
  /^### Question 3 of 7/ { if (flag) exit }
  /^### Question 2 of 7/ { flag = 1 }
  flag { print }
' "$init_file")

for field in step_style explanation_budget extras_section tone; do
  assert_contains "$q2_section" "$field" "init question 2 must name '$field' as one of the four fields it sets"
done

# BLOCKER fix: the field-NAME check above passed even when the VALUES
# were wrong (the exact regression the reviewer rejected: C mapped to
# extras_section=yes, tone=warm - the opposite of what PLAN.md's
# authoritative table requires). Pin down each answer's exact row, not
# just that the four field names appear somewhere in the section.
# shellcheck disable=SC2016 # backtick-quoted field/value names below
# are literal text to search for in the skill's own markdown table, not
# command substitution.
assert_contains "$q2_section" '| A - long walls of text | `checklist` | 1 | `no` | `terse` |' "init question 2 must map answer A to step_style=checklist, explanation_budget=1, extras_section=no, tone=terse exactly (PLAN.md's authoritative table)"
# shellcheck disable=SC2016
assert_contains "$q2_section" '| B - jumps around, disorganized | `numbered` | 3 | `yes` | `neutral` |' "init question 2 must map answer B to step_style=numbered, explanation_budget=3, extras_section=yes, tone=neutral exactly (PLAN.md's authoritative table)"
# shellcheck disable=SC2016
assert_contains "$q2_section" '| C - too many options at once | `numbered` | 2 | `no` | `neutral` |' "init question 2 must map answer C to step_style=numbered, explanation_budget=2, extras_section=no, tone=neutral exactly - the exact regression PLAN.md's table fixes: someone paralysed by choice (C) must NOT also be handed extras_section=yes to evaluate"

# --- Failure proof: the three assertions above are not vacuous --------
#
# Reintroduces the exact rejected regression (C's extras_section flipped
# back to 'yes', tone back to 'warm') into a scratch COPY of the real
# skill file, then re-runs the SAME extraction + exact-row check against
# the mutant, confirming it correctly no longer matches. The real,
# shipped skill file is never touched.
fp_q2_scratch=$(skill_scratch "$init_file")
# shellcheck disable=SC2016 # single-quoted deliberately: this is a
# literal sed pattern/replacement (backtick-quoted markdown text to
# search for and substitute), not an expression to expand in this shell.
sed -e 's#2 | `no` | `neutral` |#2 | `yes` | `warm` |#' "$fp_q2_scratch" >"$fp_q2_scratch.tmp" && mv "$fp_q2_scratch.tmp" "$fp_q2_scratch"

fp_q2_section=$(awk '
  /^### Question 3 of 7/ { if (flag) exit }
  /^### Question 2 of 7/ { flag = 1 }
  flag { print }
' "$fp_q2_scratch")

# shellcheck disable=SC2016
if printf '%s' "$fp_q2_section" | grep -qF '| C - too many options at once | `numbered` | 2 | `no` | `neutral` |'; then
  fp_q2_still_matches=yes
else
  fp_q2_still_matches=no
fi
assert_eq "no" "$fp_q2_still_matches" "FAILURE PROOF (Q2 mapping): reintroducing the rejected C-answer regression (extras_section back to yes) in a scratch copy must make the exact-row assertion fail - proving scenario 8's per-value checks are not vacuous"

# ==========================================================================
# 9. tune references all 11 fields.
# ==========================================================================
tune_body=$(read_file "$(skill_file_for "tune")")
for field in language answer_position step_style max_list_items code_style explanation_budget options_per_answer confirm_topic_switch progress_recap extras_section tone; do
  assert_contains "$tune_body" "$field" "tune must reference the '$field' field"
done

# ==========================================================================
# 10. pickup references the injected checkpoint path and does NOT contain
#     a slug-derivation instruction - the specific failure mode to
#     prevent is duplicating load-profile.sh's hashing/basename algorithm
#     here, where it would inevitably drift from the shell implementation.
# ==========================================================================
pickup_file=$(skill_file_for "pickup")
pickup_body=$(read_file "$pickup_file")

assert_contains "$pickup_body" "Project checkpoint path" "pickup must reference the injected 'Project checkpoint path' context line"
assert_contains "$pickup_body" "Read that exact path" "pickup must instruct reading the injected path directly, not recomputing it"

# NIT fix: the banned-word list below is a substring blocklist, evadable
# by rephrasing ("figure out this session's own directory tag" contains
# none of the banned words but is the exact same drift risk). Also
# assert the POSITIVE requirement verbatim, not just the absence of
# certain words.
assert_contains "$pickup_body" "Do not attempt to compute, guess, or re-derive the path yourself" "pickup must state, verbatim, the positive requirement to read the injected path rather than recomputing it - not merely avoid a fixed list of banned words"

pickup_lower=$(printf '%s' "$pickup_body" | tr '[:upper:]' '[:lower:]')
for banned in hash basename cksum; do
  assert_not_contains "$pickup_lower" "$banned" "pickup must not contain '$banned' (that is load-profile.sh's slug algorithm, and duplicating it here is the drift risk this scenario exists to prevent)"
done

# ==========================================================================
# 11. pickup's section order is wins -> Doing -> Next -> Open decisions;
#     assert the byte offsets of each section's first occurrence are
#     strictly ascending.
#
#     NIT fix: the original version of this check scanned the WHOLE
#     file, so it passed even if the real, ordered template were
#     deleted entirely - every one of these four phrases also appears
#     (in the same relative order) inside this skill's own prose about
#     the malformed-checkpoint fallback, elsewhere in the file. Bound
#     the scan to the text between the "Output, in this exact order"
#     heading and the "## Then stop" heading, which is the actual fixed
#     template this scenario means to check.
# ==========================================================================
pickup_output_section=$(section_between "$pickup_file" '^## Output, in this exact order' '^## Then stop')

off_wins=$(first_byte_offset_in_string "$pickup_output_section" "Recent wins")
off_doing=$(first_byte_offset_in_string "$pickup_output_section" "You were doing")
off_next=$(first_byte_offset_in_string "$pickup_output_section" "Next action")
off_open=$(first_byte_offset_in_string "$pickup_output_section" "Open decisions")

if [ "$off_wins" -lt "$off_doing" ] && [ "$off_doing" -lt "$off_next" ] && [ "$off_next" -lt "$off_open" ]; then
  order_status="ascending"
else
  order_status="NOT ascending: wins=$off_wins doing=$off_doing next=$off_next open=$off_open"
fi
assert_eq "ascending" "$order_status" "pickup's fixed-output template must present its sections in byte order: Recent wins, then You were doing, then Next action, then Open decisions"

# ==========================================================================
# 12. off and on both reference ~/.claude/squirrel/off/ and both mention
#     /plugin disable.
# ==========================================================================
off_body=$(read_file "$(skill_file_for "off")")
on_body=$(read_file "$(skill_file_for "on")")

# shellcheck disable=SC2088 # single-quoted deliberately: this is a
# literal needle assert_contains searches the file's TEXT for (the
# documented path as written in prose), never a path this shell opens or
# expands - a leading "~" here is not tilde-expansion gone wrong.
assert_contains "$off_body" '~/.claude/squirrel/off/' "off must reference ~/.claude/squirrel/off/"
# shellcheck disable=SC2088 # same reasoning as the line above.
assert_contains "$on_body" '~/.claude/squirrel/off/' "on must reference ~/.claude/squirrel/off/"
assert_contains "$off_body" "/plugin disable" "off must mention /plugin disable as the hard off"
assert_contains "$on_body" "/plugin disable" "on must mention /plugin disable as the hard off"

# ==========================================================================
# 13. digest covers all four input cases and mentions Jira and
#     --for-reply.
# ==========================================================================
digest_body=$(read_file "$(skill_file_for "digest")")

assert_contains "$digest_body" "Text was pasted after the command" "digest must cover the pasted-text input case"
assert_contains "$digest_body" "names a file path that exists in the current project" "digest must cover the file-path input case"
assert_contains "$digest_body" "Jira ticket reference" "digest must cover the Jira-reference input case"
assert_contains "$digest_body" "Paste the content or give me a file path / ticket ID." "digest must cover the no-input case with the exact fallback question"
assert_contains "$digest_body" "Jira" "digest must mention Jira"
assert_contains "$digest_body" "--for-reply" "digest must mention --for-reply"

# ==========================================================================
# 14. plan mentions the 45-minute cap, the Parking lot, and "Phase 1", and
#     states that only Phase 1 is expanded.
# ==========================================================================
plan_body=$(read_file "$(skill_file_for "plan")")

assert_contains "$plan_body" "45-minute cap" "plan must mention the 45-minute cap"
assert_contains "$plan_body" "Parking lot" "plan must mention the Parking lot"
assert_contains "$plan_body" "Phase 1" "plan must mention Phase 1"
assert_contains "$plan_body" "Expand only Phase 1." "plan must state that only Phase 1 is expanded"

# ==========================================================================
# 15. Every skill references `language`, or explicitly says to mirror the
#     user.
# ==========================================================================
for name in $new_skill_names; do
  body=$(read_file "$(skill_file_for "$name")")
  assert_contains "$body" "language" "skills/$name/SKILL.md must reference the language field"
  assert_contains "$body" "mirror the language the user is currently writing in" "skills/$name/SKILL.md must instruct mirroring the user's language when applicable"
done

# ==========================================================================
# 16. Every profile field named in any skill body is one of the 11 real
#     fields - the list is DERIVED by parsing PLAN.md's own profile
#     example (the exact technique tests/test_build.sh uses for the same
#     purpose), never hardcoded as a second copy that could silently
#     drift from a PLAN.md rename. A typo like "max_list_item" (missing
#     the final "s") must fail this.
#
#     Scanning is restricted to backtick-quoted, all-lowercase tokens
#     containing at least one underscore - this covers 9 of the 11 real
#     field names (everything except "language" and "tone", which carry
#     no underscore and are checked directly by name in scenarios 7 and
#     9 instead) and empirically produces zero false positives against
#     these seven files: no field VALUE (numbered, checklist, yes, no,
#     warm, terse, code-first, ...) contains an underscore, and no other
#     backtick-quoted token in these skills (paths, session ids, command
#     names) is written as a bare lowercase-plus-underscore word.
# ==========================================================================
plan_file="$repo_root/PLAN.md"
valid_fields=$(awk '
  /^### The profile/ { in_section=1 }
  in_section && /^```markdown/ && !in_fence { in_fence=1; next }
  in_fence && /^```$/ { in_fence=0; in_section=0; next }
  in_fence {
    if (match($0, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
      print substr($0, 1, RLENGTH - 1)
    }
  }
' "$plan_file")

is_valid_field() {
  # is_valid_field <candidate> - returns 0 iff <candidate> is a member of
  # $valid_fields (a newline-separated list captured above).
  candidate=$1
  for vf in $valid_fields; do
    if [ "$vf" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

unknown_field_hits=""
for name in $new_skill_names; do
  f=$(skill_file_for "$name")
  # shellcheck disable=SC2016 # single-quoted deliberately: the backtick
  # here is a literal character in the grep pattern (matching a Markdown
  # backtick in the file), not command substitution to evaluate.
  candidates=$(grep -oE '`[a-z][a-z_]*_[a-z_]*`' "$f" 2>/dev/null | tr -d '`' | sort -u) || candidates=""
  for candidate in $candidates; do
    if ! is_valid_field "$candidate"; then
      unknown_field_hits="$unknown_field_hits $name:$candidate"
    fi
  done
done
assert_eq "" "$unknown_field_hits" "every backtick-quoted, underscore-containing field-shaped token in a skill body must be one of the 11 real profile fields parsed from PLAN.md"

# Sanity: PLAN.md's profile example must itself still yield exactly 11
# fields - if this drops to 0 (e.g. PLAN.md's fence markers changed
# shape), scenario 16 above would vacuously pass with an empty allow-list
# instead of actually checking anything, which is worse than not running
# it at all.
valid_field_count=$(printf '%s\n' "$valid_fields" | sed '/^$/d' | wc -l | awk '{print $1}')
assert_eq "11" "$valid_field_count" "PLAN.md's profile example must yield exactly 11 field names (vacuous-pass guard for scenario 16)"

# ==========================================================================
# 17. skills/ contains exactly the eight expected entries: the seven new
#     command skills plus the generated rules/. A stray directory (or
#     file) must fail this.
# ==========================================================================
skills_entries=""
for entry in "$skills_dir"/* "$skills_dir"/.[!.]* "$skills_dir"/..?*; do
  if [ -e "$entry" ]; then
    skills_entries="$skills_entries $(basename "$entry")"
  fi
done
skills_listing=$(printf '%s\n' "$skills_entries" | tr -s ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ *$//')
assert_eq "digest init off on pickup plan rules tune" "$skills_listing" "skills/ must contain exactly the 8 expected entries (7 new command skills + generated rules/), nothing else"

# ==========================================================================
# 18. No obsolete .gitkeep remains under skills/ (none of the seven new
#     directories needs one - each already holds a real SKILL.md).
# ==========================================================================
stray_gitkeep=$(find "$skills_dir" -name '.gitkeep' 2>/dev/null || true)
assert_eq "" "$stray_gitkeep" "no .gitkeep file must remain under skills/ (every directory there holds a real SKILL.md)"

# ==========================================================================
# 19. BLOCKER fix: digest and plan must respect `step_style` for their
#     multi-step output (Breakdown / Phase 1) instead of hardcoding a
#     numbered list, which left checklist users unserved. Both bodies
#     were already read in scenarios 13/14 above.
# ==========================================================================
digest_skill_path=$(skill_file_for "digest")
plan_skill_path=$(skill_file_for "plan")

assert_contains "$digest_body" "step_style" "digest must reference the step_style field (BLOCKER: Breakdown previously hardcoded a numbered list, ignoring checklist users)"
assert_contains "$plan_body" "step_style" "plan must reference the step_style field (BLOCKER: Phase 1 previously hardcoded 'numbered', ignoring checklist users)"

# Bound specifically to each command's own "Respecting the profile"
# section (PLAN.md's explicit fix location), not merely anywhere in the
# file, so a mention elsewhere without the section actually naming it
# does not vacuously pass this.
digest_profile_section=$(section_between "$digest_skill_path" '^## Respecting the profile' '')
plan_profile_section=$(section_between "$plan_skill_path" '^## Respecting the profile' '')
assert_contains "$digest_profile_section" "step_style" "digest's 'Respecting the profile' section must itself name step_style, not just the file somewhere else"
assert_contains "$plan_profile_section" "step_style" "plan's 'Respecting the profile' section must itself name step_style, not just the file somewhere else"

# --- Failure proof: the section-bound assertions above are not vacuous -
fp_ss_digest_scratch=$(skill_scratch "$digest_skill_path")
sed -e 's/step_style/xxx_style_removed/g' "$fp_ss_digest_scratch" >"$fp_ss_digest_scratch.tmp" && mv "$fp_ss_digest_scratch.tmp" "$fp_ss_digest_scratch"
fp_ss_digest_section=$(section_between "$fp_ss_digest_scratch" '^## Respecting the profile' '')
if printf '%s' "$fp_ss_digest_section" | grep -qF "step_style"; then
  fp_ss_digest_still_there=yes
else
  fp_ss_digest_still_there=no
fi
assert_eq "no" "$fp_ss_digest_still_there" "FAILURE PROOF (digest step_style): stripping every 'step_style' occurrence from a scratch copy must make the section-bound assertion fail - proving it is not vacuous"

fp_ss_plan_scratch=$(skill_scratch "$plan_skill_path")
sed -e 's/step_style/xxx_style_removed/g' "$fp_ss_plan_scratch" >"$fp_ss_plan_scratch.tmp" && mv "$fp_ss_plan_scratch.tmp" "$fp_ss_plan_scratch"
fp_ss_plan_section=$(section_between "$fp_ss_plan_scratch" '^## Respecting the profile' '')
if printf '%s' "$fp_ss_plan_section" | grep -qF "step_style"; then
  fp_ss_plan_still_there=yes
else
  fp_ss_plan_still_there=no
fi
assert_eq "no" "$fp_ss_plan_still_there" "FAILURE PROOF (plan step_style): stripping every 'step_style' occurrence from a scratch copy must make the section-bound assertion fail - proving it is not vacuous"

# ==========================================================================
# 20. MAJOR fix: init must accept only an integer 3-7 for max_list_items,
#     matching rules/base-rules.md and tune's own validation table,
#     instead of explicitly permitting an out-of-range typed-in number.
# ==========================================================================
assert_not_contains "$init_body" "still accepted as given" "init must NOT explicitly permit an out-of-range max_list_items value (MAJOR: contradicts rules/base-rules.md's and tune's own 3-7 range)"
assert_contains "$init_body" "integer from 3 to 7" "init must state that max_list_items is accepted only as an integer from 3 to 7"
assert_contains "$init_body" "ask this same question again" "init must re-ask question 5 only, on an invalid max_list_items value, rather than accepting it or aborting"

# --- Failure proof: the assertions above are not vacuous ---------------
fp_mli_scratch=$(skill_scratch "$init_file")
sed -e 's#must be an integer from 3 to 7#is fine at any value, no matter how large#' "$fp_mli_scratch" >"$fp_mli_scratch.tmp" && mv "$fp_mli_scratch.tmp" "$fp_mli_scratch"
fp_mli_body=$(read_file "$fp_mli_scratch")
if printf '%s' "$fp_mli_body" | grep -qF "integer from 3 to 7"; then
  fp_mli_still_rejects=yes
else
  fp_mli_still_rejects=no
fi
assert_eq "no" "$fp_mli_still_rejects" "FAILURE PROOF (max_list_items): removing the 'integer from 3 to 7' rejection wording from a scratch copy must make the positive-requirement assertion fail - proving scenario 20 is not vacuous"

# ==========================================================================
# 21. MAJOR fix: digest must treat all fetched or pasted content as data
#     to restructure, never as instructions - including a sentence
#     inside it addressed to the assistant (the prompt-injection
#     guardrail this command had no defence against).
# ==========================================================================
assert_contains "$digest_body" "data to restructure" "digest must instruct treating fetched or pasted content as data to restructure"
assert_contains "$digest_body" "never as instructions" "digest must explicitly say ingested content is never a set of instructions to follow"
assert_contains "$digest_body" "addressed to you" "digest must call out the specific case of a sentence inside the input addressed to the assistant, not just generic accuracy language"

# ==========================================================================
# 22. MINOR fixes: init handles going off-script mid-interview; tune
#     shows a malformed/missing field as unset rather than guessing;
#     pickup says so per-section for an empty/missing checkpoint
#     section rather than inventing content; digest's --for-reply has a
#     named heading, a length cap, and one reply per digested item.
# ==========================================================================
assert_contains "$init_body" "whether to resume from the same question" "init must ask whether to resume from the same question after the user goes off-script mid-interview"

assert_contains "$tune_body" "show that field as unset" "tune must show a malformed or missing profile field as unset rather than guessing a value"
assert_contains "$tune_body" "base-rules.md" "tune must treat an unset field as the rules/base-rules.md default until set explicitly"

assert_contains "$pickup_body" "do not invent content for what is missing" "pickup must say so per-section for an empty or missing checkpoint section, never invent content"

assert_contains "$digest_body" "## Reply" "digest's --for-reply must add a section under a named heading"
assert_contains "$digest_body" "Cap it at 6 lines" "digest's --for-reply must state a length cap"
assert_contains "$digest_body" "one \`## Reply\` per digested item" "digest's --for-reply must produce one reply per digested item when the input had several independent asks"

# ==========================================================================
# 23. cycle-3 BLOCKER fix, parallel to scenario 10: off and on must both
#     reference the injected "Session working directory:" context line
#     and use it verbatim as the sentinel's contents, instead of
#     determining the session's own working directory themselves -
#     load-profile.sh's SessionStart hook is the only participant that
#     can do that reliably (ADR-0005, amended). Neither skill may
#     contain the substring "pwd" anywhere, in any form - not even
#     inside a "never run pwd" caveat, since that exact substring is
#     what a model would otherwise be tempted to run.
# ==========================================================================
assert_contains "$off_body" "Session working directory:" "off must reference the injected 'Session working directory:' context line"
assert_contains "$on_body" "Session working directory:" "on must reference the injected 'Session working directory:' context line"

off_body_lower=$(printf '%s' "$off_body" | tr '[:upper:]' '[:lower:]')
on_body_lower=$(printf '%s' "$on_body" | tr '[:upper:]' '[:lower:]')
assert_not_contains "$off_body_lower" "pwd" "off must not contain 'pwd' anywhere - the session's working directory must come from the injected context line, never from running a command"
assert_not_contains "$on_body_lower" "pwd" "on must not contain 'pwd' anywhere - the session's working directory must come from the injected context line, never from running a command"

# ==========================================================================
# 24. cycle-1 item 7 fix, now actually enforced: plan's Step 3 fallback
#     (picking the likeliest reading itself once all 3 clarifying
#     questions from Step 2 are spent) draws from the SAME question
#     budget as Step 2 - it is not a bonus 4th question tacked on after
#     the cap. No assertion anywhere previously referenced this: a
#     future edit reverting to "always ask a 4th question" would have
#     kept the suite green. Bound to Step 2's and Step 3's own sections,
#     not merely anywhere in the file, the same discipline scenario 19
#     uses for step_style.
# ==========================================================================
plan_step2_section=$(section_between "$plan_skill_path" '^## Step 2: clarify, at most 3 questions' '^## Step 3: converge and write the plan')
plan_step3_section=$(section_between "$plan_skill_path" '^## Step 3: converge and write the plan' '^## Step 4: offer file or Jira, only if relevant')

assert_contains "$plan_step2_section" "same budget" "plan's Step 2 must state that Step 3's fallback draws from the same budget as Step 2's own 3-question cap"
assert_contains "$plan_step2_section" "not a bonus round" "plan's Step 2 must state the fallback is not a bonus round after the 3-question cap"
assert_contains "$plan_step3_section" "pick the likeliest reading yourself" "plan's Step 3 must state that once all 3 clarifying questions are spent, it picks the likeliest reading itself rather than asking a 4th question"

# --- Failure proof: the assertions above are not vacuous ---------------
fp_budget_scratch=$(skill_scratch "$plan_skill_path")
sed -e 's/pick the likeliest reading yourself/always ask a 4th clarifying question instead/' "$fp_budget_scratch" >"$fp_budget_scratch.tmp" && mv "$fp_budget_scratch.tmp" "$fp_budget_scratch"
fp_budget_step3=$(section_between "$fp_budget_scratch" '^## Step 3: converge and write the plan' '^## Step 4: offer file or Jira, only if relevant')
if printf '%s' "$fp_budget_step3" | grep -qF "pick the likeliest reading yourself"; then
  fp_budget_still_there=yes
else
  fp_budget_still_there=no
fi
assert_eq "no" "$fp_budget_still_there" "FAILURE PROOF (plan budget-sharing fallback): reverting Step 3's fallback to 'always ask a 4th question' in a scratch copy must make the positive-requirement assertion fail - proving this scenario is not vacuous"

# ==========================================================================
# 25. MINOR fix: init's question 1 (language) maps an unsupported
#     free-form language answer to `auto`, never to whichever of A-C
#     sounds closest by geography or family (e.g. French must not
#     become Spanish or Portuguese by guesswork).
# ==========================================================================
init_q1_section=$(awk '
  /^### Question 2 of 7/ { if (flag) exit }
  /^### Question 1 of 7/ { flag = 1 }
  flag { print }
' "$init_file")

# shellcheck disable=SC2016 # backtick-quoted `auto` below is literal
# text to search for in the skill's own markdown, not command substitution.
assert_contains "$init_q1_section" 'maps to D (`auto`)' "init question 1 must map an unsupported free-form language answer to auto, not to the closest-sounding supported language"

# --- Failure proof: the assertion above is not vacuous -----------------
fp_lang_scratch=$(skill_scratch "$init_file")
# shellcheck disable=SC2016 # single-quoted deliberately: literal sed
# pattern/replacement text to match/rewrite in the skill file, not an
# expression to expand in this shell.
sed -e 's/maps to D (`auto`), never to whichever of A-C sounds closest by geography or family/maps to whichever of A-C sounds closest by geography or family/' "$fp_lang_scratch" >"$fp_lang_scratch.tmp" && mv "$fp_lang_scratch.tmp" "$fp_lang_scratch"
fp_lang_q1=$(awk '
  /^### Question 2 of 7/ { if (flag) exit }
  /^### Question 1 of 7/ { flag = 1 }
  flag { print }
' "$fp_lang_scratch")
# shellcheck disable=SC2016 # single-quoted deliberately: literal needle
# grep -F searches for, not an expansion.
if printf '%s' "$fp_lang_q1" | grep -qF 'maps to D (`auto`)'; then
  fp_lang_still_there=yes
else
  fp_lang_still_there=no
fi
assert_eq "no" "$fp_lang_still_there" "FAILURE PROOF (init language fallback): removing the 'maps to D (auto)' wording from a scratch copy must make the positive-requirement assertion fail - proving this scenario is not vacuous"

assert_report
