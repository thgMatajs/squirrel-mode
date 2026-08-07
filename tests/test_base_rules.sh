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
# progress_recap) now carries the ordering statement; rule 1
# cross-references it by number instead of repeating it. This pins both
# halves of that split: rule 1 must point at rule 8 and must not
# reimport rule 8's ordering phrase, and rule 8 must still carry it.
rule_1_body=$(get_rule_body_prose 1)
rule_8_body=$(get_rule_body_prose 8)
assert_contains "$rule_1_body" "rule 8" "rule 1 must cross-reference rule 8 by number for the recap-ordering interaction, instead of restating it"
assert_not_contains "$rule_1_body" "on the next line" "rule 1 must not duplicate rule 8's ordering phrasing (the interaction is stated once, in rule 8)"
assert_contains "$rule_8_body" "on the next line" "rule 8 must still state the recap-then-answer ordering explicitly (it is the single owner of this interaction)"

assert_report
