#!/bin/sh
# Coverage for S6: docs/RESEARCH.md, the evidence base. Extended in S9 (scenario 27, near the end
# of this file) to also check README.md's own population tags, which S6 never covered.
#
# This file checks structural/parsing invariants of the research document, not the truth of
# any citation (that was verified by hand against primary sources while writing the file, per
# the citation policy stated inside docs/RESEARCH.md itself). What IS mechanically checkable,
# and therefore what this file checks:
#
#   1. The file exists and is non-empty.
#   2. Every population tag used is one of exactly three allowed strings.
#   3. Every "## Finding" section carries at least one population tag.
#   4. Every citation line carries a 4-digit year and an http(s) link.
#   5. Every base-rule number referenced ("**Rules justified:** N, M") exists in
#      rules/base-rules.md — parsed from that file, never hardcoded here.
#   6. The three corrections (Liebel first-author, 2511.14636's population, the interruption
#      figure) are present and correctly stated.
#   7. No TODO:/FIXME:/XXX: marker and no bare "[citation needed]"-style placeholder.
#   8. A "What we could not verify" section exists.
#   9. Every arXiv: reference matches the NNNN.NNNNN shape, nothing looser.
#  10. docs/ contains nothing but ACCEPTANCE.md, OTHER-TOOLS.md, RESEARCH.md and adr/.
#  11. The citation policy section names all four checks (identity, support, whose finding it
#      is, population) and states plainly that identity alone is not verification.
#  12. No citation bullet cites Sweller (1988) — the paper this file established does not
#      contain the intrinsic/extraneous distinction, or fit anywhere else in this file either.
#  13. Finding 1's ADHD sentence is the corrected load-sensitivity claim, with the old,
#      contradicted "reduced ... across load conditions ... worsens as load increases" framing
#      absent — asserted as specific text, not just "a citation exists."
#  14. Finding 11 does not contain the phrase "well established" anywhere in the file, and
#      Finding 5's heading does not contain "well established" or "well documented" either.
#  15. The Corrections section records the five pre-existing identity misattributions AND the
#      five substance failures found in the second verification pass.
#  16. PLAN.md drift check, part A: every author-year style citation extracted from PLAN.md
#      Section 2 (a capitalized name run immediately followed by a 4-digit 19xx/20xx year, in
#      "Name, YYYY" / "Name et al., YYYY" / "Name & Name (YYYY)" shape) has both its name token(s)
#      and its year corroborated as substrings somewhere in docs/RESEARCH.md. This is what makes
#      cycle 2's actual failure mechanically detectable: PLAN.md asserting something RESEARCH.md
#      does not carry.
#  17. PLAN.md drift check, part B: a name this file's Corrections section retired as wrong
#      (Karalunas, Salari, Roberts, or a bare "Sweller" not immediately followed by "& Chandler")
#      may not appear anywhere in PLAN.md except inside a paragraph that itself contains a "⚠"
#      correction marker — i.e. a paragraph telling the story of the mistake, not asserting it
#      live. This is the complement to check 16: 16 alone would not catch a retired name coming
#      back, because the retired name legitimately appears *somewhere* in RESEARCH.md too (in the
#      prose describing why it was wrong), so "the name and year both appear in RESEARCH.md"
#      would pass even for a resurrected bad citation. See the comment above
#      check_retired_name_violations for the exact scoping rule and its known blind spot.
#  18. The Corrections section's stated substance-failure count (the word after "found" and
#      before "citations that were bibliographically correct") equals the number of "N. **...**"
#      enumerated items actually present under the "### Substance failures found in a second
#      verification pass" subheading — so the count and the list cannot silently drift apart
#      again (this is exactly the item-2 bug this cycle fixed: the prose said four, the list had
#      five).
#  19. README.md drift check, part A (S8): the identical author-year citation-drift check as 16,
#      extended to the whole of README.md (which has no "## 2. WHY"-shaped section to scope to).
#      Unlike PLAN.md Section 2, README.md legitimately carries zero author-year citations by
#      design — it links to docs/RESEARCH.md rather than restating findings by name — so a real
#      "0" here is an expected pass; the mutation fixture is what proves the extractor still
#      catches a real fabricated citation.
#  20. README.md drift check, part B (S8): the identical retired-name check as 17
#      (check_retired_name_violations takes a file path and was already fully generic — no
#      README-specific variant was needed), applied directly to README.md.
#  21. Rules-coverage cross-check, part A (S8, review cycle 1, S8-1): every rule number appearing
#      in any "**Rules justified:**" line in docs/RESEARCH.md, collected and de-duplicated, must
#      equal an explicitly declared expected set. Catches a future edit that adds a citation for a
#      rule without this test file being updated to expect it (or vice versa).
#  22. Rules-coverage cross-check, part B: every rule number named as "- **Rule N (...)**" under
#      the "## Rules with no research claim behind them" section must equal an explicitly declared
#      expected set — the six rules with no citation. Catches a future edit to that section
#      drifting from the rules it is supposed to name.
#  23. Rules-coverage cross-check, part C: every rule number 1..16 (parsed from
#      rules/base-rules.md, never hardcoded) is accounted for in EXACTLY ONE of the two groups
#      above — no rule cited AND named as design-decision, no rule in neither. This is the
#      assertion that must go red if someone adds a "Rules justified:" line without updating the
#      design-decisions section, or removes a rule from that section without adding a citation.
#  24. [REWRITTEN, S8 review cycle 2, T1 BLOCKER; WIDENED, S8 review cycle 3, U2 BLOCKER] No
#      tracked markdown-family file — scanned via `git ls-files "*.$ext"` once per extension in
#      MARKDOWN_FAMILY_EXTENSIONS ("md mdc" today), SCAN-ALL-BY-DEFAULT, not a hardcoded filename
#      list — contains an absolute "every/each/all rule(s) ... trace(s) to a finding" style claim,
#      in any of the phrasings this project has now shipped twice: README.md and docs/RESEARCH.md
#      in cycle 1; CONTEXT.md and PLAN.md (twice) in cycle 2. The cycle-1 fix wired the guard to
#      those first two filenames by name, which is exactly why the identical sentence, unnoticed,
#      shipped in three MORE files the very next cycle — a hardcoded allowlist inverts the
#      fail-safe default, since a new document is unscanned until someone remembers to add it.
#      Cycle 2's fix widened the scan to every tracked file matching `git ls-files '*.md'`, but
#      that glob structurally cannot match targets/cursor/squirrel-mode.mdc — a tracked,
#      markdown-family, GENERATED FILE with a different extension — so the identical class of bug
#      shipped a third time (U2 BLOCKER). The cycle-3 fix generalizes the extension itself into
#      MARKDOWN_FAMILY_EXTENSIONS, a real, checked constant, plus a standing watchdog
#      (check_uncovered_markdown_extensions) that lists any DISTINCT extension actually present
#      among tracked files whose content looks markdown-family-shaped but isn't yet named in that
#      constant — so a future ".mdx"/".markdown"/".mkd" file fails this test the moment it's
#      added, rather than silently going unscanned. The detector itself is also broadened past the
#      original two exact strings into a co-occurrence class (an absolute quantifier over "rule"
#      paired with a trace/finding/citation/research term in the same paragraph) — see
#      check_absolute_rule_claim_present's own comment for exactly what that class does and does
#      not cover. Checked against the real repo (expect 0 files flagged, over the full real
#      per-extension `git ls-files` list — captured and asserted to cover every tracked
#      markdown-family file, no more and no fewer), then against scratch copies of FIVE different
#      files — README.md, docs/RESEARCH.md (the original two), CONTEXT.md, a docs/adr/ file (the
#      two cycle-1 missed), and targets/cursor/squirrel-mode.mdc (U2's actual gap) — each with the
#      claim injected, proving the detector is not still silently scoped to the original pair or to
#      the .md extension. A declared, asserted exemption list (empty today) is also checked:
#      equality-asserted against an expected constant so an exemption cannot be added without a
#      matching, visible test update, plus a real scratch git repository with both a .md and a .mdc
#      offender, proving the scan-all driver catches a violation in either extension when a file was
#      never on any list, and that the exemption is per-file (not per-extension) when only one of
#      the two is exempted.
#  25. The retired "success amnesia" / "blurs the memory of one's own accomplishments" / "own
#      recent progress" framing docs/RESEARCH.md Finding 8 explicitly retired stays dead in
#      README.md (S8-2's BLOCKER). Scoped to README.md only, deliberately: docs/RESEARCH.md's own
#      "What we could not verify" section legitimately names both exact phrases while explaining
#      why they were retired, so a file-generic ban would wrongly fail the real, correct
#      docs/RESEARCH.md. Checked against the real README.md (expect 0), then against a scratch
#      copy with all three phrases appended (expect 3).
#  26. The "N of the 16" / "other M rules" prose counts in README.md, docs/RESEARCH.md's, AND (added
#      this cycle, T1) PLAN.md's opening statements are literally derived from the same declared
#      expected-set sizes checks 21/22 compare against — not just eyeballed to currently match them.
#      This is a TWO-STEP mechanism, not a one-shot one, and the comment above the assertions
#      themselves says so explicitly: editing docs/RESEARCH.md's actual "Rules justified:"/design-
#      decision lines reddens checks 21/22/23 FIRST (the extracted set no longer matches the
#      declared EXPECTED_CITED_RULES/EXPECTED_DESIGN_RULES constants); only once a maintainer
#      updates those constants to match does the prose-count needle derived from them change,
#      reddening THIS check next because the prose itself has not been rewritten yet. Two separate,
#      sequential prompts toward two separate fixes, not one failure that "goes red everywhere at
#      once" (S8 review cycle 3, U8 MINOR fix — the comment used to read that way).
#
# [REMOVED, S8 review cycle 3, U4 MAJOR fix] A co-occurrence tripwire ("scenario 27") briefly lived
# here, flagging any sentence that paired an ADHD/memory term with an own-work term, with one
# sanctioned sentence exempted by exact text. It was deleted rather than narrowed. The tech lead's
# own six-sentence fixture (four legitimate sentences that must pass, plus the reviewer's paraphrase
# and the original retired sentence that must fail) proved narrowing cannot save it: any own-work
# term list broad enough to catch the paraphrase ("...unable to recall how much they've already
# gotten done...", which shares no vocabulary with the retired sentence at all) is also broad enough
# to flag ordinary prose about the Done log or /squirrel:pickup, and — independent of how the list is
# tuned — a CORRECTLY HEDGED restatement of Finding 8 that explicitly distinguishes it from the
# retired claim must still NAME the retired claim's own vocabulary to reject it, which no bag-of-
# words check can tell apart from asserting that vocabulary live. That is a structural limit, not a
# tuning problem: see check_retired_success_amnesia_phrasing's own comment, further down, for what
# replaces this class of check.
#  27. [S9, PLAN.md Section 5: "Every citation in README and RESEARCH.md is ... tagged with the
#      population it was measured in"] Every finding bullet in README.md's "## Why it's shaped
#      this way" section carries one of the three allowed population tags. Checks 2 and 3 above
#      only ever examined docs/RESEARCH.md's own `**Population:**` lines — until this scenario,
#      README's four inline, backtick-tagged bullets were unchecked entirely, so a hostile reader's
#      literal reading of the Section 5 criterion ("every citation in README...") had no automated
#      backing for the README half. Checked against the real file (expect 0 missing, and a
#      non-zero bullet count so this cannot pass vacuously if the section were ever emptied), then
#      against a scratch copy with one bullet's tag deleted (expect 1).
#  28. [THIRD VERIFICATION PASS] Finding 3 states the directionality its own citation MEASURED, not
#      the reverse. Kofler et al. (2020) carries the subtitle "Evidence for directionality of
#      effects" because it tested whether slowed processing degrades working memory and found it did
#      not — yet this file asserted that rejected direction for two review cycles, because both
#      earlier passes checked that the paper was real rather than what it said. Pinned as specific
#      text, exactly like scenario 13, plus a companion assertion that the finding DECLARES the
#      conflict between its own two citations (Hulsbosch et al. 2025 builds on the direction Kofler
#      et al. rejected) — a finding can state the right direction and still hide that its sources
#      disagree.
#  29. [THIRD VERIFICATION PASS] Finding 5's Meltzer & Basho citation does not sit under an `ADHD`
#      population tag. The chapter was downloaded and searched in full: "ADHD", "attention deficit"
#      and "attention-deficit" occur zero times, and it addresses "All students" in a
#      general-education classroom, so the `ADHD` tag asserted a population the source does not
#      have. Checked STRUCTURALLY (which tag is in force at that citation bullet) rather than by
#      phrase, because a substring check cannot distinguish "this source is about ADHD" from "this
#      source is not about ADHD" — both contain the token.
#  30. [THIRD VERIFICATION PASS] Finding 12 states Brown et al. (2020)'s main effect and does not
#      assert the ADHD-by-redundancy interaction its abstract never reports. The study really does
#      have redundancy and nonredundancy groups, which is what made the invented conditional
#      plausible enough to survive two passes. Both retired phrasings are banned file-wide, which is
#      affordable only because Finding 12's ⚠ note and Corrections entry were written to DESCRIBE
#      the retired conditional rather than quote it.
#
# Scenarios 2, 4, 5, 6, 9, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
# and 30 are
# checked twice each: once against the real, committed file(s) (expecting zero violations), and
# once against a scratch copy deliberately corrupted to contain exactly the bad pattern the check
# exists to catch (expecting the check to report a violation). Scenario 14 is checked once directly
# against the real file with the generic assert_not_contains helper, plus a subshell-isolated proof
# that the helper itself reports FAIL when the phrase is present, so the check is not vacuously
# true. Every check is implemented as a function taking a file path, specifically so the same code
# path can run against both the real file and a corrupted scratch fixture — a check that can only
# ever run against the one real file it was written to match proves nothing about whether it would
# catch a real regression.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the first failed assertion.
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

research_file="$repo_root/docs/RESEARCH.md"
base_rules_file="$repo_root/rules/base-rules.md"
docs_dir="$repo_root/docs"
plan_file="$repo_root/PLAN.md"
readme_file="$repo_root/README.md"

# --- Scratch fixtures, cleaned up on exit no matter how the script ends -----------------------
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-research-test.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT

# ================================================================================================
# Reusable checks. Each takes a FILE PATH and prints a result (a count, or yes/no) to stdout —
# never asserts directly — so the same function can be called against the real file and against
# scratch fixtures with different expected outcomes.
# ================================================================================================

# Rule numbers that actually exist in rules/base-rules.md, parsed from the file, never
# hardcoded. Matches the same heading shape build.sh and test_build.sh rely on:
# "### <n>. <Title>".
valid_rule_numbers=$(grep -oE '^### [0-9]+\.' "$base_rules_file" 2>/dev/null | grep -oE '[0-9]+' || true)

