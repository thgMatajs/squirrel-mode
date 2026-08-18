#!/bin/sh
# build.sh - generates every squirrel-mode artifact from rules/base-rules.md
# and from the five ported command skills under skills/.
#
# rules/base-rules.md is the ONLY place the 16 base rules exist (see
# .build-checkpoint.md invariant 1). This script parses it and writes:
#   - output-styles/squirrel-mode.md   (all 16 rules, targets: claude-code)
#   - skills/rules/SKILL.md            (all 16 rules, targets: claude-code)
#   - targets/codex/AGENTS.md          (15 rules, targets: codex)
#   - targets/cursor/squirrel-mode.mdc (15 rules, targets: cursor)
#
# It additionally ports four of the seven Claude Code command skills to
# Codex, and five of those seven to Cursor, per PLAN.md's "Which commands
# port" table (ADR-0004). Each ported artifact is generated from ONE
# source, the corresponding skills/<name>/SKILL.md - never hand-copied:
#   - targets/codex/skills/digest/SKILL.md   <- skills/digest/SKILL.md
#   - targets/codex/skills/plan/SKILL.md     <- skills/plan/SKILL.md
#   - targets/codex/skills/init/SKILL.md     <- skills/init/SKILL.md
#   - targets/codex/skills/tune/SKILL.md     <- skills/tune/SKILL.md
#   - targets/cursor/commands/digest.md      <- skills/digest/SKILL.md
#   - targets/cursor/commands/plan.md        <- skills/plan/SKILL.md
#   - targets/cursor/skills/squirrel-digest/SKILL.md <- skills/digest/SKILL.md
#   - targets/cursor/skills/squirrel-plan/SKILL.md   <- skills/plan/SKILL.md
#   - targets/cursor/skills/squirrel-init/SKILL.md   <- skills/init/SKILL.md
#   - targets/cursor/skills/squirrel-tune/SKILL.md   <- skills/tune/SKILL.md
#   - targets/cursor/skills/squirrel-pickup/SKILL.md <- skills/pickup/SKILL.md
# pickup ports to Cursor as an Agent Skill only (sessionStart injects the
# checkpoint path; Cursor now has that hook). Codex does not get pickup.
# off and on are deliberately NOT ported to either target yet: each
# depends on a lifecycle hook (UserPromptSubmit's sentinel-claiming)
# neither host has a complete equivalent for, and there is no
# host-appropriate way to fake that.
#
# Cursor gets digest and plan TWICE, in two different mechanisms, because
# Cursor has two and they are not interchangeable:
#   - targets/cursor/commands/<name>.md - a PROJECT-scoped Cursor command
#     (.cursor/commands/), copied by hand into each project that wants it;
#   - targets/cursor/skills/squirrel-<name>/SKILL.md - a Cursor Agent
#     Skill, auto-discovered from ~/.cursor/skills/ for EVERY project on
#     the machine, which is what targets/cursor/install.sh installs.
# Cursor init, tune, and pickup are Agent Skills only - never project
# commands - so the machine-wide plugin covers calibration and resume.
# The skill folder names
# carry a "squirrel-" prefix because Cursor has no command namespace
# (Claude Code's "/squirrel:" has no equivalent), so a
# bare "digest" would collide with a skill of the user's own; Cursor
# requires the frontmatter `name` to match its parent folder exactly, so
# the two are generated together and can never drift apart.
#
# THE PARSER CONTRACT: a rule body runs from immediately after its
# "<!-- targets: ... -->" marker line to the next "### <n>." heading, or
# end of file. It is NOT terminated by a blank line - 8 of the 16 rule
# bodies span multiple paragraphs, and a "stop at the first blank line"
# parser would silently amputate them. get_rule_body() below delimits a
# body only by the next numbered heading, never by whitespace.
#
# Accepts no arguments. Resolves the repo root from this script's own
# location, so it produces identical output regardless of the caller's
# working directory. Idempotent: given the same rules/base-rules.md and
# skills/*/SKILL.md, two runs produce byte-identical artifacts (no
# timestamps, no counters, no other non-deterministic content).
#
# Fails loudly (non-zero exit, message on stderr, no partial writes) if
# rules/base-rules.md is missing, does not contain exactly 16 rule
# headings numbered 1..16 with no gaps or duplicates, if any heading is
# not followed by exactly one targets marker, or if any targets value is
# not "all" or a comma-separated subset of claude-code/codex/cursor; if a
# `targets: all` rule names a non-`all` rule by number in its own body
# (S10 review cycle 2, AC2 - a targets:all rule ships verbatim into every
# target's generated artifact, so a numbered reference to a rule absent
# from one of them would be a dangling citation there); or if any of
# skills/{digest,plan,init,tune}/SKILL.md is missing or lacks a
# well-formed single-line double-quoted frontmatter "description" field.
# All validation happens before any output file is written, so malformed
# input can never produce a half-empty generated artifact.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line before this script
# ever gets to resolve its own repo root. Unset unconditionally, before
# that `cd` runs, rather than trust the invoking shell's environment.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

base_rules_file="$repo_root/rules/base-rules.md"

fail() {
  echo "build.sh: ERROR: $1" >&2
  exit 1
}

[ -f "$base_rules_file" ] || fail "rules/base-rules.md not found at $base_rules_file"

# CRLF detection: every regex below that matches a "blank line"
# (/^[ \t]*$/) or a marker's closing "-->" at end-of-line anchors on
# end-of-string. A trailing \r (Windows CRLF) is neither whitespace nor
# part of "-->", so it defeats both anchors: a blank line that is really
# just "\r" stops looking blank (the zone-closing logic below treats it
# as real content and closes the marker zone one line early) and a
# marker line's "-->\r" stops looking like a properly closed marker. The
# downstream symptom is a heading marker that appears to be missing
# entirely ("found 0"), which misattributes the failure to a missing
# marker instead of to line endings. Detect CRLF explicitly, up front,
# so the real cause is reported instead of that confusing symptom.
if grep -q "$(printf '\r')" "$base_rules_file"; then
  fail "rules/base-rules.md has CRLF (Windows) line endings - a carriage return byte was found. This breaks the blank-line and marker-closing regexes below, which anchor on end-of-line. Convert the file to LF-only (Unix) line endings and re-run."
fi

# --- Parse heading records: "<num> <marker_count> <targets> <first_indented>"
# per line -
#
# For every "### <n>. <title>" heading, walk forward skipping blank
# lines and count how many consecutive "<!-- targets: ... -->" marker
# lines appear before the first real body line. Marker recognition
# tolerates leading whitespace (`[ \t]*`), matching the blank-line
# check's own tolerance immediately above it in the awk source below -
# this is what lets a heading with TWO marker-shaped lines (say, one
# flush-left and one accidentally indented, back to back) be counted as
# 2 and rejected below as a duplicate, instead of the indented one
# silently failing to register at all. <targets> is the
# whitespace-stripped value of the FIRST marker seen; it is empty when
# marker_count is 0. <first_indented> is 1 when that first marker itself
# had leading whitespace, 0 otherwise - the validation loop below uses
# it to reject an indented marker explicitly, by name, rather than only
# via a generic "found 0" (see that loop for why "found 0" alone is
# misleading here).
heading_records=$(awk '
  /^### [0-9]+\. / {
    if (pending) print cur_num, marker_count, cur_targets, cur_first_indented
    line = $0
    sub(/^### /, "", line)
    split(line, parts, ".")
    cur_num = parts[1]
    pending = 1
    marker_count = 0
    cur_targets = ""
    cur_first_indented = 0
    in_zone = 1
    next
  }
  pending && in_zone {
    if ($0 ~ /^[ \t]*$/) { next }
    if ($0 ~ /^[ \t]*<!-- targets:/) {
      marker_count++
      if (marker_count == 1) {
        if ($0 ~ /^[ \t]+<!-- targets:/) { cur_first_indented = 1 }
        t = $0
        sub(/^[ \t]*<!-- targets:[ \t]*/, "", t)
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
    if (pending) print cur_num, marker_count, cur_targets, cur_first_indented
  }
' "$base_rules_file")

heading_count=$(printf '%s\n' "$heading_records" | grep -c '.' || true)
[ "$heading_count" -eq 16 ] || fail "expected exactly 16 rule headings in rules/base-rules.md, found $heading_count"

expected_seq="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16"
actual_seq=$(printf '%s\n' "$heading_records" | awk '{ printf "%s ", $1 }' | sed 's/ *$//')
[ "$actual_seq" = "$expected_seq" ] || fail "rule headings must be numbered 1..16 in order with no gaps or duplicates (found: $actual_seq)"

# validate_targets_value <value>: exit 0 if "all" or a comma-separated
# subset of {claude-code, codex, cursor}; exit 1 otherwise.
validate_targets_value() {
  value=$1
  case "$value" in
    all)
      return 0
      ;;
    "")
      return 1
      ;;
  esac
  # A leading or a doubled comma implies an empty token (",claude-code"
  # or "a,,b") and is already caught below, token by token: an empty
  # token never matches the claude-code/codex/cursor allowlist. A
  # TRAILING comma is different - it leaves "remaining" empty right
  # after the last real token is consumed, so the while loop below would
  # exit before ever inspecting the implicit empty final token. Reject
  # it explicitly, up front, instead of letting the loop silently miss it.
  case "$value" in
    *,) return 1 ;;
  esac
  seen=""
  remaining="$value"
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
      # "all" is deliberately NOT in this per-token allowlist: "all"
      # combined with a specific target (e.g. "all,claude-code") is
      # contradictory - "all" already means every target, so naming one
      # specific target alongside it adds nothing and only invites the
      # reader to wonder whether it means something narrower than "all"
      # after all. Rejecting the combination (rather than normalising
      # away the redundant token) keeps "all" meaning exactly one thing
      # everywhere in this file: the bare, exact value, never one item
      # in a list.
      *) return 1 ;;
    esac
    # Reject a duplicated token (e.g. "claude-code,claude-code"). This
    # has no effect on the generated output either way -
    # print_rules_section only ever tests set membership, never counts
    # occurrences - but this script's contract (see the file header) is
    # to fail loudly on malformed input, and "a comma-separated subset"
    # names a SET, which by definition has no duplicate members. A
    # repeated token is never anything other than a mistake.
    case " $seen " in
      *" $token "*) return 1 ;;
    esac
    seen="$seen $token"
  done
  return 0
}

# Every heading must carry EXACTLY one targets marker, at column 1 (no
# leading whitespace), and its value must validate. Runs to completion
# for every heading (not just the first bad one) is unnecessary here -
# failing on the first problem found is enough to satisfy "fail loudly
# and exit non-zero", and gives a precise, single-cause error message.
#
# The indentation check below is deliberately separate from, and after,
# the count check: an indented LONE marker counts as 1 in the awk above
# (indentation is tolerated for COUNTING, precisely so a duplicate is
# still detected as a duplicate), so it passes "exactly one" and needs
# its own, accurately-worded rejection here. The alternative - making
# the count regex strict again so an indented marker shows up as "found
# 0" - is exactly the misleading message the reviewer flagged: a marker
# plainly is there, just indented, and "found 0" denies that. Rejecting
# the indented form outright (rather than accepting it as a second
# valid spelling) keeps the contract simple: "<!-- targets: ... -->" has
# exactly one valid shape, flush-left, immediately after the heading
# (blank lines before it are fine); anything else - stray, duplicated,
# or merely indented - is a defect to fix in rules/base-rules.md, not a
# second form for build.sh to special-case and carry forward forever.
while read -r num mcount tgt first_indented; do
  [ -n "$num" ] || continue
  if [ "$mcount" != "1" ]; then
    fail "rule $num must be followed by exactly one <!-- targets: ... --> marker (found $mcount)"
  fi
  if [ "$first_indented" = "1" ]; then
    fail "rule $num's <!-- targets: ... --> marker has leading whitespace - it must start at column 1, immediately after the heading (blank lines before it are fine; spaces or tabs before '<!--' are not). Remove the indentation and re-run."
  fi
  if ! validate_targets_value "$tgt"; then
    fail "rule $num has an unknown targets value: '$tgt' (must be 'all' or a comma-separated subset of claude-code, codex, cursor)"
  fi
