#!/bin/sh
# Repo-wide invariants that must hold now and keep holding through every
# later build step (S2-S9). See tests/lib/assert.sh for why `set -eu`
# here does not abort on the first failed assertion.
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

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: 'git' is required for repo invariant checks but was not found on PATH." >&2
  exit 1
fi

if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $repo_root is not inside a git work tree; cannot list tracked files." >&2
  exit 1
fi

# --- Known, documented exclusions ------------------------------------
#
# 1) The two WORD-CONTENT scans below (visibility claims, and TODO/FIXME/
#    XXX markers) skip everything under `tests/`. Without this, the
#    assertion messages and comments in THIS file — which necessarily
#    name the very markers/phrases they check for, to describe what the
#    checks do — would trip the checks they implement. This is a
#    self-reference problem specific to those two content scans. It
#    does NOT apply to the executable-bit or JSON-validity checks below:
#    those have no self-reference problem, so they run over every
#    tracked file, `tests/` included (that gap previously let a missing
#    +x bit on the test runner itself go undetected).
#
# 2) The visibility scan ALSO excludes a fixed set of whole paths —
#    PLAN.md, docs/adr/, CONTEXT.md, .build-checkpoint.md — by path, not
#    by line content (see the denylist case pattern in the scan loop
#    below, and the category comment just above it). This is a
#    denylist, not an allowlist: every OTHER path, including ones a
#    later build step introduces (e.g. docs/RESEARCH.md,
#    docs/OTHER-TOOLS.md — both user-facing and deliberately NOT
#    excluded), stays in scope by default. Only docs/adr/ is excluded,
#    not all of docs/. This exclusion applies to the visibility scan
#    ONLY — the marker, executable-bit, and JSON-validity scans below
#    have no scoping question and run over every tracked file with no
#    path denylist.
#
# 3) The TODO/FIXME/XXX marker scan has NO content exclusion for
#    CONTEXT.md (or any other file): it matches marker syntax
#    (`TODO:`/`TODO(`/etc.), not the bare word, so CONTEXT.md's glossary
#    prose ("_Avoid_: backlog, icebox, TODO, notes") does not trip it
#    without needing a carve-out.
#
# 4) [NEW, S8 review cycle 3, U6 MINOR fix] The GLOSSARY-TERM scan (further below) checks that no
#    tracked markdown-family file uses a term CONTEXT.md's own `_Avoid_` lists reserve for a
#    canonical name instead — the actual bug found was README.md saying "host directories" where
#    CONTEXT.md's Target entry reserves "target" and lists "host" under `_Avoid_`. It is scoped in
#    TWO ways, both load-bearing:
#      a) FILE scope: only `*.md`/`*.mdc` files, minus the same PLAN.md/docs/adr/*/CONTEXT.md/
#         .build-checkpoint.md denylist the visibility scan uses (category 2 above) — CONTEXT.md is
#         the glossary itself and would trip on its own `_Avoid_` line for every term listed there;
#         `.sh` files are excluded structurally (not by denylist) because this project's own shell
#         comments use several of these same English words as ordinary engineering jargon ("host
#         detection" in targets/*/install.sh, "the host lacks a hook" in scripts/build.sh) with no
#         relationship to the glossary at all — those are developer-facing code comments, not
#         "user-facing docs" in the sense PLAN.md Section 5 or this scan cares about.
#      b) TERM scope: only a hand-picked SUBSET of the `_Avoid_` vocabulary across all of
#         CONTEXT.md's entries — not every word on every list. Several avoid-terms are ordinary
#         English or collide with real, already-shipped, correct product text and would false-
#         positive on files that are not violating anything:
#           - "memory" (Checkpoint) — collides with "working memory" / "negative memory bias",
#             docs/RESEARCH.md's own cognitive-science vocabulary, used dozens of times correctly.
#           - "history" (Done log) — ordinary English, and this project's own text legitimately
#             discusses "checkpoint history" as a general phrase, not always as a Done-log stand-in.
#           - "config", "settings", "preferences", "user config" (Profile) — collide with the
#             LITERAL Claude Code command `/config` (README's Install section) and Cursor's actual
#             "Rules settings UI" (docs/OTHER-TOOLS.md) — both real product surfaces, not synonyms
#             for squirrel-mode's own profile.
#           - "setup", "init" (Calibration) — "setup" is rule 1's own canonical wording ("stated
#             before any setup, caveat, or context", shipped identically in rules/base-rules.md and
#             every generated artifact); "init" collides with the literal command name
#             `/squirrel:init`, used constantly and correctly.
#           - "summary", "TL;DR", "brief", "parse" (Digest) — Digest's own shipped, ALREADY-ACCEPTED
#             spec (PLAN.md, every skills/*/digest, targets/*/skills/digest, targets/cursor/commands/
#             digest.md) calls its own output "the brief" and uses "TL;DR" as a real, fixed section
#             heading name — banning these would fail on correct, S5-accepted text, not catch a
#             violation.
#           - "instructions" (Base rules) — collides with `keep-coding-instructions` (the literal,
#             correct output-style frontmatter key) and ordinary phrases like "chunking
#             instructions" in docs/RESEARCH.md.
#         GLOSSARY_AVOID_REGEX below lists exactly the terms that were checked, by hand, against
#         every in-scope file before this fix shipped, and found to have zero legitimate collision —
#         mostly multi-word phrases ("formatting rules", "session file", "drift detection", ...)
#         specific enough that ordinary prose has no reason to produce them by accident. Extending
#         this list to a currently-excluded term is welcome, but must go through the same by-hand
#         collision check this comment records, not be added on the assumption that a word "sounds
#         glossary-related."