rule_number_is_valid() {
  # rule_number_is_valid <n> — prints "yes" or "no".
  #
  # $valid_rule_numbers is newline-separated, so splitting it into words below relies on IFS
  # containing a newline. A caller mid-way through its OWN IFS=',' loop (see
  # check_rule_ref_violations) would otherwise hand this function an IFS that cannot split the
  # list at all, silently collapsing it into a single word and making every lookup fail. This
  # function therefore always fixes its own IFS to whitespace before iterating, and restores
  # whatever the caller had on the way out, regardless of the caller's ambient IFS.
  needle=$1
  found=no
  caller_ifs=$IFS
  IFS='
 	'
  for v in $valid_rule_numbers; do
    if [ "$v" = "$needle" ]; then
      found=yes
      break
    fi
  done
  IFS=$caller_ifs
  echo "$found"
  return 0
}

# check_population_violations <file> — prints the count of "**Population:** X" lines whose X is
# not one of the three allowed tags, verbatim.
check_population_violations() {
  file=$1
  bad=0
  lines=$(grep -oE '^\*\*Population:\*\* .*$' "$file" 2>/dev/null || true)
  if [ -n "$lines" ]; then
    old_ifs=$IFS
    IFS='
'
    for line in $lines; do
      tag=${line#\*\*Population:\*\* }
      # Trim any trailing carriage return / whitespace defensively.
      tag=$(printf '%s' "$tag" | sed 's/[ \t]*$//')
      case "$tag" in
        "ADHD" | "general working memory" | "borrowed from adjacent accessibility work")
          ;;
        *)
          bad=$((bad + 1))
          ;;
      esac
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# check_findings_missing_population <file> — prints the count of "## Finding" sections
# (delimited by the next "## " heading, or EOF) that contain zero "**Population:**" lines.
check_findings_missing_population() {
  file=$1
  awk '
    BEGIN { in_finding = 0; has_pop = 0; missing = 0 }
    /^## / {
      if (in_finding == 1 && has_pop == 0) { missing++ }
      if ($0 ~ /^## Finding/) { in_finding = 1; has_pop = 0 } else { in_finding = 0 }
      next
    }
    in_finding == 1 && /^\*\*Population:\*\* / { has_pop = 1 }
    END {
      if (in_finding == 1 && has_pop == 0) { missing++ }
      print missing
    }
  ' "$file"
}

# check_readme_finding_bullets_missing_population <file> — prints "<missing> <total>": inside the
# "## Why it's shaped this way" section (delimited by the next "## " heading, or EOF), the count of
# top-level bullet lines ("- " at the start of a line) that contain NONE of the three allowed
# population tags anywhere across their own (possibly multi-line, indented-continuation) text,
# and the total number of such bullets found. A non-"- "-prefixed line while a bullet is open is
# treated as that bullet's own continuation (README wraps each finding across 2-3 physical lines),
# matching how get_rule_body-style parsers elsewhere in this repo already treat wrapped prose.
check_readme_finding_bullets_missing_population() {
  file=$1
  awk '
    BEGIN { in_section = 0; in_bullet = 0; has_tag = 0; missing = 0; total = 0 }
    /^## / {
      if (in_section == 1 && in_bullet == 1 && has_tag == 0) { missing++ }
      if ($0 == "## Why it'"'"'s shaped this way") { in_section = 1 } else { in_section = 0 }
      in_bullet = 0
      next
    }
    in_section == 1 && /^- / {
      if (in_bullet == 1 && has_tag == 0) { missing++ }
      in_bullet = 1
      has_tag = 0
      total++
    }
    in_section == 1 && in_bullet == 1 {
      if ($0 ~ /`ADHD`/ || $0 ~ /`general working memory`/ || $0 ~ /`borrowed from adjacent accessibility work`/) { has_tag = 1 }
    }
    END {
      if (in_section == 1 && in_bullet == 1 && has_tag == 0) { missing++ }
      print missing, total
    }
  ' "$file"
}

# check_citation_violations <file> — groups each "**Citations:**" block's bullets (a citation
# may wrap across several physical lines: a "- " line followed by continuation lines indented
# with two spaces) into one logical line per citation, then prints the count of citation lines
# missing a 4-digit year in parentheses, an http(s) link, or both.
check_citation_violations() {
  file=$1
  bad=0
  citations=$(awk '
    /^\*\*Citations:\*\*$/ { in_cite = 1; buf = ""; next }
    in_cite && /^-[ ]/ {
      if (buf != "") { print buf }
      buf = $0
      next
    }
    in_cite && /^  / {
      buf = buf " " $0
      next
    }
    in_cite {
      if (buf != "") { print buf; buf = "" }
      in_cite = 0
    }
    END { if (buf != "") print buf }
  ' "$file" 2>/dev/null || true)
  if [ -n "$citations" ]; then
    old_ifs=$IFS
    IFS='
'
    for c in $citations; do
      has_year=no
      case "$c" in
        *"("[0-9][0-9][0-9][0-9]")"*) has_year=yes ;;
      esac
      has_link=no
      case "$c" in
        *http*) has_link=yes ;;
      esac
      if [ "$has_year" != yes ] || [ "$has_link" != yes ]; then
        bad=$((bad + 1))
      fi
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# check_rule_ref_violations <file> — for every "**Rules justified:** N, M, ..." line, prints
# the count of referenced numbers that are empty, non-numeric, or absent from
# $valid_rule_numbers (which was parsed from rules/base-rules.md above, not hardcoded).
check_rule_ref_violations() {
  file=$1
  bad=0
  # Extract only the label plus the leading digit/comma/space run: this stops naturally at the
  # first non-digit-comma-space character (our own " — <explanation>" suffix), with no need to
  # match or depend on the em dash character itself.
  lines=$(grep -oE '^\*\*Rules justified:\*\* [0-9]+([, ]+[0-9]+)*' "$file" 2>/dev/null || true)
  if [ -n "$lines" ]; then
    old_ifs=$IFS
    IFS='
'
    for line in $lines; do
      numlist=${line#\*\*Rules justified:\*\* }
      old_ifs2=$IFS
      IFS=','
      for tok in $numlist; do
        tok=$(printf '%s' "$tok" | sed 's/^[ \t]*//; s/[ \t]*$//')
        case "$tok" in
          '' | *[!0-9]*)
            bad=$((bad + 1))
            ;;
          *)
            if [ "$(rule_number_is_valid "$tok")" != yes ]; then
              bad=$((bad + 1))
            fi
            ;;
        esac
      done
      IFS=$old_ifs2
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# check_interruption_figure_ok <file> — prints "yes" if the ~23-minute interruption-recovery
# figure is either absent entirely, or present only alongside a "Gloria Mark" attribution and
# never alongside a bare "APA" attribution; prints "no" otherwise.
check_interruption_figure_ok() {
  file=$1
  bad_apa=$(grep -cw 'APA' "$file" 2>/dev/null || true)
  bad_apa=${bad_apa:-0}
  if [ "$bad_apa" -gt 0 ]; then
    echo no
    return 0
  fi
  count_23=$(grep -icE '23[- ]minute' "$file" 2>/dev/null || true)
  count_23=${count_23:-0}
  if [ "$count_23" -eq 0 ]; then
    echo yes
    return 0
  fi
  mark_count=$(grep -c 'Gloria Mark' "$file" 2>/dev/null || true)
  mark_count=${mark_count:-0}
  if [ "$mark_count" -gt 0 ]; then
    echo yes
  else
    echo no
  fi
  return 0
}

# check_arxiv_violations <file> — prints the count of "arXiv:" references whose ID does not
# match the NNNN.NNNNN shape (exactly 4 digits, a dot, exactly 5 digits) exactly.
check_arxiv_violations() {
  file=$1
  bad=0
  tokens=$(grep -oE 'arXiv:[A-Za-z0-9._-]+' "$file" 2>/dev/null || true)
  if [ -n "$tokens" ]; then
    old_ifs=$IFS
    IFS='
'
    for t in $tokens; do
      id=${t#arXiv:}
      case "$id" in
        [0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9])
          ;;
        *)
          bad=$((bad + 1))
          ;;
      esac
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# extract_section <file> <heading_line> — prints every line strictly between an exact heading
# line (matched literally, e.g. "## Corrections") and the next line starting with "## " (a
# level-2 heading), or EOF. A "### " subheading does NOT end the section: "^## " requires a
# space in the third character position, which a "### " line does not have, so "^## " only ever
# matches a real level-2 heading. Shared by every check below that needs to scope its search to
# one named section instead of the whole file.
extract_section() {
  file=$1
  heading=$2
  awk -v heading="$heading" '
    $0 == heading { grab = 1; next }
    grab && /^## / { grab = 0 }
    grab { print }
  ' "$file" 2>/dev/null || true
}

# check_citation_policy_four_checks <file> — prints the count of required markers MISSING from
# the "## Citation policy" section: the four named checks (identity, support, whose finding it
# is, population) and an explicit statement that identity alone is not verification. 0 means
# every marker was found; the section names all four checks and says why identity alone does not
# suffice.
check_citation_policy_four_checks() {
  file=$1
  section=$(extract_section "$file" "## Citation policy")
  flat=$(printf '%s' "$section" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')
  missing=0
  case "$flat" in *"identity"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$flat" in *"support"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$flat" in *"whose finding"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$flat" in *"population"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$flat" in *"identity alone is not verification"*) ;; *) missing=$((missing + 1)) ;; esac
  echo "$missing"
}

# check_sweller_1988_citation_entries <file> — prints the count of logical citation bullets
# (inside any "**Citations:**" block, continuation lines joined exactly as
# check_citation_violations does) that cite Sweller with year 1988 — the paper this document
# established does not contain the intrinsic/extraneous distinction, and does not fit anywhere
# else in this file either. Catches a future edit reintroducing it as an actual citation, not
# just a mention of it in corrective prose (which legitimately names it while explaining why it
# was removed).
check_sweller_1988_citation_entries() {
  file=$1
  bad=0
  citations=$(awk '
    /^\*\*Citations:\*\*$/ { in_cite = 1; buf = ""; next }
    in_cite && /^-[ ]/ {
      if (buf != "") { print buf }
      buf = $0
      next
    }
    in_cite && /^  / {
      buf = buf " " $0
      next
    }
    in_cite {
      if (buf != "") { print buf; buf = "" }
      in_cite = 0
    }
    END { if (buf != "") print buf }
  ' "$file" 2>/dev/null || true)
  if [ -n "$citations" ]; then
    old_ifs=$IFS
    IFS='
'
    for c in $citations; do
      case "$c" in
        *Sweller*1988*) bad=$((bad + 1)) ;;
        *1988*Sweller*) bad=$((bad + 1)) ;;
      esac
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# check_finding1_adhd_claim_ok <file> — prints "yes" if Finding 1's ADHD-population sentence is
# the corrected, load-sensitivity claim ("show a disproportionate drop in working-memory accuracy
# as") AND the old, contradicted framing ("Adults with ADHD show reduced working-memory accuracy
# across load conditions, and that reduction") is absent; prints "no" otherwise. Locks in the
# specific replacement text so a future edit cannot silently restore the version the paper's own
# abstract contradicts.
check_finding1_adhd_claim_ok() {
  file=$1
  body=$(cat "$file" 2>/dev/null || true)
  has_new=no
  case "$body" in
    *"show a disproportionate drop in working-memory accuracy as"*) has_new=yes ;;
  esac
  has_old=no
  case "$body" in
    *"Adults with ADHD show reduced working-memory accuracy across load conditions, and that reduction"*) has_old=yes ;;
  esac
  if [ "$has_new" = yes ] && [ "$has_old" = no ]; then
    echo yes
  else
    echo no
  fi
}

# check_finding3_directionality_ok <file> — prints "yes" if Finding 3 states the direction Kofler et
# al. (2020) ACTUALLY measured (increasing working-memory demand slows information processing, while
# the reverse manipulation produced no significant change) AND the retired reverse assertion is
# absent; prints "no" otherwise. Scenario 13's counterpart for the third verification pass: the
# retired sentence claimed "slower processing keeps capacity occupied by ongoing work," which is the
# opposite of its own citation's result, and it survived two earlier passes because both checked
# that the paper was real rather than what it said.
#
# The retired needle is deliberately the CONJUNCTION "impairments in ADHD, and slower processing
# keeps capacity occupied", not the bare clause "slower processing keeps capacity occupied". The
# CORRECTED Finding 3, and the Corrections entry recording the fix, both QUOTE that bare clause in
# order to retire it — the same structural problem check_retired_success_amnesia_phrasing's comment
# describes for Finding 8 — so banning the bare clause would fail the correct file. The conjunction
# only ever appeared in the live assertion, never in prose rejecting it.
#
# Matched against a FLATTENED body (newlines to spaces, runs of spaces squeezed) because this
# document hard-wraps its prose, so any needle longer than a few words straddles a line break. Same
# reason scenario 26 flattens before matching.
check_finding3_directionality_ok() {
  file=$1
  flat=$(tr '\n' ' ' <"$file" 2>/dev/null | tr -s ' ')
  has_measured_direction=no
  case "$flat" in
    *"experimentally reducing children's information processing speed did not significantly change"*)
      has_measured_direction=yes
      ;;
  esac
  has_independence=no
  case "$flat" in
    *"relatively independent impairments in ADHD"*) has_independence=yes ;;
  esac
  has_retired=no
  case "$flat" in
    *"impairments in ADHD, and slower processing keeps capacity occupied"*) has_retired=yes ;;
  esac
  if [ "$has_measured_direction" = yes ] && [ "$has_independence" = yes ] && [ "$has_retired" = no ]; then
    echo yes
  else
    echo no
  fi
}

# check_finding5_meltzer_tag <file> — prints the population tag in force at the Meltzer & Basho
# citation bullet inside the "## Finding 5" section, or "none" if that bullet is not found there.
#
# Structural rather than phrase-based on purpose. Finding 5's defect was a TAG resting on a source
# that never mentions the tagged population: the Meltzer & Basho chapter's full text contains zero
# occurrences of "ADHD". A prose-substring check could not tell "this chapter is about ADHD" from
# "this chapter is not about ADHD" — both sentences contain the token — so this walks the section,
# tracks the `**Population:**` tag currently in force, and reports the one the Meltzer bullet
# actually sits under. That is the thing that was wrong, stated in the file's own structure.
check_finding5_meltzer_tag() {
  file=$1
  awk '
    /^## / { in_f5 = ($0 ~ /^## Finding 5:/) ? 1 : 0; next }
    in_f5 && /^\*\*Population:\*\* / { tag = substr($0, 17); next }
    in_f5 && /^- Meltzer, L\., & Basho, S\./ { print tag; found = 1; exit }
    END { if (!found) print "none" }
  ' "$file" 2>/dev/null || true
}