done <<RECORDS
$heading_records
RECORDS

# --- Detect marker-shaped lines outside the marker zone -------------------
#
# "<!-- targets: ... -->" syntax is only meaningful in the marker zone
# immediately after a heading (blank lines allowed, ending at the first
# real content line) - the same zone the heading-record parser above
# recognizes. A line matching that shape ANYWHERE ELSE in a rule's body
# is always a defect: either a stray/duplicate marker the author meant
# to delete, or an attempt to show the marker syntax as prose without
# using the inline-code convention rule 3 already establishes for other
# text that looks like markup ("- [ ]", "1."). Neither silently
# stripping it (the previous bug: it vanished from every artifact with
# no trace) nor silently keeping it (it would ship a raw, confusing HTML
# comment into every artifact carrying that rule) is acceptable here.
# Failing loudly is consistent with this script's existing "fail on the
# first problem found" contract for the heading marker itself, and it
# forces the author to either delete the stray line or re-express it
# with backticks if it is meant as prose.
#
# Both the in-zone recognition below and the stray-detection pattern
# tolerate leading whitespace (`^[ \t]*<!-- targets:`), matching the
# blank-line check's own tolerance right above it. Without this, a
# marker-shaped line indented by even one space or tab defeated the
# `^<!-- targets:` anchor on BOTH ends: it read as neither "the marker"
# (so it could not close the zone the way ordinary body text does) nor
# as "a stray marker" (so it was never reported) - it simply vanished
# from consideration here, and get_rule_body() below (before ITS OWN fix)
# would print it verbatim into the body with no error at all. That was
# the second MAJOR this file was reviewed for: leading whitespace was a
# silent bypass of this whole check, not a formatting nuisance.
#
# A second marker-shaped line immediately adjacent to a real one (still
# inside the zone, before any real content) is deliberately NOT reported
# here even after this fix, regardless of its own indentation: that is a
# duplicate marker, not a stray one, and the heading-record parser's own
# marker_count above already rejects duplicates with a precise "found N"
# message. Reporting it a second time here, under a different name for
# the same underlying defect, would only be confusing. This function's
# job stays narrower: catch a marker-shaped line once real body content
# has already started, which an adjacent duplicate, by definition, has
# not.
#
# Backtick-quoted prose that merely shows this syntax as an example
# (e.g. a sentence containing the four characters `, <, !, -- as text)
# is unaffected by either regex: both anchor on `^[ \t]*`, so a
# marker-shaped comment preceded by anything other than spaces/tabs - a
# backtick, a word, anything - never matches, indented or not. Likewise
# an unrelated HTML comment (one that does not contain the literal text
# "targets:") never matches either regex regardless of this fix.
stray_marker_records=$(awk '
  /^### [0-9]+\. / {
    line = $0
    sub(/^### /, "", line)
    split(line, parts, ".")
    cur_num = parts[1]
    pending = 1
    in_zone = 1
    next
  }
  pending && in_zone {
    if ($0 ~ /^[ \t]*$/) { next }
    if ($0 ~ /^[ \t]*<!-- targets:/) { next }
    in_zone = 0
  }
  pending && !in_zone && /^[ \t]*<!-- targets:/ {
    print cur_num ":" NR ":" $0
  }
' "$base_rules_file")

if [ -n "$stray_marker_records" ]; then
  first_stray=$(printf '%s\n' "$stray_marker_records" | head -n 1)
  stray_rule=${first_stray%%:*}
  fail "rule $stray_rule contains a '<!-- targets: ... -->'-shaped line outside its marker zone (rule:line:text = $first_stray). Delete it, move it directly after the heading, or use inline code (backticks) if it is meant as prose about the marker syntax."
fi

# --- Availability and validation of the five ported command sources ------
#
# skills/<name>/SKILL.md is committed and present for all five ported
# commands (digest, plan, init, tune, pickup) in this repository. A MISSING
# source file is now a LOUD, WHOLE-BUILD FAILURE, exactly like a
# malformed rules/base-rules.md above - never a silent skip of that one
# artifact. An earlier version of this script tolerated absence (to let
# a stripped-down scratch fixture holding only scripts/build.sh and
# rules/base-rules.md still build the four rules-derived artifacts),
# but that "skip if absent" escape hatch is exactly what let a deleted
# skills/plan/SKILL.md ship a STALE targets/cursor/commands/plan.md
# with build.sh exiting 0 - and the CI drift check could never catch
# it, because regenerating with the same skipped source reproduces the
# same stale artifact. The fixture problem is fixed in the fixture, not
# here: tests/test_build.sh's make_build_scratch() now copies the five
# real skills/{digest,plan,init,tune,pickup}/SKILL.md into its scratch tree
# too, so it no longer needs this script to tolerate their absence.
validate_source_skill() {
  name=$1
  file="$repo_root/skills/$name/SKILL.md"
  [ -f "$file" ] || fail "skills/$name/SKILL.md not found at $file - this is one of the ported command skills (digest, plan, init, tune, pickup); a missing source is a build failure, never a silently skipped artifact."
  delim_count=$(awk '/^---$/ { c++ } END { print c + 0 }' "$file")
  [ "$delim_count" -eq 2 ] || fail "skills/$name/SKILL.md must have exactly 2 '---' frontmatter delimiter lines (found $delim_count)"
  desc_line=$(awk '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && /^description: "/ { print; exit }
  ' "$file")
  [ -n "$desc_line" ] || fail "skills/$name/SKILL.md's frontmatter 'description' field could not be found (expected a single double-quoted line starting 'description: \"')"
}

for ported_name in digest plan init tune pickup; do
  validate_source_skill "$ported_name"
done

# --- Backslash guard: awk -v escape-processes backslashes ----------------
#
# literal_replace, delete_exact_line, insert_paragraph_after, and
# add_title_suffix (defined further below) all pass strings through
# `awk -v name=value`, where the awk implementation itself, not this
# script, silently turns "\n", "\t", "\\", etc. inside that value into
# their escape-sequence meaning before the awk program ever sees the
# literal text. No source text in skills/{digest,plan,init,tune,pickup}/SKILL.md
# contains a backslash today, so this is LATENT, not yet triggered - but
# it can never be caught by the drift check, because the corruption
# would be a deterministic function of the source: both the committed
# artifact and a fresh regeneration from a backslash-containing source
# would be identically, silently wrong, and "identical to a fresh
# regeneration" is the only thing the drift check can ever verify. The
# fix chosen here is to turn that silent future corruption into a loud
# failure now, not to make awk -v backslash-safe (which would mean
# reworking every one of those four transformation functions to route
# values through a mechanism other than awk -v, a larger change than
# this guard).
check_no_backslash_in_source_skills() {
  hit=""
  for name in digest plan init tune pickup; do
    file="$repo_root/skills/$name/SKILL.md"
    # shellcheck disable=SC1003 # this single quote correctly contains
    # one literal backslash character - the pattern grep -F is meant to
    # search for - not an attempt to escape the closing quote.
    if grep -qF '\' "$file"; then
      hit="$hit skills/$name/SKILL.md"
    fi
  done
  if [ -n "$hit" ]; then
    fail "the following source skill file(s) contain a literal backslash: $hit. Every ported-artifact transformation in this script (literal_replace, delete_exact_line, insert_paragraph_after, add_title_suffix) passes text through 'awk -v', which escape-processes backslash sequences (turning a literal backslash followed by n, t, or another backslash into a newline, a tab, or a single backslash) before the awk program ever sees the literal text - a backslash in the source would be silently corrupted in every ported Codex/Cursor artifact, with no way for the drift check to detect it (the corruption is a deterministic function of the source, so a fresh regeneration would be identically wrong). Remove the backslash from the source, or rework those four functions to avoid 'awk -v' first."
  fi
}
check_no_backslash_in_source_skills

# --- Accessors -----------------------------------------------------------

# targets_for <n>: prints the validated targets value for rule <n>.
targets_for() {
  rule_num=$1
  printf '%s\n' "$heading_records" | awk -v n="$rule_num" '$1 == n { print $3; exit }'
}

# get_rule_heading <n>: prints the literal "### <n>. <title>" line.
get_rule_heading() {
  rule_num=$1
  awk -v want="$rule_num" '$0 ~ ("^### " want "\\. ") { print; exit }' "$base_rules_file"
}

# get_rule_body <n>: prints rule <n>'s body, delimited by the next
# numbered heading (or EOF), never by a blank line - see the parser
# contract note at the top of this file. The targets marker line(s) are
# stripped; runs of blank lines are collapsed to exactly one, and
# leading/trailing blank lines are dropped. Internal blank lines
# (paragraph breaks) are preserved, which is what keeps a multi-
# paragraph body from being flattened into one.
get_rule_body() {
  rule_num=$1
  # The marker strip below is scoped to "in_zone" - the exact same zone
  # (blank lines allowed, ends at the first real content line) the
  # heading-record parser and the stray-marker check above both use -
  # not to "any line starting with <!-- targets: anywhere in the body".
  # A marker-shaped line outside that zone already fails the build
  # loudly, above, before this function ever runs; this scoping is
  # belt-and-suspenders so this function's OWN filter cannot silently
  # eat a body line either, independent of that earlier check.
  #
  # The marker-line match below tolerates leading whitespace
  # (`^[ \t]*<!-- targets:`), the same as the heading-record parser and
  # the stray-marker check above. By the time this function runs, a
  # heading marker with leading whitespace has already failed the build
  # loudly (see the validation loop's first_indented check), and a
  # mid-body stray one - indented or not - has already failed it too
  # (see stray_marker_records above), so in practice this line only ever
  # strips an already-validated, flush-left marker. The tolerance is
  # kept here anyway for the same "belt-and-suspenders" reason the
  # comment above gives: if this function's own notion of "zone" ever
  # drifted out of sync with the other two checks' notion of it, an
  # indented marker that they let through would otherwise print verbatim
  # into the body with no error - exactly the class of bug this whole
  # file was reviewed for.
  awk -v want="$rule_num" '
    $0 ~ ("^### " want "\\. ") { in_rule = 1; in_zone = 1; next }
    in_rule && /^### [0-9]+\. / { in_rule = 0 }
    in_rule && in_zone && /^[ \t]*$/ { print; next }
    in_rule && in_zone && /^[ \t]*<!-- targets:/ { next }
    in_rule && in_zone { in_zone = 0 }
    in_rule { print }
  ' "$base_rules_file" | awk '
    BEGIN { started = 0; blank_run = 0 }
    /^[ \t]*$/ { if (started) blank_run++; next }
    {
      if (started && blank_run > 0) print ""
      print $0
      started = 1
      blank_run = 0
    }
  '
}

# print_defaults_section: prints the "## Defaults" heading through its
# table, trimmed of trailing blank lines, verbatim from base-rules.md.
print_defaults_section() {
  awk '
    /^## Defaults$/ { capture = 1; print; next }
    /^## Rules$/ { capture = 0 }
    capture { print }
  ' "$base_rules_file" | awk '
    { lines[++n] = $0; if ($0 !~ /^[ \t]*$/) last_nonblank = n }
    END { for (i = 1; i <= last_nonblank; i++) print lines[i] }
  '
}

# print_rules_section <target>: prints every rule (heading + body,
# original numbering preserved, rules that do not apply simply omitted)
# whose targets marker is "all" or includes <target>.
print_rules_section() {
  filter=$1
  first=1
  for num in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    tgt=$(targets_for "$num")
    include=no
    if [ "$tgt" = "all" ]; then
      include=yes
    else
      case ",$tgt," in
        *",$filter,"*) include=yes ;;
      esac
    fi
    if [ "$include" = "yes" ]; then
      if [ "$first" = "0" ]; then
        printf '\n'
      fi
      first=0
      get_rule_heading "$num"
      printf '\n'
      get_rule_body "$num"
    fi
  done
}

# --- Cross-target-reference guard (S10 review cycle 2, AC2) --------------
#
# A `targets: all` rule ships, verbatim, into EVERY generated artifact -
# including targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc,
# both filtered purely by each rule's own targets value in
# print_rules_section above, with no rewriting of what a rule's prose
# happens to say. A `targets: all` rule that names a non-`all` rule BY
# NUMBER (today: rule 14, `targets: claude-code`) therefore ships a
# definitive, numbered cross-reference into a document where the cited
# rule is entirely absent - a Codex or Cursor user reads "...then rule
# 14's ... report..." with no rule 14 anywhere in the file they are
# reading. AB2 found this for rules 2 and 7 citing rule 14 specifically
# and fixed those two instances (AD3, S10 cycle 3 final gate, narrowed
# this further: rules 2 and 7 no longer describe the report's content at
# all, generic or otherwise - see rule 14's own body, which is the only
# place that concept is stated now); this check closes the CLASS, so a
# future rule cannot reintroduce the same defect under a different
# number.
#
# A reference SPAN is "rule(s) <N>" optionally continued by one or more
# of ", " / "-" / " through " / " to " / " and " (each optionally
# followed by another "rule ") plus another <N> - this is what lets
# compound expressions like "rules 1 through 12 and rule 16" or "Rules 2
# and 14" be recognised as ONE reference naming several rule numbers, not
# merely the first number after "rule(s)". Case-insensitive, matching
# both "Rule" (sentence-initial) and "rule" elsewhere in this file's
# prose.
#
# FIXED MAJOR (cycle 3, AD2): the digit extraction below used to grab
# every literal digit token inside a matched span and stop there - which
# finds the two ENDPOINTS of a range expression ("rules 1 through 12")
# but never the numbers STRICTLY BETWEEN them, because "1 through 12"
# contains exactly two digit tokens in its own text ("1" and "12") no
# matter how many rules the range actually spans. Proven: rule 13's
# shipped "This rule takes precedence over rules 1 through 12 and rule
# 16" was checked only for 1, 12, and 16 - flipping any of rules 2-11 to
# a non-`all` target left the build green. Fixed by additionally scanning
# each matched span for "A through B" / "A-B" / "A to B" range pairs and
# expanding every INTERMEDIATE integer (A's and B's own endpoints are
# already covered by the plain digit extraction, which is unchanged) -
# "1 through 12" now also checks 2, 3, ..., 11. The two lists are kept
# separate ($span_literal vs. the range-derived numbers) purely so the
# failure message below can say accurately whether rule $cited was named
# directly or only reached via a range - a rule reached only by
# expansion is never literally spelled out as a digit in the citing
# rule's own text, so a message claiming otherwise would itself become a
# false claim on exactly the path this fix adds.
check_no_all_rule_cites_non_all_rule() {
  citing_num=$1
  body=$2
  spans=$(printf '%s\n' "$body" | grep -oiE 'rules?[ ]+[0-9]+([ ]*(,|-|through|to|and)[ ]*(rule[ ]+)?[0-9]+)*') || true
  [ -n "$spans" ] || return 0

  literal_nums=""
  range_expanded_nums=""
  while IFS= read -r span; do
    [ -n "$span" ] || continue
    span_literal=$(printf '%s\n' "$span" | grep -oE '[0-9]+' | tr '\n' ' ')
    literal_nums="$literal_nums $span_literal"

    # Range pairs WITHIN this same span only - scoping to an
    # already-confirmed "rule(s) ..." span (rather than scanning the
    # whole rule body for any "N-M"-shaped text) is what keeps this from
    # false-positiving on an unrelated numeric range elsewhere in a
    # rule's prose (there is none in a rule BODY today - the Defaults
    # table's "3-7" for max_list_items lives outside every rule body and
    # is never passed to this function - but scoping to the span is the
    # correct invariant to hold regardless).
    range_pairs=$(printf '%s\n' "$span" | grep -oiE '[0-9]+[ ]*(-|through|to)[ ]*[0-9]+') || true
    if [ -n "$range_pairs" ]; then
      while IFS= read -r pair; do
        [ -n "$pair" ] || continue
        range_start=$(printf '%s\n' "$pair" | grep -oE '[0-9]+' | sed -n '1p')
        range_end=$(printf '%s\n' "$pair" | grep -oE '[0-9]+' | sed -n '2p')
        if [ -n "$range_start" ] && [ -n "$range_end" ] && [ "$range_start" -lt "$range_end" ]; then
          n=$((range_start + 1))
          while [ "$n" -lt "$range_end" ]; do
            range_expanded_nums="$range_expanded_nums $n"
            n=$((n + 1))
          done
        fi
      done <<RANGES
$range_pairs
RANGES
    fi
  done <<SPANS
$spans
SPANS

  for cited in $literal_nums $range_expanded_nums; do
    # A malformed body could in principle name a number outside 1..16
    # (e.g. inside prose unrelated to a rule reference that this pattern
    # still matched) - treat that as "not one of our rules" rather than
    # let targets_for be asked about a number it was never validated
    # against.
    case "$cited" in
      1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16) ;;
      *) continue ;;
    esac
    cited_tgt=$(targets_for "$cited")
    if [ "$cited_tgt" != "all" ]; then
      case " $literal_nums " in
        *" $cited "*) how="names rule $cited directly by number" ;;
        *) how="its own numeric range expression includes rule $cited, without ever spelling out $cited as a literal digit" ;;
      esac
      fail "rule $citing_num is marked 'targets: all' but $how in its own body, and rule $cited is marked 'targets: $cited_tgt', not 'all'. A targets:all rule ships verbatim into every generated artifact, including targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc - a reference to a rule absent from those artifacts, whether a direct citation or a range expression that spans it, leaves a dangling, definitive reference on every target that lacks rule $cited. Describe the referenced rule's content instead of naming or ranging over its number (as rule 14 now does for its own checkpoint-failure report, rather than rules 2 or 7 naming it), or change one rule's targets value so both sides agree."
    fi
  done
}