# Case-insensitive alternation over the semantic markers for "checkpoint
# writes are invisible to the user" — the current acceptance criterion
# (PLAN.md Section 5) — rather than the bare word "silently", which also
# appears in legitimate error-path phrasing ("exit quietly", "never fail
# silently") that must NOT trip this.
#
# The apostrophe position in the last alternative uses a NEGATED,
# quantified character class, `[^A-Za-z0-9_ ]{1,3}`, rather than embedding
# a literal apostrophe character. A straight apostrophe (') is 1 byte; a
# curly apostrophe (’) is 3 bytes in UTF-8.
#
# It is true that an UNQUANTIFIED bracket expression containing the curly
# apostrophe literally, `['’]` with no `{1,3}` after it, can match at most
# ONE byte under `LC_ALL=C` (grep operates byte-wise there, so the class
# is decomposed into four single-byte alternatives — 0x27, 0xE2, 0x80,
# 0x99 — and matching just one of them leaves the other bytes of the
# 3-byte curly-apostrophe sequence unconsumed, right where literal text
# is expected next). But that is NOT why this check avoids `['’]`: a
# QUANTIFIED version, `['’]{1,3}`, would in fact still succeed under
# `LC_ALL=C`, because `{1,3}` lets the class consume up to three
# repetitions, and the curly apostrophe's three raw bytes are each
# individually members of that same four-byte class. So quantifying away
# the one-byte limit was always possible; it was never the reason this
# check is built the way it is.
#
# The actual reason to avoid enumerating apostrophe glyphs at all: the set
# of "apostrophe-like" punctuation real prose uses is open-ended (straight
# ', curly ’, and whatever else an author's autocorrect produces), and any
# inclusion list has to be kept in sync with all of them by hand. Matching
# by EXCLUSION instead — 1 to 3 bytes/characters that are NOT a letter,
# digit, underscore, or space — sidesteps the enumeration problem and
# works identically under `LC_ALL=C` (byte-wise) and a UTF-8 locale
# (character-wise): under either, the bytes/characters making up any
# apostrophe variant are non-word and non-space, so they fall in this
# class regardless of which locale decodes them.
#
# Excluding word characters (letters/digits/underscore), not just space,
# is what closes the false-positive this class must not reopen: the
# earlier version of this check used `[^ ]{1,3}` (any non-space, not just
# non-word), which also matched ordinary identifier characters, so
# "Sync runs without the user_ids knowledge_base being rebuilt." satisfied
# `user[^ ]{1,3}s knowledge` — "_id" is 3 non-space bytes — with no
# apostrophe anywhere near it. `[^A-Za-z0-9_ ]{1,3}` cannot consume "_id"
# (each of those bytes is excluded from the class), so that string no
# longer matches, while every apostrophe encoding still does. Restricting
# to non-space is also what keeps this from spanning a word gap, e.g.
# "without the user is knowledgeable" must NOT match: the space right
# after "user" is excluded from the class too, so there is nothing at
# that position for `{1,3}` to consume.
VISIBILITY_REGEX="invisible|unobservable|hidden from (the )?user|without (the )?user[^A-Za-z0-9_ ]{1,3}s knowledge"