# check_corrections_records_failures <file> — prints the count of required markers MISSING from
# the "## Corrections" section: the five pre-existing identity misattributions (Liebel author
# order, arXiv:2511.14636's population, the 23-minute figure, the Karalunas mix-up, the Salari
# mix-up) plus the four substance failures from the second verification pass (Finding 1's Roberts
# citation, Finding 7's Gama & Lacerda misattribution, Finding 4's Sweller-1988 citation, and
# Finding 11's contradicted framing — matched by "Casimiro"..."unclear" rather than the retired
# phrase itself, since that phrase must not appear anywhere in this file at all). 0 means every
# marker was found.
check_corrections_records_failures() {
  file=$1
  section=$(extract_section "$file" "## Corrections")
  missing=0
  case "$section" in *"Liebel"*"Langlois"*"Gama"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"2511.14636"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"23-minute"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Karalunas"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Salari"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Roberts, Milich"*"response-selection"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Gama and Lacerda"*|*"Gama & Lacerda"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Sweller"*"1988"*"intrinsic"*) ;; *) missing=$((missing + 1)) ;; esac
  case "$section" in *"Casimiro"*"unclear"*) ;; *) missing=$((missing + 1)) ;; esac
  echo "$missing"
}

# ------------------------------------------------------------------------------------------------
# PLAN.md <-> docs/RESEARCH.md drift check.
#
# Cycle 2 was rejected because a substance fix landed in docs/RESEARCH.md but PLAN.md Section 2
# kept asserting the claim RESEARCH.md had already disproven — the same fact living in two files,
# one of which went stale. The two checks below make that class of failure mechanical instead of
# something a reviewer has to remember to re-check by eye.
# ------------------------------------------------------------------------------------------------

# extract_plan_section2 <file> — prints the lines of PLAN.md strictly between the "## 2. WHY"
# heading and the next "## " heading (exclusive): the Research foundation section, the one
# PLAN.md itself says must never drift from docs/RESEARCH.md.
extract_plan_section2() {
  file=$1
  awk '
    /^## 2\. WHY/ { grab = 1; next }
    grab && /^## / { grab = 0 }
    grab { print }
  ' "$file" 2>/dev/null || true
}

# check_plan_citation_drift <plan_file> <research_file> — prints the count of author-year style
# citations found in PLAN.md Section 2 that docs/RESEARCH.md does not corroborate.
#
# A "citation" here is deliberately narrow and structural, not a general prose parser: a run of
# capitalized name token(s) (optionally joined by "&"/"and"/"et al.") immediately followed by a
# 4-digit 19xx/20xx year, in parentheses or after a comma — "Cowan, 2010", "Mukherjee et al.,
# 2021", "Sweller & Chandler, 1994", "Gama & Lacerda (2023)", etc. This intentionally does NOT
# try to match every citation format in the file (e.g. the long-form "Name, Name & Name, *Title*,
# Venue YYYY, arXiv:..." references are not all pattern-matched) — extending the pattern's reach
# is a much bigger and more fragile undertaking than this test file should carry. What it reliably
# catches is exactly cycle 2's failure mode: a *new* tight author-year citation added to the plan
# that RESEARCH.md was never updated to carry.
#
# Corroboration is deliberately loose in the other direction: every capitalized name token in the
# citation (skipping the connectors "et"/"al"/"and") and the year itself must each appear
# *somewhere* as a plain substring in docs/RESEARCH.md — not adjacent, not in the same sentence,
# just present. This tolerates PLAN.md's compressed "Name, YYYY" phrasing differing from
# RESEARCH.md's full "Name, I. (YYYY). *Title*..." reference form, while still catching a citation
# whose name or year isn't in RESEARCH.md's evidence base at all.
#
# This check alone is NOT sufficient to catch a retired name resurrected as a live citation: the
# retired name and its original (wrong) year typically DO still appear somewhere in RESEARCH.md —
# in the Corrections prose explaining why the citation was wrong. See
# check_retired_name_violations below for the complementary check that catches that case.
#
# The actual extraction + corroboration logic lives in check_citation_drift_in_text below,
# parameterized on a flat text blob rather than a specific file+section, so this function and
# check_readme_citation_drift (S8: the same drift check extended to README.md) share ONE
# implementation instead of two copies that could themselves drift apart from each other — the
# exact failure class invariant 6e exists to prevent, applied to the test code itself.
check_plan_citation_drift() {
  plan_file=$1
  research_file=$2
  flat=$(extract_plan_section2 "$plan_file" | sed -e 's/\*//g' -e 's/`//g' | tr '\n' ' ')
  check_citation_drift_in_text "$flat" "$research_file"
}

# check_readme_citation_drift <readme_file> <research_file> — the identical check as
# check_plan_citation_drift above, applied to the WHOLE of README.md rather than one named
# section (README.md has no "## 2. WHY"-shaped section to scope to). Unlike PLAN.md Section 2,
# which is guaranteed to carry several author-year citations (it IS the research rationale
# section), README.md legitimately carries zero: the safest README states design rationale and
# links to docs/RESEARCH.md rather than restating individual findings by name and year (see the
# task brief this file's own S8 build step follows). A real-file result of "0 violations" here is
# therefore an expected, non-vacuous pass, not a sign the check found nothing to look at — the
# mutation-proof fixture below is what actually demonstrates the extractor still catches a real
# fabricated citation if one is ever added.
check_readme_citation_drift() {
  readme_file=$1
  research_file=$2
  flat=$(sed -e 's/\*//g' -e 's/`//g' "$readme_file" 2>/dev/null | tr '\n' ' ')
  check_citation_drift_in_text "$flat" "$research_file"
}

# check_citation_drift_in_text <flat_text> <research_file> — prints the count of author-year
# style citations found in <flat_text> that docs/RESEARCH.md does not corroborate. See
# check_plan_citation_drift's comment above for the full rationale (pattern shape, deliberately
# loose corroboration, and known blind spot re: retired names) — this function is that same
# logic, extracted so both callers stay byte-identical in behavior.
check_citation_drift_in_text() {
  flat=$1
  research_file=$2
  bad=0
  research_body=$(cat "$research_file" 2>/dev/null || true)
  matches=$(printf '%s' "$flat" | grep -oE "[A-Z][A-Za-z'.-]+(, [A-Z][A-Za-z'.-]+)*( (&|and) [A-Z][A-Za-z'.-]+)?( et al\.)?,? *\(?(19|20)[0-9][0-9]\)?" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    old_ifs=$IFS
    IFS='
'
    for m in $matches; do
      # Strip a trailing ")" (from a "(YYYY)" style match) so the year is always the literal last
      # 4 characters of $trimmed — done with a fixed substring index, not a regex alternation,
      # because BSD/macOS sed's BRE has no `\|`, and this file must run on both BSD and GNU sh.
      trimmed=$(printf '%s' "$m" | sed 's/)$//')
      tlen=${#trimmed}
      if [ "$tlen" -lt 4 ]; then
        continue
      fi
      year=$(printf '%s' "$trimmed" | awk '{print substr($0, length($0) - 3, 4)}')
      case "$year" in
        19[0-9][0-9] | 20[0-9][0-9]) ;;
        *) continue ;;
      esac
      name_part=${trimmed%"$year"}
      year_found=no
      case "$research_body" in *"$year"*) year_found=yes ;; esac
      all_tokens_found=yes
      old_ifs2=$IFS
      IFS=' ,&'
      for tok in $name_part; do
        tok=$(printf '%s' "$tok" | sed 's/^[.[:space:]]*//; s/[.[:space:]]*$//')
        case "$tok" in
          '') continue ;;
          et | al | and) continue ;;
        esac
        case "$tok" in
          [A-Z]*)
            case "$research_body" in
              *"$tok"*) ;;
              *) all_tokens_found=no ;;
            esac
            ;;
        esac
      done
      IFS=$old_ifs2
      if [ "$year_found" != yes ] || [ "$all_tokens_found" != yes ]; then
        bad=$((bad + 1))
      fi
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# check_retired_name_violations <file> — prints the count of occurrences of a retired/wrong-
# identity name (Karalunas, Salari, Roberts, or a bare "Sweller" not immediately followed by
# "& Chandler") found in a paragraph of $file that does not itself contain a "⚠" correction
# marker anywhere in that paragraph.
#
# Scoping rule and why: paragraphs (blocks of non-blank lines separated by a blank line) are this
# document's own visual unit — PLAN.md Section 2 writes exactly one paragraph per finding, and a
# correction note about a retired name is always woven into the same paragraph as the finding it
# corrects, not set off in its own block. A paragraph containing "⚠" is therefore read as "this
# paragraph is telling the story of a mistake" in its entirety, and every retired name inside it —
# before or after the "⚠" itself — is permitted as part of that story. A paragraph with no "⚠" at
# all gets no such allowance: any retired name there is being used live, which is exactly what
# must stay dead.
#
# Known blind spot, accepted deliberately: because permission is paragraph-wide rather than
# scoped to text immediately around the "⚠", a *new* live citation of a retired name smuggled into
# the SAME paragraph as an existing, legitimate correction note would not be caught by this check
# alone. A narrower rule (e.g. "only within N characters of a ⚠") would close that gap but is
# fragile in the other direction — it would have to be re-tuned by hand every time a correction
# note's wording shifts a retired name's distance from its "⚠", and this file's own house style
# (see extract_section's comment above) prefers a structural boundary over a distance heuristic.
# Paragraph-level scoping is the more robust choice for a document this short and this deliberately
# written; check_plan_citation_drift above is the check that would still catch a wholly new
# fabricated citation smuggled in the same way, just not a resurrected retired one.
check_retired_name_violations() {
  file=$1
  bad=0
  paragraphs=$(awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$file" 2>/dev/null || true)
  if [ -n "$paragraphs" ]; then
    old_ifs=$IFS
    IFS='
'
    for p in $paragraphs; do
      has_warning=no
      case "$p" in *"⚠"*) has_warning=yes ;; esac

      karalunas_cnt=$(printf '%s' "$p" | awk '{print gsub(/Karalunas/, "Karalunas")}')
      salari_cnt=$(printf '%s' "$p" | awk '{print gsub(/Salari/, "Salari")}')
      roberts_cnt=$(printf '%s' "$p" | awk '{print gsub(/Roberts/, "Roberts")}')
      safe=$(printf '%s' "$p" | sed 's/Sweller & Chandler/SAFEMARK/g')
      sweller_cnt=$(printf '%s' "$safe" | awk '{print gsub(/Sweller/, "Sweller")}')

      hits=$((karalunas_cnt + salari_cnt + roberts_cnt + sweller_cnt))
      if [ "$hits" -gt 0 ] && [ "$has_warning" != yes ]; then
        bad=$((bad + hits))
      fi
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# extract_subsection <file> <heading_line> — prints every line strictly between an exact "### "
# (or "## ") heading line and the NEXT line starting with "##" of any level, or EOF. Unlike
# extract_section above (which deliberately treats a "### " line as staying inside a "## "
# section), this is for scoping to a "### " subsection specifically, so it must stop at the next
# heading of either level.
extract_subsection() {
  file=$1
  heading=$2
  awk -v heading="$heading" '
    $0 == heading { grab = 1; next }
    grab && /^##/ { grab = 0 }
    grab { print }
  ' "$file" 2>/dev/null || true
}

# word_to_number <word> — prints the digit for a lowercase English number word ("one" through
# "ten"), or "-1" for anything else. "-1" can never equal a real enumerated-item count, so an
# unrecognized or missing word always registers as a mismatch rather than silently passing.
word_to_number() {
  case "$1" in
    one) echo 1 ;;
    two) echo 2 ;;
    three) echo 3 ;;
    four) echo 4 ;;
    five) echo 5 ;;
    six) echo 6 ;;
    seven) echo 7 ;;
    eight) echo 8 ;;
    nine) echo 9 ;;
    ten) echo 10 ;;
    *) echo -1 ;;
  esac
}

# check_substance_failure_count_ok <file> — prints "yes" if the number word in "found <word>
# citations that were bibliographically correct" (under "### Substance failures found in a second
# verification pass") equals the count of "N. **...**" enumerated items actually present in that
# same subsection; prints "no" otherwise (including when the sentence itself cannot be found).
check_substance_failure_count_ok() {
  file=$1
  raw_section=$(extract_subsection "$file" "### Substance failures found in a second verification pass")
  flat_section=$(printf '%s' "$raw_section" | tr '\n' ' ')
  stated_word=$(printf '%s' "$flat_section" | sed -n 's/.*found \([a-zA-Z]*\) citations that were bibliographically correct.*/\1/p')
  if [ -z "$stated_word" ]; then
    echo no
    return 0
  fi
  stated_count=$(word_to_number "$stated_word")
  actual_count=$(printf '%s\n' "$raw_section" | grep -cE '^[0-9]+\. \*\*' 2>/dev/null || true)
  actual_count=${actual_count:-0}
  if [ "$stated_count" = "$actual_count" ]; then
    echo yes
  else
    echo no
  fi
}

# ------------------------------------------------------------------------------------------------
# Rules-coverage cross-check (S8, review cycle 1, S8-1).
#
# "No rule ships without a citation" was false: only 10 of 16 rules appear in a "Rules justified:"
# line. The fix is not to invent citations for the other six, it is to say so plainly and prove it
# mechanically: every rule number must land in EXACTLY ONE of {cited-by-a-finding,
# named-as-a-design-decision}, and both groups are checked against an explicitly declared expected
# set below (not just against each other), so a silent, simultaneous drift in both places at once
# cannot slip through as "still balances."
# ------------------------------------------------------------------------------------------------

# The two groups this file expects rules/base-rules.md's 16 rules to partition into. Declared
# here, explicitly, rather than derived from anything else — the whole point of this check is to
# catch docs/RESEARCH.md drifting away from a value someone actually decided on.
EXPECTED_CITED_RULES="1 2 3 4 6 7 8 11 14 15"
EXPECTED_DESIGN_RULES="5 9 10 12 13 16"

# extract_all_justified_numbers <file> — prints every distinct rule number that appears in any
# "**Rules justified:** ..." line in <file>, numerically sorted and space-joined. Shares the same
# extraction pattern as check_rule_ref_violations above, but collects the full de-duplicated SET
# rather than counting violations against rules/base-rules.md.
extract_all_justified_numbers() {
  file=$1
  lines=$(grep -oE '^\*\*Rules justified:\*\* [0-9]+([, ]+[0-9]+)*' "$file" 2>/dev/null || true)
  result=""
  if [ -n "$lines" ]; then
    old_ifs=$IFS
    IFS='
'
    for line in $lines; do
      numlist=${line#\*\*Rules justified:\*\* }
      old_ifs2=$IFS
      IFS=','
      for tok in $numlist; do
        tok=$(printf '%s' "$tok" | sed 's/^[ \t]*//; s/[ \t]*$//')
        case "$tok" in
          '' | *[!0-9]*) continue ;;
        esac
        result="$result $tok"
      done
      IFS=$old_ifs2
    done
    IFS=$old_ifs
  fi
  printf '%s\n' "$result" | tr ' ' '\n' | sed '/^$/d' | sort -nu | tr '\n' ' ' | sed 's/ *$//'
}