for cross_ref_num in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  cross_ref_tgt=$(targets_for "$cross_ref_num")
  if [ "$cross_ref_tgt" = "all" ]; then
    check_no_all_rule_cites_non_all_rule "$cross_ref_num" "$(get_rule_body "$cross_ref_num")"
  fi
done

# print_generated_banner: the GENERATED marker every artifact opens
# with (after any YAML frontmatter - a comment above "---" breaks
# frontmatter parsing).
print_generated_banner() {
  cat <<'BANNER'
<!-- GENERATED FILE. Source: rules/base-rules.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->
BANNER
}

# print_generated_banner_for <source_rel_path>: the same GENERATED
# marker, but naming a source other than rules/base-rules.md - used by
# the ported command artifacts below, whose source is
# skills/<name>/SKILL.md, not the canonical rules file. Uses an
# UNQUOTED heredoc (unlike print_generated_banner above) specifically
# so $source_rel is interpolated.
print_generated_banner_for() {
  source_rel=$1
  cat <<BANNER
<!-- GENERATED FILE. Source: $source_rel. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->
BANNER
}

# ===========================================================================
# Ported command artifacts: Codex skills (targets/codex/skills/<name>/),
# Cursor commands (targets/cursor/commands/<name>.md), and Cursor Agent
# Skills (targets/cursor/skills/squirrel-<name>/SKILL.md).
#
# A Claude Code skill cannot ship to Codex or Cursor byte-for-byte: it
# uses "$ARGUMENTS" (a Claude Code slash-command templating token
# neither host implements - the text is substituted by the Claude Code
# harness before the model ever sees it) and it refers to itself and
# its siblings by "/squirrel:<name>" invocation syntax that names a
# command namespace that does not exist on either host. Every such
# reference below is rewritten by an explicit, LITERAL (never regex)
# find-and-replace, each one sourced from and matched against the
# CURRENT text of the Claude Code skill - never hand-authored prose
# bolted onto the output afterwards.
#
# DRIFT GUARD: if a future edit to skills/<name>/SKILL.md changes or
# removes the exact sentence one of these replacements targets, that
# replacement silently becomes a no-op and the untouched Claude-only
# text would survive into the generated artifact. check_no_claude_only_syntax
# (defined below) is what catches that - but it is NOT called from
# ported_skill_description or ported_skill_body themselves. It is
# called exactly once per artifact, in the "Write every artifact"
# section near the bottom of this file, against each artifact's own
# FULLY COMPOSED text (frontmatter, the GENERATED banner, and the body,
# with add_title_suffix and - for Cursor - the skill-to-command word
# swap already applied) read back from its own temp file, immediately
# before that temp file is mv'd into place (G5/G6, S7 review cycle 3;
# this comment used to claim the scan already ran on that final text -
# it did not, which was itself a finding). The same call also covers
# targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc, the two
# base-rules-derived artifacts this check never reached before, so a
# future rules/base-rules.md edit mentioning "Claude", a hook name, or
# "$ARGUMENTS" fails the build instead of shipping unchecked to either
# non-Claude-Code host. It deliberately does NOT run against
# output-styles/squirrel-mode.md or skills/rules/SKILL.md - the two
# Claude Code artifacts, where "Claude" and "/squirrel:" are correct.
# Any edit to skills/digest|plan|init|tune|pickup/SKILL.md that changes one of
# the sentences named below must update the matching substitution here,
# or the build stops rather than emitting broken instructions.
# ===========================================================================

# The one Cursor Agent Skill frontmatter line that is NOT shared with any
# other target, written once here so write_cursor_skill (which emits it)
# and check_no_claude_only_syntax (which permits exactly this line, in
# exactly one place, and nothing else) can never disagree about what the
# permitted text is. See check_no_claude_only_syntax's own
# "disable-model-invocation ALLOWANCE" note for why the exception exists
# and how narrow it is.
CURSOR_SKILL_INVOCATION_LINE="disable-model-invocation: true"

# Cursor init/tune closing instruction after a successful Write of
# ~/.squirrel/profile.md. Cursor has no mid-session profile re-injection,
# so the current chat must not claim it will pick the new profile up.
# Held once so write_cursor_skill and the tests that pin this sentence
# cannot silently diverge if one is edited without the other - the
# tests copy the literal; this is the generator's copy.
CURSOR_PROFILE_NEW_CHAT_SENTENCE="Start a new chat for the profile to take effect; this chat will not pick it up."

source_skill_body() {
  # source_skill_body <name>: prints skills/<name>/SKILL.md's body -
  # every line after the frontmatter's closing "---" line, verbatim.
  name=$1
  awk '
    /^---$/ { c++; if (c == 2) { in_body = 1 }; next }
    in_body { print }
  ' "$repo_root/skills/$name/SKILL.md"
}

source_skill_description() {
  # source_skill_description <name>: prints the RAW value (surrounding
  # quotes stripped) of the frontmatter "description" field from
  # skills/<name>/SKILL.md. validate_source_skill_if_present has
  # already confirmed this field exists as a single double-quoted line
  # in the frontmatter block, above, before this is ever called - and
  # this is only ever called for a <name> whose have_<name>=yes.
  name=$1
  awk '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && /^description: "/ { print; exit }
  ' "$repo_root/skills/$name/SKILL.md" | sed -e 's/^description: "//' -e 's/"$//'
}

