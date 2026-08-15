#!/bin/sh
# Coverage for S2's format contract: rules/base-rules.md is the canonical
# source scripts/build.sh (S3) will parse to generate every shipped
# artifact. A malformed rule here must fail THIS suite, not silently
# produce a broken generated artifact later.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion: every assert_* helper always returns 0, and
# only assert_report (called once, at the end) turns a failure into a
# non-zero exit code.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line. Unset
# unconditionally, before that `cd` runs.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# shellcheck source=lib/assert.sh
. "$script_dir/lib/assert.sh"

base_rules_file="$repo_root/rules/base-rules.md"
plan_file="$repo_root/PLAN.md"

# --- 1. rules/base-rules.md exists -----------------------------------
assert_file_exists "$base_rules_file" "rules/base-rules.md must exist"

if [ ! -f "$base_rules_file" ]; then
  # Every remaining assertion reads this file. Without it, report the
  # single failure above and stop rather than let every later assertion
  # fail on a missing-file technicality that adds no information.
  assert_report
fi

# --- Shared parse: one record per rule heading ------------------------
#
# For every "### <n>. <title>" heading, walk forward skipping blank
# lines and count how many consecutive "<!-- targets: ... -->" marker
# lines appear before the first real body line. Emits one line per
# heading, in document order: "<number> <marker_count> <targets>".
# <targets> is the value of the FIRST marker seen (whitespace-stripped);
# it is empty when marker_count is 0. Marker duplicates (marker_count>1)
# are still emitted with the first marker's value, because the count
# alone is enough for assertion 4 to fail on them — the exact value of a
# duplicate is not needed to prove the rule broken.
heading_records=$(awk '
  /^### [0-9]+\. / {
    if (pending) print cur_num, marker_count, cur_targets
    line = $0
    sub(/^### /, "", line)
    split(line, parts, ".")
    cur_num = parts[1]
    pending = 1
    marker_count = 0
    cur_targets = ""
    in_zone = 1
    next
  }
  pending && in_zone {
    if ($0 ~ /^[ \t]*$/) { next }
    if ($0 ~ /^<!-- targets:/) {
      marker_count++
      if (marker_count == 1) {
        t = $0
        sub(/^<!-- targets:[ \t]*/, "", t)
        sub(/[ \t]*-->[ \t]*$/, "", t)
        gsub(/[ \t]/, "", t)
        cur_targets = t
      }
      next
    } else {
      in_zone = 0
    }
  }
  END {
    if (pending) print cur_num, marker_count, cur_targets
  }
' "$base_rules_file")

# --- 2 & 3. Exactly 16 headings, numbered 1..16, in order, no gaps/dupes
heading_count=$(printf '%s\n' "$heading_records" | grep -c '.' || true)
assert_eq "16" "$heading_count" "rules/base-rules.md must contain exactly 16 rule headings"

heading_sequence=$(printf '%s\n' "$heading_records" | awk '{ printf "%s ", $1 }' | sed 's/ *$//')
assert_eq "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16" "$heading_sequence" "rule heading numbers must be exactly 1..16, in ascending order, no gaps, no duplicates"

# --- 4. Every heading followed by EXACTLY one targets marker -----------
bad_marker_count_headings=""
while read -r num mcount targets; do
  [ -n "$num" ] || continue
  if [ "$mcount" != "1" ]; then
    bad_marker_count_headings="$bad_marker_count_headings $num(count=$mcount)"
  fi
done <<EOF
$heading_records
EOF
assert_eq "" "$bad_marker_count_headings" "every rule heading must be followed by exactly one <!-- targets: ... --> marker (none, or more than one, must fail)"

# --- 5. Every targets value parses to 'all' or a subset of the allowed
# target names -----------------------------------------------------------
#
# validate_targets prints "valid" or "invalid" for a single targets
# string. "all" is valid only standalone (not combined with anything
# else); otherwise every comma-separated token must be one of
# claude-code, codex, cursor and nothing else.
validate_targets() {
  value=$1
  case "$value" in
    all)
      echo valid
      return 0
      ;;
    "")
      echo invalid
      return 0
      ;;
  esac
  remaining="$value"
  result=valid
  while [ -n "$remaining" ]; do
    case "$remaining" in
      *,*)
        token=${remaining%%,*}
        remaining=${remaining#*,}
        ;;
      *)
        token="$remaining"
        remaining=""
        ;;
    esac
    case "$token" in
      claude-code | codex | cursor) ;;
      *) result=invalid ;;
    esac
  done
  echo "$result"
  return 0
}

bad_target_value_headings=""
while read -r num mcount targets; do
  [ -n "$num" ] || continue
  verdict=$(validate_targets "$targets")
  if [ "$verdict" != "valid" ]; then
    bad_target_value_headings="$bad_target_value_headings $num($targets)"
  fi
done <<EOF
$heading_records
EOF
assert_eq "" "$bad_target_value_headings" "every targets value must be 'all' or a comma-separated subset of {claude-code, codex, cursor}; an unknown target name must fail"

# --- 6. Rules 1-13, 15 and 16 are 'all'; rule 14 is 'claude-code' -------
bad_assignment_headings=""
while read -r num mcount targets; do
  [ -n "$num" ] || continue
  if [ "$num" = "14" ]; then
    expected="claude-code"
  else
    expected="all"
  fi
  if [ "$targets" != "$expected" ]; then
    bad_assignment_headings="$bad_assignment_headings $num(expected=$expected,actual=$targets)"
  fi
done <<EOF
$heading_records
EOF
assert_eq "" "$bad_assignment_headings" "rules 1-13, 15 and 16 must be marked 'all'; rule 14 must be marked 'claude-code'"