# extract_design_decision_numbers <file> — prints every distinct rule number named as
# "- **Rule N (...)**" under the "## Rules with no research claim behind them" section of <file>,
# numerically sorted and space-joined.
extract_design_decision_numbers() {
  file=$1
  section=$(extract_section "$file" "## Rules with no research claim behind them")
  nums=$(printf '%s\n' "$section" | grep -oE '^- \*\*Rule [0-9]+' | grep -oE '[0-9]+' || true)
  printf '%s\n' "$nums" | sed '/^$/d' | sort -nu | tr '\n' ' ' | sed 's/ *$//'
}

# check_rule_partition <cited_list> <design_list> <all_list> — prints "ok" if every number in
# <all_list> (space-separated) appears in EXACTLY ONE of <cited_list>/<design_list>; otherwise
# prints a one-line description of the first rule number found in both, or in neither.
check_rule_partition() {
  cited=$1
  design=$2
  all=$3
  problem=""
  old_ifs=$IFS
  IFS=' '
  for n in $all; do
    in_cited=no
    in_design=no
    for c in $cited; do
      [ "$c" = "$n" ] && in_cited=yes
    done
    for d in $design; do
      [ "$d" = "$n" ] && in_design=yes
    done
    if [ "$in_cited" = yes ] && [ "$in_design" = yes ]; then
      problem="rule $n is in BOTH groups"
      break
    fi
    if [ "$in_cited" = no ] && [ "$in_design" = no ]; then
      problem="rule $n is in NEITHER group"
      break
    fi
  done
  IFS=$old_ifs
  if [ -z "$problem" ]; then
    echo ok
  else
    echo "$problem"
  fi
}

# ------------------------------------------------------------------------------------------------
# T1 fix (S8 review cycle 2 BLOCKER). The absolute "every rule traces to a finding" claim survived
# cycle 1's fix in three MORE files (CONTEXT.md, PLAN.md twice) because the old guard was two
# hardcoded exact strings, checked against two hardcoded filenames. Both halves are rewritten
# below: the DETECTOR is broadened from two literal strings into a co-occurrence class, and the
# DRIVER (check_absolute_rule_claim_all_md, further down) scans every tracked Markdown file by
# default instead of a named pair.
# ------------------------------------------------------------------------------------------------

# check_absolute_rule_claim_present <file> — prints the count of PARAGRAPHS (blocks of non-blank
# lines, the same unit check_retired_name_violations above uses) in <file> that pair an absolute
# rule-coverage quantifier with a traceability/evidence term, case-insensitively:
#
#   quantifier — "every rule", "each rule", "each one traces", "all rules", "no rule ships without"
#   evidence   — "trace" (also matches traces/traced/traceability), "finding", "citation", "research"
#
# This is the general SHAPE of the false absolute this project has now shipped five times across
# two review cycles ("Every rule ... traces to a finding", "Each rule traces to a specific research
# finding", "Each one traces to a specific research finding", "No rule ships without a citation
# ..."), not just the original two exact strings.
#
# What this DOES NOT guarantee, stated plainly: this is a tripwire over vocabulary, not a proof of
# falsehood. It cannot distinguish a false absolute from a true statement that happens to share the
# same words — which is exactly why PLAN.md's and CONTEXT.md's rewritten sentences (this cycle's
# T1 fix) route AROUND the five quantifiers by construction ("10 of the 16 rules trace...", "Most
# trace...", "Rules in this document are either...") rather than being exempted after the fact. A
# future paraphrase using a sixth quantifier this list does not enumerate (e.g. "every single rule",
# "not a single rule ships uncited") would not be caught: enumerating every possible English
# quantifier is not a grep/awk problem, and this check does not claim to solve it.
#
# Paragraph-level scoping is used here to match this file's other structural checks, and is
# coarser than sentence-level: a hypothetical future
# paragraph that legitimately discusses "research" in one sentence and, elsewhere in the SAME
# paragraph, uses one of the five quantifier phrases in an unrelated, safe way would false-positive.
# That has not happened anywhere in this repo as of this fix — every real, repo-wide occurrence of
# the five quantifier phrases was one of the five now-corrected false absolutes, confirmed by grep
# before this fix shipped — and paragraph-level is the same tradeoff check_retired_name_violations
# above already accepts, for the same reason (a structural boundary over a distance heuristic).
check_absolute_rule_claim_present() {
  file=$1
  bad=0
  paragraphs=$(awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$file" 2>/dev/null || true)
  if [ -n "$paragraphs" ]; then
    old_ifs=$IFS
    IFS='
'
    for p in $paragraphs; do
      lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
      has_quantifier=no
      case "$lower" in
        *"every rule"* | *"each rule"* | *"each one traces"* | *"all rules"* | *"no rule ships without"*)
          has_quantifier=yes
          ;;
      esac
      has_evidence_term=no
      case "$lower" in
        *"trace"* | *"finding"* | *"citation"* | *"research"*)
          has_evidence_term=yes
          ;;
      esac
      if [ "$has_quantifier" = yes ] && [ "$has_evidence_term" = yes ]; then
        bad=$((bad + 1))
      fi
    done
    IFS=$old_ifs
  fi
  echo "$bad"
}

# ABSOLUTE_CLAIM_EXEMPT_FILES — repo-relative paths (newline-separated) allowed to contain the
# check_absolute_rule_claim_present pattern, and why each one is there. Empty today: no shipped
# file needs this phrasing — PLAN.md's and CONTEXT.md's own rewritten sentences route around the
# tripwire by construction (see the comment above), not by exemption. Declared as a real, checked
# value rather than left as a comment specifically so it cannot grow silently:
# EXPECTED_ABSOLUTE_CLAIM_EXEMPT below is asserted equal to it, so adding a filename here without
# a matching, visible update to that expected constant fails the suite instead of quietly taking a
# file out of scope — the exact "silent allowlist growth" failure mode that let T1 happen at all.
ABSOLUTE_CLAIM_EXEMPT_FILES=""

# EXPECTED_ABSOLUTE_CLAIM_EXEMPT — declared independently of ABSOLUTE_CLAIM_EXEMPT_FILES (not
# derived from it) so the assertion comparing the two actually proves something: if this were
# `EXPECTED_ABSOLUTE_CLAIM_EXEMPT="$ABSOLUTE_CLAIM_EXEMPT_FILES"`, the two would be equal by
# construction and the check below would pass no matter what either one said.
EXPECTED_ABSOLUTE_CLAIM_EXEMPT=""

# file_is_absolute_claim_exempt <repo-relative-path> <exempt-list> — prints "yes"/"no". The exempt
# list is passed in explicitly, not read from the global, so the git-repo round-trip proof further
# down can exercise the skip branch with a temporary, test-local list without touching the real
# ABSOLUTE_CLAIM_EXEMPT_FILES the rest of this file relies on.
file_is_absolute_claim_exempt() {
  needle=$1
  list=$2
  found=no
  old_ifs=$IFS
  IFS='
'
  for f in $list; do
    [ "$f" = "$needle" ] && found=yes
  done
  IFS=$old_ifs
  echo "$found"
}

# ------------------------------------------------------------------------------------------------
# U2 fix (S8 review cycle 3 BLOCKER). check_absolute_rule_claim_all_md below scanned
# `git ls-files '*.md'` only. targets/cursor/squirrel-mode.mdc is a tracked, markdown-family,
# GENERATED file with a DIFFERENT extension — the one file the '*.md' glob structurally cannot
# match — and it carries a static, hand-written sentence with no source in rules/base-rules.md
# (scripts/build.sh's write_cursor_mdc). The previous fixer argued this file's prose was all
# derived from rules/base-rules.md and therefore already covered by scanning that file; that
# argument is false, proven by injecting a false absolute into write_cursor_mdc's own literal,
# rebuilding, and watching the suite stay green (see the DoD proof this fix ships with).
#
# The fix widens the glob, but doing that by simply adding a second hardcoded '*.mdc' string would
# repeat cycle 1's original mistake one level up: a hardcoded EXTENSION list is exactly as brittle
# as cycle 1's hardcoded FILENAME list was, just at a different granularity. So this file declares
# the covered extensions as a real, checked constant (MARKDOWN_FAMILY_EXTENSIONS, immediately
# below) and separately, permanently watches for a tracked file with an UNCOVERED markdown-family
# extension ever appearing (check_uncovered_markdown_extensions, further below) — so a future
# ".mdx", ".markdown", or ".mkd" file fails this suite loudly the moment it is added, instead of
# silently falling through the same gap ".mdc" just fell through for an entire review cycle.
# ------------------------------------------------------------------------------------------------

# MARKDOWN_FAMILY_EXTENSIONS — every file extension (no leading dot, space-separated) this repo's
# absolute-claim scan treats as "markdown-family" and therefore scans. Extend this list, together
# with EXPECTED at check_uncovered_markdown_extensions' call site further down, the moment a
# tracked file with a new markdown-family extension is added on purpose.
MARKDOWN_FAMILY_EXTENSIONS="md mdc"

# check_uncovered_markdown_extensions <repo_root> <covered-extensions> — prints every DISTINCT
# extension, among ALL tracked files in <repo_root>, that looks markdown-family (its extension,
# lower-cased, contains the substring "md" — matching .md, .mdc, .markdown, .mdown, .mkd, .mkdn,
# .mdx, and similar) but is NOT already listed in <covered-extensions>. Empty output means
# MARKDOWN_FAMILY_EXTENSIONS above still covers every markdown-family file actually tracked. This
# is the "assert explicitly which extensions are covered, and fail if an uncovered one appears"
# half of the U2 fix: rather than trying to enumerate every markdown-adjacent extension that could
# ever exist (not a solvable grep/awk problem, and not attempted), it watches for one showing up
# UNCOVERED and fails loudly the moment it does.
check_uncovered_markdown_extensions() {
  repo_root=$1
  covered=$2
  bad=""
  files=$(git -C "$repo_root" ls-files 2>/dev/null || true)
  old_ifs=$IFS
  IFS='
'
  for f in $files; do
    case "$f" in
      *.*) ext=${f##*.} ;;
      *) continue ;;
    esac
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
      *md*) ;;
      *) continue ;;
    esac
    is_covered=no
    # $covered ("md mdc", ...) is space-separated, but IFS is newline-only here (for the outer
    # file loop above) - switch to space just for this inner split, then back to newline
    # immediately after, or every entry in $covered collapses into a single word and this loop
    # never matches anything real, wrongly flagging every already-covered extension as uncovered.
    IFS=' '
    for c in $covered; do
      [ "$c" = "$ext" ] && is_covered=yes
    done
    IFS='
'
    if [ "$is_covered" = no ]; then
      case " $bad " in
        *" $ext "*) ;;
        *) bad="$bad $ext" ;;
      esac
    fi
  done
  IFS=$old_ifs
  printf '%s\n' "$bad" | sed 's/^ *//; s/ *$//'
}

# check_absolute_rule_claim_all_md <repo_root> <exempt-list> — prints two lines:
#   BAD_COUNT=<n>   the number of scanned, non-exempt markdown-family files with a nonzero
#                   check_absolute_rule_claim_present count
#   SCANNED=<space-joined list of every scanned file path the scan considered, exempt or not>
# Scans `git -C <repo_root> ls-files` once per extension in $MARKDOWN_FAMILY_EXTENSIONS (currently
# "*.md" and "*.mdc") — every tracked markdown-family file — rather than a hardcoded list. This is
# the actual T1 structural fix, widened again by U2: cycle 1 hardcoded README.md and
# docs/RESEARCH.md; cycle 2's three new violations landed in exactly the files that list omitted;
# cycle 3's found that the widened-but-still-'*.md'-only glob itself omitted a whole EXTENSION
# (targets/cursor/squirrel-mode.mdc). A file or extension this scan does not enumerate is a file or
# extension that reverts to that same class of bug.
check_absolute_rule_claim_all_md() {
  repo_root=$1
  exempt_list=$2
  bad_files=0
  scanned=""
  files=""
  old_ifs=$IFS
  for ext in $MARKDOWN_FAMILY_EXTENSIONS; do
    ext_files=$(git -C "$repo_root" ls-files "*.$ext" 2>/dev/null || true)
    if [ -n "$ext_files" ]; then
      files="$files
$ext_files"
    fi
  done
  IFS='
'
  for relpath in $files; do
    [ -z "$relpath" ] && continue
    scanned="$scanned $relpath"
    if [ "$(file_is_absolute_claim_exempt "$relpath" "$exempt_list")" = yes ]; then
      continue
    fi
    count=$(check_absolute_rule_claim_present "$repo_root/$relpath")
    if [ "$count" -gt 0 ]; then
      bad_files=$((bad_files + 1))
    fi
  done
  IFS=$old_ifs
  printf 'BAD_COUNT=%s\n' "$bad_files"
  printf 'SCANNED=%s\n' "$(printf '%s' "$scanned" | sed 's/^ *//')"
}

# RETIRED_SUCCESS_AMNESIA_PHRASES — the exact phrases (newline-separated) check_retired_success_
# amnesia_phrasing below bans from README.md: the literal phrase "blurs the memory of one's own
# accomplishments", the literal phrase "success amnesia", or the fragment "own recent progress"
# (which catches the specific "own recent progress ... unprompted" construction the S8-2 BLOCKER
# review found, and any close rewording of the same sentence, without needing to match the whole
# retired sentence verbatim). Declared as a named constant, not inline literals, specifically so a
# failure message can point at "RETIRED_SUCCESS_AMNESIA_PHRASES in tests/test_research.sh" as the
# one concrete place to look — see the U4 fix note directly below for why this exact-phrase list is
# now this project's ONLY mechanical defense against a resurrected retired claim.
RETIRED_SUCCESS_AMNESIA_PHRASES="blurs the memory of one's own accomplishments
success amnesia
own recent progress"

