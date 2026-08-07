#!/bin/sh
# build.sh - generates every squirrel-mode artifact from rules/base-rules.md.
#
# rules/base-rules.md is the ONLY place the 16 base rules exist (see
# .build-checkpoint.md invariant 1). This script parses it and writes:
#   - output-styles/squirrel-mode.md   (all 16 rules, targets: claude-code)
#   - skills/rules/SKILL.md            (all 16 rules, targets: claude-code)
#   - targets/codex/AGENTS.md          (15 rules, targets: codex)
#   - targets/cursor/squirrel-mode.mdc (15 rules, targets: cursor)
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
# working directory. Idempotent: given the same rules/base-rules.md, two
# runs produce byte-identical artifacts (no timestamps, no counters, no
# other non-deterministic content).
#
# Fails loudly (non-zero exit, message on stderr, no partial writes) if
# rules/base-rules.md is missing, does not contain exactly 16 rule
# headings numbered 1..16 with no gaps or duplicates, if any heading is
# not followed by exactly one targets marker, or if any targets value is
# not "all" or a comma-separated subset of claude-code/codex/cursor. All
# validation happens before any output file is written, so a malformed
# input can never produce a half-empty generated artifact.
set -eu

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

# print_generated_banner: the GENERATED marker every artifact opens
# with (after any YAML frontmatter - a comment above "---" breaks
# frontmatter parsing).
print_generated_banner() {
  cat <<'BANNER'
<!-- GENERATED FILE. Source: rules/base-rules.md. Generator: scripts/build.sh.
     Hand edits to this file will be overwritten the next time scripts/build.sh runs. -->
BANNER
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

The profile, when it exists, lives at ~/.claude/squirrel/profile.md.
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

The profile, when it exists, lives at ~/.claude/squirrel/profile.md.
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

This block was generated from squirrel-mode defaults. If ~/.claude/squirrel/profile.md exists, read it and let its values override the defaults below, field by field. There is no lifecycle hook on Codex to guarantee this read happens - treat it as best-effort.
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

Cursor has no profile mechanism, so the defaults below apply as-is and cannot be personalized automatically. To hand-tune them, see docs/OTHER-TOOLS.md in the squirrel-mode repository.
BODY
  printf '\n'
  print_defaults_section
  printf '\n## Rules\n\n'
  print_rules_section cursor
  printf '\n'
}

# --- Write every artifact --------------------------------------------
#
# All validation above already ran to completion before this point, so
# every write below is backed by known-good input.
mkdir -p "$repo_root/output-styles" "$repo_root/skills/rules" \
  "$repo_root/targets/codex" "$repo_root/targets/cursor"

# Atomicity, honestly stated: each artifact is first written to a
# hidden temp file in the SAME DIRECTORY as its final target - never
# /tmp, since the repo could be on a different filesystem/mount and mv
# (rename(2)) is only atomic within one filesystem - and only mv'd into
# place once every one of the four temp writes below has already
# succeeded. That covers the WRITE phase completely: a failure partway
# through the four writes (a full disk, a read-only target directory, a
# signal - see the traps below) leaves every real artifact exactly as it
# was, never a mix of freshly regenerated and stale files, because no mv
# has run yet at that point.
#
# The MV PHASE is a narrower, different story, and this comment used to
# overstate it. Four independent rename(2) calls, one per fixed
# committed path, cannot be made atomic AS A GROUP under POSIX sh - there
# is no multi-file rename primitive available here. Two things narrow
# that window as far as this shell can narrow it: each mv is individually
# atomic (so no single artifact is ever observed half-written, only "old"
# or "new", never a mix within one file), and HUP/INT/TERM are ignored for
# the short duration of the four mv's (see the trap right before them),
# so a signal arriving mid-sequence cannot land between two of them.
#
# What neither defense reaches is SIGKILL or power loss: either can still
# stop the process between mv 1 and mv 4, leaving some artifacts
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

cleanup_build_tmp() {
  rm -f "$tmp_output_style" "$tmp_skill" "$tmp_codex" "$tmp_cursor"
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

# All four writes above succeeded (set -e would otherwise have aborted
# already, triggering the cleanup trap and leaving every final_* path
# untouched). Each mv below is a rename(2) within one directory, hence
# individually atomic; only now, with known-good content already fully
# written to disk under every temp name, do the real targets get
# replaced.
#
# POSIX sh has no way to BLOCK a signal, only to IGNORE it (`trap ''`):
# a signal delivered while ignored is discarded outright, not queued for
# later delivery. That is why restoring the real handlers immediately
# after the last mv is safe and cannot trigger some delayed, backlogged
# signal from during this window - by the time the real handlers are
# back, there is nothing left pending to deliver. Ignoring rather than
# leaving the real handlers active is deliberate, not an oversight:
# on_hup/on_int/on_term calling `exit` between two of these four mv's is
# exactly the half-applied state the comment above is about, so this is
# the one place those handlers must NOT run.
#
# Restoring happens on every path out of this block. If all four mv's
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
trap on_hup HUP
trap on_int INT
trap on_term TERM