# --- 7. Defaults table lists exactly 11 fields, matching PLAN.md's
# profile field names exactly ---------------------------------------
#
# The expected names are DERIVED from PLAN.md's "### The profile" fenced
# example block, not hardcoded here a second time, so a rename in
# PLAN.md that is not mirrored in rules/base-rules.md is caught rather
# than silently tolerated by two independently-typed copies of the same
# list.
plan_profile_fields=$(awk '
  /^### The profile/ { in_section=1 }
  in_section && /^```markdown/ && !in_fence { in_fence=1; next }
  in_fence && /^```$/ { in_fence=0; in_section=0; next }
  in_fence {
    if (match($0, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
      print substr($0, 1, RLENGTH - 1)
    }
  }
' "$plan_file" | sort)

defaults_table_fields=$(awk '
  /^## Defaults$/ { in_defaults = 1; next }
  /^## Rules$/ { in_defaults = 0 }
  in_defaults && /^\| / {
    if ($0 ~ /^\| Field \|/) next
    if ($0 ~ /^\| :--/) next
    split($0, cells, "|")
    f = cells[2]
    gsub(/^[ \t]+|[ \t]+$/, "", f)
    print f
  }
' "$base_rules_file" | sort)

plan_field_count=$(printf '%s\n' "$plan_profile_fields" | grep -c '.' || true)
assert_eq "11" "$plan_field_count" "sanity check: PLAN.md's profile example must itself contain exactly 11 fields (this assertion protects the derivation, not base-rules.md)"

defaults_field_count=$(printf '%s\n' "$defaults_table_fields" | grep -c '.' || true)
assert_eq "11" "$defaults_field_count" "the Defaults table in rules/base-rules.md must list exactly 11 fields"

assert_eq "$plan_profile_fields" "$defaults_table_fields" "the Defaults table's field names must match PLAN.md's profile field names exactly (derived from PLAN.md, not a hardcoded second copy)"

# --- 8. Every backticked profile-field reference in a rule body is one
# of the 11 declared fields ----------------------------------------------
#
# A field-name REFERENCE is a backticked span shaped like a bare
# lowercase identifier: `[a-z][a-z_]*`. This deliberately excludes
# backticked file paths (contain '/' or '~'), tool/section names
# (capitalized, e.g. `Write`, `Doing`), and enum VALUES written in plain
# text per rules/base-rules.md's own convention (code-first, auto, yes,
# no - never backticked, and hyphenated values could not match this
# shape regardless). Scoped to the "## Rules" section only, so the
# Defaults table's plain-text field names (not backticked there) cannot
# accidentally feed this check.
rules_section=$(sed -n '/^## Rules$/,$p' "$base_rules_file")
backticked_field_refs=$(printf '%s\n' "$rules_section" | grep -oE "\`[a-z][a-z_]*\`" | sed 's/`//g' | sort -u)

unknown_field_refs=""
for ref in $backticked_field_refs; do
  found=no
  for known in $plan_profile_fields; do
    if [ "$known" = "$ref" ]; then
      found=yes
      break
    fi
  done
  if [ "$found" = "no" ]; then
    unknown_field_refs="$unknown_field_refs $ref"
  fi
done
assert_eq "" "$unknown_field_refs" "every backticked bare-lowercase-identifier in the Rules section must be one of the 11 declared profile fields (a typo like max_list_item must fail)"

# --- 9. No \${...} placeholder syntax anywhere in the file --------------
placeholder_hits=$(grep -F "\${" "$base_rules_file" || true)
assert_eq "" "$placeholder_hits" "rules/base-rules.md must contain no \${...} placeholder syntax (ADR-0001: the output style cannot resolve it)"

# --- 10. Rule 13 exists, is marked 'all', and its body mentions
# destructive operations, security, and data loss -----------------------
rule_13_targets=$(printf '%s\n' "$heading_records" | awk '$1 == "13" { print $3 }')
assert_eq "all" "$rule_13_targets" "rule 13 (safety override) must be marked 'all'"

rule_13_body=$(awk '
  /^### 13\. / { in_rule = 1; next }
  /^### 14\. / { in_rule = 0 }
  in_rule { print }
' "$base_rules_file")
assert_contains "$rule_13_body" "destructive operations" "rule 13's body must mention destructive operations"
assert_contains "$rule_13_body" "security" "rule 13's body must mention security"
assert_contains "$rule_13_body" "data loss" "rule 13's body must mention data loss"

# Mentioning safety topics is not enough on its own: rule 13 must also
# state that it OUTRANKS the other rules (finding: a model reading rule
# 7's "when extras_section is no, omit it entirely" literally can drop
# an adjacent safety warning while satisfying rule 7's letter). Anchored
# to rule 7's extras_section gate specifically, not just "precedence" in
# the abstract, so a rewrite that drops the rule-7 tie stays caught.
assert_contains "$rule_13_body" "precedence" "rule 13's body must explicitly state that it takes precedence over the other rules, not merely describe the safety override"
assert_contains "$rule_13_body" "extras_section" "rule 13's body must anchor its precedence claim to rule 7's extras_section gate by name"

# --- 11. Non-ASCII policy: the ONLY non-ASCII content permitted anywhere
# in the file is the literal squirrel emoji (chipmunk + variation
# selector-16, U+1F43F U+FE0F) that PLAN.md's own rule 15 example uses.
# Every one of its bytes has the high bit set, so stripping every
# occurrence of the exact emoji byte sequence out of the file and then
# scanning what remains for any byte outside printable ASCII (0x20-0x7E)
# proves nothing else non-ASCII slipped in. This also implicitly forbids
# tabs (not part of the 0x20-0x7E range) - rules/base-rules.md uses
# spaces only, so a real tab appearing anywhere is itself unintended
# content, not a formatting choice this check should tolerate.
squirrel_emoji='🐿️'
after_emoji_strip=$(sed "s/$squirrel_emoji//g" "$base_rules_file")
non_ascii_lines=$(printf '%s\n' "$after_emoji_strip" | LC_ALL=C grep -n '[^ -~]' || true)
if [ -n "$non_ascii_lines" ]; then
  non_ascii_status="found non-ASCII outside the permitted squirrel emoji: $non_ascii_lines"
else
  non_ascii_status="clean"
fi
assert_eq "clean" "$non_ascii_status" "rules/base-rules.md must contain no non-ASCII byte other than the permitted squirrel emoji (chipmunk + variation selector-16)"

emoji_present=$(grep -Fc "$squirrel_emoji" "$base_rules_file" || true)
if [ "$emoji_present" -ge 1 ]; then
  emoji_present_status=yes
else
  emoji_present_status=no
fi
assert_eq "yes" "$emoji_present_status" "the permitted squirrel emoji must actually appear at least once (rule 15's scope-guard example, per PLAN.md)"

# --- 12. Every one of the 11 Defaults fields is referenced at least once
# as a backticked name in the Rules section -----------------------------
#
# Finding 8 from the S2 review: assertion 8 above only proves every
# backticked reference NAMES a known field. That is exactly why
# answer_position, step_style, and tone previously passed clean while
# having zero rule bodies that referenced them - /squirrel:tune would
# have offered three inert fields. This is the mirror check: every
# DECLARED field must be referenced by at least one rule body. Reuses
# plan_profile_fields and backticked_field_refs, both already derived
# above (from PLAN.md and from rules/base-rules.md's Rules section
# respectively) - not recomputed, so this cannot drift from assertion 8's
# derivation.
unreferenced_fields=""
for field in $plan_profile_fields; do
  found=no
  for ref in $backticked_field_refs; do
    if [ "$field" = "$ref" ]; then
      found=yes
      break
    fi
  done
  if [ "$found" = "no" ]; then
    unreferenced_fields="$unreferenced_fields $field"
  fi
done
assert_eq "" "$unreferenced_fields" "every one of the 11 Defaults fields must be referenced at least once as a backticked name in the Rules section (a dead field with zero references must fail)"

# --- 13. At least two rule bodies span multiple paragraphs -------------
#
# Advisory from the S2 review: a naive "read to the next blank line"
# parser (the kind S3's build.sh might be tempted to write) truncates a
# rule the moment it hits an internal blank line, silently dropping
# everything after it - the review proved this against rule 5's
# step-by-step branch and rule 14's "not invisibility" sentence even
# before this cycle's rewrites of rules 1, 3, 13, and the new rule 16
# added more multi-paragraph bodies. This assertion does not fix a
# parser (that is S3's job) - it keeps the CANONICAL file permanently
# carrying the condition that would expose one, so a future build.sh
# cannot pass its own tests by coincidentally being fed a
# single-paragraph-per-rule file.
#
# get_rule_body_prose extracts the lines between a "### <n>. " heading
# and the next "### <digits>. " heading (or EOF for the last rule),
# then drops the leading "<!-- targets: ... -->" marker line(s) - a
# marker is metadata, not prose, and must not count toward paragraph
# structure. paragraph_count then counts blank-line-delimited blocks of
# consecutive non-blank lines in what remains: 1 means single-paragraph,
# 2+ means the body has at least one internal blank line.
get_rule_body_prose() {
  n=$1
  awk -v want="$n" '
    $0 ~ ("^### " want "\\. ") { in_rule = 1; next }
    in_rule && /^### [0-9]+\. / { in_rule = 0 }
    in_rule { print }
  ' "$base_rules_file" | grep -v '^<!-- targets:'
}

multi_paragraph_rule_count=0
multi_paragraph_rule_numbers=""
for num in $heading_sequence; do
  rule_prose=$(get_rule_body_prose "$num")
  paragraph_count=$(printf '%s\n' "$rule_prose" | awk '
    BEGIN { count = 0; in_para = 0 }
    /^[ \t]*$/ { in_para = 0; next }
    { if (!in_para) { count++; in_para = 1 } }
    END { print count }
  ')
  if [ "$paragraph_count" -ge 2 ]; then
    multi_paragraph_rule_count=$((multi_paragraph_rule_count + 1))
    multi_paragraph_rule_numbers="$multi_paragraph_rule_numbers $num"
  fi
done

if [ "$multi_paragraph_rule_count" -ge 2 ]; then
  multi_paragraph_status=yes
else
  multi_paragraph_status=no
fi
assert_eq "yes" "$multi_paragraph_status" "at least two rule bodies must span multiple paragraphs (found $multi_paragraph_rule_count: rules$multi_paragraph_rule_numbers) - guards against a blank-line-terminated parser silently truncating a rule"

# --- 14. Rule 3's body must reference rule 9's carve-out ----------------
#
# Cycle-3 review finding 3: the reviewer deleted the "governs task steps
# only ... rule 9" sentence from rule 3's body and all 56 assertions at
# the time still passed. Reuses get_rule_body_prose (defined above, for
# assertion 13) rather than a second bespoke extraction.
rule_3_body=$(get_rule_body_prose 3)
assert_contains "$rule_3_body" "rule 9" "rule 3's body must reference rule 9's carve-out for multi-question answers (regression: deleting this sentence previously passed the whole suite)"

# --- 15. Rule 6's options_per_answer > 1 branch must be presented up
# front, unprompted -------------------------------------------------------
#
# Cycle-3 review finding 2: the reviewer reverted rule 6 to the pre-fix
# collapsing wording (the >1 branch reads just like the N=1 branch,
# alternatives withheld until asked) and all 56 assertions still passed.
# A blind assert_contains over the whole rule body is not enough: rule
# 6's own opening sentence ("Offer exactly options_per_answer option(s)
# up front, unprompted.") already contains "up front" regardless of what
# the >1 branch says, so a collapsed >1 branch could hide behind it.
# Instead, isolate the specific clause describing the >1 branch - from
# "greater than 1" to the following period - and check THAT clause,
# not the whole body.
rule_6_body=$(get_rule_body_prose 6)
options_gt1_clause=$(printf '%s\n' "$rule_6_body" | grep -oE "greater than 1[^.]*\." | head -n 1)
assert_contains "$options_gt1_clause" "up front" "rule 6's options_per_answer > 1 branch must state the extra options are presented up front (not withheld until asked)"
assert_contains "$options_gt1_clause" "without waiting" "rule 6's options_per_answer > 1 branch must state the options are unprompted, i.e. presented without waiting to be asked"

# --- 16. Rule 16's body must state that rule 2 subordinates the
# warm-tone acknowledgement ------------------------------------------------
#
# Cycle-3 MAJOR finding: rule 16's warm branch collided with rule 2's
# no-preamble ban (a standalone warm opener is rhetorically the same
# preamble rule 2 bans). PLAN.md now settles this explicitly - rule 2
# wins structurally, the acknowledgement must be fused into the same
# sentence as the answer, never a sentence of its own preceding it. This
# pins that settlement into rule 16's body so a future edit cannot
# quietly reopen the collision the way rules 6 and 3 above were reopened.
rule_16_body=$(get_rule_body_prose 16)
assert_contains "$rule_16_body" "rule 2" "rule 16's body must name rule 2 as the rule that subordinates the warm-tone acknowledgement"
assert_contains "$rule_16_body" "same sentence" "rule 16's body must require the acknowledgement be fused into the same sentence as the answer or next action"
assert_contains "$rule_16_body" "preamble" "rule 16's body must state that a standalone warm opener counts as preamble under rule 2"

# --- 17. Rules 1 and 8 state the recap-ordering interaction exactly
# once, in rule 8 -----------------------------------------------------------
#
# Cycle-3 review finding 4: rules 1 and 8 used to restate the same
# recap-then-answer ordering claim in different words ("before anything
# else" vs "never folded into the same sentence"), free to silently
# diverge on the next edit to either one. Rule 8 (which owns
# progress_recap) was made the single owner, and rule 1 kept a paragraph
# pointing at it by number.
#
# [TOKEN AUDIT] That pointer paragraph is gone now too. Naming the
# interaction from rule 1's side cost the system prompt a paragraph in
# every session to say only "rule 8 handles this" - a pure restatement,
# on the side that does not own the behaviour. Rule 8's own second
# paragraph is untouched and still states the ordering in full, so
# nothing rule 1 governed is unstated; what is gone is the second
# mention. The pin is inverted rather than deleted: rule 1 must now name
# rule 8 NOWHERE, so the bookkeeping cannot creep back one clause at a
# time.
rule_1_body=$(get_rule_body_prose 1)
rule_8_body=$(get_rule_body_prose 8)
assert_not_contains "$rule_1_body" "rule 8" "rule 1 must not name rule 8 at all - rule 8 owns progress_recap and states the recap/answer ordering itself, and a cross-reference from rule 1 is bookkeeping shipped in every session's system prompt"
assert_not_contains "$rule_1_body" "on the next line" "rule 1 must not duplicate rule 8's ordering phrasing (the interaction is stated once, in rule 8)"
assert_contains "$rule_8_body" "on the next line" "rule 8 must still state the recap-then-answer ordering explicitly (it is the single owner of this interaction, and now its only statement anywhere)"
assert_contains "$rule_8_body" "The recap is the lead line, not a substitute for the answer" "rule 8 must still state that the recap leads without replacing the answer - with rule 1's pointer paragraph cut, this sentence is the whole of that interaction in the rules"

# --- 18. Rule 10's amended carve-out (S9, X1) is present in the
# canonical body, AND PLAN.md's own restatement of rule 10 agrees with
# it ---------------------------------------------------------------------
#
# S9 probe 8 found rule 10, as originally written, had no carve-out for a
# topic switch the USER has already named: it demanded a confirmation
# question even when the user had just said "forget that, help me with
# X" -- pointless, and itself a violation of rule 2 (no preamble). The
# fix added two things to rule 10's body: a narrowed trigger (assistant-
# initiated, or abandoning open work) and an explicit carve-out for a
# user-named switch. This assertion pins BOTH into the canonical source,
# and separately pins the same carve-out into PLAN.md's own rule-10
# summary (PLAN.md Section 3's "### The base rules" list) -- so a future
# edit that fixes one copy and forgets the other (the exact class named
# in .build-checkpoint.md's invariant 6e, and the reason S6 was rejected
# twice) fails loudly in EITHER direction: reverting rules/base-rules.md
# alone fails the first two assertions below; reverting PLAN.md alone
# fails the third and fourth.
#
# PLAN.md's item 10 is hard-wrapped across five lines with a 4-space
# continuation indent (matching items 13-16), so the anchor phrases below
# would be split by a mid-phrase newline if checked against the raw
# extraction -- flattened first (newlines to spaces, runs of spaces
# squeezed to one), the same technique tests/test_research.sh's
# check_citation_drift_in_text already uses for the identical reason.
rule_10_body=$(get_rule_body_prose 10)
RULE10_CARVEOUT_PHRASE="the user has already named the new topic themselves"
RULE10_TRIGGER_PHRASE="still open and unfinished"
assert_contains "$rule_10_body" "$RULE10_CARVEOUT_PHRASE" "rule 10's canonical body must carve out a topic switch the user has already named (regression: this is the exact clause S9 probe 8 found missing)"
assert_contains "$rule_10_body" "$RULE10_TRIGGER_PHRASE" "rule 10's canonical body must narrow the confirmation trigger to an assistant-initiated switch or abandoning work that is still open and unfinished"

# [S9 fix cycle 1, Y5] PLAN.md's own restatement of a numbered rule (item 10, item 15, ...)
# must be extracted from WITHIN "### The base rules" section only, never from the raw file
# top to bottom. Section 4 ("BUILD STEPS") also has a plain, unnumbered "10. **Iterate:**"
# list item with no "11." after it (the Build Steps list stops at 10) -- an extraction bounded
# only by the next literal "^11\. " line, as this used to be, matches the REAL rule-10 item
# first, correctly stops at the REAL rule 11, but then matches Build Steps item 10 a SECOND
# time later in the file and, finding no subsequent "^11\. " anywhere before EOF, silently
# captures everything from there through the end of the document (all of Section 5 and
# Section 6). That did not cause a false PASS the day this was found only because the pinned
# phrases happened to still be present in the real rule-10 item; a future edit could delete a
# pinned phrase from the real item while an unrelated later match of the same phrase (in the
# accidentally-captured tail) kept the assertion green. Fixed by bounding extraction to the
# "### The base rules" heading's own section first, so Build Steps and everything after it is
# structurally out of reach regardless of numbering collisions.
plan_base_rules_section=$(awk '
  /^### The base rules/ { in_section = 1; next }
  in_section && /^### / { in_section = 0 }
  in_section { print }
' "$plan_file")

# FAILURE PROOF (Y5): the bounded section itself must never reach as far as Section 4's
# Build Steps list (named by its own heading text) or contain the word unique to Build Steps
# item 10's own wording ("Iterate") -- proving the boundary actually holds, not just that the
# two assertions below happen to pass today.
assert_not_contains "$plan_base_rules_section" "BUILD STEPS" "PLAN.md's base-rules section extraction must stop before Section 4 (BUILD STEPS) -- this is exactly the boundary Y5's fix depends on"

plan_rule_10_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^10\. / { in_item = 1 }
  /^11\. / { in_item = 0 }
  in_item { print }
')
assert_not_contains "$plan_rule_10_block" "Iterate" "PLAN.md's rule-10 block, once bounded to the base-rules section, must not include Build Steps item 10 ('**Iterate:**') -- this is exactly the cross-section leakage Y5 fixed"
plan_rule_10_flat=$(printf '%s\n' "$plan_rule_10_block" | tr '\n' ' ' | tr -s ' ')
assert_contains "$plan_rule_10_flat" "$RULE10_CARVEOUT_PHRASE" "PLAN.md's rule-10 summary must carve out a topic switch the user has already named, matching rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_10_flat" "$RULE10_TRIGGER_PHRASE" "PLAN.md's rule-10 summary must narrow the confirmation trigger the same way rules/base-rules.md does (cross-file agreement, invariant 6e)"

plan_rule_15_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^15\. / { in_item = 1 }
  /^16\. / { in_item = 0 }
  in_item { print }
')
plan_rule_15_flat=$(printf '%s\n' "$plan_rule_15_block" | tr '\n' ' ' | tr -s ' ')

# --- 19. Rule 10 and rule 15 state their mutual precedence explicitly
# (S9 fix cycle 1, Y2) ----------------------------------------------------
#
# S9's rule-10 amendment (assertion 18, above) carved out a topic switch the user has already
# named. That carve-out silences rule 10's OWN yes/no question, but rule 15's scope guard
# (a one-line notice with an offer to park, never a gate) still fires on the identical drift,
# because rule 15 does not care who named the new topic -- and rule 15's own worked example is
# itself phrased as a question, so a reader could otherwise mistake it for a second gate. Left
# unstated, rule 10's carve-out reads as though it also silences rule 15, which would swallow
# almost all of rule 15's domain (rule 7 already bars the assistant from introducing tangents,
# so nearly every real drift is one the user named). Both rules now say plainly that they
# govern different acts and both apply. Pinned in BOTH rules/base-rules.md and PLAN.md, in
# both directions, the same cross-file-agreement pattern assertion 18 already uses.
rule_15_body=$(get_rule_body_prose 15)
RULE10_RULE15_PHRASE="does not remove rule 15's flag"
RULE15_RULE10_PHRASE="rule 10 asks no confirmation"
assert_contains "$rule_10_body" "$RULE10_RULE15_PHRASE" "rule 10's canonical body must state that its user-named-topic carve-out does not silence rule 15's flag"
assert_contains "$rule_15_body" "$RULE15_RULE10_PHRASE" "rule 15's canonical body must state that it still fires even when rule 10 asks no confirmation"
assert_contains "$plan_rule_10_flat" "$RULE10_RULE15_PHRASE" "PLAN.md's rule-10 summary must state the same rule-15 precedence as rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_15_flat" "$RULE15_RULE10_PHRASE" "PLAN.md's rule-15 summary must state the same rule-10 precedence as rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 20. Rule 6 carves out a clarifying question's own choices from
# options_per_answer (S9 fix cycle 1, Y3) ----------------------------------
#
# skills/plan/SKILL.md's Step 2 (and skills/init/SKILL.md's seven-question interview, and
# skills/tune/SKILL.md's field-selection question) all present lettered, multiple-choice
# clarifying questions -- probe 6 produced exactly one, with three lettered choices, and
# rule 6's literal pre-fix text ("Offer exactly options_per_answer option(s) up front") had no
# carve-out for a QUESTION's own choices as opposed to SOLUTIONS offered in an answer, so a
# profile with options_per_answer: 1 made every one of those shipped clarifying questions read
# as a violation of the base rules they ship alongside. Fixed by scoping rule 6 to solutions
# offered in an answer, not choices inside a question the assistant is asking. Pinned here so
# the carve-out cannot be quietly dropped the way rule 3's and rule 6's own >1 branch were
# both dropped and still passed, per the S8 cycle-3 findings above (assertions 14-15).
rule_6_body=$(get_rule_body_prose 6)
RULE6_CLARIFYING_CARVEOUT_PHRASE="does not govern the lettered choices inside a question"
assert_contains "$rule_6_body" "$RULE6_CLARIFYING_CARVEOUT_PHRASE" "rule 6's canonical body must carve out a clarifying question's own lettered choices from options_per_answer (regression: this is the exact gap Y3 found between rule 6 and skills/plan, skills/init, skills/tune)"

# --- 21. Rule 2 and rule 15 state the scope-guard flag's position
# explicitly, and agree, in both files (S9 review cycle 2, Z2) -------------
#
# Review cycle 2's MAJOR: rule 15 said the flag "belongs in the same response" but never said
# WHERE in that response -- rule 1 is answer-first and rule 2 bans postamble, so a flag placed
# before the answer reads as preamble (violating rule 1) and a flag placed after reads as the
# postamble rule 2 bans, unless rule 2 names an exception. Fixed by making the flag's position
# explicit (the final line) and naming it as rule 2's one exception, in BOTH rules, and in BOTH
# rules/base-rules.md and PLAN.md's restatements -- the same cross-file-agreement pattern
# assertions 18-19 already use for rules 10/15.
rule_2_body=$(get_rule_body_prose 2)
SCOPE_GUARD_FLAG_PHRASE="rule 15's scope-guard flag"
RULE_FLAG_FINAL_LINE_PHRASE="final line of the response"
RULE15_NAMES_RULE2_PHRASE="rule 2's postamble ban"
assert_contains "$rule_2_body" "$SCOPE_GUARD_FLAG_PHRASE" "rule 2's canonical body must name rule 15's scope-guard flag as trailing content this rule does not ban as postamble [AD3, S10 cycle 3 final gate: rule 2 now defers GENERICALLY ('trailing content another rule expressly licenses') rather than enumerating what rule 7 licenses, so a claude-code-only concept like rule 14's checkpoint-failure report is never named or described here at all; see the AD3 assertions below]"
assert_contains "$rule_2_body" "$RULE_FLAG_FINAL_LINE_PHRASE" "rule 2's canonical body must state the excepted flag is a final-line exception, matching rule 15"
assert_contains "$rule_15_body" "$RULE_FLAG_FINAL_LINE_PHRASE" "rule 15's canonical body must state the flag is the final line of the response, not merely 'the same response'"
assert_contains "$rule_15_body" "$RULE15_NAMES_RULE2_PHRASE" "rule 15's canonical body must name rule 2's postamble ban as the rule its flag is an exception to"

plan_rule_1_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^1\. / { in_item = 1 }
  /^2\. / { in_item = 0 }
  in_item { print }
')
plan_rule_1_flat=$(printf '%s\n' "$plan_rule_1_block" | tr '\n' ' ' | tr -s ' ')

plan_rule_2_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^2\. / { in_item = 1 }
  /^3\. / { in_item = 0 }
  in_item { print }
')
plan_rule_2_flat=$(printf '%s\n' "$plan_rule_2_block" | tr '\n' ' ' | tr -s ' ')

assert_contains "$plan_rule_2_flat" "$SCOPE_GUARD_FLAG_PHRASE" "PLAN.md's rule-2 summary must name the same rule-15 exception as rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_2_flat" "$RULE_FLAG_FINAL_LINE_PHRASE" "PLAN.md's rule-2 summary must state the final-line exception, matching rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_15_flat" "$RULE_FLAG_FINAL_LINE_PHRASE" "PLAN.md's rule-15 summary must state the flag is the final line of the response, matching rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_15_flat" "$RULE15_NAMES_RULE2_PHRASE" "PLAN.md's rule-15 summary must name rule 2's postamble ban, matching rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 22. Rule 7 and rule 15 adjudicate Extra-section-vs-flag ordering,
# and agree, in both files (S9 review cycle 2, Z2 follow-on) ---------------
#
# Naming the flag "the final line" (assertion 21) collides with rule 7's own, pre-existing
# absolute claim that the Extra section sits "at the very end of the response" -- a response
# that fires both would have two different things each claiming to be the actual last line.
# Fixed by having rule 7 name the exception the same way rule 2 does, and rule 15 state it
# yields to nothing but sits after any Extra section, in both files.
rule_7_body=$(get_rule_body_prose 7)
RULE15_RULE7_PHRASE="rule 7 also produces an Extra section in the same response, the flag follows it"
RULE7_RULE15_PHRASE="when rule 15's scope-guard flag also fires in the same response, that flag becomes the actual final line"
assert_contains "$rule_7_body" "$SCOPE_GUARD_FLAG_PHRASE" "rule 7's canonical body must name rule 15's scope-guard flag as part of the trailing-content ordering it states [AD3, S10 cycle 3 final gate: rule 7 now states a GENERIC two-part order (Extra section, then whichever other trailing content another rule licenses, then the flag) rather than naming rule 14's checkpoint-failure report by content - that report's own place in the order is stated by rule 14 itself now; see the AD3 assertions below]"
assert_contains "$rule_7_body" "$RULE7_RULE15_PHRASE" "rule 7's canonical body must state that rule 15's flag, when it also fires, becomes the actual final line after the Extra section"
assert_contains "$rule_15_body" "$RULE15_RULE7_PHRASE" "rule 15's canonical body must state it follows any Extra section rule 7 also produces in the same response"

plan_rule_7_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^7\. / { in_item = 1 }
  /^8\. / { in_item = 0 }
  in_item { print }
')
plan_rule_7_flat=$(printf '%s\n' "$plan_rule_7_block" | tr '\n' ' ' | tr -s ' ')

assert_contains "$plan_rule_7_flat" "$SCOPE_GUARD_FLAG_PHRASE" "PLAN.md's rule-7 summary must name the same rule-15 exception as rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_7_flat" "$RULE7_RULE15_PHRASE" "PLAN.md's rule-7 summary must agree with rules/base-rules.md on the flag-after-Extra-section ordering (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_15_flat" "$RULE15_RULE7_PHRASE" "PLAN.md's rule-15 summary must agree with rules/base-rules.md that the flag follows any Extra section rule 7 produces (cross-file agreement, invariant 6e)"

# --- 23. Rule 6's clarifying-question carve-out (Y3) reaches PLAN.md, and
# rule 6's per-sub-answer scoping under rule 9 (S9 review cycle 2, Z4) is
# stated in both files ------------------------------------------------------
#
# Z3's BLOCKER-adjacent finding: PLAN.md item 6 still read as the pre-Y3 rule, with no cross-file
# test -- invariant 6e failing again, in the same cycle it was fixed for rules 10 and 15. Fixed by
# updating PLAN.md item 6 to match and pinning it the same way. Z4 (cheap, same rule): rule 6 never
# said whether options_per_answer is capped per sub-answer or globally when rule 9 is in play,
# unlike rule 3's explicit rule-9 carve-out (assertion 14). Fixed in both files, pinned in both.
plan_rule_6_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^6\. / { in_item = 1 }
  /^7\. / { in_item = 0 }
  in_item { print }
')
plan_rule_6_flat=$(printf '%s\n' "$plan_rule_6_block" | tr '\n' ' ' | tr -s ' ')

RULE6_PER_SUBANSWER_PHRASE="applies to each sub-answer on its own, not to the response as a whole"
assert_contains "$plan_rule_6_flat" "$RULE6_CLARIFYING_CARVEOUT_PHRASE" "PLAN.md's rule-6 summary must carve out a clarifying question's own choices, matching rules/base-rules.md (cross-file agreement, invariant 6e -- this is Z3's headline fix)"
# [TOKEN AUDIT] Rule 6's copy of that sentence is cut. Rule 3 carries the
# identical sentence for its own cap (assertion 28, below), and the
# variable is still defined here because that assertion uses it.
#
# Stated plainly rather than glossed over: this is NOT a case of the
# surviving side restating the same fact. Rule 3's sentence scopes
# max_list_items; rule 6's scoped options_per_answer. After the cut, rule
# 6's scoping is implied by the parallel wording rather than stated, and
# that is the cost the project owner accepted for this cut. What is NOT
# left unstated is the thing rule 6's sentence actually guarded against -
# rule 9's guarantee that every question gets answered, which rule 3's
# body carries by name (assertion 14).
assert_not_contains "$rule_6_body" "$RULE6_PER_SUBANSWER_PHRASE" "rule 6's canonical body must not carry its own copy of the per-sub-answer sentence - rule 3 states it for its own cap, and two identical sentences ship in every session's system prompt"
assert_not_contains "$plan_rule_6_flat" "$RULE6_PER_SUBANSWER_PHRASE" "PLAN.md's rule-6 summary must not carry it either, matching the cut in rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 24. Rule 1's rule-8 cross-reference and rule 8's recap-ordering
# sentence both reach PLAN.md (S9 review cycle 2, Z3 audit finding) --------
#
# Neither mismatch was named in Z2/Z3's own text, but the same audit standard Z3 asks for --
# "does PLAN.md's restatement still match rules/base-rules.md, and is that agreement pinned by a
# test?" -- turned these up: PLAN.md items 1 and 8 still read as their pre-S8-cycle-3 wording,
# missing the rule-1/rule-8 recap-ordering split that assertion 17 already pins on the canonical
# side only. Fixed and pinned the same way as rule 6 above.
RULE1_RULE8_ORDERING_PHRASE="governs the ordering of the recap and the answer that follows it"
RULE8_ORDERING_PHRASE="follows immediately after the recap, on the next line, never folded into the same sentence"
# [TOKEN AUDIT] Inverted along with assertion 17: rule 1's pointer
# paragraph is cut on the canonical side, so PLAN.md's item 1 must not
# keep restating it either - the two files agreeing that it is GONE is
# the same invariant-6e guarantee as the two agreeing it is present.
assert_not_contains "$plan_rule_1_flat" "$RULE1_RULE8_ORDERING_PHRASE" "PLAN.md's rule-1 summary must not restate rule 8's ordering, matching the cut in rules/base-rules.md (cross-file agreement, invariant 6e)"

plan_rule_8_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^8\. / { in_item = 1 }
  /^9\. / { in_item = 0 }
  in_item { print }
')
plan_rule_8_flat=$(printf '%s\n' "$plan_rule_8_block" | tr '\n' ' ' | tr -s ' ')
assert_contains "$plan_rule_8_flat" "$RULE8_ORDERING_PHRASE" "PLAN.md's rule-8 summary must state the recap-then-answer ordering, matching rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 25. Rule 3's rule-9 carve-out reaches PLAN.md (S9 review cycle 2, Z3
# audit finding) -------------------------------------------------------------
#
# Same audit standard as assertion 24: PLAN.md item 3 was missing the "governs task steps only"
# rule-9 carve-out assertion 14 already pins on the canonical side.
RULE3_RULE9_PHRASE="does not shrink or delay answers covered by rule 9"
plan_rule_3_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^3\. / { in_item = 1 }
  /^4\. / { in_item = 0 }
  in_item { print }
')
plan_rule_3_flat=$(printf '%s\n' "$plan_rule_3_block" | tr '\n' ' ' | tr -s ' ')
assert_contains "$plan_rule_3_flat" "$RULE3_RULE9_PHRASE" "PLAN.md's rule-3 summary must carve out rule 9's multi-question answers from the step cap, matching rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 26. Rule 16's warm-tone/rule-2 settlement, already correct in both
# files, is now pinned cross-file too (S9 review cycle 2, Z3 audit) --------
#
# Z3's full 16-row audit found rule 16 already agreed between the two files (unlike rules 1, 3, 6,
# and 8 above) -- but, like rule 6 before this cycle, that agreement was pinned on the canonical
# side only (assertion 16). Pinning the PLAN.md side closes the same invariant-6e gap
# pre-emptively, before a future edit to only one copy can reopen it.
plan_rule_16_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^16\. / { in_item = 1 }
  in_item { print }
')
plan_rule_16_flat=$(printf '%s\n' "$plan_rule_16_block" | tr '\n' ' ' | tr -s ' ')
assert_contains "$plan_rule_16_flat" "rule 2" "PLAN.md's rule-16 summary must name rule 2 as the rule that subordinates the warm-tone acknowledgement, matching rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_16_flat" "same sentence" "PLAN.md's rule-16 summary must require the acknowledgement be fused into the same sentence, matching rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_16_flat" "preamble" "PLAN.md's rule-16 summary must state that a standalone warm opener counts as preamble, matching rules/base-rules.md (cross-file agreement, invariant 6e)"

# --- 27. Rule 2 and rule 15 no longer forbid "other trailing content" —
# rule 7 owns the Extra-section/flag ordering alone (S9 review cycle 3, AA1
# MAJOR) ---------------------------------------------------------------------
#
# Review cycle 3's MAJOR: rule 2 ended "...rule 15 requires it by name, and no other trailing
# content is permitted," and rule 15 echoed it ("rule 2 permits exactly this one trailing line when
# this rule fires, and nothing else"). Both are absolute claims that directly contradict rule 7,
# which REQUIRES an Extra section (also "trailing content", sitting between the answer and rule 15's
# flag) whenever extras_section is yes and something adjacent genuinely matters. In the combined
# case — drift AND a genuine Extra — rule 2/15's "nothing else" forbids exactly what rule 7 mandates.
# Fixed by deletion, not a narrower absolute: both over-reaching clauses are gone, and rule 7 remains
# the only rule that states where the Extra section sits relative to the flag (already pinned by
# assertion 22's RULE7_RULE15_PHRASE / RULE15_RULE7_PHRASE pair, unaffected by this fix). These two
# negative pins guard against either clause quietly returning.
assert_not_contains "$rule_2_body" "no other trailing content is permitted" "rule 2's canonical body must not restate an absolute forbidding other trailing content (AA1) — rule 7 already requires the Extra section as trailing content between the answer and rule 15's flag, and the two must not compete"
assert_not_contains "$rule_15_body" "rule 2 permits exactly this one trailing line when this rule fires, and nothing else" "rule 15's canonical body must not claim rule 2 permits nothing else trailing (AA1) — the same over-reach as rule 2's, restated"

# --- 28. Rule 3 gets the same per-sub-answer scoping rule 6 already has
# (S9 review cycle 3, AA3) ---------------------------------------------------
#
# Rule 6 (Z4, assertion 23) states options_per_answer's cap applies per sub-answer, not to the whole
# response, when rule 9 puts several answers in one response. Rule 3's max_list_items cap had the
# identical ambiguity — a two-question response with multi-step sub-answers was undetermined — and
# no equivalent statement. Fixed with wording parallel to rule 6's own (RULE6_PER_SUBANSWER_PHRASE,
# defined above), so the two rules read as one decision applied twice, not two independent ones.
assert_contains "$rule_3_body" "$RULE6_PER_SUBANSWER_PHRASE" "rule 3's canonical body must state the max_list_items cap applies per sub-answer when rule 9 produces several in one response (AA3), worded parallel to rule 6's own per-sub-answer sentence"
assert_contains "$plan_rule_3_flat" "$RULE6_PER_SUBANSWER_PHRASE" "PLAN.md's rule-3 summary must state the same per-sub-answer scoping as rules/base-rules.md (AA3, cross-file agreement, invariant 6e)"

# --- 29. Rule 7's extras_section:no branch reaches PLAN.md (S9 review cycle
# 3, AA2) ---------------------------------------------------------------------
#
# PLAN.md item 7 was missing canonical rule 7's closing sentence, "When extras_section is no, omit
# it entirely" — a real behavioral clause (the Extra section must not appear at all when the field is
# off), not decorative. Fixed by adding it to PLAN.md item 7 and pinning both sides, since canonical
# already had it but nothing pinned it either.
RULE7_OMIT_PHRASE="omit it entirely"
assert_contains "$rule_7_body" "$RULE7_OMIT_PHRASE" "rule 7's canonical body must state that the Extra section is omitted entirely when extras_section is no"
assert_contains "$plan_rule_7_flat" "$RULE7_OMIT_PHRASE" "PLAN.md's rule-7 summary must state the same extras_section:no behavior as rules/base-rules.md (AA2, cross-file agreement, invariant 6e)"

# --- 30. Rule 15's rule-2 scope sentence (as rewritten by AA1) reaches
# PLAN.md (S9 review cycle 3, AA2) --------------------------------------------
#
# PLAN.md item 15 omitted canonical rule 15's sentence naming exactly what rule 2 permits ("rule 2
# permits exactly this one trailing line when this rule fires") entirely — it jumped straight from
# "an explicit, named exception to rule 2's postamble ban" to the rule-7 Extra-section sentence, with
# no restatement of rule 2's own scope in between. Fixed by adding the AA1-rewritten sentence (without
# the deleted "and nothing else") to PLAN.md item 15, and pinning both sides.
RULE15_RULE2_SCOPE_PHRASE="rule 2 permits exactly this one trailing line when this rule fires"
assert_contains "$rule_15_body" "$RULE15_RULE2_SCOPE_PHRASE" "rule 15's canonical body must state what rule 2 permits, without the deleted over-reach (AA1)"
assert_contains "$plan_rule_15_flat" "$RULE15_RULE2_SCOPE_PHRASE" "PLAN.md's rule-15 summary must state the same rule-2 scope sentence as rules/base-rules.md (AA2, cross-file agreement, invariant 6e)"

# --- 31. Rule 16's three PLAN.md omissions — "before the answer", "regardless
# of `tone`", and the closing tie to rule 13 (S9 review cycle 3, AA2) --------
#
# PLAN.md item 16 dropped three pieces of canonical rule 16's meaning: the warm-opener sentence said
# only "stands alone is preamble" (missing "before the answer") and "rule 2 forbids it" with no
# "regardless of `tone`"; and the closing sentence stopped at "never overrides rule 13" with no tie
# to what that means for a safety warning's content. None of these were pinned on the canonical side
# either. Fixed both files, pinned both sides for all three.
RULE16_BEFORE_ANSWER_PHRASE="warm opener that stands alone before the answer is preamble"
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted field name, not
# a command substitution.
RULE16_TONE_OVERRIDE_PHRASE='rule 2 forbids it regardless of `tone`'
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted field name, not
# a command substitution.
RULE16_SAFETY_TIE_PHRASE='a safety warning keeps its full content regardless of `tone`'
assert_contains "$rule_16_body" "$RULE16_BEFORE_ANSWER_PHRASE" "rule 16's canonical body must state a standalone warm opener is preamble specifically because it precedes the answer"
assert_contains "$rule_16_body" "$RULE16_TONE_OVERRIDE_PHRASE" "rule 16's canonical body must state rule 2 forbids a standalone warm opener regardless of tone"
assert_contains "$plan_rule_16_flat" "$RULE16_BEFORE_ANSWER_PHRASE" "PLAN.md's rule-16 summary must state the same before-the-answer scoping as rules/base-rules.md (AA2, cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_16_flat" "$RULE16_TONE_OVERRIDE_PHRASE" "PLAN.md's rule-16 summary must state the same regardless-of-tone override as rules/base-rules.md (AA2, cross-file agreement, invariant 6e)"

# [TOKEN AUDIT] Rule 16's second paragraph, which carried the phrase
# above, is cut. Rule 13 owns its own precedence and already states it
# from that side, naming rule 16 by number and carrying the behaviour-
# changing extras_section:no carve-out with it (assertion 8's
# "precedence"/"extras_section" pins, above). Rule 16 restating "rule 13
# wins" was the non-owning half of a bilateral pair, priced in every
# session's system prompt. Inverted on both sides, and the surviving
# owner is pinned here by name so the relationship cannot be lost by
# cutting rule 13's paragraph next.
assert_not_contains "$rule_16_body" "$RULE16_SAFETY_TIE_PHRASE" "rule 16's canonical body must not restate rule 13's precedence - rule 13 owns it, states it, and carries the extras_section:no carve-out that makes it behavioural"
assert_not_contains "$plan_rule_16_flat" "$RULE16_SAFETY_TIE_PHRASE" "PLAN.md's rule-16 summary must not restate rule 13's precedence either, matching the cut in rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$rule_13_body" "rule 16" "rule 13's canonical body must name rule 16 in its precedence list - with rule 16's own restatement cut, this is the only place the two rules' relationship is stated"

# --- 32. Rule 14 licenses a one-line failure report for its checkpoint
# read/write, and PLAN.md agrees (S10-1) --------------------------------
#
# S10-1's live probe (.build-checkpoint.md) found the model narrating a checkpoint operation's
# failure -- the right instinct, since a failure must never be absorbed silently, but unlicensed
# by rule 14 as originally written: the rule only ever said not to announce a SUCCESSFUL write and
# not to ask permission first, and never addressed what to do when the read or the write fails.
# Fixed by adding one sentence to rule 14's body, stating a failure is reported in one line and
# that this is not the "no commentary" ban's target (which governs an ordinary, successful update).
# Mirrored into PLAN.md item 14 verbatim (the same identical-wording convention AA3 used for rule
# 3/rule 6's per-sub-answer sentence), pinned in both directions the same way every other rule
# amendment in this build has been.
rule_14_body=$(get_rule_body_prose 14)
RULE14_FAILURE_PHRASE="a failure is reported, never absorbed silently"
assert_contains "$rule_14_body" "$RULE14_FAILURE_PHRASE" "rule 14's canonical body must license a one-line report when the checkpoint read or write fails (S10-1: this is the narration a live probe found the model doing, unlicensed, before this fix)"

plan_rule_14_block=$(printf '%s\n' "$plan_base_rules_section" | awk '
  /^14\. / { in_item = 1 }
  /^15\. / { in_item = 0 }
  in_item { print }
')
assert_not_contains "$plan_rule_14_block" "Scope guard" "PLAN.md's rule-14 block, once bounded to the base-rules section, must not include item 15's own heading text -- guards against the same cross-item leakage class Y5 fixed for rule 10"
plan_rule_14_flat=$(printf '%s\n' "$plan_rule_14_block" | tr '\n' ' ' | tr -s ' ')
assert_contains "$plan_rule_14_flat" "$RULE14_FAILURE_PHRASE" "PLAN.md's rule-14 summary must state the same one-line failure report as rules/base-rules.md (S10-1, cross-file agreement, invariant 6e)"

# FAILURE PROOF (S10-1, assertion 32): deleting the failure-report sentence from an IN-MEMORY
# mutant of each file's own content independently must make that file's own assertion above fail,
# and must leave the OTHER file's assertion (checked against the real, unmodified file) passing --
# proving the two pins are independent, not one accidentally covering for the other. Built purely
# from variables and awk/grep/sed on stdin (no scratch file or directory needed, so no
# cleanup/trap is required at all).
#
# rules/base-rules.md holds the whole sentence on ONE line (line 133; every paragraph in this
# canonical source is a single long line), so a whole-line delete is exact and needs no flattening.
# PLAN.md hard-wraps the identical sentence across three lines (mid-line, per its own
# continuation-indent convention for items 13-16) -- flattened first, the same technique used for
# plan_rule_14_flat above, then the exact phrase is removed by literal substring match via sed.
RULE14_FULL_SENTENCE="If the read or the write fails, say so in one line: a failure is reported, never absorbed silently, and that one-line report is not the commentary the paragraph above forbids."
rule14_canonical_mutant_content=$(grep -vxF "$RULE14_FULL_SENTENCE" "$base_rules_file")
rule14_canonical_mutant_body=$(printf '%s\n' "$rule14_canonical_mutant_content" | awk '
  /^### 14\. / { in_rule = 1; next }
  in_rule && /^### [0-9]+\. / { in_rule = 0 }
  in_rule { print }
' | grep -v '^<!-- targets:')
if printf '%s' "$rule14_canonical_mutant_body" | grep -qF "$RULE14_FAILURE_PHRASE"; then
  rule14_canonical_mutant_still_has_phrase=yes
else
  rule14_canonical_mutant_still_has_phrase=no
fi
assert_eq "no" "$rule14_canonical_mutant_still_has_phrase" "FAILURE PROOF (S10-1, assertion 32): deleting the failure-report sentence from an in-memory mutant of rules/base-rules.md must remove it from rule 14's body, proving the canonical-side pin is not vacuous"

plan_mutant_flat=$(printf '%s' "$plan_rule_14_flat" | sed "s/ $RULE14_FULL_SENTENCE//")
if printf '%s' "$plan_mutant_flat" | grep -qF "$RULE14_FAILURE_PHRASE"; then
  plan_mutant_still_has_phrase=yes
else
  plan_mutant_still_has_phrase=no
fi
assert_eq "no" "$plan_mutant_still_has_phrase" "FAILURE PROOF (S10-1, assertion 32): deleting the failure-report sentence from an in-memory (flattened) mutant of PLAN.md's rule-14 summary must remove it, proving the PLAN.md-side pin is not vacuous"

# Cross-check: the canonical mutant (failure sentence deleted from rules/base-rules.md only) must
# leave PLAN.md's own, UNMODIFIED copy of the sentence untouched, and vice versa -- proving the two
# assertions above are independent pins, neither accidentally covering for the other.
assert_contains "$plan_rule_14_flat" "$RULE14_FAILURE_PHRASE" "FAILURE PROOF (S10-1, assertion 32) independence check: the real, unmodified PLAN.md must still carry the failure-report sentence even while a SEPARATE in-memory mutant of rules/base-rules.md just had it deleted"
# Sanity: the flattened PLAN.md mutant must actually be SHORTER than the real one -- proving the
# sed substitution above genuinely removed text rather than silently matching nothing (a pattern
# typo would leave plan_mutant_flat byte-identical to plan_rule_14_flat and this check would fail).
if [ "${#plan_mutant_flat}" -lt "${#plan_rule_14_flat}" ]; then
  plan_mutant_flat_shorter=yes
else
  plan_mutant_flat_shorter=no
fi
assert_eq "yes" "$plan_mutant_flat_shorter" "sanity: the PLAN.md deletion mutant above must actually be shorter than the real flattened text, proving the sed removal matched real text and did not silently no-op"

# --- 33. Rules 2 and 7 no longer claim rule 15's flag is the SINGULAR
# exception to their own absolute; rule 7 states the trailing-content
# order once, and rule 2 defers to it (S10 review cycle 1, AB2; further
# narrowed by AD3, S10 cycle 3 final gate) --------------------------------
#
# AB2's own history, unchanged here: S10-1's fix (assertion 32, above)
# added a one-line failure-report license to rule 14. Rule 2 still said
# "The one named exception is rule 15's scope-guard flag" and rule 7 still
# said "The one exception: when rule 15's scope-guard flag also fires" -
# both literally singular claims that named ONLY rule 15's flag as
# licensed trailing content. A checkpoint write failure (rule 14's report)
# with extras_section: yes and no drift needs Answer -> Extra -> failure
# report, which rule 2's "the one ... exception" text forbids by omission
# (it names no other licensed trailing content) and which rule 7's
# identically-shaped claim forbids the same way. Same defect class as
# S9's AA1 (rule 2/15's "no other trailing content"/"and nothing else"),
# recurring on a different pair of rules. AB2 fixed it the way AA1 was
# fixed: deleted the over-broad singular claims, and had rule 7 state a
# three-item order BY NAME - Extra section, then rule 14's checkpoint-
# failure report, then rule 15's scope-guard flag - with rules 2 and 14
# deferring to it.
#
# AD3 (this cycle): AB2's three-item order still named the checkpoint-
# failure report's CONCEPT in rules 2 and 7, and both are `targets: all` -
# so that concept shipped, described in prose, into
# targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc, where
# checkpoints do not exist at all (README's parity table: "Auto
# checkpoints: no"; docs/OTHER-TOOLS.md: nothing writes to a checkpoints
# directory on either target). AC2's fix (below) had already stopped
# rules 2/7 from naming rule 14 BY NUMBER; the CONCEPT surviving in prose
# is the gap AD3 closes. Fixed by making rule 7's ordering GENERIC
# ("whichever other trailing content another rule licenses for this
# response") instead of naming the report, and by having rule 14 itself
# state where its own report falls in that generic slot - the only place
# left that can say so, since rule 14 is the only one of the three rules
# that is `targets: claude-code`. Deliberately NOT a second closed,
# two-item list ("Extra section, then the flag") with the report just
# removed and nothing put in its place: that would recreate AB2's own
# forbid-by-omission shape one level up. The slot is genuinely open-ended -
# rule 7 does not enumerate what may fill it, only where it goes.
rule_2_body=$(get_rule_body_prose 2)
rule_7_body=$(get_rule_body_prose 7)
rule_14_body=$(get_rule_body_prose 14)

RULE2_SINGULAR_RETIRED="The one named exception is rule 15's scope-guard flag"
RULE7_SINGULAR_RETIRED="The one exception: when rule 15's scope-guard flag also fires"
assert_not_contains "$rule_2_body" "$RULE2_SINGULAR_RETIRED" "rule 2's canonical body must not claim rule 15's flag is its ONE (singular) exception (AB2) - other rule-licensed trailing content is possible, and rule 2 no longer enumerates exceptions itself"
assert_not_contains "$rule_7_body" "$RULE7_SINGULAR_RETIRED" "rule 7's canonical body must not claim rule 15's flag is THE (singular) exception to the Extra section being final (AB2) - the ordering below names a generic slot for other trailing content, not a fixed second item"

# AD3 negative pins: the AB2-era wording that named the checkpoint-
# failure report's CONTENT directly in rules 2 or 7 must never return -
# that is precisely the defect AD3 fixed. "checkpoint" appears nowhere in
# either rule's canonical body any more (rule 15's own, unrelated "does
# not assume a checkpoint... exists on any target" disclaimer is the only
# correct use of that word among the `targets: all` rules, and it is
# neither rule 2 nor rule 7).
assert_not_contains "$rule_2_body" "checkpoint" "AD3: rule 2's canonical body ('targets: all') must not mention checkpoints at all - that concept only exists on Claude Code and belongs in rule 14 alone"
assert_not_contains "$rule_7_body" "checkpoint" "AD3: rule 7's canonical body ('targets: all') must not mention checkpoints at all - that concept only exists on Claude Code and belongs in rule 14 alone"

RULE7_AB2_ORDER_RETIRED="then the failure report, then the flag, and the flag is always last"
assert_not_contains "$rule_7_body" "$RULE7_AB2_ORDER_RETIRED" "AD3: rule 7's canonical body must not carry AB2's three-item order naming the failure report specifically - the order is now generic, and the report's own place in it is stated by rule 14 instead"

RULE14_AB2_DEFER_RETIRED="is set by rule 7, not by this rule"
assert_not_contains "$rule_14_body" "$RULE14_AB2_DEFER_RETIRED" "AD3: rule 14's canonical body must not merely defer to rule 7 for its report's position any more - rule 7 no longer knows the report exists, so rule 14 now states its own place in the ordering directly"

RULE7_GENERIC_ORDER_PHRASE="then whichever other trailing content another rule licenses for this response"
assert_contains "$rule_7_body" "$RULE7_GENERIC_ORDER_PHRASE" "AD3: rule 7's canonical body must state a GENERIC slot for other rule-licensed trailing content (not the retired AB2 three-item order that named the checkpoint-failure report specifically)"

RULE2_DEFERS_TO_RULE7_PHRASE="Rule 7 states what may trail the answer and in what order"
assert_contains "$rule_2_body" "$RULE2_DEFERS_TO_RULE7_PHRASE" "rule 2's canonical body must defer to rule 7 for the trailing-content ordering, rather than restating its own absolute"

RULE2_GENERIC_DEFER_PHRASE="the trailing content another rule expressly licenses"
assert_contains "$rule_2_body" "$RULE2_GENERIC_DEFER_PHRASE" "AD3: rule 2's canonical body must defer GENERICALLY ('another rule expressly licenses') rather than enumerating what rule 7 licenses - an enumeration is exactly what forbade rule 14's report by omission under AB2"

RULE14_SLOT_PHRASE="the other trailing content rule 7's ordering makes room for"
assert_contains "$rule_14_body" "$RULE14_SLOT_PHRASE" "AD3: rule 14's canonical body must state that its failure report is the 'other trailing content' rule 7's generic ordering makes room for, and place it explicitly between any Extra section and rule 15's flag"

# Cross-file: PLAN.md items 2, 7, and 14 restate the AD3 fix identically
# (plan_rule_2_flat / plan_rule_7_flat / plan_rule_14_flat are already
# derived, fresh, from the real file earlier in this script - assertions
# 21, 22, and 32 respectively - reused here rather than recomputed, so
# this cannot silently drift from those derivations).
assert_contains "$plan_rule_2_flat" "$RULE2_DEFERS_TO_RULE7_PHRASE" "PLAN.md's rule-2 summary must defer to rule 7 the same way rules/base-rules.md does (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_2_flat" "$RULE2_GENERIC_DEFER_PHRASE" "PLAN.md's rule-2 summary must defer GENERICALLY, matching rules/base-rules.md (AD3, cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_7_flat" "$RULE7_GENERIC_ORDER_PHRASE" "PLAN.md's rule-7 summary must state the same GENERIC ordering as rules/base-rules.md (AD3, cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_14_flat" "$RULE14_SLOT_PHRASE" "PLAN.md's rule-14 summary must state the same generic-slot placement as rules/base-rules.md (AD3, cross-file agreement, invariant 6e)"
assert_not_contains "$plan_rule_2_flat" "$RULE2_SINGULAR_RETIRED" "PLAN.md's rule-2 summary must not carry the retired singular-exception wording either (AB2)"
assert_not_contains "$plan_rule_7_flat" "$RULE7_SINGULAR_RETIRED" "PLAN.md's rule-7 summary must not carry the retired singular-exception wording either (AB2)"
assert_not_contains "$plan_rule_2_flat" "checkpoint" "AD3: PLAN.md's rule-2 summary must not mention checkpoints either, matching rules/base-rules.md"
assert_not_contains "$plan_rule_7_flat" "checkpoint" "AD3: PLAN.md's rule-7 summary must not mention checkpoints either, matching rules/base-rules.md"

# FAILURE PROOF (positive pins): deleting each new sentence from an
# IN-MEMORY mutant of the real, current rule body must remove the phrase
# this assertion pins - proving the positive canonical pins above are not
# vacuous. Each new sentence is its own whole physical line in
# rules/base-rules.md (this project's one-paragraph-per-line convention),
# so a whole-line delete via grep -vxF is exact, the same technique
# assertion 32 already uses for rule 14's failure-report sentence.
RULE2_NEW_PARA="None of that bans the trailing content another rule expressly licenses. Rule 7 states what may trail the answer and in what order; this rule does not restate it. The clearest example is rule 15's scope-guard flag: when rule 15 fires, its one line follows the completed answer as the final line of the response, and it is never the postamble this rule bans."
RULE7_NEW_PARA="This rule states, once, the order that applies on every target: the \`Extra\` section comes first, then whichever other trailing content another rule licenses for this response; when rule 15's scope-guard flag also fires in the same response, that flag becomes the actual final line, after the Extra section and after any such other trailing content. Rule 2 defers to this ordering rather than restating it."
RULE14_NEW_PARA="This report is the other trailing content rule 7's ordering makes room for: it falls after any Extra section rule 7 produces and before rule 15's scope-guard flag, exactly where rule 7 says other rule-licensed trailing content goes. That only matters here, on Claude Code: neither this report nor a checkpoint exists on the other two targets."

extract_rule_body_from_content() {
  # extract_rule_body_from_content <content> <n> - same delimiter logic as
  # get_rule_body_prose, but over an in-memory mutant's content instead of
  # re-reading base_rules_file, so a mutation never touches the tracked file.
  content=$1
  n=$2
  printf '%s\n' "$content" | awk -v want="$n" '
    $0 ~ ("^### " want "\\. ") { in_rule = 1; next }
    in_rule && /^### [0-9]+\. / { in_rule = 0 }
    in_rule { print }
  ' | grep -v '^<!-- targets:'
}

rule2_mutant_content=$(grep -vxF "$RULE2_NEW_PARA" "$base_rules_file")
rule2_mutant_body=$(extract_rule_body_from_content "$rule2_mutant_content" 2)
if printf '%s' "$rule2_mutant_body" | grep -qF -- "$RULE2_DEFERS_TO_RULE7_PHRASE"; then
  rule2_mutant_still_has=yes
else
  rule2_mutant_still_has=no
fi
assert_eq "no" "$rule2_mutant_still_has" "FAILURE PROOF: deleting rule 2's new deferral sentence from an in-memory mutant must remove the deferral phrase, proving the canonical-side pin is not vacuous"

if printf '%s' "$rule2_mutant_body" | grep -qF -- "$RULE2_GENERIC_DEFER_PHRASE"; then
  rule2_mutant_still_has_generic=yes
else
  rule2_mutant_still_has_generic=no
fi
assert_eq "no" "$rule2_mutant_still_has_generic" "FAILURE PROOF (AD3): deleting rule 2's new deferral sentence from an in-memory mutant must also remove the GENERIC-defer phrase, proving that canonical-side pin is not vacuous either"

rule7_mutant_content=$(grep -vxF "$RULE7_NEW_PARA" "$base_rules_file")
rule7_mutant_body=$(extract_rule_body_from_content "$rule7_mutant_content" 7)
if printf '%s' "$rule7_mutant_body" | grep -qF -- "$RULE7_GENERIC_ORDER_PHRASE"; then
  rule7_mutant_still_has=yes
else
  rule7_mutant_still_has=no
fi
assert_eq "no" "$rule7_mutant_still_has" "FAILURE PROOF (AD3): deleting rule 7's new ordering sentence from an in-memory mutant must remove the GENERIC ordering phrase, proving the canonical-side pin is not vacuous"

rule14_mutant_content=$(grep -vxF "$RULE14_NEW_PARA" "$base_rules_file")
rule14_mutant_body=$(extract_rule_body_from_content "$rule14_mutant_content" 14)
if printf '%s' "$rule14_mutant_body" | grep -qF -- "$RULE14_SLOT_PHRASE"; then
  rule14_mutant_still_has=yes
else
  rule14_mutant_still_has=no
fi
assert_eq "no" "$rule14_mutant_still_has" "FAILURE PROOF (AD3): deleting rule 14's new slot-placement sentence from an in-memory mutant must remove the slot phrase, proving the canonical-side pin is not vacuous"

# FAILURE PROOF (AB2, negative pins): appending the exact retired singular
# phrase to an in-memory mutant of the real, current rule 2 / rule 7 body
# must make it FOUND by the same grep -qF check assert_not_contains uses
# internally - proving the negative pins above would actually catch a
# reintroduction, not merely never trigger.
rule2_reintro_body="$rule_2_body
$RULE2_SINGULAR_RETIRED"
if printf '%s' "$rule2_reintro_body" | grep -qF -- "$RULE2_SINGULAR_RETIRED"; then
  rule2_reintro_found=yes
else
  rule2_reintro_found=no
fi
assert_eq "yes" "$rule2_reintro_found" "FAILURE PROOF (AB2, negative pin): re-appending rule 2's retired singular-exception phrase to an in-memory mutant must be detected, proving the assert_not_contains guard above is not vacuous"

rule7_reintro_body="$rule_7_body
$RULE7_SINGULAR_RETIRED"
if printf '%s' "$rule7_reintro_body" | grep -qF -- "$RULE7_SINGULAR_RETIRED"; then
  rule7_reintro_found=yes
else
  rule7_reintro_found=no
fi
assert_eq "yes" "$rule7_reintro_found" "FAILURE PROOF (AB2, negative pin): re-appending rule 7's retired singular-exception phrase to an in-memory mutant must be detected, proving the assert_not_contains guard above is not vacuous"

# FAILURE PROOF (AB2, PLAN.md cross-file side): removing each phrase from
# a FLATTENED in-memory mutant of PLAN.md's own text (the same flatten-
# then-sed technique assertion 32 already uses for PLAN.md's rule-14
# summary, since PLAN.md hard-wraps these items across multiple lines)
# must remove it there too, and the real, unmodified PLAN.md text must be
# unaffected by a separate mutant - proving the three PLAN-side pins are
# independent of the canonical-side ones, neither accidentally covering
# for the other.
plan_rule_2_mutant_flat=$(printf '%s' "$plan_rule_2_flat" | sed "s/ $RULE2_DEFERS_TO_RULE7_PHRASE;/;/")
if printf '%s' "$plan_rule_2_mutant_flat" | grep -qF -- "$RULE2_DEFERS_TO_RULE7_PHRASE"; then
  plan_rule_2_mutant_still_has=yes
else
  plan_rule_2_mutant_still_has=no
fi
assert_eq "no" "$plan_rule_2_mutant_still_has" "FAILURE PROOF: removing the deferral phrase from a flattened in-memory mutant of PLAN.md's rule-2 summary must remove it, proving the PLAN.md-side pin is not vacuous"
assert_contains "$plan_rule_2_flat" "$RULE2_DEFERS_TO_RULE7_PHRASE" "FAILURE PROOF independence check: the real, unmodified PLAN.md must still carry rule 2's deferral phrase even while a SEPARATE in-memory mutant just had it removed"

plan_rule_2_mutant_generic_flat=$(printf '%s' "$plan_rule_2_flat" | sed "s/$RULE2_GENERIC_DEFER_PHRASE//")
if printf '%s' "$plan_rule_2_mutant_generic_flat" | grep -qF -- "$RULE2_GENERIC_DEFER_PHRASE"; then
  plan_rule_2_mutant_generic_still_has=yes
else
  plan_rule_2_mutant_generic_still_has=no
fi
assert_eq "no" "$plan_rule_2_mutant_generic_still_has" "FAILURE PROOF (AD3): removing the GENERIC-defer phrase from a flattened in-memory mutant of PLAN.md's rule-2 summary must remove it, proving that PLAN.md-side pin is not vacuous"
assert_contains "$plan_rule_2_flat" "$RULE2_GENERIC_DEFER_PHRASE" "FAILURE PROOF (AD3) independence check: the real, unmodified PLAN.md must still carry rule 2's generic-defer phrase even while a SEPARATE in-memory mutant just had it removed"

plan_rule_7_mutant_flat=$(printf '%s' "$plan_rule_7_flat" | sed "s/$RULE7_GENERIC_ORDER_PHRASE//")
if printf '%s' "$plan_rule_7_mutant_flat" | grep -qF -- "$RULE7_GENERIC_ORDER_PHRASE"; then
  plan_rule_7_mutant_still_has=yes
else
  plan_rule_7_mutant_still_has=no
fi
assert_eq "no" "$plan_rule_7_mutant_still_has" "FAILURE PROOF (AD3): removing the GENERIC ordering phrase from a flattened in-memory mutant of PLAN.md's rule-7 summary must remove it, proving the PLAN.md-side pin is not vacuous"
assert_contains "$plan_rule_7_flat" "$RULE7_GENERIC_ORDER_PHRASE" "FAILURE PROOF (AD3) independence check: the real, unmodified PLAN.md must still carry rule 7's generic ordering phrase even while a SEPARATE in-memory mutant just had it removed"

plan_rule_14_mutant_flat=$(printf '%s' "$plan_rule_14_flat" | sed "s/$RULE14_SLOT_PHRASE//")
if printf '%s' "$plan_rule_14_mutant_flat" | grep -qF -- "$RULE14_SLOT_PHRASE"; then
  plan_rule_14_mutant_still_has=yes
else
  plan_rule_14_mutant_still_has=no
fi
assert_eq "no" "$plan_rule_14_mutant_still_has" "FAILURE PROOF (AD3): removing the slot-placement phrase from a flattened in-memory mutant of PLAN.md's rule-14 summary must remove it, proving the PLAN.md-side pin is not vacuous"
assert_contains "$plan_rule_14_flat" "$RULE14_SLOT_PHRASE" "FAILURE PROOF (AD3) independence check: the real, unmodified PLAN.md must still carry rule 14's slot-placement phrase even while a SEPARATE in-memory mutant just had it removed"

# --- 34. [P1, TECH-LEAD DECISION D2] Rule 14 names no path shape ------
#
# Rule 14 used to spell out `~/.squirrel/checkpoints/<project-slug>.md`.
# It cannot any more, for two independent reasons. The path is now
# per-session, so no shape written into the rule text is complete
# without a value only the hook knows; and the model has never been able
# to compute the slug, which is why the resolved path is injected in the
# first place (tech-lead Decision 1). Every other consumer already reads
# the injected `Project checkpoint path:` line; rule 14 now does too.
#
# The ten-entry cap is redefined as ten entries IN THE SESSION'S OWN
# FILE. A cap across the whole project would require the model to read
# files other sessions own, concurrently, to enforce it - the exact
# shared-state problem P1 removes. The user-visible behaviour is
# preserved at READ time instead, where /squirrel:pickup folds by mtime.
#
# Deliberately NOT pinned against PLAN.md, unlike assertion 32's
# failure-report sentence: PLAN.md's own rule-14 summary still describes
# the old flat path and is outside this step's ownership. That
# divergence is reported, not silently pinned green here.
RULE14_INJECTED_PATH_PHRASE="the \`Project checkpoint path:\` line injected at the start of the session"
RULE14_PER_FILE_CAP_PHRASE="keeping only the last 10 entries in that file"
RULE14_OTHER_SESSIONS_PHRASE="Every other file in that project's checkpoint directory belongs to a different session"
# shellcheck disable=SC2088 # not a path this shell ever opens: a literal
# needle searched for in rule 14's TEXT, where the leading "~" is part of
# the retired wording being banned.
RULE14_RETIRED_PATH_SHAPE="~/.squirrel/checkpoints/<project-slug>.md"

assert_contains "$rule_14_body" "$RULE14_INJECTED_PATH_PHRASE" "D2: rule 14's canonical body must point at the injected 'Project checkpoint path:' line rather than naming a path shape - the model cannot compute the slug, and the path is now per-session"
assert_contains "$rule_14_body" "$RULE14_PER_FILE_CAP_PHRASE" "D2: rule 14's ten-entry cap must be scoped to the session's OWN file - a project-wide cap would need the model to read files other sessions are concurrently writing"
assert_contains "$rule_14_body" "$RULE14_OTHER_SESSIONS_PHRASE" "D2: rule 14 must tell the model to leave other sessions' files alone - without that, 'keep 10 entries' invites exactly the cross-file editing the per-session layout exists to prevent"
assert_not_contains "$rule_14_body" "$RULE14_RETIRED_PATH_SHAPE" "D2: rule 14 must no longer name the retired flat path shape - it is wrong twice over now (the layout is nested, and the slug is not something the model can compute)"

# FAILURE PROOF (D2): delete each new sentence from an in-memory mutant
# of the real file and confirm that phrase, and only that phrase,
# disappears from rule 14's body. Built with grep -vxF against whole
# lines, the same technique assertion 32 uses, since every paragraph in
# this canonical source is one long line.
RULE14_D2_SENTENCE="When a meaningful unit of work completes, update this session's own checkpoint file with the new Doing and Next state, and append finished items to the Done log, keeping only the last 10 entries in that file. The file is named for you in context, on the \`Project checkpoint path:\` line injected at the start of the session: use that path exactly as given, and never compute, guess, or re-derive one. Every other file in that project's checkpoint directory belongs to a different session; leave them alone, and let \`/squirrel:pickup\` be the one that reads across them. Write with no commentary in the response: do not announce the write and do not ask permission first. Make at most one such write per turn, and only when Doing or Next actually changed."

rule14_d2_mutant_content=$(grep -vxF "$RULE14_D2_SENTENCE" "$base_rules_file")
rule14_d2_mutant_body=$(extract_rule_body_from_content "$rule14_d2_mutant_content" 14)

for rule14_d2_phrase in "$RULE14_INJECTED_PATH_PHRASE" "$RULE14_PER_FILE_CAP_PHRASE" "$RULE14_OTHER_SESSIONS_PHRASE"; do
  if printf '%s' "$rule14_d2_mutant_body" | grep -qF -- "$rule14_d2_phrase"; then
    rule14_d2_still_has=yes
  else
    rule14_d2_still_has=no
  fi
  assert_eq "no" "$rule14_d2_still_has" "FAILURE PROOF (D2): deleting rule 14's opening paragraph from an in-memory mutant must remove '$rule14_d2_phrase' from its body, proving that pin is not matching some other line of the rule"
done

# Independence: the same mutant must leave rule 14's OTHER pinned
# sentences (assertion 32's failure report, AD3's slot placement)
# untouched - all three live in separate paragraphs, and a rewrite that
# fused them into one would make every pin above rise and fall together
# without any of them measuring anything on its own.
assert_contains "$rule14_d2_mutant_body" "$RULE14_FAILURE_PHRASE" "FAILURE PROOF (D2, independence): deleting rule 14's opening paragraph must leave the SEPARATE failure-report sentence in place"
assert_contains "$rule14_d2_mutant_body" "$RULE14_SLOT_PHRASE" "FAILURE PROOF (D2, independence): deleting rule 14's opening paragraph must leave the SEPARATE slot-placement sentence in place"

# FAILURE PROOF (D2, negative pin): re-appending the retired path shape
# to an in-memory mutant of the real rule-14 body must be detected by
# the same grep -qF check assert_not_contains uses, proving that guard
# would actually catch a reintroduction rather than never firing.
rule14_d2_reintro_body="$rule_14_body
update $RULE14_RETIRED_PATH_SHAPE with the new Doing and Next state"
if printf '%s' "$rule14_d2_reintro_body" | grep -qF -- "$RULE14_RETIRED_PATH_SHAPE"; then
  rule14_d2_reintro_found=yes
else
  rule14_d2_reintro_found=no
fi
assert_eq "yes" "$rule14_d2_reintro_found" "FAILURE PROOF (D2, negative pin): re-appending the retired flat path shape to an in-memory mutant must be detected, proving the assert_not_contains guard above is not vacuous"

# --- 35. Rule 14 defines the shape of the file it mandates -------------
#
# Rule 14 required updating "the new Doing and Next state" and appending
# to "the Done log" while nothing anywhere said what that file looks
# like. A live probe on a completed unit of work produced a 130-byte
# checkpoint under an invented title with "## Doing" left COMPLETELY
# EMPTY - Next and Done filled, and the one section /squirrel:pickup
# reads as this session's state blank. Across sessions that yields files
# with no shared shape for pickup to fold. Fixed by naming the four
# sections and their order in rule 14's body, and pinned on both sides
# (canonical + PLAN.md's own item 14) the same cross-file way rules 6,
# 10, 15 and 16 already are.
#
# The three needles are deliberately substrings common to BOTH files'
# wording rather than either file's full sentence, so the pin measures
# the agreement (invariant 6e) instead of one file's phrasing.
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# backtick-quoted section names searched for in the rules' own markdown,
# not command substitution.
RULE14_SHAPE_ORDER_PHRASE='`Doing` (one line), `Next` (the single startable step), `Open decisions` (only when there are any), `Done` (the finished items)'
RULE14_SHAPE_NONEMPTY_PHRASE="a heading with nothing under it"

assert_contains "$rule_14_body" "$RULE14_SHAPE_ORDER_PHRASE" "rule 14's canonical body must name the checkpoint's four sections in order, with Open decisions marked conditional and Done last - without it the rule mandates a file whose shape is left to each session to invent"
assert_contains "$rule_14_body" "$RULE14_SHAPE_NONEMPTY_PHRASE" "rule 14's canonical body must forbid a section heading with nothing under it - the empty '## Doing' is the exact failure observed live"
assert_contains "$plan_rule_14_flat" "$RULE14_SHAPE_ORDER_PHRASE" "PLAN.md's rule-14 summary must name the same four sections in the same order as rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_14_flat" "$RULE14_SHAPE_NONEMPTY_PHRASE" "PLAN.md's rule-14 summary must carry the same no-empty-heading requirement as rules/base-rules.md (cross-file agreement, invariant 6e)"

# The order pinned above must also be the order PLAN.md's own worked
# checkpoint template writes further down the file (Section 3's
# "### Checkpoints and /squirrel:pickup" fenced block). That template
# predates rule 14 carrying any shape at all, and is the concrete
# artifact a reader copies; the two disagreeing is the same invariant-6e
# drift as a rule summary going stale, one file further out.
plan_checkpoint_template=$(awk '
  /^### Checkpoints and/ { in_section = 1 }
  in_section && /^```markdown$/ { grab = 1; next }
  grab && /^```$/ { exit }
  grab { print }
' "$plan_file")
plan_template_heading_order=$(printf '%s\n' "$plan_checkpoint_template" | sed -n 's/^## //p' | tr '\n' ' ' | sed 's/ *$//')
assert_eq "Doing Next Open decisions Done" "$plan_template_heading_order" "PLAN.md's worked checkpoint template must use the same section order rule 14 now mandates"

# --- 36. Rule 14 names the tools its auto-approval actually covers -----
#
# hooks/hooks.json's PreToolUse matcher is "Write|Edit|Read" - letters
# and pipes, which Claude Code reads as an exact-string LIST, not a
# substring regex - so no hook OF THIS PLUGIN'S runs on a `Bash` call at
# any path, and none of them can auto-approve one. ADR-0002 records that
# as a decision and not as a limit: a PreToolUse hook may match `Bash`
# and may answer permissionDecision "allow", and that ADR says in as many
# words why squirrel-mode declines to register one. Rule 14 said only "update this
# session's own checkpoint file", and docs/ACCEPTANCE.md records from a
# live run that with tool-agnostic wording "the model reaches for a
# `Bash` heredoc first" - so the rule's own "do not ask permission
# first" promise silently failed whenever it did. skills/pickup already
# names `Read` for the read side; rule 14 now names both for the write
# side. Rule 14 is `targets: claude-code`, so naming a Claude Code tool
# in it is legitimate in a way it would not be in a rule that also ships
# to Codex and Cursor.
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# backtick-quoted tool names searched for in the rule's own markdown, not
# command substitution.
RULE14_TOOLS_PHRASE='`Read` and `Write` tools'
RULE14_NO_SHELL_PHRASE="never a shell command"

assert_contains "$rule_14_body" "$RULE14_TOOLS_PHRASE" "rule 14's canonical body must name the Read and Write tools - the PreToolUse auto-approval covers exactly those, and a tool-agnostic rule sends the model to a Bash heredoc that always prompts"
assert_contains "$rule_14_body" "$RULE14_NO_SHELL_PHRASE" "rule 14's canonical body must rule out a shell command for the checkpoint write, since this plugin registers no hook that runs on one"
assert_contains "$plan_rule_14_flat" "$RULE14_TOOLS_PHRASE" "PLAN.md's rule-14 summary must name the same two tools as rules/base-rules.md (cross-file agreement, invariant 6e)"
assert_contains "$plan_rule_14_flat" "$RULE14_NO_SHELL_PHRASE" "PLAN.md's rule-14 summary must rule out a shell command the same way rules/base-rules.md does (cross-file agreement, invariant 6e)"

# FAILURE PROOF (36): deleting the tool-naming sentence from an in-memory
# mutant must remove both phrases from rule 14's body while leaving the
# shape paragraph - pinned just above - untouched, so the two paragraphs'
# pins cannot rise and fall together.
rule14_tools_mutant_content=$(grep -v -F "Use the \`Read\` and \`Write\` tools on this file" "$base_rules_file")
rule14_tools_mutant_body=$(extract_rule_body_from_content "$rule14_tools_mutant_content" 14)

for rule14_tools_phrase in "$RULE14_TOOLS_PHRASE" "$RULE14_NO_SHELL_PHRASE"; do
  if printf '%s' "$rule14_tools_mutant_body" | grep -qF -- "$rule14_tools_phrase"; then
    rule14_tools_still_has=yes
  else
    rule14_tools_still_has=no
  fi
  assert_eq "no" "$rule14_tools_still_has" "FAILURE PROOF (36): deleting rule 14's tool-naming sentence from an in-memory mutant must remove '$rule14_tools_phrase' from its body, proving that pin is not matching some other line of the rule"
done

assert_contains "$rule14_tools_mutant_body" "$RULE14_SHAPE_ORDER_PHRASE" "FAILURE PROOF (36, independence): deleting rule 14's tool-naming sentence must leave the SEPARATE checkpoint-shape paragraph in place"

# FAILURE PROOF (35): delete the shape paragraph from an in-memory mutant
# of the real file and confirm all three phrases disappear from rule 14's
# body, while the rule's OTHER pinned sentences (D2's opening paragraph,
# assertion 32's failure report, AD3's slot placement) stay put - so a
# rewrite that fused the shape into an existing paragraph could not make
# every rule-14 pin rise and fall together.
rule14_shape_mutant_content=$(grep -v -F "Give the file these \`##\` sections" "$base_rules_file")
rule14_shape_mutant_body=$(extract_rule_body_from_content "$rule14_shape_mutant_content" 14)

for rule14_shape_phrase in "$RULE14_SHAPE_ORDER_PHRASE" "$RULE14_SHAPE_NONEMPTY_PHRASE"; do
  if printf '%s' "$rule14_shape_mutant_body" | grep -qF -- "$rule14_shape_phrase"; then
    rule14_shape_still_has=yes
  else
    rule14_shape_still_has=no
  fi
  assert_eq "no" "$rule14_shape_still_has" "FAILURE PROOF (35): deleting rule 14's shape paragraph from an in-memory mutant must remove '$rule14_shape_phrase' from its body, proving that pin is not matching some other line of the rule"
done

assert_contains "$rule14_shape_mutant_body" "$RULE14_INJECTED_PATH_PHRASE" "FAILURE PROOF (35, independence): deleting rule 14's shape paragraph must leave the SEPARATE injected-path sentence in place"
assert_contains "$rule14_shape_mutant_body" "$RULE14_FAILURE_PHRASE" "FAILURE PROOF (35, independence): deleting rule 14's shape paragraph must leave the SEPARATE failure-report sentence in place"
assert_contains "$rule14_shape_mutant_body" "$RULE14_SLOT_PHRASE" "FAILURE PROOF (35, independence): deleting rule 14's shape paragraph must leave the SEPARATE slot-placement sentence in place"

assert_report