literal_replace() {
  # literal_replace <text> <old> <new>: replaces every literal
  # (non-regex) occurrence of <old> with <new>, scanning line by line.
  # Used instead of sed's s/// throughout this section because several
  # <old> patterns below contain characters (parentheses, a literal
  # "$") that sed would treat as regex metacharacters and require
  # per-pattern escaping to match literally; awk's index()/substr()
  # need no escaping at all, only exact text.
  text=$1
  old=$2
  new=$3
  printf '%s\n' "$text" | awk -v old="$old" -v new="$new" '
    {
      rest = $0
      result = ""
      oldlen = length(old)
      if (oldlen == 0) { print; next }
      while (1) {
        pos = index(rest, old)
        if (pos == 0) { result = result rest; break }
        result = result substr(rest, 1, pos - 1) new
        rest = substr(rest, pos + oldlen)
      }
      print result
    }
  '
}

delete_exact_line() {
  # delete_exact_line <text> <line>: removes every line equal to <line>
  # verbatim. Used to drop the Claude Code-only "Arguments: $ARGUMENTS"
  # declaration line, which has no host-neutral equivalent to rewrite
  # it INTO - it is pure Claude Code slash-command templating syntax,
  # not prose, so the correct transformation is deletion, not rewording.
  text=$1
  line=$2
  printf '%s\n' "$text" | awk -v t="$line" '$0 != t'
}

collapse_blank_runs() {
  # collapse_blank_runs <text>: the same normalisation get_rule_body()
  # already applies to rule bodies above - collapse any run of blank
  # lines to exactly one, and drop leading/trailing blank lines. Needed
  # here because delete_exact_line above can leave two adjacent blank
  # lines where the deleted line used to separate them.
  text=$1
  printf '%s\n' "$text" | awk '
    BEGIN { started = 0; blank_run = 0 }
    /^[ \t]*$/ { if (started) blank_run++; next }
    {
      if (started && blank_run > 0) print ""
      print $0
      started = 1
      blank_run = 0
    }
  '
}

insert_paragraph_after() {
  # insert_paragraph_after <text> <after_line> <paragraph>: inserts a
  # blank line followed by <paragraph> (itself a single line - a
  # one-line paragraph, no embedded newline) immediately after the
  # FIRST line of <text> that equals <after_line> exactly. The blank
  # line comes from a literal `print ""` in the awk PROGRAM text below,
  # not from any -v value, deliberately: passing a value containing an
  # embedded newline via awk's `-v name=value` is not portable (some
  # awk implementations reject it outright with "newline in string"),
  # so every -v value used anywhere in this section, including here,
  # is kept to a single line on purpose.
  text=$1
  after_line=$2
  paragraph=$3
  printf '%s\n' "$text" | awk -v target="$after_line" -v para="$paragraph" '
    {
      print
      if (!done && $0 == target) {
        print ""
        print para
        done = 1
      }
    }
  '
}

extract_h1_title() {
  # extract_h1_title <text>: prints the first line matching "^# " - the
  # document's own H1 heading - so add_title_suffix below can target it
  # by its actual current content instead of a hardcoded per-command
  # string that could silently drift from the source.
  text=$1
  printf '%s\n' "$text" | awk '/^# / { print; exit }'
}

add_title_suffix() {
  # add_title_suffix <text> <suffix>: appends " <suffix>" (e.g.
  # "(Codex)") to the text's own H1 title line, wherever that line's
  # current content actually is.
  text=$1
  suffix=$2
  title_line=$(extract_h1_title "$text")
  literal_replace "$text" "$title_line" "$title_line $suffix"
}

check_no_claude_only_syntax() {
  # check_no_claude_only_syntax <text> <label> [allow_cursor_skill_frontmatter]:
  # fails the build loudly if <text> - the FINAL, fully-transformed text
  # of a Codex or Cursor artifact, read back from that artifact's own
  # temp file right before it is mv'd into place (see "Write every
  # artifact" near the bottom of this file for every call site: the
  # eleven ported command artifacts AND targets/codex/AGENTS.md and
  # targets/cursor/squirrel-mode.mdc) - still contains any syntax or
  # reference that only makes sense on Claude Code. Never called against
  # output-styles/squirrel-mode.md or skills/rules/SKILL.md - the two
  # Claude Code artifacts, where "Claude" and "/squirrel:" are correct.
  # See the DRIFT GUARD note at the top of this section.
  #
  # EXTENDED (B5, S7 review): the original version checked only two
  # literals ($ARGUMENTS and /squirrel:) and was structurally unable to
  # catch B4's leak - "Claude" meaning the model answering right now
  # (wrong on Codex, possibly wrong on Cursor), not the separate
  # product "Claude Code" sharing the profile file (which is correct
  # and must keep passing). Every check below names, in its own failure
  # message, exactly which pattern matched.
  #
  # THE disable-model-invocation ALLOWANCE. That key entered the pattern
  # list below as a Claude-Code-only mechanism, and for Codex it still
  # is: Codex's own skill spec has no equivalent, which is exactly why
  # init's and tune's Codex descriptions say "never run unprompted" in
  # prose instead. Cursor's Agent Skills DO document it, with the same
  # meaning - the skill is never applied by the model on its own and is
  # only included when the user types its slash command - and the
  # targets/cursor/skills/squirrel-*/SKILL.md artifacts set it
  # deliberately. For those five, and only those five, the third argument
  # is "yes" and ONE occurrence is permitted.
  #
  # The allowance is the narrowest one that works, so this guard keeps
  # catching a real leak in those five artifacts as thoroughly as in the
  # other nine. The permitted occurrence must be the EXACT full line
  # held in CURSOR_SKILL_INVOCATION_LINE, must appear EXACTLY once in
  # the whole artifact, and must sit inside that artifact's own leading
  # YAML frontmatter block - never in the body, where a mention could
  # only have arrived from a source skill's prose. A second occurrence,
  # another spelling, or one below the frontmatter still fails the
  # build. Nothing else is skipped for these five: the one permitted line
  # is REMOVED from the text, and every check below then runs over the
  # remainder exactly as it does everywhere else.
  text=$1
  label=$2
  allow_cursor_skill_frontmatter=${3:-no}

  if [ "$allow_cursor_skill_frontmatter" = "yes" ]; then
    # Two counts in ONE awk pass: how many lines mention the key at all
    # (total), and how many of those are the exact permitted line inside
    # the leading frontmatter block (permitted). "Inside the leading
    # frontmatter block" is "the text's first line is ---, and exactly
    # one --- has been seen so far" - the shape write_cursor_skill below
    # emits and every frontmatter accessor in this repository assumes.
    dmi_counts=$(printf '%s\n' "$text" | awk -v want="$CURSOR_SKILL_INVOCATION_LINE" '
      NR == 1 && $0 == "---" { opens_with_delim = 1 }
      /^---$/ { delim_seen++ }
      index($0, "disable-model-invocation") > 0 {
        total++
        if ($0 == want && opens_with_delim && delim_seen == 1) { permitted++ }
      }
      END { printf "%d %d\n", total + 0, permitted + 0 }
    ')
    dmi_total=${dmi_counts%% *}
    dmi_permitted=${dmi_counts##* }
    if [ "$dmi_total" != "1" ] || [ "$dmi_permitted" != "1" ]; then
      fail "$label may carry exactly ONE 'disable-model-invocation' occurrence - the literal line '$CURSOR_SKILL_INVOCATION_LINE' inside its own leading YAML frontmatter block, which is Cursor's own documented Agent Skill field - but it has $dmi_total occurrence(s) of that key, of which $dmi_permitted match that rule. An extra occurrence, a different spelling, or one below the frontmatter is a Claude-Code-only mechanism that leaked through from a source skill's prose. Remove it from the source, or fix the frontmatter this script composes."
    fi
    text=$(printf '%s\n' "$text" | awk -v want="$CURSOR_SKILL_INVOCATION_LINE" '$0 != want')
  fi

  # shellcheck disable=SC2016 # single-quoted deliberately throughout
  # this loop: every pattern is literal text a `grep -F` search is
  # meant to find, never an expression meant to expand in this shell.
  for pattern in '$ARGUMENTS' '${CLAUDE_' 'CLAUDE_PLUGIN_ROOT' 'CLAUDE_PLUGIN_DATA' 'SessionStart' 'UserPromptSubmit' 'PreToolUse' 'disable-model-invocation'; do
    if printf '%s' "$text" | grep -qF "$pattern"; then
      fail "$label still contains a literal '$pattern' after transformation - either a substitution in scripts/build.sh no longer matches the current text of its source skill, or a mechanism only Claude Code has leaked through untransformed. Update the substitution, or remove the leaked reference, to match the new source text."
    fi
  done

  if printf '%s' "$text" | grep -qFi '/squirrel:'; then
    fail "$label still contains a case-insensitive '/squirrel:' reference after transformation - a substitution in scripts/build.sh no longer matches the current text of its source skill. Update the substitution to match the new source text."
  fi

  # "Claude" naming the separate product "Claude Code" (or its
  # hyphenated spelling "Claude-Code") - which happens to share the same
  # profile file - is correct and must keep passing; "Claude" meaning
  # the model answering right now is the model-identity leak B4/F2
  # found and must fail the build.
  #
  # F2 (S7 review cycle 2, headline finding): the previous version was a
  # bare `sed 's/Claude Code/PLACEHOLDER/'` with NO word boundary at
  # either end. Two failures, both reproduced: (1) "Claude Codex" is not
  # "Claude Code" at all - the sed only matches the 11-character
  # substring "Claude Code", which IS present as a PREFIX of "Claude
  # Codex", so the placeholder swap fired anyway and consumed it,
  # leaving nothing for the bare-"Claude" grep below to catch - the
  # exact model-identity-leak class this check exists to catch shipped
  # straight through, verbatim, into a generated artifact; (2)
  # "Claude-Code" (hyphenated) does not match the sed's literal SPACE at
  # all, so it was never stripped, and the bare-"Claude" grep then
  # wrongly flagged it as a leak even though it unambiguously names the
  # product.
  #
  # Replaced with a single awk scan implementing the exact rule: an
  # occurrence of "Claude" is permitted ONLY when (a) "Claude" itself
  # starts at a WORD BOUNDARY - the character immediately before it, if
  # any, is not [A-Za-z0-9_] (this is what keeps "Claudette" and other
  # words merely STARTING WITH "Claude" from ever being examined as an
  # occurrence of the word "Claude" at all - see the word-char check
  # immediately after the boundary check below, which treats "Claude"
  # immediately followed by a word character as "not a standalone
  # occurrence", not as "a violation"), and (b) what follows it is
  # exactly one SEPARATOR character (a space or a newline - see the
  # STREAM SCAN note below) followed by "Code", or exactly "-Code", AND
  # the character after "Code" is itself not a word character (so
  # "Claude Code", "Claude Code's", "Claude Code.", and "Claude-Code"
  # all pass, but "Claude Codex" - "Code" immediately followed by the
  # word character "x" - fails, exactly like a bare "Claude", "Claude.",
  # or "Claude will").
  #
  # STREAM SCAN (G4, S7 review cycle 3): awk's default per-record
  # (per-line) loop would treat a "Claude"/"Code" pair split across a
  # line break as two independent, unrelated lines - "Claude" alone at
  # the end of one line, matching neither " Code" nor "-Code" because
  # there is no character left on THAT line to check, would wrongly
  # report a leak even though the rendered Markdown reads "Claude Code"
  # with an ordinary soft line wrap in between. <text> is therefore
  # accumulated whole, embedded newlines and all, into one awk string
  # (`full`) before the character-by-character scan below ever runs -
  # the scan itself is unchanged except that its separator check now
  # accepts a literal newline exactly where it already accepted a
  # literal space, so a wrapped "Claude\nCode" is recognised exactly
  # like an unwrapped "Claude Code". Dormant today (the four source
  # skills use one long line per paragraph, so no generated artifact
  # currently exercises this), but a future rewrap of the source prose
  # would otherwise fail the build for a reason that made no sense to
  # whoever hit it.
  #
  # The first offending match is reported as a bounded, single-line
  # SNIPPET (up to 40 characters on either side, any embedded newline
  # flattened to a space for display) rather than "the offending line" -
  # once <text> can contain a match spanning two lines, "the line" is no
  # longer a well-defined thing to print; a short window around the
  # match is quoted verbatim in the fail() message instead, so the
  # author can still find it immediately.
  first_bad_claude_snippet=$(printf '%s' "$text" | awk '
    { full = (NR == 1) ? $0 : full "\n" $0 }
    END {
      line = full
      n = length(line)
      for (i = 1; i <= n; i++) {
        if (substr(line, i, 6) != "Claude") { continue }
        if (i > 1) {
          prevch = substr(line, i - 1, 1)
          if (prevch ~ /[A-Za-z0-9_]/) { continue }
        }
        afterclaude = substr(line, i + 6, 1)
        if (afterclaude ~ /[A-Za-z0-9_]/) { continue }
        rest = substr(line, i + 6)
        sep = substr(rest, 1, 1)
        matched = 0
        if ((sep == " " || sep == "\n") && substr(rest, 2, 4) == "Code") {
          aftercode = substr(rest, 6, 1)
          if (aftercode ~ /[A-Za-z0-9_]/) { matched = 1 }
        } else if (substr(rest, 1, 5) == "-Code") {
          aftercode = substr(rest, 6, 1)
          if (aftercode ~ /[A-Za-z0-9_]/) { matched = 1 }
        } else {
          matched = 1
        }
        if (matched) {
          start = i - 40
          if (start < 1) { start = 1 }
          snippet = substr(line, start, 90)
          gsub(/\n/, " ", snippet)
          print snippet
          exit
        }
      }
    }
  ')
  if [ -n "$first_bad_claude_snippet" ]; then
    fail "$label still contains the bare word 'Claude' (meaning the model answering right now, not the separate product 'Claude Code'/'Claude-Code') after transformation - a substitution in scripts/build.sh no longer matches the current text of its source skill, or a Claude-Code-only claim leaked through untransformed. Offending text: $first_bad_claude_snippet"
  fi
}

check_cursor_skill_swap_is_word_only() {
  # check_cursor_skill_swap_is_word_only <text> <label>: fails the build
  # loudly if <text> - the Cursor-bound body as it stands IMMEDIATELY
  # BEFORE write_cursor_command's `literal_replace "$body" "skill"
  # "command"` runs on it - contains an occurrence of the lowercase
  # substring "skill" that is not the standalone WORD "skill".
  #
  # WHY THIS EXISTS. That substitution is a blanket, literal,
  # every-occurrence swap with no notion of a word boundary. It is
  # correct today only because every occurrence in the Cursor bodies
  # happens to be the standalone word ("This skill restructures...",
  # "...any tool call this skill makes."), which is exactly what has to
  # become "command" in Cursor's own vocabulary. Nothing enforced that.
  # A source sentence such as
  #
  #   See the skills/rules/SKILL.md file; skillful use of the skills
  #   directory helps.
  #
  # shipped, verbatim and silently, as
  #
  #   See the commands/rules/SKILL.md file; commandful use of the
  #   commands directory helps.
  #
  # - a broken path and an invented word - with build.sh exiting 0.
  #
  # This is the same hazard class as check_no_backslash_in_source_skills
  # near the top of this file, and it is unreachable by the CI drift
  # check for the same reason that one gives: the corruption is a
  # deterministic function of the source, so a fresh regeneration is
  # identically wrong and `git diff --exit-code` can never see it. The
  # fix chosen is the same one: turn a silent future corruption into a
  # loud failure now.
  #
  # THE RULE. An occurrence is safe iff neither the character before it
  # nor the character after it is a word character or "/". That accepts
  # the standalone word in ordinary prose ("a skill", "this skill.",
  # "the skill's output") and rejects:
  #   - a longer word containing it   - skills, skillful, reskill
  #   - a path segment                - skills/rules/SKILL.md, /skill
  # Uppercase and mixed-case spellings ("SKILL.md", "Skill") are not
  # examined at all, deliberately: the substitution is case-sensitive
  # and lowercase-only, so those are never rewritten and are not a
  # hazard. Note that "skills/rules/SKILL.md" is still rejected - by the
  # lowercase "skill" inside "skills", which the substitution WOULD
  # rewrite.
  #
  # Fixing an occurrence this rejects means editing the source skill's
  # prose (or the substitution in this script), never loosening the
  # rule: there is no safe way for the blanket swap to leave a
  # non-standalone occurrence alone.
  cursor_swap_text=$1
  cursor_swap_label=$2
  cursor_swap_hits=$(printf '%s\n' "$cursor_swap_text" | grep -n -E '[A-Za-z0-9_/]skill|skill[A-Za-z0-9_/]' | head -n 3 | tr '\n' ' ' || true)
  if [ -n "$cursor_swap_hits" ]; then
    fail "$cursor_swap_label: the Cursor 'skill' -> 'command' substitution would rewrite an occurrence of 'skill' that is NOT the standalone word - it is part of a longer word or of a path (e.g. 'skills/rules/SKILL.md' would become 'commands/rules/SKILL.md', 'skillful' would become 'commandful'). That swap is a blanket literal replacement of every occurrence and has no way to skip one; the drift check cannot see the damage either, because a fresh regeneration from the same source is identically wrong. Reword the offending text in the source skill so the only lowercase 'skill' occurrences left are standalone words. Offending line(s): $cursor_swap_hits"
  fi
}

# ported_skill_description <name>: the Codex frontmatter "description"
# for <name>, mechanically derived from skills/<name>/SKILL.md's own
# description by literal substitution (see the section header above).
ported_skill_description() {
  name=$1
  desc=$(source_skill_description "$name")
  case "$name" in
    digest)
      desc=$(literal_replace "$desc" "an explicit /squirrel:digest invocation, " "")
      ;;
    plan)
      desc=$(literal_replace "$desc" "an explicit /squirrel:plan invocation, or " "")
      ;;
    init)
      desc=$(literal_replace "$desc" "Only for an explicit /squirrel:init invocation." "Only run this when the user explicitly asks to run squirrel-mode calibration - for example, asked to run squirrel init or calibrate squirrel-mode. Never start this interview unprompted, and never run it merely because no profile exists yet.")
      ;;
    tune)
      # B9 (S7 review): init's description already carries a concrete
      # foreclosure ("never run it merely because no profile exists
      # yet") - a specific, plausible-sounding wrong trigger it rules
      # out by name. tune's did not have an equivalent; Codex has no
      # disable-model-invocation, so this prose IS the entire guard,
      # and a vaguer "never change the profile unprompted" alone is
      # weaker than naming the concrete wrong trigger explicitly.
      desc=$(literal_replace "$desc" "Only for an explicit /squirrel:tune invocation." "Only run this when the user explicitly asks to change or tune a squirrel-mode profile field. Never change the profile unprompted, and never run it merely because the user mentioned a preference in passing without asking for the change.")
      ;;
    pickup)
      desc=$(literal_replace "$desc" "an explicit /squirrel:pickup invocation, or " "")
      ;;
  esac
  # G5/G6 (S7 review cycle 3): check_no_claude_only_syntax does NOT run
  # here. This description is only ONE ingredient of the artifact
  # write_codex_skill eventually composes (frontmatter + banner + this
  # description + the body ported_skill_body below produces) - scanning
  # it in isolation, before that composition happens, is exactly the gap
  # G5 found (the scan never reached the base-rules-derived artifacts at
  # all) and exactly what made G6's "scans the FINAL, fully-transformed
  # text" comment false (add_title_suffix and Cursor's skill->command
  # swap both still run AFTER this function returns). See the "Write
  # every artifact" section near the bottom of this file for the single
  # place the check now runs: on every fully composed artifact's own
  # temp-file content, immediately before that content is mv'd into its
  # final path.
  printf '%s' "$desc"
}