# Marker SYNTAX (colon or open-paren immediately after the word), not the
# bare word — so prose that merely mentions "TODO" as a word (glossary
# entries, this comment) cannot trip it, while a real marker anywhere,
# including in CONTEXT.md, still can.
MARKER_REGEX='(TODO|FIXME|XXX)[:(]'

# [V3 -> W4, S8 accuracy fix] HISTORY, because the reasoning matters for anyone tempted to bring
# the old approach back: V3 shipped a cross-sentence PROXIMITY regex (`/plugin (disable|enable)`
# then any non-period run, then `/clear`). W3 widened it to all four verbs and, to catch a
# numbered-list-wrapped install regression, changed the gap class to also cross a digit-period
# (`1.`, `2.`, `2.1.195`). That gap class is what broke it: W2's own fix to README's install step 2
# added TWO new sentence-ending periods ("`Plugin is now active.`", "`Run /reload-plugins to
# activate.`") between the `/plugin install` anchor and the `/clear` anchor. Both are
# letter-preceded, so they DO close the gap — but the fix had already moved `/plugin install` and
# `/clear` three sentences apart, and no distance bound, however generously chosen, can both (a)
# stay short enough to avoid bridging genuinely unrelated sentences elsewhere in a file and (b) stay
# long enough to survive whatever prose a future edit inserts between two anchors it is supposed to
# guard. The coordinator caught this by reproducing it in a scratch copy: reverting ONLY README's
# install step 3 left the suite green, because the regex could no longer reach across step 2's new
# text to find it — a guard that cannot fail for its own primary target. Distance is not a property
# a static check can bound; it was replaced, not re-tuned, with the two checks below.
#
# WHAT REPLACED IT — two independent mechanisms, deliberately narrow, each with a stated limit:
#
# 1. PIN_* below: exact-text pins on the six sentences that make the "then a new session" claim
#    (see the PIN_* block and the per-file assertions after the main scan loop). A pin catches an
#    edit to ITS OWN sentence, in either direction — the claim regressing back to `/clear`, or the
#    sentence being reworded into something else entirely — because either way the exact text stops
#    matching and the assertion fails, naming the constant to fix and why it exists. A pin does NOT
#    catch the same false claim appearing in a NEW, seventh location; nothing but code review does.
#
# 2. PLUGIN_CLEAR_SAME_SENTENCE_REGEX below: a global scan, over every tracked file outside tests/,
#    for `/clear` and a `/plugin install|uninstall|enable|disable` verb occurring in the SAME
#    sentence, in either order. "Same sentence" is operationalized by splitting each file's
#    flattened content on `.` (see the scan loop's `tr '.' '\n'` below) and checking each resulting
#    chunk for both anchors with two piped `grep` calls — no distance bound anywhere, because a
#    sentence boundary, not a character count, is what the real defect always crossed. This catches
#    the pattern being reintroduced ANYWHERE in a tracked file, including a location none of the six
#    pins cover — but it does NOT catch a claim spread across two sentences ("Run `/plugin disable
#    squirrel@squirrel-mode`. Then `/clear` finishes it.") in a file with no matching sentence today;
#    splitting on every `.` (including ones inside backtick-quoted phrases like "`Plugin is now
#    active.`") makes this scan MORE conservative than a human's idea of "one sentence," which is
#    the safe direction — it trades a handful of hypothetical multi-sentence misses (caught in
#    review, same as any check that stops at some boundary) for zero risk of bridging two genuinely
#    unrelated mentions of `/clear` and a `/plugin` verb elsewhere in a long file.
PLUGIN_CLEAR_SAME_SENTENCE_REGEX='/plugin (install|uninstall|enable|disable)'

