#!/bin/sh
# Coverage for S6: docs/RESEARCH.md, the evidence base.
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
#  10. docs/ contains nothing but RESEARCH.md and adr/.
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
#
# Scenarios 2, 4, 5, 6, 9, 11, 12, 13, 15, 16, 17, and 18 are checked twice each: once against the
# real, committed file(s) (expecting zero violations), and once against a scratch copy
# deliberately corrupted to contain exactly the bad pattern the check exists to catch (expecting
# the check to report a violation). Scenario 14 is checked once directly against the real file
# with the generic assert_not_contains helper, plus a subshell-isolated proof that the helper
# itself reports FAIL when the phrase is present, so the check is not vacuously true. Every check
# is implemented as a function taking a file path, specifically so the same code path can run
# against both the real file and a corrupted scratch fixture — a check that can only ever run
# against the one real file it was written to match proves nothing about whether it would catch
# a real regression.
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
check_plan_citation_drift() {
  plan_file=$1
  research_file=$2
  bad=0
  flat=$(extract_plan_section2 "$plan_file" | sed -e 's/\*//g' -e 's/`//g' | tr '\n' ' ')
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
# 10. docs/ contains no stray files beyond RESEARCH.md and adr/.
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
# OTHER-TOOLS.md is S7's deliverable and is named in PLAN.md's repository layout. The point of this
# assertion is that nothing UNEXPECTED lands in docs/, not that the set never grows -- so the
# expected set is stated here and a genuinely stray file still fails.
assert_eq "OTHER-TOOLS.md RESEARCH.md adr" "$docs_listing" "docs/ must contain exactly OTHER-TOOLS.md, RESEARCH.md and adr/, nothing else"

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

assert_report