# ------------------------------------------------------------------------------------------------
# U4 fix (S8 review cycle 3 MAJOR). A broader co-occurrence tripwire used to sit alongside this
# exact-phrase check (any sentence pairing an ADHD/memory term with an own-work term, one sentence
# exempted by name). It was DELETED, not narrowed, after a six-sentence fixture — four legitimate
# sentences that must pass, plus the reviewer's paraphrase and the original retired sentence that
# must fail — proved no term list threads the needle:
#   - Any own-work vocabulary broad enough to catch the reviewer's paraphrase ("...unable to recall
#     how much they've already gotten done...", which shares essentially no vocabulary with the
#     retired sentence) is also broad enough to flag ordinary, correct prose about the Done log or
#     /squirrel:pickup ("remembering where you left off", "recent wins", "your own progress").
#   - Narrowing the own-work vocabulary down to words unique to the retired sentence itself
#     ("accomplishments", "success amnesia", ...) stops flagging that ordinary prose, but ALSO stops
#     catching the paraphrase entirely (it shares none of those words) — and, independent of any
#     tuning, still wrongly flags a CORRECTLY HEDGED restatement of Finding 8 that explicitly
#     distinguishes it from the retired claim, because such a sentence must NAME the retired claim's
#     own vocabulary in order to reject it. No bag-of-words check can tell "citing a claim to reject
#     it" from "asserting that claim" apart — that is a structural limit of grep/awk pattern
#     matching, not a tuning problem, and no amount of narrowing removes it.
# What actually guarantees README.md's research claims stay accurate is PLAN.md Section 2's
# four-check citation policy (identity, support, whose finding it is, population), applied by a
# human reviewer reading the paper's own text — not a grep tripwire. The exact-phrase ban above is
# the honest, narrower thing this file can still mechanically guarantee: it kills the ONE retired
# sentence dead, in all three of its known phrasings, forever. A future paraphrase carrying the same
# retired inference in yet other words is a review-time catch, not a test-suite one.
# ------------------------------------------------------------------------------------------------
check_retired_success_amnesia_phrasing() {
  file=$1
  body=$(cat "$file" 2>/dev/null || true)
  bad=0
  old_ifs=$IFS
  IFS='
'
  for phrase in $RETIRED_SUCCESS_AMNESIA_PHRASES; do
    case "$body" in
      *"$phrase"*) bad=$((bad + 1)) ;;
    esac
  done
  IFS=$old_ifs
  echo "$bad"
}

# ================================================================================================
# 1. docs/RESEARCH.md exists and is non-empty.
# ================================================================================================
assert_file_exists "$research_file" "docs/RESEARCH.md must exist"
if [ -s "$research_file" ]; then
  research_nonempty=yes
else
  research_nonempty=no
fi
assert_eq "yes" "$research_nonempty" "docs/RESEARCH.md must be non-empty"

# ================================================================================================
# 2. Every population tag used is from the allowed set of three. Checked against the real file
#    (expect 0), then against a fixture with an invented tag appended (expect >0).
# ================================================================================================
real_population_bad=$(check_population_violations "$research_file")
assert_eq "0" "$real_population_bad" "every population tag in the real file must be one of the three allowed strings"

population_fixture="$scratch_dir/bad_population.md"
cp "$research_file" "$population_fixture"
printf '\n**Population:** hyperfocus superpower\n' >>"$population_fixture"
fixture_population_bad=$(check_population_violations "$population_fixture")
assert_eq "1" "$fixture_population_bad" "FAILURE PROOF (scenario 2): an invented population tag must be caught"

# ================================================================================================
# 3. Every "## Finding" section has at least one population tag.
# ================================================================================================
findings_missing_population=$(check_findings_missing_population "$research_file")
assert_eq "0" "$findings_missing_population" "every '## Finding' section must carry at least one population tag"

# ================================================================================================
# 4. Every citation line carries a year (4 digits) and a link (http). Checked against the real
#    file (expect 0), then against a fixture with a linkless, yearless citation (expect >0).
# ================================================================================================
real_citation_bad=$(check_citation_violations "$research_file")
assert_eq "0" "$real_citation_bad" "every citation line in the real file must carry a 4-digit year and an http link"

citation_fixture="$scratch_dir/bad_citation.md"
cp "$research_file" "$citation_fixture"
printf '\n**Citations:**\n- Nobody, N. Nothing ever published, no year, no link.\n' >>"$citation_fixture"
fixture_citation_bad=$(check_citation_violations "$citation_fixture")
assert_eq "1" "$fixture_citation_bad" "FAILURE PROOF (scenario 4): a citation with no year and no link must be caught"

# ================================================================================================
# 5. Every base-rule number referenced exists in rules/base-rules.md, parsed from that file.
#    Checked against the real file (expect 0), then against a fixture referencing rule 17,
#    which does not exist (expect >0).
# ================================================================================================
# Sanity check on the parse itself: rules/base-rules.md must have yielded a non-empty,
# plausible set of rule numbers, or the "no violations" result below would be vacuously true
# for the wrong reason (nothing to compare against, rather than everything actually valid).
valid_rule_count=0
for _v in $valid_rule_numbers; do
  valid_rule_count=$((valid_rule_count + 1))
done
if [ "$valid_rule_count" -gt 0 ]; then
  valid_rules_nonempty=yes
else
  valid_rules_nonempty=no
fi
assert_eq "yes" "$valid_rules_nonempty" "parsing rule numbers out of rules/base-rules.md must yield at least one number (vacuous-pass guard)"
assert_eq "no" "$(rule_number_is_valid 17)" "rule 17 must not exist in rules/base-rules.md (this repo defines exactly 16 rules)"

real_rule_ref_bad=$(check_rule_ref_violations "$research_file")
assert_eq "0" "$real_rule_ref_bad" "every rule number referenced in the real file must exist in rules/base-rules.md"

rule_fixture="$scratch_dir/bad_rule.md"
cp "$research_file" "$rule_fixture"
printf '\n**Rules justified:** 17 — a rule that does not exist.\n' >>"$rule_fixture"
fixture_rule_bad=$(check_rule_ref_violations "$rule_fixture")
assert_eq "1" "$fixture_rule_bad" "FAILURE PROOF (scenario 5): a reference to rule 17 must be caught"

# ================================================================================================
# 6. The three corrections are present: Liebel is named first author of 2312.05029, 2511.14636's
#    population is identified as blind and low-vision, and the interruption figure is attributed
#    correctly (to Gloria Mark, never to the APA) or omitted entirely.
# ================================================================================================
research_body=$(cat "$research_file")
assert_contains "$research_body" "Liebel, G., Langlois, N., & Gama, K." "the file must name Liebel as first author (Langlois second, Gama third) for arXiv:2312.05029"
assert_contains "$research_body" "arXiv:2511.14636" "the file must reference arXiv:2511.14636"
assert_contains "$research_body" "blind and low-vision" "the file must identify arXiv:2511.14636's population as blind and low-vision"

real_interruption_ok=$(check_interruption_figure_ok "$research_file")
assert_eq "yes" "$real_interruption_ok" "the interruption-recovery figure must be attributed correctly (to Gloria Mark, never the APA) or omitted"

# Failure proof, variant A: the figure kept, but its only attribution stripped out.
interruption_fixture_a="$scratch_dir/bad_interruption_a.md"
sed 's/Gloria Mark/Someone Else Entirely/g' "$research_file" >"$interruption_fixture_a"
fixture_a_ok=$(check_interruption_figure_ok "$interruption_fixture_a")
assert_eq "no" "$fixture_a_ok" "FAILURE PROOF (scenario 6, variant A): the 23-minute figure with no Gloria Mark attribution must be caught"

# Failure proof, variant B: a false APA attribution introduced.
interruption_fixture_b="$scratch_dir/bad_interruption_b.md"
cp "$research_file" "$interruption_fixture_b"
printf '\nThe APA published the 23 minute recovery figure as an original finding.\n' >>"$interruption_fixture_b"
fixture_b_ok=$(check_interruption_figure_ok "$interruption_fixture_b")
assert_eq "no" "$fixture_b_ok" "FAILURE PROOF (scenario 6, variant B): a false APA attribution must be caught"

# ================================================================================================
# 7. No TODO:/FIXME:/XXX: marker and no bare "[citation needed]"-style placeholder.
# ================================================================================================
marker_hit=$(grep -cE '(TODO|FIXME|XXX)[:(]' "$research_file" 2>/dev/null || true)
marker_hit=${marker_hit:-0}
assert_eq "0" "$marker_hit" "docs/RESEARCH.md must contain no TODO:/FIXME:/XXX: marker"

placeholder_hit=$(grep -icE '\[citation needed\]' "$research_file" 2>/dev/null || true)
placeholder_hit=${placeholder_hit:-0}
assert_eq "0" "$placeholder_hit" "docs/RESEARCH.md must contain no bare [citation needed]-style placeholder"

# ================================================================================================
# 8. A "What we could not verify" section exists.
# ================================================================================================
verify_section_hit=$(grep -c '^## What we could not verify$' "$research_file" 2>/dev/null || true)
verify_section_hit=${verify_section_hit:-0}
assert_eq "1" "$verify_section_hit" "docs/RESEARCH.md must contain exactly one 'What we could not verify' section heading"

# ================================================================================================
# 9. No arXiv ID appears in a malformed shape. Checked against the real file (expect 0), then
#    against a fixture with a 3-digit-prefix arXiv ID appended (expect >0).
# ================================================================================================
real_arxiv_bad=$(check_arxiv_violations "$research_file")
assert_eq "0" "$real_arxiv_bad" "every arXiv: reference in the real file must match the NNNN.NNNNN shape"

arxiv_fixture="$scratch_dir/bad_arxiv.md"
cp "$research_file" "$arxiv_fixture"
printf '\nSee also arXiv:231.05029 for a related discussion.\n' >>"$arxiv_fixture"
fixture_arxiv_bad=$(check_arxiv_violations "$arxiv_fixture")
assert_eq "1" "$fixture_arxiv_bad" "FAILURE PROOF (scenario 9): a malformed arXiv ID (3-digit prefix) must be caught"