# PIN_* — the exact expected text of the six sentences that state the plugin-state-change hard-off
# or install-activation trigger. Each is normalized (see the scan loop's `tr -s ' '` below) so
# incidental re-wrapping at a different column width does not trip these, but every WORD must
# match. If you are editing one of these sentences: the reason it is pinned is that "a new session"
# is the only trigger output-styles.md and prompt-caching.md jointly guarantee for a plugin-state
# change to drop or pick up a `force-for-plugin` output style — `/clear` alone is not documented to
# do this, and `/reload-plugins` alone is not documented to either (its own reload list never names
# output styles). Update the constant deliberately, only after re-checking that guarantee still
# holds, never just to make a failing assertion pass.
# shellcheck disable=SC2016 # single-quoted deliberately, all six PIN_* below: literal expected
# file text, backtick-quoted commands and all, never shell command substitution.
PIN_README_INSTALL='Start a new session. The base rules load as an output style with `force-for-plugin: true` — no `/config` step — and a new session is the one thing this repo can promise makes that happen.'
# shellcheck disable=SC2016 # single-quoted deliberately: literal file text, not substitution.
PIN_README_HARDOFF='`/plugin disable squirrel@squirrel-mode`, then a new session, removes them from the system prompt entirely — the hard off.'
# shellcheck disable=SC2016 # single-quoted deliberately: literal file text, not substitution.
PIN_PLAN_HARDOFF='README documents `/plugin disable squirrel@squirrel-mode`, then a new session, as the hard off.'
# shellcheck disable=SC2016 # single-quoted deliberately: literal file text, not substitution.
PIN_ADR0005_HARDOFF='`/plugin disable squirrel@squirrel-mode`, then a new session, remains the hard off, and README documents it as such: it is the only path that truly removes the rules from the system prompt.'
# shellcheck disable=SC2016 # single-quoted deliberately: literal file text, not substitution.
PIN_SKILLS_OFF_HARDOFF='For a hard off that removes the rules from the system prompt entirely, run `/plugin disable squirrel@squirrel-mode`, then start a new session.'
# shellcheck disable=SC2016 # single-quoted deliberately: literal file text, not substitution.
PIN_SKILLS_ON_HARDOFF='The hard off is `/plugin disable squirrel@squirrel-mode`, then a new session. Running `/plugin enable squirrel@squirrel-mode`, then a new session, restores squirrel-mode from that state;'

# Path-level denylist for the visibility scan ONLY (see exclusion 2
# above). Category comment, not four per-file justifications: these are
# internal design records; the rule scopes to shipped instructions and
# user-facing docs (PLAN.md Section 5). docs/adr/ is excluded as a
# directory prefix, not as part of a blanket docs/* exclusion — files
# like docs/RESEARCH.md and docs/OTHER-TOOLS.md are user-facing and
# stay in scope.

# GLOSSARY_AVOID_REGEX — [U6 fix] the hand-picked, hand-collision-checked subset of CONTEXT.md's
# `_Avoid_` vocabulary this scan actually enforces (see exclusion 4 above for exactly which terms
# were left out and why). `grep -w` (word-regexp) bounds every alternative, single-word or
# multi-word, at both ends by a non-word character or string boundary — "host" cannot match inside
# "hosted" or "hostile", and "squirrel mode" (a literal space) cannot match "squirrel-mode" (a
# literal hyphen) regardless of -w, since the two are different characters to begin with.
GLOSSARY_AVOID_REGEX="host|platform|client|IDE|formatting rules|style rules|the skill|state file|session file|context file|changelog|completed tasks|backlog|icebox|drift detection|focus check|nag|onboarding|wizard|plugin name|package name|squirrel mode"