# ported_skill_body <name>: the host-neutral body (H1 title line not
# yet suffixed - callers add "(Codex)"/"(Cursor)" via add_title_suffix)
# for <name>, mechanically derived from skills/<name>/SKILL.md's own
# body by literal substitution (see the section header above). init
# and tune additionally gain one boilerplate paragraph, inserted
# immediately after their own opening sentence, stating explicitly that
# they write/edit the exact ~/.squirrel/profile.md path Claude
# Code and Cursor also read (task requirement: "say so"). The Codex
# insert currently also says Cursor cannot read that file; write_cursor_skill
# replaces that Codex-only paragraph (and the mid-session demonstration)
# in the Cursor artifact, so Codex targets/codex/skills/init|tune stay
# byte-identical to the shared insert.
ported_skill_body() {
  name=$1
  body=$(source_skill_body "$name")
  case "$name" in
    digest)
      body=$(delete_exact_line "$body" "Arguments: \$ARGUMENTS")
      body=$(literal_replace "$body" "/squirrel:digest restructures messy inbound content into the fixed brief below." "This skill restructures messy inbound content into the fixed brief below.")
      # Model-identity leak (S7 review B4): the source sentence names
      # "Claude's own output" - correct on Claude Code, where the
      # answering model really is Claude, but false on Codex and
      # possibly false on Cursor, neither of which is guaranteed to be
      # running Claude. Rewritten host-neutrally; skills/digest/SKILL.md
      # itself is left unchanged, since "Claude" is the correct word
      # there.
      body=$(literal_replace "$body" "the same treatment squirrel-mode's base rules apply to Claude's own output, applied here to content the user received." "the same treatment squirrel-mode's base rules apply to the assistant's own output, applied here to content the user received.")
      body=$(literal_replace "$body" "Text was pasted after the command, in \$ARGUMENTS. Use it directly." "Text was pasted directly into this request. Use it directly.")
      body=$(literal_replace "$body" "\$ARGUMENTS names a file path that exists in the current project." "The request names a file path that exists in the current project.")
      body=$(literal_replace "$body" "\$ARGUMENTS is a Jira ticket reference" "The request is a Jira ticket reference")
      body=$(literal_replace "$body" "\$ARGUMENTS is empty and nothing else was pasted." "Nothing was pasted or otherwise provided at all.")
      body=$(literal_replace "$body" "When \$ARGUMENTS includes \`--for-reply\`," "When the request includes \`--for-reply\`,")
      ;;
    plan)
      body=$(delete_exact_line "$body" "Arguments: \$ARGUMENTS")
      body=$(literal_replace "$body" "/squirrel:plan turns a raw, disordered idea into a scoped, startable plan." "This skill turns a raw, disordered idea into a scoped, startable plan.")
      body=$(literal_replace "$body" "If \$ARGUMENTS is empty and nothing else was provided, ask exactly one question:" "If nothing was provided with the request and nothing else was pasted, ask exactly one question:")
      body=$(literal_replace "$body" "Otherwise, treat \$ARGUMENTS, plus anything pasted with it, as the idea dump," "Otherwise, treat whatever was provided, plus anything pasted with it, as the idea dump,")
      ;;
    init)
      body=$(literal_replace "$body" "/squirrel:init builds the user's personal squirrel-mode profile through a seven-question interview." "This skill builds the user's personal squirrel-mode profile through a seven-question interview.")
      # B6 (S7 review): the original inserted paragraph claimed running
      # this skill "calibrates squirrel-mode on every target installed
      # on this machine, Cursor included", with no caveat - but Cursor
      # cannot read the profile at all (its own .mdc says so: "Cursor
      # has no profile mechanism ... cannot be personalized
      # automatically"). Rewritten to state the truth without hedging:
      # Claude Code and this skill both read the profile automatically;
      # Cursor does not read it, period, and has to be hand-tuned
      # separately.
      body=$(insert_paragraph_after "$body" "This skill builds the user's personal squirrel-mode profile through a seven-question interview. Follow this procedure exactly, in every session it runs in." "This writes to \`~/.squirrel/profile.md\`. Claude Code and this skill both read that file automatically. Cursor cannot read it at all - Cursor's rules file has to be hand-edited to match, see docs/OTHER-TOOLS.md in the squirrel-mode repository.")
      # B7 (S7 review): rules/base-rules.md is a repo-relative path that
      # does not exist on a Codex install - substituted for the
      # host-appropriate equivalent, the defaults table Codex actually
      # ships in ~/.codex/AGENTS.md. Matched and replaced as one full
      # phrase (not a bare "rules/base-rules.md" token swap), so the
      # surrounding grammar stays correct.
      body=$(literal_replace "$body" "the same range \`rules/base-rules.md\` and \`/squirrel:tune\` both enforce for this field" "the same range the defaults table in \`~/.codex/AGENTS.md\` and the squirrel-mode \`tune\` skill both enforce for this field")
      body=$(literal_replace "$body" "\`/squirrel:tune\`" "the squirrel-mode \`tune\` skill")
      body=$(literal_replace "$body" "The demonstration is part of \`/squirrel:init\` itself, not a separate step the user has to ask for." "The demonstration is part of this skill itself, not a separate step the user has to ask for.")
      ;;
    tune)
      body=$(literal_replace "$body" "/squirrel:tune edits one field of the existing profile at \`~/.squirrel/profile.md\`." "This skill edits one field of the existing profile at \`~/.squirrel/profile.md\`.")
      # B6, same rationale as the init branch above: state the truth
      # without hedging instead of an unqualified "Cursor included".
      body=$(insert_paragraph_after "$body" "This skill edits one field of the existing profile at \`~/.squirrel/profile.md\`. It never re-runs the seven-question interview." "Claude Code and this skill both read \`~/.squirrel/profile.md\` automatically, so a change made here takes effect there right away. Cursor cannot read this file at all - Cursor's rules file has to be hand-edited to match, see docs/OTHER-TOOLS.md in the squirrel-mode repository.")
      body=$(literal_replace "$body" "\`/squirrel:init\`" "the squirrel-mode \`init\` skill")
      body=$(literal_replace "$body" "Any list \`/squirrel:tune\` shows," "Any list this skill shows,")
      # B7, same rationale as the init branch above.
      body=$(literal_replace "$body" "and treat it as the \`rules/base-rules.md\` default for that field until the user sets it explicitly through this command." "and treat it as the default for that field shown in the defaults table in \`~/.codex/AGENTS.md\` until the user sets it explicitly through this command.")
      ;;
  esac
  # Applied uniformly after the case statement, so every
  # ported body gets the same normalisation regardless of which
  # branch ran: delete_exact_line (digest/plan) can leave two adjacent
  # blank lines where the deleted "Arguments: $ARGUMENTS" line used to
  # separate them, and a body that never went through delete_exact_line
  # at all (init/tune) still opens with the ONE leading blank line every
  # skills/<name>/SKILL.md body has (immediately after the frontmatter's
  # closing "---") - collapsing it here, rather than per-branch, is what
  # keeps write_codex_skill/write_cursor_command's own single blank
  # line (printed right after the GENERATED banner) from stacking into
  # two before the H1 title for init/tune specifically.
  body=$(collapse_blank_runs "$body")
  # G5/G6: see ported_skill_description's identical comment just above -
  # the check does not run on this body in isolation either; it runs
  # once, later, on the fully composed artifact text (see "Write every
  # artifact" near the bottom of this file).
  printf '%s' "$body"
}