# ================================================================================================
# 10. docs/ contains no stray files beyond ACCEPTANCE.md, OTHER-TOOLS.md, RESEARCH.md and adr/.
# ================================================================================================
if [ -d "$docs_dir" ]; then
  docs_listing=""
  for entry in "$docs_dir"/* "$docs_dir"/.[!.]* "$docs_dir"/..?*; do
    if [ -e "$entry" ]; then
      docs_listing="$docs_listing $(basename "$entry")"
    fi
  done
  docs_listing=$(printf '%s\n' "$docs_listing" | tr -s ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//')
else
  docs_listing="<directory missing>"
fi
# OTHER-TOOLS.md is S7's deliverable and ACCEPTANCE.md is S9's, both named in PLAN.md's repository
# layout / this build's own acceptance sweep. The point of this assertion is that nothing
# UNEXPECTED lands in docs/, not that the set never grows -- so the expected set is stated here
# and a genuinely stray file still fails.
assert_eq "ACCEPTANCE.md OTHER-TOOLS.md RESEARCH.md adr" "$docs_listing" "docs/ must contain exactly ACCEPTANCE.md, OTHER-TOOLS.md, RESEARCH.md and adr/, nothing else"

# ================================================================================================
# 11. The citation policy section names all four checks (identity, support, whose finding it is,
#     population) and states plainly that identity alone is not verification. Checked against the
#     real file (expect 0 missing), then against a fixture with the word "Support" scrubbed from
#     the whole file, which removes it from the policy section too (expect >0 missing).
# ================================================================================================
real_policy_missing=$(check_citation_policy_four_checks "$research_file")
assert_eq "0" "$real_policy_missing" "the citation policy section must name all four checks and state identity alone is not verification"

policy_fixture="$scratch_dir/bad_policy.md"
sed 's/[Ss]upport/xxx/g' "$research_file" >"$policy_fixture"
fixture_policy_missing=$(check_citation_policy_four_checks "$policy_fixture")
assert_eq "1" "$fixture_policy_missing" "FAILURE PROOF (scenario 11): a citation policy section missing the support check must be caught"

# ================================================================================================
# 12. No finding cites Sweller (1988) for the intrinsic/extraneous distinction — or for anything
#     else: this file established it does not fit any claim in it, so no citation bullet may cite
#     Sweller with year 1988 at all. Checked against the real file (expect 0), then against a
#     fixture with such a citation bullet appended (expect >0).
# ================================================================================================
real_sweller1988_bad=$(check_sweller_1988_citation_entries "$research_file")
assert_eq "0" "$real_sweller1988_bad" "no citation bullet in the real file may cite Sweller (1988)"

sweller_fixture="$scratch_dir/bad_sweller1988.md"
cp "$research_file" "$sweller_fixture"
printf '\n**Citations:**\n- Sweller, J. (1988). *Cognitive Load During Problem Solving: Effects on Learning*. Cognitive Science, 12(2), 257-285. <https://onlinelibrary.wiley.com/doi/10.1207/s15516709cog1202_4>\n' >>"$sweller_fixture"
fixture_sweller1988_bad=$(check_sweller_1988_citation_entries "$sweller_fixture")
assert_eq "1" "$fixture_sweller1988_bad" "FAILURE PROOF (scenario 12): a re-added Sweller (1988) citation bullet must be caught"

# ================================================================================================
# 13. Finding 1's ADHD sentence matches the corrected, load-sensitivity claim — asserted as
#     specific text, not just "a citation exists" — so a future edit cannot silently restore the
#     version its own cited paper's abstract contradicts. Checked against the real file (expect
#     "yes"), then against a fixture with the old, contradicted sentence appended (expect "no").
# ================================================================================================
real_finding1_ok=$(check_finding1_adhd_claim_ok "$research_file")
assert_eq "yes" "$real_finding1_ok" "Finding 1's ADHD sentence must be the corrected load-sensitivity claim, with the old contradicted framing absent"

finding1_fixture="$scratch_dir/bad_finding1.md"
cp "$research_file" "$finding1_fixture"
printf '\nAdults with ADHD show reduced working-memory accuracy across load conditions, and that reduction worsens as load increases.\n' >>"$finding1_fixture"
fixture_finding1_ok=$(check_finding1_adhd_claim_ok "$finding1_fixture")
assert_eq "no" "$fixture_finding1_ok" "FAILURE PROOF (scenario 13): silently restoring the old contradicted ADHD sentence must be caught"

# ================================================================================================
# 14. Finding 11 does not contain "well established" — the phrase its own cited scoping review
#     contradicts. Checked against the real file (expect absent), then against a fixture with the
#     phrase reintroduced (expect the assertion helper itself to report a failure, proving the
#     substring check is not vacuous).
# ================================================================================================
assert_not_contains "$research_body" "well established" "docs/RESEARCH.md must not contain the phrase 'well established' anywhere (Finding 11's own citation contradicts it)"

# Failure proof, run in a subshell so its deliberately-triggered FAIL does not pollute this
# file's real ASSERT_PASS_COUNT/ASSERT_FAIL_COUNT or its exit code: reintroduce the phrase into a
# copy of the real content and confirm assert_not_contains itself reports FAIL on it.
proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  fixture_body="$research_body

well established, for this proof fixture only"
  assert_not_contains "$fixture_body" "well established" "proof check"
) )
case "$proof_output" in
  *"FAIL:"*) fixture_well_established_caught=yes ;;
  *) fixture_well_established_caught=no ;;
esac
assert_eq "yes" "$fixture_well_established_caught" "FAILURE PROOF (scenario 14): reintroducing 'well established' must be caught by assert_not_contains"

# Finding 5's heading specifically must not overclaim either: "well documented" sits one register
# below "well established," but its own two citations are practitioner pieces, not controlled
# trials, so the heading must not read as stronger than that.
finding5_heading=$(grep '^## Finding 5:' "$research_file" 2>/dev/null | head -n 1 || true)
assert_contains "$finding5_heading" "Finding 5" "docs/RESEARCH.md must contain a '## Finding 5:' heading line (sanity check so the two assertions below are not vacuous)"
assert_not_contains "$finding5_heading" "well established" "Finding 5's heading must not contain 'well established'"
assert_not_contains "$finding5_heading" "well documented" "Finding 5's heading must not contain 'well documented' (this cycle's fix: reworded to 'widely recommended')"

# Failure proof: the assert_not_contains helper itself must report FAIL when a corrupted heading
# contains the phrase — run in the same subshell-isolated style as the proof above.
proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  bad_heading="## Finding 5: Instructional accommodations for ADHD are well documented"
  assert_not_contains "$bad_heading" "well documented" "proof check"
) )
case "$proof_output" in
  *"FAIL:"*) fixture_well_documented_caught=yes ;;
  *) fixture_well_documented_caught=no ;;
esac
assert_eq "yes" "$fixture_well_documented_caught" "FAILURE PROOF (scenario 14b): a Finding 5 heading reading 'well documented' must be caught by assert_not_contains"

# ================================================================================================
# 15. The Corrections section records the five pre-existing identity misattributions AND the four
#     substance failures from the second verification pass (Finding 1/Roberts, Finding 7/Gama &
#     Lacerda, Finding 4/Sweller-1988, Finding 11/contradicted framing). Checked against the real
#     file (expect 0 missing), then against a fixture with "intrinsic" scrubbed file-wide, which
#     breaks the Sweller-1988 substance-failure marker (expect >0 missing).
# ================================================================================================
real_corrections_missing=$(check_corrections_records_failures "$research_file")
assert_eq "0" "$real_corrections_missing" "the Corrections section must record all five identity misattributions and all four substance failures"

corrections_fixture="$scratch_dir/bad_corrections.md"
sed 's/intrinsic/xxx/g' "$research_file" >"$corrections_fixture"
fixture_corrections_missing=$(check_corrections_records_failures "$corrections_fixture")
assert_eq "1" "$fixture_corrections_missing" "FAILURE PROOF (scenario 15): a Corrections section missing the Sweller-1988 substance failure must be caught"

# ================================================================================================
# 16. PLAN.md <-> docs/RESEARCH.md drift check, part A: every author-year style citation
#     extracted from PLAN.md Section 2 is corroborated (name token(s) and year, each as a
#     substring) somewhere in docs/RESEARCH.md. Checked against the real PLAN.md (expect 0), then
#     against a scratch copy of PLAN.md with a brand-new, wholly fabricated citation inserted into
#     Section 2 (expect >0). This is the mechanism that makes cycle 2's actual failure — PLAN.md
#     asserting something RESEARCH.md does not carry — fail a test run instead of a reviewer's
#     memory.
# ================================================================================================
assert_file_exists "$plan_file" "PLAN.md must exist for the drift check"

real_plan_citation_bad=$(check_plan_citation_drift "$plan_file" "$research_file")
assert_eq "0" "$real_plan_citation_bad" "every author-year citation in PLAN.md Section 2 must be corroborated (name and year) somewhere in docs/RESEARCH.md"

# Sanity check on the extractor itself, so "0 violations" above cannot be a vacuous pass from an
# extraction pattern that silently matches nothing: PLAN.md Section 2 must yield at least one
# extracted citation to check in the first place.
plan_citation_sample=$(extract_plan_section2 "$plan_file" | sed -e 's/\*//g' -e 's/`//g' | tr '\n' ' ' | grep -oE "[A-Z][A-Za-z'.-]+(, [A-Z][A-Za-z'.-]+)*( (&|and) [A-Z][A-Za-z'.-]+)?( et al\.)?,? *\(?(19|20)[0-9][0-9]\)?" 2>/dev/null | wc -l | tr -d ' ')
plan_citation_sample=${plan_citation_sample:-0}
if [ "$plan_citation_sample" -gt 0 ]; then
  plan_citations_nonempty=yes
else
  plan_citations_nonempty=no
fi
assert_eq "yes" "$plan_citations_nonempty" "extracting author-year citations from PLAN.md Section 2 must yield at least one (vacuous-pass guard for scenario 16)"

# FAILURE PROOF (scenario 16): insert a wholly fabricated citation into a scratch copy of PLAN.md
# Section 2 (before the "## 3. HOW" boundary, so it lands inside the extracted section) and
# confirm the drift check catches it. Fitzgerald/Owusu/2019 appear nowhere in docs/RESEARCH.md.
plan_citation_fixture="$scratch_dir/bad_plan_citation.md"
awk '
  /^## 3\. HOW/ && !done {
    print "**A fabricated finding.** `ADHD`"
    print "Some new effect was found (Fitzgerald & Owusu, 2019, *Journal of Nowhere*)."
    print ""
    done = 1
  }
  { print }
' "$plan_file" >"$plan_citation_fixture"
fixture_plan_citation_bad=$(check_plan_citation_drift "$plan_citation_fixture" "$research_file")
assert_eq "1" "$fixture_plan_citation_bad" "FAILURE PROOF (scenario 16): a PLAN.md citation absent from docs/RESEARCH.md must be caught"

# ================================================================================================
# 17. PLAN.md <-> docs/RESEARCH.md drift check, part B: a retired/wrong-identity name (Karalunas,
#     Salari, Roberts, or a bare "Sweller" not immediately followed by "& Chandler") must not
#     appear anywhere in PLAN.md except inside a paragraph carrying its own "⚠" correction marker.
#     Checked against the real PLAN.md (expect 0 — every current occurrence sits inside the
#     correction paragraph that names it as a past mistake), then against a scratch copy with a
#     brand-new paragraph, carrying no "⚠", that cites "Roberts, Milich & Fillmore, 2012" and
#     "Sweller, 1988" as if they were live evidence (expect >0). Complements scenario 16: check 16
#     alone would not catch this, because both retired names and their original years already
#     appear somewhere in docs/RESEARCH.md's own Corrections prose.
# ================================================================================================
real_retired_name_bad=$(check_retired_name_violations "$plan_file")
assert_eq "0" "$real_retired_name_bad" "no retired name (Karalunas/Salari/Roberts/bare Sweller) may appear live in PLAN.md outside a ⚠-marked correction paragraph"

retired_name_fixture="$scratch_dir/bad_plan_retired_name.md"
awk '
  /^## 3\. HOW/ && !done {
    print "**A resurrected finding.** `ADHD`"
    print "Working memory declines with load (Roberts, Milich & Fillmore, 2012). Also (Sweller, 1988)."
    print ""
    done = 1
  }
  { print }
' "$plan_file" >"$retired_name_fixture"
fixture_retired_name_bad=$(check_retired_name_violations "$retired_name_fixture")
assert_eq "2" "$fixture_retired_name_bad" "FAILURE PROOF (scenario 17): a retired name (Roberts) and a bare Sweller used as live citations outside a ⚠ paragraph must both be caught"

# ================================================================================================
# 18. The Corrections section's stated substance-failure count equals the number of "N. **...**"
#     enumerated items actually present under "### Substance failures found in a second
#     verification pass" — the exact bug this cycle fixed (prose said "four," list had five items).
#     Checked against the real file (expect "yes"), then against a fixture with the count word
#     reverted to "four" while the five-item list stays intact (expect "no").
# ================================================================================================
real_substance_count_ok=$(check_substance_failure_count_ok "$research_file")
assert_eq "yes" "$real_substance_count_ok" "the stated substance-failure count must equal the number of enumerated items under that subheading"

substance_count_fixture="$scratch_dir/bad_substance_count.md"
sed 's/found five citations that were bibliographically correct/found four citations that were bibliographically correct/' "$research_file" >"$substance_count_fixture"
fixture_substance_count_ok=$(check_substance_failure_count_ok "$substance_count_fixture")
assert_eq "no" "$fixture_substance_count_ok" "FAILURE PROOF (scenario 18): a stated count of four against five enumerated items must be caught"

# ================================================================================================
# 19. README.md <-> docs/RESEARCH.md drift check (S8), part A: the same author-year citation-drift
#     check as scenario 16, extended to the whole of README.md. README.md must exist. Checked
#     against the real README.md (expect 0 — by design README.md links to docs/RESEARCH.md rather
#     than restating individual author-year citations; see check_readme_citation_drift's own
#     comment for why a real-file "0" here is an expected pass, not a vacuous one), then against a
#     scratch copy with a wholly fabricated citation appended (expect 1) — the actual proof that
#     the extractor is not simply matching nothing.
# ================================================================================================
assert_file_exists "$readme_file" "README.md must exist for the drift check"

real_readme_citation_bad=$(check_readme_citation_drift "$readme_file" "$research_file")
assert_eq "0" "$real_readme_citation_bad" "every author-year citation in README.md must be corroborated (name and year) somewhere in docs/RESEARCH.md"

readme_citation_fixture="$scratch_dir/bad_readme_citation.md"
cp "$readme_file" "$readme_citation_fixture"
printf '\nSome new effect was found (Fitzgerald & Owusu, 2019, *Journal of Nowhere*).\n' >>"$readme_citation_fixture"
fixture_readme_citation_bad=$(check_readme_citation_drift "$readme_citation_fixture" "$research_file")
assert_eq "1" "$fixture_readme_citation_bad" "FAILURE PROOF (scenario 19): a fabricated citation added to README.md, absent from docs/RESEARCH.md, must be caught"

# ================================================================================================
# 20. README.md <-> docs/RESEARCH.md drift check (S8), part B: the same retired-name check as
#     scenario 17 (check_retired_name_violations is already file-generic — no README-specific
#     variant needed), applied directly to README.md. A retired/wrong-identity name (Karalunas,
#     Salari, Roberts, or a bare "Sweller" not immediately followed by "& Chandler") must not
#     appear anywhere in README.md except inside a paragraph carrying its own "⚠" correction
#     marker. Checked against the real README.md (expect 0), then against a scratch copy with a
#     brand-new paragraph, carrying no "⚠", that cites "Roberts, Milich & Fillmore, 2012" and
#     "Sweller, 1988" as if they were live evidence (expect 2, the same count scenario 17 expects
#     for the identical injected text).
# ================================================================================================
real_readme_retired_name_bad=$(check_retired_name_violations "$readme_file")
assert_eq "0" "$real_readme_retired_name_bad" "no retired name (Karalunas/Salari/Roberts/bare Sweller) may appear live in README.md outside a ⚠-marked correction paragraph"

readme_retired_name_fixture="$scratch_dir/bad_readme_retired_name.md"
cp "$readme_file" "$readme_retired_name_fixture"
printf '\nWorking memory declines with load (Roberts, Milich & Fillmore, 2012). Also (Sweller, 1988).\n' >>"$readme_retired_name_fixture"
fixture_readme_retired_name_bad=$(check_retired_name_violations "$readme_retired_name_fixture")
assert_eq "2" "$fixture_readme_retired_name_bad" "FAILURE PROOF (scenario 20): a retired name (Roberts) and a bare Sweller used as live citations in README.md, outside a ⚠ paragraph, must both be caught"

# ================================================================================================
# 21. Rules-coverage cross-check, part A (S8-1 BLOCKER fix): every rule number appearing in any
#     "**Rules justified:**" line in docs/RESEARCH.md, de-duplicated, must equal the explicitly
#     declared EXPECTED_CITED_RULES set. Checked against the real file (expect a match), then
#     against a scratch copy with a fabricated "**Rules justified:** 5" line appended — rule 5 is
#     already claimed by the design-decisions section, so this is exactly "someone adds a citation
#     without updating the design-decisions section" (expect no match, and see scenario 23 for the
#     resulting partition break).
# ================================================================================================
real_cited_rules=$(extract_all_justified_numbers "$research_file")
assert_eq "$EXPECTED_CITED_RULES" "$real_cited_rules" "the rule numbers appearing in docs/RESEARCH.md's 'Rules justified:' lines must equal the declared expected set"

fake_citation_fixture="$scratch_dir/bad_fake_citation.md"
cp "$research_file" "$fake_citation_fixture"
printf '\n**Rules justified:** 5 — a fabricated citation for an otherwise-uncited rule.\n' >>"$fake_citation_fixture"
fixture_cited_rules=$(extract_all_justified_numbers "$fake_citation_fixture")
assert_eq "1 2 3 4 5 6 7 8 11 14 15" "$fixture_cited_rules" "FAILURE PROOF (scenario 21): a fabricated 'Rules justified: 5' line must change the extracted cited-rule set to include 5"

# ================================================================================================
# 22. Rules-coverage cross-check, part B (S8-1 BLOCKER fix): every rule number named as
#     "- **Rule N (...)**" under docs/RESEARCH.md's "## Rules with no research claim behind them"
#     section must equal the explicitly declared EXPECTED_DESIGN_RULES set. Checked against the
#     real file (expect a match), then against a scratch copy with rule 13's bullet deleted —
#     exactly "someone removes a rule from the design-decisions section without giving it a
#     citation" (expect no match, and see scenario 23 for the resulting partition break).
# ================================================================================================
real_design_rules=$(extract_design_decision_numbers "$research_file")
assert_eq "$EXPECTED_DESIGN_RULES" "$real_design_rules" "the rule numbers named in docs/RESEARCH.md's design-decisions section must equal the declared expected set"

missing_design_fixture="$scratch_dir/bad_missing_design_rule.md"
grep -v '^- \*\*Rule 13 (Safety override)\.\*\*' "$research_file" >"$missing_design_fixture"
fixture_design_rules=$(extract_design_decision_numbers "$missing_design_fixture")
assert_eq "5 9 10 12 16" "$fixture_design_rules" "FAILURE PROOF (scenario 22): deleting rule 13's bullet from the design-decisions section must drop 13 from the extracted set"

# ================================================================================================
# 23. Rules-coverage cross-check, part C (S8-1 BLOCKER fix): every rule number 1..16, parsed from
#     rules/base-rules.md (never hardcoded — reuses $valid_rule_numbers from scenario 5 above), is
#     accounted for in EXACTLY ONE of {cited, design-decision}. Checked against the real file
#     (expect "ok"), then against the two scenario 21/22 fixtures independently: the fabricated
#     "Rules justified: 5" line puts rule 5 in BOTH groups, and the deleted rule-13 bullet puts
#     rule 13 in NEITHER — the two directions of drift invariant 6e's fix must catch.
# ================================================================================================
all_rules_flat=$(printf '%s\n' "$valid_rule_numbers" | sed '/^$/d' | sort -nu | tr '\n' ' ' | sed 's/ *$//')
assert_eq "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16" "$all_rules_flat" "sanity check: rules/base-rules.md must parse to exactly rules 1 through 16 (vacuous-pass guard for scenario 23)"

real_partition=$(check_rule_partition "$real_cited_rules" "$real_design_rules" "$all_rules_flat")
assert_eq "ok" "$real_partition" "every rule 1..16 must be accounted for in exactly one of {cited, design-decision}, no overlap and no gap"

fixture_partition_extra_citation=$(check_rule_partition "$fixture_cited_rules" "$real_design_rules" "$all_rules_flat")
assert_eq "rule 5 is in BOTH groups" "$fixture_partition_extra_citation" "FAILURE PROOF (scenario 23, direction A): a fabricated citation for an already-design-decision rule must be caught as a BOTH-groups overlap"

fixture_partition_missing_design=$(check_rule_partition "$real_cited_rules" "$fixture_design_rules" "$all_rules_flat")
assert_eq "rule 13 is in NEITHER group" "$fixture_partition_missing_design" "FAILURE PROOF (scenario 23, direction B): deleting a design-decision rule's bullet without giving it a citation must be caught as a NEITHER-group gap"

# ================================================================================================
# 24. [REWRITTEN, T1 BLOCKER fix; WIDENED, U2 BLOCKER fix (S8 review cycle 3)] No tracked
#     markdown-family file contains an absolute "every/each/all rule(s) ... trace(s) to a finding"
#     style claim, scanned via `git ls-files` once per extension in $MARKDOWN_FAMILY_EXTENSIONS
#     ("*.md" and, as of U2, "*.mdc") — SCAN-ALL-BY-DEFAULT — rather than the two hardcoded
#     filenames cycle 1 used, or the single hardcoded EXTENSION cycle 1/2's '*.md'-only glob used.
#     Checked against the real repo (expect 0 flagged files, over the real, full file list), then
#     against scratch copies of FOUR files: the original two (README.md, docs/RESEARCH.md) plus the
#     two kinds of file cycle 2's actual violations landed in — a top-level doc (CONTEXT.md) and a
#     docs/adr/ file — each with the claim injected. A FIFTH proof (U2) covers the actual cycle-3
#     BLOCKER: targets/cursor/squirrel-mode.mdc, the one tracked markdown-family file the old
#     '*.md'-only glob structurally could not match. Extension coverage is also asserted explicitly
#     (check_uncovered_markdown_extensions), so a future ".mdx"/".markdown"/".mkd" file fails this
#     suite the moment it appears instead of silently falling through the same gap ".mdc" did. The
#     exemption mechanism (empty today) is proven too: the declared list is asserted equal to an
#     independently-declared expected constant, and a throwaway scratch git repository proves the
#     scan-all driver both flags a violation in a file that was never on any list and correctly
#     skips a file explicitly named as exempt — now proven across TWO extensions, not just one.
# ================================================================================================
real_all_md_result=$(check_absolute_rule_claim_all_md "$repo_root" "$ABSOLUTE_CLAIM_EXEMPT_FILES")
real_absolute_claim_bad=$(printf '%s\n' "$real_all_md_result" | sed -n 's/^BAD_COUNT=//p')
real_absolute_claim_scanned=$(printf '%s\n' "$real_all_md_result" | sed -n 's/^SCANNED=//p')
assert_eq "0" "$real_absolute_claim_bad" "no tracked markdown-family file (scanned via git ls-files, once per extension in MARKDOWN_FAMILY_EXTENSIONS) may contain an absolute 'every/each/all rule(s) ... trace(s) to a finding' style claim"

# Sanity checks on the scan itself (vacuous-pass guards): the scanned count must equal the repo's
# own independently-computed count across every extension in MARKDOWN_FAMILY_EXTENSIONS (nothing
# silently dropped), and the list must include files well outside the original hardcoded pair —
# CONTEXT.md, PLAN.md, a docs/adr/ file, AND (U2) targets/cursor/squirrel-mode.mdc — which is the
# entire T1/U2 bug in one assertion: a scan still secretly scoped to {README.md, docs/RESEARCH.md}
# or to the '*.md' extension alone would fail this immediately.
real_markdown_family_file_count=0
for _ext in $MARKDOWN_FAMILY_EXTENSIONS; do
  _ext_count=$(git -C "$repo_root" ls-files "*.$_ext" 2>/dev/null | wc -l | tr -d ' ')
  real_markdown_family_file_count=$((real_markdown_family_file_count + _ext_count))
done
scanned_md_file_count=$(printf '%s\n' "$real_absolute_claim_scanned" | tr ' ' '\n' | sed '/^$/d' | wc -l | tr -d ' ')
assert_eq "$real_markdown_family_file_count" "$scanned_md_file_count" "the absolute-claim scan must cover every tracked markdown-family file (every extension in MARKDOWN_FAMILY_EXTENSIONS), no more and no fewer (vacuous-pass guard)"
assert_contains "$real_absolute_claim_scanned" "targets/cursor/squirrel-mode.mdc" "the scan must cover targets/cursor/squirrel-mode.mdc — U2's actual gap: the one tracked markdown-family file the old '*.md'-only glob structurally could not match"

# U2 fix: extension coverage is declared, not just assumed. Checked against the real repo (expect
# no uncovered markdown-family extension), then against a throwaway scratch git repository with a
# brand-new ".mdx" file (expect it flagged as uncovered).
real_uncovered_extensions=$(check_uncovered_markdown_extensions "$repo_root" "$MARKDOWN_FAMILY_EXTENSIONS")
assert_eq "" "$real_uncovered_extensions" "every tracked file with a markdown-family extension must be listed in MARKDOWN_FAMILY_EXTENSIONS in tests/test_research.sh, or the scan silently misses it the way '*.mdc' was missed for an entire review cycle"

uncovered_ext_repo="$scratch_dir/uncovered_ext_repo"
mkdir -p "$uncovered_ext_repo"
(
  cd "$uncovered_ext_repo" || exit 1
  git init -q
  printf '# A new markdown-family extension\n\nNothing special here.\n' >sample.mdx
  git add sample.mdx
) >/dev/null 2>&1
fixture_uncovered_extensions=$(check_uncovered_markdown_extensions "$uncovered_ext_repo" "$MARKDOWN_FAMILY_EXTENSIONS")
assert_eq "mdx" "$fixture_uncovered_extensions" "FAILURE PROOF (U2, extension coverage): a brand-new '.mdx' file must be reported as an uncovered markdown-family extension"
assert_contains "$real_absolute_claim_scanned" "README.md" "the scan must cover README.md"
assert_contains "$real_absolute_claim_scanned" "docs/RESEARCH.md" "the scan must cover docs/RESEARCH.md"
assert_contains "$real_absolute_claim_scanned" "CONTEXT.md" "the scan must cover CONTEXT.md — one of the two files cycle 1's hardcoded list missed"
assert_contains "$real_absolute_claim_scanned" "PLAN.md" "the scan must cover PLAN.md — the other file cycle 1's hardcoded list missed"
assert_contains "$real_absolute_claim_scanned" "docs/adr/0001-output-style-not-skill.md" "the scan must cover a docs/adr/ file (vacuous-pass guard: proves this is not still a two-file allowlist)"

# FAILURE PROOF (scenario 24a/24b): the original two files, same injected text as before this fix,
# run through the broadened per-file detector directly.
absolute_readme_fixture="$scratch_dir/bad_absolute_readme.md"
cp "$readme_file" "$absolute_readme_fixture"
printf '\nNo rule ships without a citation, full stop.\n' >>"$absolute_readme_fixture"
fixture_absolute_readme_bad=$(check_absolute_rule_claim_present "$absolute_readme_fixture")
assert_eq "1" "$fixture_absolute_readme_bad" "FAILURE PROOF (scenario 24a, README.md): re-adding the retired 'No rule ships without' claim must be caught"

absolute_research_fixture="$scratch_dir/bad_absolute_research.md"
cp "$research_file" "$absolute_research_fixture"
# shellcheck disable=SC2016 # single-quoted deliberately: the backtick-quoted
# `rules/base-rules.md` below is literal text to inject, not a command substitution.
printf '\nEvery rule in `rules/base-rules.md` traces to a finding, no exceptions.\n' >>"$absolute_research_fixture"
fixture_absolute_research_bad=$(check_absolute_rule_claim_present "$absolute_research_fixture")
assert_eq "1" "$fixture_absolute_research_bad" "FAILURE PROOF (scenario 24b, docs/RESEARCH.md): re-adding the retired 'Every rule ... traces' claim must be caught"

# FAILURE PROOF (scenario 24c/24d) — T1's ACTUAL bug: a file that is NEITHER README.md NOR
# docs/RESEARCH.md. Injected into scratch copies of CONTEXT.md's real content and a docs/adr/
# file's real content — the two kinds of file cycle 2's violations actually landed in. Cycle 1's
# guard, wired to the original two filenames, could not have caught either of these.
context_file="$repo_root/CONTEXT.md"
adr_sample_file="$repo_root/docs/adr/0001-output-style-not-skill.md"
assert_file_exists "$context_file" "CONTEXT.md must exist for scenario 24's generalization proof"
assert_file_exists "$adr_sample_file" "docs/adr/0001-output-style-not-skill.md must exist for scenario 24's generalization proof"

absolute_context_fixture="$scratch_dir/bad_absolute_context.md"
cp "$context_file" "$absolute_context_fixture"
printf '\nEach rule traces to a specific research finding, no exceptions.\n' >>"$absolute_context_fixture"
fixture_absolute_context_bad=$(check_absolute_rule_claim_present "$absolute_context_fixture")
assert_eq "1" "$fixture_absolute_context_bad" "FAILURE PROOF (scenario 24c, CONTEXT.md — not one of the two originally hardcoded files): the retired 'Each rule traces' claim must be caught here too"

absolute_adr_fixture="$scratch_dir/bad_absolute_adr.md"
cp "$adr_sample_file" "$absolute_adr_fixture"
printf '\nAll rules trace to a citation in the research record, without exception.\n' >>"$absolute_adr_fixture"
fixture_absolute_adr_bad=$(check_absolute_rule_claim_present "$absolute_adr_fixture")
assert_eq "1" "$fixture_absolute_adr_bad" "FAILURE PROOF (scenario 24d, a docs/adr/ file — not one of the two originally hardcoded files): an 'All rules trace to a citation' claim must be caught here too"

# FAILURE PROOF (scenario 24, U2 BLOCKER fix) — the actual cycle-3 bug: a tracked markdown-family
# file with an extension OTHER than .md. targets/cursor/squirrel-mode.mdc is real, tracked, and
# GENERATED (see .build-checkpoint.md invariant 2 — never hand-edit it), so this proof injects the
# claim into a SCRATCH COPY of its real content rather than the tracked file itself, exactly the
# same pattern already used for README.md/docs/RESEARCH.md/CONTEXT.md/the docs/adr/ file above.
mdc_sample_file="$repo_root/targets/cursor/squirrel-mode.mdc"
assert_file_exists "$mdc_sample_file" "targets/cursor/squirrel-mode.mdc must exist for scenario 24's .mdc generalization proof (U2)"

absolute_mdc_fixture="$scratch_dir/bad_absolute.mdc"
cp "$mdc_sample_file" "$absolute_mdc_fixture"
printf '\nEvery rule here traces to a specific research finding, no exceptions.\n' >>"$absolute_mdc_fixture"
fixture_absolute_mdc_bad=$(check_absolute_rule_claim_present "$absolute_mdc_fixture")
assert_eq "1" "$fixture_absolute_mdc_bad" "FAILURE PROOF (scenario 24, U2 BLOCKER, targets/cursor/squirrel-mode.mdc): the per-file detector itself already catches the claim in a .mdc file — U2's actual bug was that the DRIVER never handed it a .mdc path at all, proven by the widened-scan assertions above"

# ------------------------------------------------------------------------------------------------
# Exemption mechanism: declared, and ASSERTED so it cannot grow silently (scenario 24e/24f).
# ------------------------------------------------------------------------------------------------
assert_eq "$EXPECTED_ABSOLUTE_CLAIM_EXEMPT" "$ABSOLUTE_CLAIM_EXEMPT_FILES" "the absolute-claim exemption list must equal the declared, independently-stated expected value — an exemption added without updating this assertion must fail loudly, not silently take a file out of scope"

# FAILURE PROOF (scenario 24e): simulate a future edit that adds an exemption without updating the
# expected constant, run in the same subshell-isolated style as scenario 14's proofs so its
# deliberate FAIL does not pollute this file's real counters.
proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  simulated_exempt_files="CONTEXT.md"
  assert_eq "$EXPECTED_ABSOLUTE_CLAIM_EXEMPT" "$simulated_exempt_files" "proof check"
) )
case "$proof_output" in
  *"FAIL:"*) fixture_silent_exemption_caught=yes ;;
  *) fixture_silent_exemption_caught=no ;;
esac
assert_eq "yes" "$fixture_silent_exemption_caught" "FAILURE PROOF (scenario 24e): adding a file to the exemption list without updating EXPECTED_ABSOLUTE_CLAIM_EXEMPT must be caught"

# ------------------------------------------------------------------------------------------------
# FAILURE PROOF (scenario 24f): full round trip on real `git ls-files` plumbing, in a throwaway
# scratch git repository (no identity/commit needed — `git ls-files` reads the index, populated by
# `git add` alone). Proves the scan-all driver (a) flags a violation in a brand-new file that was
# never on any historical list, and (b) correctly SKIPS that same file once it is named in the
# exempt list passed in.
# ------------------------------------------------------------------------------------------------
mini_repo="$scratch_dir/mini_absolute_claim_repo"
mkdir -p "$mini_repo"
(
  cd "$mini_repo" || exit 1
  git init -q
  printf '# Clean file\n\nNothing to see here.\n' >clean.md
  printf '# A brand new doc\n\nEvery rule in this file traces to a finding, no exceptions.\n' >new_offender.md
  printf '# A brand new .mdc doc\n\nEvery rule in this file traces to a finding, no exceptions.\n' >new_offender.mdc
  git add clean.md new_offender.md new_offender.mdc
) >/dev/null 2>&1

mini_result_no_exempt=$(check_absolute_rule_claim_all_md "$mini_repo" "")
mini_bad_no_exempt=$(printf '%s\n' "$mini_result_no_exempt" | sed -n 's/^BAD_COUNT=//p')
assert_eq "2" "$mini_bad_no_exempt" "FAILURE PROOF (scenario 24f, part 1, widened by U2): the scan-all driver must flag a violation in BOTH a brand-new .md file and a brand-new .mdc file, neither ever on any hardcoded list"

mini_result_one_exempt=$(check_absolute_rule_claim_all_md "$mini_repo" "new_offender.md")
mini_bad_one_exempt=$(printf '%s\n' "$mini_result_one_exempt" | sed -n 's/^BAD_COUNT=//p')
assert_eq "1" "$mini_bad_one_exempt" "FAILURE PROOF (scenario 24f, part 2, U2): exempting only the .md offender must leave the .mdc offender still flagged - proves the exemption is per-file, not per-extension"

mini_result_both_exempt=$(check_absolute_rule_claim_all_md "$mini_repo" "new_offender.md
new_offender.mdc")
mini_bad_both_exempt=$(printf '%s\n' "$mini_result_both_exempt" | sed -n 's/^BAD_COUNT=//p')
assert_eq "0" "$mini_bad_both_exempt" "FAILURE PROOF (scenario 24f, part 3): the scan-all driver must skip every file explicitly named in the exempt list passed to it, across both extensions"

# ================================================================================================
# 25. The retired "success amnesia" framing (docs/RESEARCH.md Finding 8's own retraction) stays
#     dead in README.md (S8-2 BLOCKER fix). Scoped to README.md only — see
#     check_retired_success_amnesia_phrasing's comment for why docs/RESEARCH.md is deliberately
#     never checked by this function. Checked against the real README.md (expect 0), then against
#     a scratch copy with all three retired phrasings appended (expect 3). This is the ONLY
#     mechanical guard against this specific retired claim as of S8 review cycle 3 (U4 fix) — the
#     broader co-occurrence tripwire that used to sit alongside it was deleted; see the U4 note near
#     RETIRED_SUCCESS_AMNESIA_PHRASES, above, for why.
# ================================================================================================
real_readme_amnesia_bad=$(check_retired_success_amnesia_phrasing "$readme_file")
assert_eq "0" "$real_readme_amnesia_bad" "README.md must not contain a phrase listed in RETIRED_SUCCESS_AMNESIA_PHRASES (tests/test_research.sh). If this fired on a genuinely new, correct sentence: reword that sentence to avoid these specific phrases - do not add an exemption. A paraphrase carrying the same retired inference in DIFFERENT words is not something this check can see; that class of drift is caught by a human reviewer applying PLAN.md Section 2's four-check citation policy, not by grep."

amnesia_fixture="$scratch_dir/bad_amnesia.md"
cp "$readme_file" "$amnesia_fixture"
printf '\nADHD blurs the memory of one'"'"'s own accomplishments, sometimes called success amnesia, making their own recent progress hard to recall.\n' >>"$amnesia_fixture"
fixture_amnesia_bad=$(check_retired_success_amnesia_phrasing "$amnesia_fixture")
assert_eq "3" "$fixture_amnesia_bad" "FAILURE PROOF (scenario 25): all three retired success-amnesia phrasings, reintroduced into README.md, must be caught"

# ================================================================================================
# 26. The "N of the 16" / "other M rules" prose counts in README.md, docs/RESEARCH.md, AND (added
#     this cycle as part of the T1 fix — PLAN.md now states these same specific counts, see
#     PLAN.md's rewritten Section 1 item 1) PLAN.md's opening statements are tied to the same
#     declared expected-set sizes checks 21/22 compare against, not just independently worded to
#     currently match. All three files hard-wrap their prose, so the needle is checked against a
#     FLATTENED copy of each body (newlines replaced with spaces, then runs of spaces squeezed to
#     one — `tr -s ' '` — so a needle is never missed purely because a line-wrap boundary landed a
#     multi-space run in the middle of it) exactly like check_citation_drift_in_text already does
#     above for the same reason. Checked against all three real files (expect the derived needles
#     present in each), then against a scratch copy of README.md AND a scratch copy of PLAN.md,
#     each with the cited-rule count changed from 10 to 9 (expect the needle absent from both).
#
#     [CORRECTED, S8 review cycle 3, U8 MINOR fix] THIS is a two-step mechanism, not a one-shot
#     one — a comment here used to imply every place stating a count goes red together, which is
#     false. Editing docs/RESEARCH.md's real "Rules justified:"/design-decision lines (a genuine
#     new citation) reddens checks 21/22/23 FIRST — the extracted set no longer matches the
#     declared EXPECTED_CITED_RULES/EXPECTED_DESIGN_RULES constants above. THIS check stays green
#     at that point, because its needle is derived from those constants (still unchanged) and the
#     prose (also still unchanged) still matches them. Only once a maintainer updates those two
#     constants to reflect the new true partition does the needle THIS check derives from change —
#     and only THEN does this check go red, because the prose in README.md/docs/RESEARCH.md/PLAN.md
#     has not been rewritten yet. Two separate, sequential prompts toward two separate fixes: first
#     "update the declared rule sets," then "now rewrite the prose to match them" — never one
#     failure lighting up everywhere at once.
# ================================================================================================
# Word counts via `wc -w`, not an unquoted `set -- $var` word-split, so this stays clean
# under shellcheck's default globbing/word-splitting check.
expected_cited_count=$(printf '%s\n' "$EXPECTED_CITED_RULES" | wc -w | tr -d ' ')
expected_design_count=$(printf '%s\n' "$EXPECTED_DESIGN_RULES" | wc -w | tr -d ' ')
total_rule_count=$(printf '%s\n' "$all_rules_flat" | wc -w | tr -d ' ')

cited_count_needle="${expected_cited_count} of the ${total_rule_count} base rules"
design_count_needle="other ${expected_design_count} rules are stated design decisions"

readme_flat=$(tr '\n' ' ' <"$readme_file" | tr -s ' ')
research_flat=$(tr '\n' ' ' <"$research_file" | tr -s ' ')
plan_flat=$(tr '\n' ' ' <"$plan_file" | tr -s ' ')

assert_contains "$readme_flat" "$cited_count_needle" "README.md's cited-rule-count prose must match the declared expected-set size"
assert_contains "$research_flat" "$cited_count_needle" "docs/RESEARCH.md's cited-rule-count prose must match the declared expected-set size"
assert_contains "$plan_flat" "$cited_count_needle" "PLAN.md's cited-rule-count prose must match the declared expected-set size"
assert_contains "$readme_flat" "$design_count_needle" "README.md's design-decision-count prose must match the declared expected-set size"
assert_contains "$research_flat" "$design_count_needle" "docs/RESEARCH.md's design-decision-count prose must match the declared expected-set size"
assert_contains "$plan_flat" "$design_count_needle" "PLAN.md's design-decision-count prose must match the declared expected-set size"

stale_count_fixture="$scratch_dir/bad_stale_count.md"
sed "s/${expected_cited_count} of the ${total_rule_count} base rules/9 of the ${total_rule_count} base rules/" "$readme_file" >"$stale_count_fixture"
stale_count_flat=$(tr '\n' ' ' <"$stale_count_fixture" | tr -s ' ')
assert_not_contains "$stale_count_flat" "$cited_count_needle" "FAILURE PROOF (scenario 26, README.md): a README.md cited-rule count changed to 9 must no longer match the needle derived from the declared expected set"

stale_plan_count_fixture="$scratch_dir/bad_stale_plan_count.md"
sed "s/${expected_cited_count} of the ${total_rule_count} base rules/9 of the ${total_rule_count} base rules/" "$plan_file" >"$stale_plan_count_fixture"
stale_plan_count_flat=$(tr '\n' ' ' <"$stale_plan_count_fixture" | tr -s ' ')
assert_not_contains "$stale_plan_count_flat" "$cited_count_needle" "FAILURE PROOF (scenario 26, PLAN.md): a PLAN.md cited-rule count changed to 9 must no longer match the needle derived from the declared expected set"

# ================================================================================================
# 27. Every finding bullet in README.md's "## Why it's shaped this way" section carries a
#     population tag (PLAN.md Section 5: "every citation in README and RESEARCH.md is ... tagged
#     with the population it was measured in" — see check_readme_finding_bullets_missing_population
#     above for why this was previously unchecked for README specifically).
# ================================================================================================
readme_pop_result=$(check_readme_finding_bullets_missing_population "$readme_file")
readme_pop_missing=$(printf '%s\n' "$readme_pop_result" | awk '{print $1}')
readme_pop_total=$(printf '%s\n' "$readme_pop_result" | awk '{print $2}')
assert_eq "0" "$readme_pop_missing" "every bullet in README.md's 'Why it's shaped this way' section must carry one of the three allowed population tags"

if [ "${readme_pop_total:-0}" -ge 1 ] 2>/dev/null; then
  readme_pop_nonvacuous=yes
else
  readme_pop_nonvacuous=no
fi
assert_eq "yes" "$readme_pop_nonvacuous" "sanity check: README.md's 'Why it's shaped this way' section must actually contain at least one bullet, or the check above passes vacuously"

readme_pop_fixture="$scratch_dir/bad_readme_population.md"
# shellcheck disable=SC2016 # single-quoted deliberately: literal sed pattern, not substitution.
sed 's/ `general working memory`//' "$readme_file" >"$readme_pop_fixture"
fixture_pop_result=$(check_readme_finding_bullets_missing_population "$readme_pop_fixture")
fixture_pop_missing=$(printf '%s\n' "$fixture_pop_result" | awk '{print $1}')
assert_eq "1" "$fixture_pop_missing" "FAILURE PROOF (scenario 27): stripping one bullet's population tag from README.md must be caught"

# ================================================================================================
# 28. Finding 3 states the directionality its own citation measured, not the reverse (third
#     verification pass). Kofler et al. (2020) is subtitled "Evidence for directionality of
#     effects" because it tested whether slowed processing degrades working memory and found it did
#     not; the retired sentence asserted exactly that rejected direction. Checked against the real
#     file (expect "yes"), then against a fixture with the retired sentence restored (expect "no").
#     The companion assertion pins that the finding DECLARES the disagreement between its own two
#     citations — Hulsbosch et al. (2025) builds on processing speed underlying working-memory
#     deficits, which is the direction Kofler et al. rejected — since a finding can state the right
#     direction and still hide that its own sources conflict.
# ================================================================================================
real_finding3_ok=$(check_finding3_directionality_ok "$research_file")
assert_eq "yes" "$real_finding3_ok" "Finding 3 must state the direction Kofler et al. (2020) actually measured (working-memory demand slows processing; the reverse manipulation did not), with the retired reverse assertion absent"

finding3_fixture="$scratch_dir/bad_finding3.md"
cp "$research_file" "$finding3_fixture"
printf '\nWorking memory and processing speed are at least partly independent impairments in ADHD, and slower processing keeps capacity occupied by ongoing work rather than freeing it up.\n' >>"$finding3_fixture"
fixture_finding3_ok=$(check_finding3_directionality_ok "$finding3_fixture")
assert_eq "no" "$fixture_finding3_ok" "FAILURE PROOF (scenario 28): restoring the retired 'slower processing keeps capacity occupied' assertion must be caught"

research_flat_28=$(tr '\n' ' ' <"$research_file" | tr -s ' ')
assert_contains "$research_flat_28" "These two citations disagree with each other" "Finding 3 must declare the contradiction between Kofler et al. (2020) and Hulsbosch et al. (2025) rather than presenting them as agreeing"

# ================================================================================================
# 29. Finding 5's Meltzer & Basho citation does not sit under an `ADHD` population tag (third
#     verification pass). The chapter's full text was downloaded and searched: "ADHD", "attention
#     deficit" and "attention-deficit" occur zero times in it, and it addresses "All students" in a
#     general-education classroom — so tagging it `ADHD` broke this file's own definition of that
#     tag ("measured in an ADHD population"). Checked against the real file (expect "general working
#     memory"), then against a fixture that flips Finding 5's tag back to `ADHD` (expect "ADHD").
#     The companion assertion pins that the retired ADHD-convergence sentence stays retired.
# ================================================================================================
real_finding5_tag=$(check_finding5_meltzer_tag "$research_file")
assert_eq "general working memory" "$real_finding5_tag" "Finding 5's Meltzer & Basho citation must sit under 'general working memory' — its full text never mentions ADHD, so an 'ADHD' tag would assert a population the source does not have"

finding5_fixture="$scratch_dir/bad_finding5.md"
awk '
  /^## / { in_f5 = ($0 ~ /^## Finding 5:/) ? 1 : 0 }
  in_f5 && !flipped && $0 == "**Population:** general working memory" {
    print "**Population:** ADHD"
    flipped = 1
    next
  }
  { print }
' "$research_file" >"$finding5_fixture"
fixture_finding5_tag=$(check_finding5_meltzer_tag "$finding5_fixture")
assert_eq "ADHD" "$fixture_finding5_tag" "FAILURE PROOF (scenario 29): re-tagging Finding 5's Meltzer & Basho citation as an ADHD-population source must be caught"

assert_not_contains "$research_flat_28" "Educational guidance for ADHD converges" "the retired claim that ADHD guidance converges on three specific accommodations must stay retired — only the chunking one is in the source, and the source is general-education"

# ================================================================================================
# 30. Finding 12 states Brown et al. (2020)'s MAIN EFFECT and does not assert the ADHD-by-redundancy
#     INTERACTION its abstract never reports (third verification pass). The study does have
#     redundancy and nonredundancy groups, which is what made the invented conditional plausible
#     enough to survive two passes; the abstract nonetheless states the result flat, and the full
#     text is paywalled, so check 2 cannot be cleared for the conditional.
#
#     Both retired phrasings are banned OUTRIGHT here, file-wide, rather than allowed inside
#     correction prose. That is affordable only because Finding 12's own ⚠ note and its Corrections
#     entry were deliberately written to DESCRIBE the retired conditional instead of quoting it —
#     the same dodge Finding 3's Corrections entry needed for scenario 28's needle, and the reason
#     check_retired_success_amnesia_phrasing's comment says a correction that must quote its own
#     retired claim cannot be guarded this cheaply. Checked against the real file (expect both
#     absent, and the main-effect quote present), then against a fixture with the retired sentence
#     restored (expect the ban to fire).
# ================================================================================================
assert_contains "$research_flat_28" "an increase in ADHD symptoms resulted in an increase in mental effort and a decrease in recall and transfer" "Finding 12 must quote Brown et al. (2020)'s actual reported result — the unconditional main effect"
assert_not_contains "$research_flat_28" "when that redundant information was present" "Finding 12 must not assert an ADHD-by-redundancy interaction: the abstract reports a main effect only, and the full text is paywalled"
assert_not_contains "$research_flat_28" "direct, ADHD-population confirmation" "Finding 12 must not call itself a direct ADHD-population confirmation of Finding 4 — that reading needed the interaction its source never reports"

# Failure proof, subshell-isolated in the same style as scenario 14's, so the deliberate FAIL does
# not pollute this file's real counters.
proof_output=$( (
  ASSERT_PASS_COUNT=0
  ASSERT_FAIL_COUNT=0
  fixture_body="$research_flat_28 higher symptom scores were associated with more mental effort and less recall and transfer when that redundant information was present"
  assert_not_contains "$fixture_body" "when that redundant information was present" "proof check"
) )
case "$proof_output" in
  *"FAIL:"*) fixture_finding12_caught=yes ;;
  *) fixture_finding12_caught=no ;;
esac
assert_eq "yes" "$fixture_finding12_caught" "FAILURE PROOF (scenario 30): restoring Finding 12's retired interaction conditional must be caught"

assert_report