visibility_hits=""
marker_hits=""
non_exec_hits=""
invalid_json_hits=""
glossary_avoid_hits=""
same_sentence_hits=""

for f in $(git -C "$repo_root" ls-files); do
  # Executable-bit and JSON-validity: every tracked file, no exclusions.
  case "$f" in
    *.sh)
      if [ ! -x "$repo_root/$f" ]; then
        non_exec_hits="$non_exec_hits $f"
      fi
      ;;
  esac

  case "$f" in
    *.json)
      if ! jq empty "$repo_root/$f" >/dev/null 2>&1; then
        invalid_json_hits="$invalid_json_hits $f"
      fi
      ;;
  esac

  # Word-content scans: skip tests/* (self-reference, see exclusion 1).
  case "$f" in
    tests/*)
      continue
      ;;
  esac

  case "$f" in
    PLAN.md | docs/adr/* | CONTEXT.md | .build-checkpoint.md)
      # Denylisted path — excluded from the visibility scan by path
      # (see the category comment above VISIBILITY_REGEX / MARKER_REGEX).
      ;;
    *)
      if grep -qiE "$VISIBILITY_REGEX" "$repo_root/$f" 2>/dev/null; then
        visibility_hits="$visibility_hits $f"
      fi
      ;;
  esac

  if grep -qE "$MARKER_REGEX" "$repo_root/$f" 2>/dev/null; then
    marker_hits="$marker_hits $f"
  fi

  # /plugin install|uninstall|enable|disable + /clear, SAME SENTENCE scan: every tracked file that
  # reached this point in the loop (tests/* already `continue`d above, for the same self-reference
  # reason as MARKER_REGEX/VISIBILITY_REGEX). Deliberately NOT run through the
  # PLAN.md/docs/adr/CONTEXT.md/.build-checkpoint.md path denylist the visibility and glossary
  # scans use above: two of the five real occurrences of the disable/enable-side defect (ADR-0005
  # and PLAN.md) lived inside that denylist, so reusing it here would exempt precisely the files
  # that carried the bug — the same allowlist-shaped mistake the task that added this check was
  # written to prevent. See the PLUGIN_CLEAR_SAME_SENTENCE_REGEX comment above for why this replaced
  # the old distance-bounded version and what it does/does not guarantee.
  #
  # "Same sentence" = flatten newlines to spaces, then split on `.` so each resulting chunk is one
  # sentence-or-shorter; the first `grep` keeps only chunks containing a `/plugin <verb>`, the
  # second checks whether ANY of those SAME retained chunks also contains `/clear`. Because `grep`
  # never sees across its own line boundaries, a hit here is only possible when both anchors sit in
  # the same chunk — order does not matter, so one regex (not a FORWARD/BACKWARD pair) covers both.
  if printf '%s' "$(tr '\n' ' ' <"$repo_root/$f" 2>/dev/null)" | tr '.' '\n' \
    | grep -iE "$PLUGIN_CLEAR_SAME_SENTENCE_REGEX" 2>/dev/null | grep -qi '/clear' 2>/dev/null; then
    same_sentence_hits="$same_sentence_hits $f"
  fi

  # Glossary-term scan: markdown-family files only (see exclusion 4 above for why `.sh`/`.json`
  # etc. are out of scope structurally, not by denylist), minus the same internal-design-record
  # denylist the visibility scan uses — CONTEXT.md is the glossary itself and legitimately contains
  # every one of these terms, once each, on its own `_Avoid_` lines.
  case "$f" in
    *.md | *.mdc)
      case "$f" in
        PLAN.md | docs/adr/* | CONTEXT.md | .build-checkpoint.md)
          ;;
        *)
          if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$repo_root/$f" 2>/dev/null; then
            glossary_avoid_hits="$glossary_avoid_hits $f"
          fi
          ;;
      esac
      ;;
  esac
done

# 1. No tracked file (excl. tests/ and the path denylist above) may
#    claim checkpoint writes are invisible, unobservable, hidden from
#    the user, or happen without the user's knowledge.
assert_eq "" "$visibility_hits" "no tracked file may claim checkpoint writes are invisible/unobservable/hidden from the user/without the user's knowledge"

# 2. No tracked file (excl. tests/) contains a TODO, FIXME, or XXX
#    marker (syntax form: the word immediately followed by a colon or
#    an open parenthesis).
assert_eq "" "$marker_hits" "no tracked file may contain a TODO/FIXME/XXX marker (word followed by ':' or '(')"

# 3. Every tracked .sh file is executable.
assert_eq "" "$non_exec_hits" "every tracked .sh file must be executable"

# 4. Every tracked .json file is valid JSON.
assert_eq "" "$invalid_json_hits" "every tracked .json file must be valid JSON"

# 5. tests/run.sh fails cleanly (exit 1, no crash) when told to run a
#    test file that does not exist, instead of quietly reporting
#    success. Exercises assert_exit_code against a genuine repo
#    condition (see run.sh's "test file not found" branch).
assert_exit_code 1 sh "$script_dir/run.sh" "__no_such_test_file__.sh"

# 6. .shellcheckrc must stay tracked in git. It exists on disk and is
#    not gitignored, so `shellcheck` passes locally whether or not it is
#    staged — the only way a fresh checkout (CI cloning from the index)
#    notices it went missing is this assertion. `git ls-files
#    --error-unmatch` exits non-zero the moment the path is untracked or
#    does not exist, which is exactly the failure mode to catch.
assert_exit_code 0 git -C "$repo_root" ls-files --error-unmatch .shellcheckrc

# 7. [NEW, S8 review cycle 3, U6 MINOR fix] No tracked user-facing markdown-family file (excl. the
#    internal-design-record denylist — see exclusion 4 above) uses a reserved `_Avoid_` term from
#    CONTEXT.md's glossary in place of the canonical name it exists to enforce (e.g. "host
#    directories" instead of "target directories" — the actual README.md:106 regression this fix
#    was written against). Checked against the real repo (expect 0 files flagged), then against a
#    scratch copy of a real in-scope file with a reserved term injected (expect 1 flagged).
assert_eq "" "$glossary_avoid_hits" "no tracked user-facing markdown-family file may use a reserved _Avoid_ term from CONTEXT.md's glossary (see GLOSSARY_AVOID_REGEX, above) in place of its canonical name"

glossary_avoid_scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-glossary-avoid-test.XXXXXX")
trap 'rm -rf "$glossary_avoid_scratch"' EXIT
glossary_avoid_fixture="$glossary_avoid_scratch/bad_glossary_term.md"
printf '# Sample doc\n\nThe installers write to the host directories listed above.\n' >"$glossary_avoid_fixture"
if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$glossary_avoid_fixture" 2>/dev/null; then
  glossary_avoid_fixture_caught=yes
else
  glossary_avoid_fixture_caught=no
fi
assert_eq "yes" "$glossary_avoid_fixture_caught" "FAILURE PROOF (invariant 7): a scratch file reusing the exact 'host directories' regression must be caught by GLOSSARY_AVOID_REGEX"

# Sanity check the word-boundary matching itself: "hosted"/"hostile" (host as a SUBSTRING, not a
# whole word) must NOT trip the same regex, or this check would be far too broad to ship.
glossary_avoid_safe_fixture="$glossary_avoid_scratch/safe_substring.md"
printf '# Sample doc\n\nThis paragraph is hosted on a hostile-sounding but harmless server.\n' >"$glossary_avoid_safe_fixture"
if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$glossary_avoid_safe_fixture" 2>/dev/null; then
  glossary_avoid_safe_caught=yes
else
  glossary_avoid_safe_caught=no
fi
assert_eq "no" "$glossary_avoid_safe_caught" "sanity check: 'hosted'/'hostile' (the word 'host' as a SUBSTRING, not a whole word) must NOT trip GLOSSARY_AVOID_REGEX — word-boundary matching is what keeps this check from being too broad to ship"

# 8. [W4, replaces the V3/W3 proximity heuristic — see the HISTORY comment above PIN_* for why]
#    Exact-text pins on the six sentences that state the plugin-state hard-off/install-activation
#    trigger. Each must appear, word-for-word, in its file (whitespace-normalized only: `tr '\n' '
#    '` then `tr -s ' '`, so re-wrapping at a different column width does not trip this, but no word
#    may change). A failing pin names the exact constant to check against the PIN_* comment's
#    guarantee before updating it. This does NOT run through the PLAN.md/docs/adr/CONTEXT.md path
#    denylist other scans use — it checks these exact two files directly by path, the same as every
#    other file below.
readme_norm=$(tr '\n' ' ' <"$repo_root/README.md" 2>/dev/null | tr -s ' ') || readme_norm=""
plan_norm=$(tr '\n' ' ' <"$repo_root/PLAN.md" 2>/dev/null | tr -s ' ') || plan_norm=""
adr0005_norm=$(tr '\n' ' ' <"$repo_root/docs/adr/0005-session-flag-off-switch.md" 2>/dev/null | tr -s ' ') || adr0005_norm=""
skills_off_norm=$(tr '\n' ' ' <"$repo_root/skills/off/SKILL.md" 2>/dev/null | tr -s ' ') || skills_off_norm=""
skills_on_norm=$(tr '\n' ' ' <"$repo_root/skills/on/SKILL.md" 2>/dev/null | tr -s ' ') || skills_on_norm=""

if printf '%s' "$readme_norm" | grep -qF -- "$PIN_README_INSTALL" 2>/dev/null; then pin_readme_install=yes; else pin_readme_install=no; fi
assert_eq "yes" "$pin_readme_install" "README.md must contain PIN_README_INSTALL verbatim — this is the install-flow sentence claiming what makes the forced output style take effect; 'a new session' is the only docs-guaranteed trigger, so re-verify that guarantee before updating this constant"

if printf '%s' "$readme_norm" | grep -qF -- "$PIN_README_HARDOFF" 2>/dev/null; then pin_readme_hardoff=yes; else pin_readme_hardoff=no; fi
assert_eq "yes" "$pin_readme_hardoff" "README.md must contain PIN_README_HARDOFF verbatim — the /squirrel:off hard-off sentence; re-verify 'a new session' is still the only docs-guaranteed trigger before updating this constant"

if printf '%s' "$plan_norm" | grep -qF -- "$PIN_PLAN_HARDOFF" 2>/dev/null; then pin_plan_hardoff=yes; else pin_plan_hardoff=no; fi
assert_eq "yes" "$pin_plan_hardoff" "PLAN.md must contain PIN_PLAN_HARDOFF verbatim — re-verify 'a new session' is still the only docs-guaranteed trigger before updating this constant"

if printf '%s' "$adr0005_norm" | grep -qF -- "$PIN_ADR0005_HARDOFF" 2>/dev/null; then pin_adr0005_hardoff=yes; else pin_adr0005_hardoff=no; fi
assert_eq "yes" "$pin_adr0005_hardoff" "docs/adr/0005-session-flag-off-switch.md must contain PIN_ADR0005_HARDOFF verbatim — re-verify 'a new session' is still the only docs-guaranteed trigger before updating this constant"

if printf '%s' "$skills_off_norm" | grep -qF -- "$PIN_SKILLS_OFF_HARDOFF" 2>/dev/null; then pin_skills_off_hardoff=yes; else pin_skills_off_hardoff=no; fi
assert_eq "yes" "$pin_skills_off_hardoff" "skills/off/SKILL.md must contain PIN_SKILLS_OFF_HARDOFF verbatim — re-verify 'a new session' is still the only docs-guaranteed trigger before updating this constant"

if printf '%s' "$skills_on_norm" | grep -qF -- "$PIN_SKILLS_ON_HARDOFF" 2>/dev/null; then pin_skills_on_hardoff=yes; else pin_skills_on_hardoff=no; fi
assert_eq "yes" "$pin_skills_on_hardoff" "skills/on/SKILL.md must contain PIN_SKILLS_ON_HARDOFF verbatim (covers both the disable and enable clauses) — re-verify 'a new session' is still the only docs-guaranteed trigger before updating this constant"

# 9. [W4] Global same-sentence scan (see PLUGIN_CLEAR_SAME_SENTENCE_REGEX comment above for what
#    this does and does not guarantee). Checked against the real repo (expect 0 files), then a
#    scratch fixture adding a BRAND-NEW same-sentence violation to a file none of the six pins
#    cover, and a scratch fixture reproducing the shape README/PLAN.md still legitimately ship
#    today (a /plugin verb and a separate, later-sentence /clear) that must NOT be flagged.
assert_eq "" "$same_sentence_hits" "no tracked file may mention /clear in the SAME SENTENCE as a /plugin install/uninstall/enable/disable verb (see PLUGIN_CLEAR_SAME_SENTENCE_REGEX, above)"

# FAILURE PROOF: a brand-new violation, in a file none of the six PIN_* constants cover, proving
# the global scan — not just the six pins — is what would catch a seventh occurrence of this defect.
same_sentence_fixture="$glossary_avoid_scratch/same_sentence_violation.md"
# shellcheck disable=SC2016 # single-quoted deliberately: literal fixture text, not substitution.
printf 'Running `/plugin install squirrel@squirrel-mode` and then `/clear` finishes the setup.\n' >"$same_sentence_fixture"
if printf '%s' "$(tr '\n' ' ' <"$same_sentence_fixture")" | tr '.' '\n' \
  | grep -iE "$PLUGIN_CLEAR_SAME_SENTENCE_REGEX" 2>/dev/null | grep -qi '/clear' 2>/dev/null; then
  same_sentence_fixture_caught=yes
else
  same_sentence_fixture_caught=no
fi
assert_eq "yes" "$same_sentence_fixture_caught" "FAILURE PROOF (invariant 9): a brand-new /plugin-verb-and-/clear-in-one-sentence violation, in a file none of the six PIN_* constants cover, must be caught by the global same-sentence scan"

# SAFETY PROOF: a /plugin disable mention and a separate, correct /clear mention about an unrelated
# output-style setting/content change, in a later, DIFFERENT sentence of the same file, must NOT
# trip this check. This is the shape README's "Checking it's active" section and PLAN's "Iterate"
# step still legitimately ship today — /clear entirely on its own, for the output-style *setting or
# content* refresh output-styles.md documents directly, with no `/plugin` verb in that sentence.
same_sentence_safe_fixture="$glossary_avoid_scratch/same_sentence_safe.md"
# shellcheck disable=SC2016 # single-quoted deliberately: literal fixture text, not substitution.
printf '`/plugin disable squirrel@squirrel-mode` suspends the plugin for future sessions. Separately, if an output style setting is not taking effect, run `/clear` or start a new session.\n' >"$same_sentence_safe_fixture"
if printf '%s' "$(tr '\n' ' ' <"$same_sentence_safe_fixture")" | tr '.' '\n' \
  | grep -iE "$PLUGIN_CLEAR_SAME_SENTENCE_REGEX" 2>/dev/null | grep -qi '/clear' 2>/dev/null; then
  same_sentence_safe_caught=yes
else
  same_sentence_safe_caught=no
fi
assert_eq "no" "$same_sentence_safe_caught" "sanity check: a /plugin verb and an UNRELATED /clear mention in a separate, later sentence of the same file must NOT trip the global same-sentence scan"

assert_report