write_codex_skill() {
  # write_codex_skill <name>: composes targets/codex/skills/<name>/SKILL.md
  # in full - Codex frontmatter (name + description only; Codex's own
  # spec has no equivalent of Claude Code's disable-model-invocation,
  # which is why init/tune's descriptions above say explicitly, in
  # prose, never to run unprompted), the GENERATED banner naming
  # skills/<name>/SKILL.md as source, then the ported, title-suffixed body.
  name=$1
  desc=$(ported_skill_description "$name")
  printf '%s\n' "---"
  printf 'name: %s\n' "$name"
  printf 'description: "%s"\n' "$desc"
  printf '%s\n' "---"
  printf '\n'
  print_generated_banner_for "skills/$name/SKILL.md"
  printf '\n'
  body=$(ported_skill_body "$name")
  body=$(add_title_suffix "$body" "(Codex)")
  printf '%s\n' "$body"
}

write_cursor_command() {
  # write_cursor_command <name>: composes targets/cursor/commands/<name>.md
  # in full - NO frontmatter at all (verified: Cursor's own command
  # files are plain Markdown; the command name comes from the filename,
  # not from a field inside it), the GENERATED banner naming
  # skills/<name>/SKILL.md as source, then the ported, title-suffixed
  # body. Cursor-ONLY vocabulary fix (B8, S7 review), applied AFTER the
  # shared ported_skill_body transformation: Cursor's own mechanism is
  # a *command*, not a skill, so the word "skill" - which
  # ported_skill_body's shared substitutions introduce into the body
  # (e.g. "This skill restructures...") - reads wrong here. Codex keeps
  # "skill", unchanged, in write_codex_skill above - that word is
  # Codex's own vocabulary for the exact same mechanism, so no
  # substitution runs there.
  name=$1
  print_generated_banner_for "skills/$name/SKILL.md"
  printf '\n'
  body=$(ported_skill_body "$name")
  body=$(add_title_suffix "$body" "(Cursor)")
  # Guarded, not blind: the swap below rewrites EVERY literal occurrence
  # of "skill", so the check immediately above it proves there is no
  # occurrence left that is anything but the standalone word. See
  # check_cursor_skill_swap_is_word_only for what it rejects and why the
  # drift check can never catch this on its own. Runs against $body only
  # - the GENERATED banner printed above names skills/<name>/SKILL.md as
  # the source and is deliberately NOT part of $body, so the swap never
  # reaches it and the banner keeps saying "skills/".
  check_cursor_skill_swap_is_word_only "$body" "targets/cursor/commands/$name.md"
  body=$(literal_replace "$body" "skill" "command")
  printf '%s\n' "$body"
}

cursor_skill_folder_name() {
  # cursor_skill_folder_name <name>: the folder AND frontmatter `name`
  # for <name>'s Cursor Agent Skill - one function so the two can never
  # be generated from different expressions. Cursor requires `name` to
  # be lowercase letters, numbers and hyphens only AND to match the
  # parent folder exactly; it has no command namespace of its own (there
  # is no Cursor equivalent of Claude Code's "/squirrel:" prefix), so a
  # bare "digest" would sit in the user's global skill namespace under a
  # name anyone else's skill could plausibly want. The "squirrel-"
  # prefix is what keeps /squirrel-digest, /squirrel-plan,
  # /squirrel-init, /squirrel-tune and /squirrel-pickup unmistakably
  # squirrel-mode's.
  printf 'squirrel-%s\n' "$1"
}

cursor_skill_body_substitutions() {
  # cursor_skill_body_substitutions <name> <body>: Cursor-only pass on
  # the already-ported body. Codex artifacts are composed from
  # ported_skill_body with no call here, so targets/codex/skills/init|tune
  # stay byte-identical when this function changes. Init/tune's shared
  # insert currently claims Cursor cannot read ~/.squirrel/profile.md;
  # that is false for these skills (the Task 2 projection hook reads it
  # on the next session), so it is replaced here rather than by
  # rewriting the Codex insert.
  name=$1
  body=$2
  case "$name" in
    init)
      body=$(literal_replace "$body" "This writes to \`~/.squirrel/profile.md\`. Claude Code and this skill both read that file automatically. Cursor cannot read it at all - Cursor's rules file has to be hand-edited to match, see docs/OTHER-TOOLS.md in the squirrel-mode repository." "This writes to \`~/.squirrel/profile.md\`.")
      body=$(literal_replace "$body" "the same range the defaults table in \`~/.codex/AGENTS.md\` and the squirrel-mode \`tune\` skill both enforce for this field" "the same range the defaults table in \`~/.cursor/rules/squirrel-mode.mdc\` and the squirrel-mode \`tune\` skill both enforce for this field")
      body=$(literal_replace "$body" "Once the file is written, confirm in one line and immediately answer the user's very next message using the new profile. The demonstration is part of this skill itself, not a separate step the user has to ask for." "Once the file is written, confirm in one line. $CURSOR_PROFILE_NEW_CHAT_SENTENCE")
      ;;
    tune)
      body=$(literal_replace "$body" "Claude Code and this skill both read \`~/.squirrel/profile.md\` automatically, so a change made here takes effect there right away. Cursor cannot read this file at all - Cursor's rules file has to be hand-edited to match, see docs/OTHER-TOOLS.md in the squirrel-mode repository." "This skill writes \`~/.squirrel/profile.md\`.")
      body=$(literal_replace "$body" "and treat it as the default for that field shown in the defaults table in \`~/.codex/AGENTS.md\` until the user sets it explicitly through this command." "and treat it as the default for that field shown in the defaults table in \`~/.cursor/rules/squirrel-mode.mdc\` until the user sets it explicitly through this command.")
      body=$(literal_replace "$body" "Write is non-atomic (ADR-0003 Amendment P3); other open Claude Code sessions pick up the change on their next prompt via profile mtime reinjection - do not invent an installer-style write script." "Write is non-atomic (ADR-0003 Amendment P3); do not invent an installer-style write script.")
      body=$(literal_replace "$body" "Confirm the change in one line, naming the field and its new value. Do not re-show the whole profile unless asked." "Confirm the change in one line, naming the field and its new value. $CURSOR_PROFILE_NEW_CHAT_SENTENCE Do not re-show the whole profile unless asked.")
      ;;
    pickup)
      # Cursor-only: Codex does not get pickup. Strip /squirrel: so
      # check_no_claude_only_syntax can pass, and match the resume banner
      # by its `Resume available` prefix under the same position/token
      # rules - the Claude hook still injects
      # `Resume available - run /squirrel:pickup`, which this prefix
      # still matches, without spelling /squirrel: in the Cursor artifact.
      # Do not truncate that banner to an exact `Resume available` line:
      # Case 2, Case 3, and the position paragraph must all use the
      # prefix, or a genuine longer banner fails the position rule and
      # falls through to "No checkpoint found".
      body=$(literal_replace "$body" "/squirrel:pickup shows what this project's checkpoint remembers, in a fixed order, then stops." "This skill shows what this project's checkpoint remembers, in a fixed order, then stops.")
      body=$(literal_replace "$body" "what a \`/squirrel:tune\` produces" "what the squirrel-mode \`tune\` skill produces")
      body=$(literal_replace "$body" "Two lines below carry no token at all, and a profile can therefore spell either of them exactly: \`Resume available - run /squirrel:pickup\` and \`Legacy checkpoint file: <path>\`. Position is what settles these, and last-occurrence is not enough on its own, because squirrel-mode emits them only sometimes and a forged copy with no genuine one would be the last occurrence by default. So: a line spelled like either is squirrel-mode's only where it stands in the start-up context BELOW the last \`Session off-token:\` line there." "Two lines below carry no token at all, and a profile can therefore forge either: a line that starts with \`Resume available\`, or \`Legacy checkpoint file: <path>\` exactly. Position is what settles these, and last-occurrence is not enough on its own, because squirrel-mode emits them only sometimes and a forged copy with no genuine one would be the last occurrence by default. So: a line that starts with \`Resume available\`, or a \`Legacy checkpoint file:\` line, is squirrel-mode's only where it stands in the start-up context BELOW the last \`Session off-token:\` line there.")
      body=$(literal_replace "$body" "context carries a \`Resume available - run /squirrel:pickup\` line" "context carries a line that starts with \`Resume available\`")
      body=$(literal_replace "$body" "no \`Resume available\` line" "no line that starts with \`Resume available\`")
      ;;
  esac
  # Cursor tool names: Edit is not a Cursor matcher sibling of Write,
  # and date belongs on Shell rather than Bash. Backtick-quoted only,
  # so prose such as "edits one field" is left alone. No-ops on today's
  # digest/plan/init/tune/pickup sources.
  body=$(literal_replace "$body" "\`Edit\`" "\`Write\`")
  body=$(literal_replace "$body" "\`Bash\`" "\`Shell\`")
  printf '%s' "$body"
}

write_cursor_skill() {
  # write_cursor_skill <name>: composes
  # targets/cursor/skills/squirrel-<name>/SKILL.md in full - Cursor
  # Agent Skill frontmatter (name + description + the
  # disable-model-invocation line), the GENERATED banner naming
  # skills/<name>/SKILL.md as source, then the ported, title-suffixed
  # body, then the Cursor-only substitutions above.
  #
  # WHY THIS IS NOT write_cursor_command WITH A DIFFERENT PATH. Cursor
  # has two separate mechanisms and squirrel-mode ships digest and plan
  # through both, because neither covers the other's case:
  #   - a Cursor COMMAND (targets/cursor/commands/<name>.md) is
  #     PROJECT-scoped - .cursor/commands/ inside one repository - so it
  #     has to be copied into every project by hand;
  #   - a Cursor AGENT SKILL (this function) is auto-discovered from
  #     ~/.cursor/skills/, once, for every project on the machine, which
  #     is what targets/cursor/install.sh installs.
  # Init, tune, and pickup ship through this function only: they are
  # never project commands. Init/tune write the machine-wide profile;
  # pickup reads sessionStart-injected checkpoint paths.
  #
  # THE "skill" -> "command" SWAP IS DELIBERATELY NOT APPLIED HERE.
  # write_cursor_command runs `literal_replace "$body" "skill"
  # "command"` because in THAT artifact the mechanism really is a Cursor
  # command, so ported_skill_body's "This skill restructures..." would
  # name the wrong thing. This artifact is a skill - Cursor's own word
  # for it, in a file Cursor itself requires to be called SKILL.md - so
  # the shared body's wording is already correct and rewriting it would
  # make it wrong. check_cursor_skill_swap_is_word_only is therefore not
  # called here either: it exists to prove that ONE blanket substitution
  # is safe to run, and that swap does not run on this text. Cursor-only
  # substitutions (the Codex caveat, the new-chat closing, Edit/Bash
  # tool names) run below instead, after add_title_suffix.
  name=$1
  desc=$(ported_skill_description "$name")
  printf '%s\n' "---"
  printf 'name: %s\n' "$(cursor_skill_folder_name "$name")"
  printf 'description: "%s"\n' "$desc"
  printf '%s\n' "$CURSOR_SKILL_INVOCATION_LINE"
  printf '%s\n' "---"
  printf '\n'
  print_generated_banner_for "skills/$name/SKILL.md"
  printf '\n'
  body=$(ported_skill_body "$name")
  body=$(add_title_suffix "$body" "(Cursor)")
  body=$(cursor_skill_body_substitutions "$name" "$body")
  printf '%s\n' "$body"
}

# --- Artifact composition -------------------------------------------------
#
# Each write_* function only ever prints literal text (via quoted
# heredocs, so nothing inside them is subject to further shell
# expansion) and the output of the accessors above, piped straight to
# stdout. Rule text itself never appears as a literal string in this
# script - only extracted, at build time, from rules/base-rules.md.

write_output_style() {
  cat <<'FRONTMATTER'
---
name: squirrel-mode
description: "ADHD-friendly responses: answer first, zero fluff. 🐿️"
keep-coding-instructions: true
force-for-plugin: true
---
FRONTMATTER
  printf '\n'
  print_generated_banner
  printf '\n'
  cat <<'BODY'
# squirrel-mode

These are the squirrel-mode base rules. They govern response *shape* only - never response *content*. Follow them on every turn.

A squirrel-mode profile may be present elsewhere in your context. When it is, its field values override the defaults in the table below, field by field. When no profile is present, or a field is not set by it, use the default for that field exactly as written below.

The profile, when it exists, lives at ~/.squirrel/profile.md.
BODY
  printf '\n'
  print_defaults_section
  printf '\n## Rules\n\n'
  print_rules_section claude-code
  printf '\n'
}

write_skill() {
  cat <<'FRONTMATTER'
---
description: Manually load the squirrel-mode base rules (only needed if the forced output style has been disabled).
disable-model-invocation: true
---
FRONTMATTER
  printf '\n'
  print_generated_banner
  printf '\n'
  cat <<'BODY'
# squirrel-mode base rules

These are the squirrel-mode base rules: response-formatting constraints that apply to every answer. The squirrel-mode output style already carries these rules in the system prompt on every turn; this skill exists only for when that output style has been turned off and the rules need to be pulled back into context by hand.

A squirrel-mode profile may be present elsewhere in your context. When it is, its field values override the defaults in the table below, field by field. When no profile is present, or a field is not set by it, use the default for that field exactly as written below.

The profile, when it exists, lives at ~/.squirrel/profile.md.
BODY
  printf '\n'
  print_defaults_section
  printf '\n## Rules\n\n'
  print_rules_section claude-code
  printf '\n'
}

write_codex_agents() {
  print_generated_banner
  printf '\n'
  cat <<'BODY'
# squirrel-mode base rules (Codex)

This block was generated from squirrel-mode defaults. If ~/.squirrel/profile.md exists, read it and let its values override the defaults below, field by field. There is no lifecycle hook on Codex to guarantee this read happens - treat it as best-effort.
BODY
  printf '\n'
  print_defaults_section
  printf '\n## Rules\n\n'
  print_rules_section codex
  printf '\n'
}

write_cursor_mdc() {
  cat <<'FRONTMATTER'
---
description: ADHD-friendly response rules for squirrel-mode - answer first, zero fluff.
alwaysApply: true
---
FRONTMATTER
  printf '\n'
  print_generated_banner
  printf '\n'
  cat <<'BODY'
# squirrel-mode base rules (Cursor)

If ~/.squirrel/profile.md exists, squirrel-mode projects it to ~/.cursor/rules/squirrel-profile.mdc with alwaysApply so those field values override the defaults below. If no profile exists yet, the defaults apply as-is. To hand-tune them, see docs/OTHER-TOOLS.md in the squirrel-mode repository.
BODY
  printf '\n'
  print_defaults_section
  printf '\n## Rules\n\n'
  print_rules_section cursor
  printf '\n'
}

write_cursor_hooks() {
  cat <<'EOF'
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "\"${CURSOR_PLUGIN_ROOT}\"/scripts/load-profile.sh"
      }
    ],
    "beforeSubmitPrompt": [
      {
        "command": "\"${CURSOR_PLUGIN_ROOT}\"/scripts/check-off-flag.sh"
      },
      {
        "command": "\"${CURSOR_PLUGIN_ROOT}\"/scripts/load-profile.sh"
      }
    ],
    "preToolUse": [
      {
        "matcher": "Write|Read",
        "command": "\"${CURSOR_PLUGIN_ROOT}\"/scripts/allow-checkpoint.sh"
      }
    ]
  }
}
EOF
}

# --- Write every artifact --------------------------------------------
#
# All validation above already ran to completion before this point, so
# every write below is backed by known-good input.
mkdir -p "$repo_root/output-styles" "$repo_root/skills/rules" \
  "$repo_root/targets/codex" "$repo_root/targets/cursor" \
  "$repo_root/targets/codex/skills/digest" "$repo_root/targets/codex/skills/plan" \
  "$repo_root/targets/codex/skills/init" "$repo_root/targets/codex/skills/tune" \
  "$repo_root/targets/cursor/commands" "$repo_root/targets/cursor/hooks" \
  "$repo_root/targets/cursor/skills/$(cursor_skill_folder_name digest)" \
  "$repo_root/targets/cursor/skills/$(cursor_skill_folder_name plan)" \
  "$repo_root/targets/cursor/skills/$(cursor_skill_folder_name init)" \
  "$repo_root/targets/cursor/skills/$(cursor_skill_folder_name tune)" \
  "$repo_root/targets/cursor/skills/$(cursor_skill_folder_name pickup)"

# Atomicity, honestly stated: each artifact is first written to a
# hidden temp file in the SAME DIRECTORY as its final target - never
# /tmp, since the repo could be on a different filesystem/mount and mv
# (rename(2)) is only atomic within one filesystem - and only mv'd into
# place once every one of the sixteen temp writes below has already
# succeeded. That covers the WRITE phase completely: a failure partway
# through the sixteen writes (a full disk, a read-only target directory, a
# signal - see the traps below) leaves every real artifact exactly as it
# was, never a mix of freshly regenerated and stale files, because no mv
# has run yet at that point.
#
# The MV PHASE is a narrower, different story, and this comment used to
# overstate it. Sixteen independent rename(2) calls, one per fixed
# committed path, cannot be made atomic AS A GROUP under POSIX sh - there
# is no multi-file rename primitive available here. Two things narrow
# that window as far as this shell can narrow it: each mv is individually
# atomic (so no single artifact is ever observed half-written, only "old"
# or "new", never a mix within one file), and HUP/INT/TERM are ignored for
# the short duration of the sixteen mv's (see the trap right before them),
# so a signal arriving mid-sequence cannot land between two of them.
#
# What neither defense reaches is SIGKILL or power loss: either can still
# stop the process between mv 1 and mv 16, leaving some artifacts
# regenerated and others stale. That residual is real, not hypothetical,
# and is not eliminated here - it cannot be, in POSIX sh, against those
# two failure modes specifically. It is not silent forever, though: the
# next run's drift check (tests/test_build.sh's "regenerate into scratch
# and diff against committed" scenario) catches exactly that
# inconsistency, because a half-applied mv sequence looks identical, from
# that check's point of view, to a hand-edited artifact - both drift from
# what rules/base-rules.md would regenerate.
final_output_style="$repo_root/output-styles/squirrel-mode.md"
final_skill="$repo_root/skills/rules/SKILL.md"
final_codex="$repo_root/targets/codex/AGENTS.md"
final_cursor="$repo_root/targets/cursor/squirrel-mode.mdc"

tmp_output_style="$repo_root/output-styles/.squirrel-mode.md.tmp.$$"
tmp_skill="$repo_root/skills/rules/.SKILL.md.tmp.$$"
tmp_codex="$repo_root/targets/codex/.AGENTS.md.tmp.$$"
tmp_cursor="$repo_root/targets/cursor/.squirrel-mode.mdc.tmp.$$"

# The eleven ported command artifacts (see the "Ported command artifacts"
# section above) plus the Cursor hooks.json. Every one of the sixteen
# final_*/tmp_* paths below is now
# written and moved UNCONDITIONALLY - validate_source_skill above
# already guaranteed, before this point, that all five
# skills/{digest,plan,init,tune,pickup}/SKILL.md sources exist and are
# well-formed, so there is no absent-source case left to skip.
cursor_skill_dir_digest="$repo_root/targets/cursor/skills/$(cursor_skill_folder_name digest)"
cursor_skill_dir_plan="$repo_root/targets/cursor/skills/$(cursor_skill_folder_name plan)"
cursor_skill_dir_init="$repo_root/targets/cursor/skills/$(cursor_skill_folder_name init)"
cursor_skill_dir_tune="$repo_root/targets/cursor/skills/$(cursor_skill_folder_name tune)"
cursor_skill_dir_pickup="$repo_root/targets/cursor/skills/$(cursor_skill_folder_name pickup)"

final_codex_skill_digest="$repo_root/targets/codex/skills/digest/SKILL.md"
final_codex_skill_plan="$repo_root/targets/codex/skills/plan/SKILL.md"
final_codex_skill_init="$repo_root/targets/codex/skills/init/SKILL.md"
final_codex_skill_tune="$repo_root/targets/codex/skills/tune/SKILL.md"
final_cursor_command_digest="$repo_root/targets/cursor/commands/digest.md"
final_cursor_command_plan="$repo_root/targets/cursor/commands/plan.md"
final_cursor_skill_digest="$cursor_skill_dir_digest/SKILL.md"
final_cursor_skill_plan="$cursor_skill_dir_plan/SKILL.md"
final_cursor_skill_init="$cursor_skill_dir_init/SKILL.md"
final_cursor_skill_tune="$cursor_skill_dir_tune/SKILL.md"
final_cursor_skill_pickup="$cursor_skill_dir_pickup/SKILL.md"
final_cursor_hooks="$repo_root/targets/cursor/hooks/hooks.json"

tmp_codex_skill_digest="$repo_root/targets/codex/skills/digest/.SKILL.md.tmp.$$"
tmp_codex_skill_plan="$repo_root/targets/codex/skills/plan/.SKILL.md.tmp.$$"
tmp_codex_skill_init="$repo_root/targets/codex/skills/init/.SKILL.md.tmp.$$"
tmp_codex_skill_tune="$repo_root/targets/codex/skills/tune/.SKILL.md.tmp.$$"
tmp_cursor_command_digest="$repo_root/targets/cursor/commands/.digest.md.tmp.$$"
tmp_cursor_command_plan="$repo_root/targets/cursor/commands/.plan.md.tmp.$$"
tmp_cursor_skill_digest="$cursor_skill_dir_digest/.SKILL.md.tmp.$$"
tmp_cursor_skill_plan="$cursor_skill_dir_plan/.SKILL.md.tmp.$$"
tmp_cursor_skill_init="$cursor_skill_dir_init/.SKILL.md.tmp.$$"
tmp_cursor_skill_tune="$cursor_skill_dir_tune/.SKILL.md.tmp.$$"
tmp_cursor_skill_pickup="$cursor_skill_dir_pickup/.SKILL.md.tmp.$$"
tmp_cursor_hooks="$repo_root/targets/cursor/hooks/.hooks.json.tmp.$$"

cleanup_build_tmp() {
  # rm -f is a silent no-op on a path that was never created (e.g. if
  # the script failed before reaching that particular write) - safe to
  # list every one of the sixteen temp paths unconditionally.
  rm -f "$tmp_output_style" "$tmp_skill" "$tmp_codex" "$tmp_cursor" \
    "$tmp_codex_skill_digest" "$tmp_codex_skill_plan" \
    "$tmp_codex_skill_init" "$tmp_codex_skill_tune" \
    "$tmp_cursor_command_digest" "$tmp_cursor_command_plan" \
    "$tmp_cursor_skill_digest" "$tmp_cursor_skill_plan" \
    "$tmp_cursor_skill_init" "$tmp_cursor_skill_tune" \
    "$tmp_cursor_skill_pickup" \
    "$tmp_cursor_hooks"
}

# A signal handler that only cleans up and never calls `exit` does not
# stop the script: POSIX sh runs the trap action and then RESUMES on the
# very next statement, exactly as if nothing had interrupted it. On a
# signal delivered mid-build, that resumed execution used to delete the
# very temp files a not-yet-run `mv` still needed - corrupting the
# working tree instead of leaving it untouched. Each handler below
# therefore cleans up AND terminates, with the conventional 128+signum
# exit status for its signal (129=HUP, 130=INT, 143=TERM), so a signal
# genuinely stops the script instead of letting it blunder forward past
# work that has not happened yet. The plain EXIT trap deliberately has no
# handler-specific `exit` call: it must not clobber whatever exit status
# the normal path (0), a `set -e` abort, or `fail()`'s own `exit 1`
# already established before EXIT fired.
trap cleanup_build_tmp EXIT
on_hup() {
  cleanup_build_tmp
  exit 129
}
on_int() {
  cleanup_build_tmp
  exit 130
}
on_term() {
  cleanup_build_tmp
  exit 143
}
trap on_hup HUP
trap on_int INT
trap on_term TERM

write_output_style >"$tmp_output_style"
write_skill >"$tmp_skill"
write_codex_agents >"$tmp_codex"
write_cursor_mdc >"$tmp_cursor"

# The eleven ported command artifacts - written UNCONDITIONALLY.
# validate_source_skill already guaranteed every one of
# skills/{digest,plan,init,tune,pickup}/SKILL.md exists and is well-formed
# before this point (see the "Availability" comment above it) - there
# is no absent-source case left to guard against here, and a fixture
# that wants build.sh to succeed without these eleven writes must supply
# real skills/ sources instead (tests/test_build.sh's
# make_build_scratch() does exactly that).
write_codex_skill digest >"$tmp_codex_skill_digest"
write_codex_skill plan >"$tmp_codex_skill_plan"
write_codex_skill init >"$tmp_codex_skill_init"
write_codex_skill tune >"$tmp_codex_skill_tune"
write_cursor_command digest >"$tmp_cursor_command_digest"
write_cursor_command plan >"$tmp_cursor_command_plan"
write_cursor_skill digest >"$tmp_cursor_skill_digest"
write_cursor_skill plan >"$tmp_cursor_skill_plan"
write_cursor_skill init >"$tmp_cursor_skill_init"
write_cursor_skill tune >"$tmp_cursor_skill_tune"
write_cursor_skill pickup >"$tmp_cursor_skill_pickup"
write_cursor_hooks >"$tmp_cursor_hooks"

# G5/G6 (S7 review cycle 3): check_no_claude_only_syntax runs HERE,
# against each artifact's own FULLY COMPOSED text - read back from the
# temp file it was just written to, after every transformation
# (frontmatter, the GENERATED banner, add_title_suffix, and - for
# Cursor - the skill-to-command word swap) has already been applied,
# never against an isolated ingredient (a bare description or body)
# before that composition happens. Deliberately placed AFTER all sixteen
# temp writes above but BEFORE the first `mv` below: a failure here
# still leaves every real artifact untouched (the cleanup trap removes
# the temp files; no `mv` has run yet), so the file header's "All
# validation happens before any output file is written" stays true.
# Covers the eleven ported command artifacts (G5's own fix) AND the two
# base-rules-derived artifacts, targets/codex/AGENTS.md and
# targets/cursor/squirrel-mode.mdc, which this check never reached
# before at all - a future rules/base-rules.md edit mentioning
# "Claude", a hook name, or "$ARGUMENTS" now fails the build instead of
# shipping unchecked into either non-Claude-Code host. Deliberately
# excludes $tmp_output_style and $tmp_skill - the two Claude Code
# artifacts, where "Claude" and "/squirrel:" are correct and must keep
# passing.
#
# The five Cursor Agent Skills pass "yes" as the third argument, and are
# the only call sites that ever do: their frontmatter carries Cursor's
# own documented disable-model-invocation field, which the pattern list
# otherwise rejects outright. Every other check still runs on them
# unchanged, and even that one key is only tolerated as the exact
# permitted line, exactly once, inside the frontmatter - see
# check_no_claude_only_syntax's "disable-model-invocation ALLOWANCE".
check_no_claude_only_syntax "$(cat "$tmp_codex")" "targets/codex/AGENTS.md"
check_no_claude_only_syntax "$(cat "$tmp_cursor")" "targets/cursor/squirrel-mode.mdc"
check_no_claude_only_syntax "$(cat "$tmp_codex_skill_digest")" "targets/codex/skills/digest/SKILL.md"
check_no_claude_only_syntax "$(cat "$tmp_codex_skill_plan")" "targets/codex/skills/plan/SKILL.md"
check_no_claude_only_syntax "$(cat "$tmp_codex_skill_init")" "targets/codex/skills/init/SKILL.md"
check_no_claude_only_syntax "$(cat "$tmp_codex_skill_tune")" "targets/codex/skills/tune/SKILL.md"
check_no_claude_only_syntax "$(cat "$tmp_cursor_command_digest")" "targets/cursor/commands/digest.md"
check_no_claude_only_syntax "$(cat "$tmp_cursor_command_plan")" "targets/cursor/commands/plan.md"
check_no_claude_only_syntax "$(cat "$tmp_cursor_skill_digest")" "targets/cursor/skills/$(cursor_skill_folder_name digest)/SKILL.md" "yes"
check_no_claude_only_syntax "$(cat "$tmp_cursor_skill_plan")" "targets/cursor/skills/$(cursor_skill_folder_name plan)/SKILL.md" "yes"
check_no_claude_only_syntax "$(cat "$tmp_cursor_skill_init")" "targets/cursor/skills/$(cursor_skill_folder_name init)/SKILL.md" "yes"
check_no_claude_only_syntax "$(cat "$tmp_cursor_skill_tune")" "targets/cursor/skills/$(cursor_skill_folder_name tune)/SKILL.md" "yes"
check_no_claude_only_syntax "$(cat "$tmp_cursor_skill_pickup")" "targets/cursor/skills/$(cursor_skill_folder_name pickup)/SKILL.md" "yes"
check_no_claude_only_syntax "$(cat "$tmp_cursor_hooks")" "targets/cursor/hooks/hooks.json"

# All writes above succeeded (set -e would otherwise have aborted
# already, triggering the cleanup trap and leaving every final_* path
# untouched). Each of the sixteen mv's below is a rename(2) within one
# directory, hence individually atomic; only now, with known-good
# content already fully written to disk under every temp name, do the
# real targets get replaced.
#
# POSIX sh has no way to BLOCK a signal, only to IGNORE it (`trap ''`):
# a signal delivered while ignored is discarded outright, not queued for
# later delivery. That is why restoring the real handlers immediately
# after the last mv is safe and cannot trigger some delayed, backlogged
# signal from during this window - by the time the real handlers are
# back, there is nothing left pending to deliver. Ignoring rather than
# leaving the real handlers active is deliberate, not an oversight:
# on_hup/on_int/on_term calling `exit` between two of these sixteen mv's is
# exactly the half-applied state the comment above is about, so this is
# the one place those handlers must NOT run.
#
# Restoring happens on every path out of this block. If all sixteen mv's
# succeed, the three `trap` calls immediately below always run next,
# unconditionally. If any mv fails instead, `set -e` ends the script
# right there without ever reaching those `trap` calls - but the ignored
# dispositions do not outlive the process (a new process, including any
# later invocation of this script, always starts with default signal
# dispositions), so there is no continued execution during which leaving
# HUP/INT/TERM ignored could cause harm; the EXIT trap still runs
# cleanup_build_tmp on that path exactly as it does on every other one.
trap '' HUP INT TERM
mv "$tmp_output_style" "$final_output_style"
mv "$tmp_skill" "$final_skill"
mv "$tmp_codex" "$final_codex"
mv "$tmp_cursor" "$final_cursor"
mv "$tmp_codex_skill_digest" "$final_codex_skill_digest"
mv "$tmp_codex_skill_plan" "$final_codex_skill_plan"
mv "$tmp_codex_skill_init" "$final_codex_skill_init"
mv "$tmp_codex_skill_tune" "$final_codex_skill_tune"
mv "$tmp_cursor_command_digest" "$final_cursor_command_digest"
mv "$tmp_cursor_command_plan" "$final_cursor_command_plan"
mv "$tmp_cursor_skill_digest" "$final_cursor_skill_digest"
mv "$tmp_cursor_skill_plan" "$final_cursor_skill_plan"
mv "$tmp_cursor_skill_init" "$final_cursor_skill_init"
mv "$tmp_cursor_skill_tune" "$final_cursor_skill_tune"
mv "$tmp_cursor_skill_pickup" "$final_cursor_skill_pickup"
mv "$tmp_cursor_hooks" "$final_cursor_hooks"
trap on_hup HUP
trap on_int INT
trap on_term TERM
