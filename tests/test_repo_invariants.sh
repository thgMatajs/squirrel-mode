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
# 1) There are now FOUR word-content scans below — visibility claims,
#    TODO/FIXME/XXX markers, the glossary-avoid-term scan, and the
#    /plugin+/clear same-sentence scan — and all four skip everything
#    under `tests/` (via the single `continue` in the main loop, right
#    before the visibility-scan case statement). Without this, the
#    assertion messages and comments in THIS file — which necessarily
#    name the very markers/phrases/terms they check for, to describe
#    what the checks do — would trip the checks they implement. This is
#    a self-reference problem specific to these four content scans (this
#    comment block itself was stale at "the two WORD-CONTENT scans" for
#    a while after the third and fourth were added — fixed in S9's
#    sweep; if a fifth word-content scan is ever added here, update this
#    count again rather than letting it drift a second time). It does
#    NOT apply to the executable-bit or JSON-validity checks below:
#    those have no self-reference problem, so they run over every
#    tracked file, `tests/` included (that gap previously let a missing
#    +x bit on the test runner itself go undetected).
#
# 2) The visibility scan ALSO excludes a fixed set of whole paths —
#    PLAN.md, docs/adr/, CONTEXT.md, and .build-checkpoint.md — by path, not by line content (see
#    the denylist case pattern in the scan loop below, and the category comment just above it).
#    This is a denylist, not an allowlist: every OTHER path, including ones a later build step
#    introduces (e.g. docs/RESEARCH.md, docs/OTHER-TOOLS.md — both user-facing and deliberately
#    NOT excluded), stays in scope by default. Only docs/adr/ is excluded, not all of docs/.
#    docs/ACCEPTANCE.md is DELIBERATELY NOT on this whole-path list and carries NO exemption of
#    ANY KIND -- not a whole-file skip, not a per-line rule, nothing. Two narrower designs were
#    tried here first and BOTH failed:
#      [S9, first pass] a blanket whole-file exemption -- a made-up sentence appended anywhere in
#      the file passed clean, because "this file quotes PLAN.md Section 5 verbatim" supports
#      exempting one heading line, not the whole document.
#      [S9 fix cycle 1, Y1] a narrower per-line rule -- a flagged line was permitted only when that
#      exact line's own text, whitespace-normalized, also appeared as a contiguous substring of
#      PLAN.md's own Section 5 text, computed fresh every run. [S9 review cycle 2, Z1] Defeated by
#      an ordinary line break: a false checkpoint-invisibility claim split across three lines has
#      its middle line read, IN ISOLATION, as a short fragment that happens to be a substring of
#      the criterion that bans it -- the ban and the claim necessarily share vocabulary -- so the
#      per-line check let it through even though no human reading the paragraph would call it a
#      quote.
#    [S9 review cycle 2, Z1] Both designs are deleted outright, not tightened a third time: the
#    fix removes the CONDITION under which docs/ACCEPTANCE.md was allowed to reproduce the banned
#    phrasing, rather than tuning that condition again. docs/ACCEPTANCE.md's own criterion 19 no
#    longer quotes PLAN.md Section 5's criterion 19 verbatim -- it states the criterion by number
#    and paraphrase and points back to PLAN.md for the exact wording (see docs/ACCEPTANCE.md's own
#    "Note on how this scan treats docs/ACCEPTANCE.md itself" for the full reasoning) -- so it
#    never reproduces the banned phrasing anywhere and needs no exemption to pass this scan. There
#    is no docs/ACCEPTANCE.md arm left in the case statement in the scan loop below at all; it
#    falls through to the same unconditional `*)` branch as every other tracked file. This
#    exclusion/narrowing question applies to the visibility scan ONLY -- the marker,
#    executable-bit, and JSON-validity scans below have no scoping question and run over every
#    tracked file with no path denylist.
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
#         .build-checkpoint.md whole-path denylist the visibility scan's category-2 exclusions use
#         — CONTEXT.md is the glossary itself and would trip on its own `_Avoid_` line for every
#         term listed there. [S9 fix cycle 1, Y1] docs/ACCEPTANCE.md is DELIBERATELY NOT on this
#         denylist: it once was, on the same "audit record, not a user-facing doc" reasoning given
#         for CONTEXT.md above, but that reasoning has no support here — `grep -nwiE
#         "$GLOSSARY_AVOID_REGEX" docs/ACCEPTANCE.md` returns zero hits against the real file, so the
#         exemption was protecting against nothing, and docs/ACCEPTANCE.md's own "Note on its own
#         exclusion" section disclosed only the visibility-scan exemption, never this one — an
#         undisclosed scope change the document's own stated promise (report every scope change
#         plainly) does not allow. Deleted outright rather than narrowed, since there was nothing to
#         narrow to. `.sh` files are excluded structurally (not by denylist) because this project's
#         own shell
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
#
# 5) [S9] The fourth word-content scan — the /plugin-verb + /clear SAME-SENTENCE check (see
#    PLUGIN_CLEAR_SAME_SENTENCE_REGEX below) — is deliberately NOT run through the PLAN.md/
#    docs/adr/CONTEXT.md/.build-checkpoint.md path denylist categories 2 and 4 use. Two of the five
#    real occurrences of the defect this scan catches lived inside that denylist (ADR-0005 and
#    PLAN.md itself) — reusing the denylist here would have exempted precisely the files that
#    carried the bug. It still skips `tests/` (category 1, self-reference), the same as the other
#    three word-content scans, but applies to every OTHER tracked file with no further exclusion.
#    This was previously documented only inline at the scan's own call site, not summarised here
#    with the other exclusion categories — fixed in the same S9 sweep that corrected item 1's count.

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
      # [S9 review cycle 2, Z1] docs/ACCEPTANCE.md has no arm of its own here any more (see the
      # category-2 comment above VISIBILITY_REGEX/MARKER_REGEX for the two exemption designs that
      # were tried and deleted): it falls into this same unconditional branch as every other
      # in-scope file, no special-casing at all.
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
  # every one of these terms, once each, on its own `_Avoid_` lines. [S9 fix cycle 1, Y1]
  # docs/ACCEPTANCE.md is deliberately NOT on this denylist (see exclusion 4 above): its old
  # exemption here had zero real hits to protect against and was never disclosed in this document's
  # own "Note on its own exclusion" section, so it is deleted outright rather than narrowed.
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

# [S9 review cycle 2, Z1 — BLOCKER fix, replaces the Y1 per-line exemption above] The narrowed
# PLAN.md-derived allow-list (plan_section5_flat / acceptance_visibility_bad_line_found) that used
# to live here is deleted outright, not tightened a third time (see the category-2 comment above
# VISIBILITY_REGEX for the mechanism and why it failed). docs/ACCEPTANCE.md has no special-case
# arm left in the loop above at all — it is scanned by the exact same unconditional per-file
# `grep -qiE "$VISIBILITY_REGEX"` as every other tracked file, and its own criterion 19 has been
# rewritten to state the criterion by number and paraphrase, pointing to PLAN.md Section 5 for the
# verbatim wording, so it never reproduces the banned phrasing and never needs an exemption.
# Mutation-proved below against the CURRENT docs/ACCEPTANCE.md: the exact reproduction from the
# review (a checkpoint-write-invisibility claim split across a line break, so no single line the
# OLD per-line exemption inspected was ever the full claim) and a single-line variant of the
# identical claim, proving the fix is not merely reacting to the specific shape of a line break.
z1_scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-z1-test.XXXXXX")
trap 'rm -rf "$z1_scratch"' EXIT

z1_threeline_fixture="$z1_scratch/ACCEPTANCE_threeline.md"
cp "$repo_root/docs/ACCEPTANCE.md" "$z1_threeline_fixture"
printf '\nsquirrel-mode deliberately keeps every checkpoint write\nhidden from the user.\nThis is a feature, not an oversight.\n' >>"$z1_threeline_fixture"
if grep -qiE "$VISIBILITY_REGEX" "$z1_threeline_fixture" 2>/dev/null; then
  z1_threeline_caught=yes
else
  z1_threeline_caught=no
fi
assert_eq "yes" "$z1_threeline_caught" "FAILURE PROOF (invariant 1, Z1): the exact three-line reproduction from S9 review cycle 2 (a checkpoint-write-invisibility claim split across a line break, once let through by the now-deleted per-line PLAN.md allow-list) must be caught now that docs/ACCEPTANCE.md has no exemption of any kind"

z1_oneline_fixture="$z1_scratch/ACCEPTANCE_oneline.md"
cp "$repo_root/docs/ACCEPTANCE.md" "$z1_oneline_fixture"
printf '\nsquirrel-mode deliberately keeps every checkpoint write hidden from the user. This is a feature, not an oversight.\n' >>"$z1_oneline_fixture"
if grep -qiE "$VISIBILITY_REGEX" "$z1_oneline_fixture" 2>/dev/null; then
  z1_oneline_caught=yes
else
  z1_oneline_caught=no
fi
assert_eq "yes" "$z1_oneline_caught" "FAILURE PROOF (invariant 1, Z1): the single-line variant of the identical claim must also be caught, proving the fix removed the exemption mechanism rather than reacting to line breaks specifically"

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

# [S9 fix cycle 1, Y1] FAILURE PROOF: with docs/ACCEPTANCE.md's glossary-scan exemption deleted
# outright, the scan's OWN failure fixture sentence above, appended to a scratch copy of the
# real docs/ACCEPTANCE.md, must now be caught the same way it is for any other in-scope file.
y1_glossary_fixture="$glossary_avoid_scratch/ACCEPTANCE_glossary.md"
cp "$repo_root/docs/ACCEPTANCE.md" "$y1_glossary_fixture"
printf '\nThe installers write only to the host directories listed above.\n' >>"$y1_glossary_fixture"
if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$y1_glossary_fixture" 2>/dev/null; then
  y1_glossary_caught=yes
else
  y1_glossary_caught=no
fi
assert_eq "yes" "$y1_glossary_caught" "FAILURE PROOF (invariant 7, Y1): with docs/ACCEPTANCE.md's glossary-scan exemption deleted, appending 'The installers write only to the host directories listed above.' to it must be caught"

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

# ================================================================================================
# 10. [S9, PLAN.md Section 5: "No network calls, no telemetry anywhere"] No SHIPPED script (the
#     ones a user's install actually runs: scripts/*.sh, discovered via git ls-files so a script
#     added by a later step is covered automatically, and targets/*/install.sh, named explicitly
#     because "shipped" here means "installer entry point," not every file under targets/)
#     invokes a network-capable command. tests/*.sh is deliberately OUT of scope — it is dev/CI
#     tooling, never installed onto a user's machine by either target. [S9 fix cycle 1, Y6
#     correction] scripts/build.sh is NOT excluded the same way: the `scripts/*.sh` glob below
#     matches every file directly under scripts/, build.sh included, so it IS scanned along with
#     the other three shipped scripts — confirmed by `git ls-files 'scripts/*.sh'` listing all
#     four. The prior wording here claimed otherwise; corrected to match what the code actually
#     does, not what it was originally meant to do.
#
#     "Invokes" means the command name appears as a whole word (`grep -w`, so an identifier like
#     `codex_home` or `agents_skills_dir` can never collide with a bare command name) on a line
#     whose first non-whitespace character is not '#' — every shipped script in this repo puts ALL
#     of its prose commentary on dedicated, full-line comments (hand-verified before this check
#     shipped: grepping every shipped script for a trailing "code # comment" on the same physical
#     line turns up only awk/parameter-expansion uses of '#' — `${var#pattern}`, `${#var}`, awk
#     regex literals like `/^### /` — never a genuine trailing comment), so stripping whole-line
#     comments is exact for this corpus, not an approximation that would only work by accident
#     against the text it was written to match (the recurring failure class named at the top of
#     this file). Checked against the real repo (expect 0 hits), then against a scratch copy of a
#     real shipped script with a real network call injected on its own CODE line (expect 1 hit),
#     AND a scratch copy with the identical text injected as a COMMENT instead (expect 0 hits —
#     proving this is not the "matches inside a comment" false-positive class scripts/
#     allow-checkpoint.sh's own header comment about ".ssh/id_rsa" would otherwise trip: an earlier,
#     uncommented draft of this exact check matched that comment before comment-stripping was
#     added).
# ================================================================================================
NETWORK_COMMAND_REGEX="curl|wget|fetch|nc|ncat|netcat|socat|ssh|scp|sftp|ftp|tftp|telnet|rsync|ping|traceroute|tracepath|nslookup|dig|drill|whois|openssl|python|python3|perl|ruby|node|nodejs|php|lwp-request|lynx|w3m|links"

network_hits=""
shipped_scripts=$(git -C "$repo_root" ls-files 'scripts/*.sh')
shipped_scripts="$shipped_scripts
targets/codex/install.sh
targets/cursor/install.sh"
old_ifs=$IFS
IFS='
'
for f in $shipped_scripts; do
  [ -n "$f" ] || continue
  [ -f "$repo_root/$f" ] || continue
  code_only=$(grep -vE '^[[:space:]]*#' "$repo_root/$f" 2>/dev/null || true)
  if printf '%s\n' "$code_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
    network_hits="$network_hits $f"
  fi
done
IFS=$old_ifs
assert_eq "" "$network_hits" "no shipped script (scripts/*.sh, targets/*/install.sh) may invoke a network-capable command (see NETWORK_COMMAND_REGEX, above)"

network_code_fixture="$glossary_avoid_scratch/network_code.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_code_fixture"
printf '\ncurl https://example.com/exfiltrate >/dev/null 2>&1\n' >>"$network_code_fixture"
fixture_code_only=$(grep -vE '^[[:space:]]*#' "$network_code_fixture" 2>/dev/null || true)
if printf '%s\n' "$fixture_code_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_code_fixture_caught=yes
else
  network_code_fixture_caught=no
fi
assert_eq "yes" "$network_code_fixture_caught" "FAILURE PROOF (invariant 10, code line): a real curl invocation appended as a genuine code line to a real shipped script must be caught"

network_comment_fixture="$glossary_avoid_scratch/network_comment.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_comment_fixture"
printf '\n# example of what NOT to do: curl https://example.com/exfiltrate would be a network call\n' >>"$network_comment_fixture"
fixture_comment_only=$(grep -vE '^[[:space:]]*#' "$network_comment_fixture" 2>/dev/null || true)
if printf '%s\n' "$fixture_comment_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_comment_fixture_caught=yes
else
  network_comment_fixture_caught=no
fi
assert_eq "no" "$network_comment_fixture_caught" "sanity check: the identical text placed inside a full-line comment must NOT be caught — this check scans CODE, not the prose that happens to describe an attack path (e.g. this very file's own '.ssh/id_rsa' comment, or allow-checkpoint.sh's identical comment)"

# --- 11. docs/ACCEPTANCE.md's probe-6 citation is the corrected one (S9 fix cycle 1, Y4) --------
#
# `.build-checkpoint.md` originally attributed probe 6's three lettered choices to "rule 9's
# multiple-choice-question exemption (noted in docs/RESEARCH.md)" -- docs/RESEARCH.md:606 does not
# support that; it is about rule 3's max_list_items cap not applying to rule 9's own multi-question
# answers, and says nothing about options_per_answer or a clarifying question's choices.
# docs/ACCEPTANCE.md had inherited the same false citation. Pinned here, by exact substring, so the
# corrected reference (rule 6's own carve-out, added as Y3) cannot silently rot back to the
# unsupported one without this assertion catching it.
ACCEPTANCE_Y4_FIX_PHRASE="rule 6's own carve-out for a clarifying question's choices"
if grep -qF -- "$ACCEPTANCE_Y4_FIX_PHRASE" "$repo_root/docs/ACCEPTANCE.md" 2>/dev/null; then
  acceptance_y4_pin_present=yes
else
  acceptance_y4_pin_present=no
fi
assert_eq "yes" "$acceptance_y4_pin_present" "docs/ACCEPTANCE.md must cite rule 6's carve-out (not rule 9 / docs/RESEARCH.md) for probe 6's three lettered choices"

# --- 12. Every docs/ACCEPTANCE.md criterion heading is byte-identical to its
# PLAN.md Section 5 source, criterion 19 excepted by name (S9 review cycle 3,
# AA4) -------------------------------------------------------------------------
#
# This repo already treated a missing-emphasis gap on criterion 19's heading as a real defect (S9
# fix cycle 1, Y4's third finding: the heading was missing the markdown emphasis around "error" that
# PLAN.md's own copy has). Criteria 3, 9, and 12 had the identical class of drift — their headings
# dropped PLAN.md's `**first**`/`**every**`, `**stays**`, and `**no permission prompt and no prose in
# the response**` bold emphasis respectively — and nothing generic caught it; only Y4's one-off,
# hand-written pin for criterion 19 existed. This closes the CLASS, not just those three instances:
# every criterion heading in docs/ACCEPTANCE.md is derived fresh from its own "## N. " line, every
# corresponding PLAN.md Section 5 checklist item is derived fresh from PLAN.md's own text (dewrapped:
# PLAN.md hard-wraps several items across multiple lines with a 6-space continuation indent, joined
# here with a single space per continuation line, matching how docs/ACCEPTANCE.md's own single-line
# headings were written), and the two are compared byte-for-byte. Criterion 19 is excepted BY NUMBER,
# not by any text-shaped exemption: docs/ACCEPTANCE.md's own criterion 19 states, in its own section,
# why it deliberately paraphrases rather than quotes verbatim (PLAN.md Section 5's criterion 19 is
# worded using the exact phrases the checkpoint-visibility scan above forbids, so quoting it verbatim
# would trip that scan) — this is a stated, reasoned exception, not a narrowing of what "verbatim"
# means for the other 18.
#
# Neither side is hand-copied: a future edit to either file's wording, without updating the other, is
# exactly what this assertion is built to catch, INCLUDING silently dropping one emphasis marker
# (**bold**/*italic*) from either copy — a hostile reading of "quoted verbatim" if this document's own
# claim to that effect is to mean anything.
plan_file="$repo_root/PLAN.md"
acceptance_file="$repo_root/docs/ACCEPTANCE.md"

extract_plan_criteria() {
  # Prints one Section 5 checklist item per output line, dewrapped (hard-wrap
  # continuation lines joined with a single space, "- [ ] " prefix stripped).
  awk '
    /^## 5\. ACCEPTANCE CRITERIA/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec {
      line = $0
      if (line ~ /^- \[ \] /) {
        if (item != "") print item
        sub(/^- \[ \] /, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        item = line
      } else {
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line != "") { item = (item == "" ? line : item " " line) }
      }
    }
    END { if (item != "") print item }
  ' "$1"
}

extract_acceptance_numbers() {
  # Prints the leading number of every "## N. ..." criterion heading, one per line.
  awk '
    /^## [0-9]+\. / {
      line = $0
      sub(/^## /, "", line)
      dot = index(line, ". ")
      print substr(line, 1, dot - 1)
    }
  ' "$1"
}

extract_acceptance_texts() {
  # Prints the text of every "## N. ..." criterion heading (number and ". " stripped), one per line.
  awk '
    /^## [0-9]+\. / {
      line = $0
      sub(/^## /, "", line)
      dot = index(line, ". ")
      print substr(line, dot + 2)
    }
  ' "$1"
}

plan_criteria=$(extract_plan_criteria "$plan_file")
plan_criteria_count=$(printf '%s\n' "$plan_criteria" | grep -c '.' || true)
assert_eq "19" "$plan_criteria_count" "sanity check: PLAN.md Section 5 must itself contain exactly 19 checklist items (protects the derivation, not docs/ACCEPTANCE.md's text)"

acceptance_numbers=$(extract_acceptance_numbers "$acceptance_file")
acceptance_number_sequence=$(printf '%s\n' "$acceptance_numbers" | tr '\n' ' ' | sed 's/ *$//')
assert_eq "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19" "$acceptance_number_sequence" "docs/ACCEPTANCE.md's criterion headings must be numbered 1..19, in order, no gaps, no duplicates (protects the derivation)"

acceptance_texts=$(extract_acceptance_texts "$acceptance_file")

mismatched_criteria=""
n=0
old_ifs=$IFS
IFS='
'
for acc_text in $acceptance_texts; do
  n=$((n + 1))
  if [ "$n" = "19" ]; then
    # Criterion 19 is deliberately paraphrased; excepted by number, not by text shape (see comment
    # block above this invariant).
    continue
  fi
  plan_text=$(printf '%s\n' "$plan_criteria" | sed -n "${n}p")
  if [ "$acc_text" != "$plan_text" ]; then
    mismatched_criteria="$mismatched_criteria $n"
  fi
done
IFS=$old_ifs
assert_eq "" "$mismatched_criteria" "every docs/ACCEPTANCE.md criterion heading, except criterion 19 (deliberately paraphrased, stated as such in its own section), must be byte-identical to PLAN.md Section 5's corresponding checklist item"

# FAILURE PROOF (AA4): dropping a single emphasis marker from one heading, in a scratch copy, must
# be caught. Mirrors the exact regression this assertion exists to prevent: criterion 3's heading
# reverted from "**first**"/"**every**" back to plain "first"/"every".
#
# Reuses $glossary_avoid_scratch (created earlier in this file) rather than mktemp-ing a fresh
# directory of its own — the same pattern same_sentence_fixture and network_code_fixture already
# follow below. `trap ... EXIT` REPLACES the previous handler in POSIX sh rather than stacking with
# it, so a fourth `mktemp -d` + `trap` pair here would silently stop $glossary_avoid_scratch itself
# from ever being cleaned up on exit — a leak this fix would introduce, not fix. (z1_scratch, set up
# even earlier, is already superseded by glossary_avoid_scratch's own trap this same way; that is
# pre-existing residue from before this cycle, not something to silently expand scope to fix here.)
aa4_fixture="$glossary_avoid_scratch/ACCEPTANCE_mutated.md"
sed 's/on the \*\*first\*\* message/on the first message/; s/and on \*\*every\*\* message/and on every message/' "$acceptance_file" >"$aa4_fixture"

aa4_mutated_texts=$(extract_acceptance_texts "$aa4_fixture")
aa4_mismatched=""
n=0
IFS='
'
for acc_text in $aa4_mutated_texts; do
  n=$((n + 1))
  if [ "$n" = "19" ]; then
    continue
  fi
  plan_text=$(printf '%s\n' "$plan_criteria" | sed -n "${n}p")
  if [ "$acc_text" != "$plan_text" ]; then
    aa4_mismatched="$aa4_mismatched $n"
  fi
done
IFS=$old_ifs
assert_eq " 3" "$aa4_mismatched" "FAILURE PROOF (invariant 12, AA4): dropping the '**first**'/'**every**' emphasis from criterion 3's heading in a scratch copy must be caught, and only criterion 3 must be flagged"

# --- 13. No docs/ACCEPTANCE.md criterion marked `observed` may also claim
# its own probe was not run or never observed (S10, AB3) ---------------------
#
# AB3's finding: criteria 10, 11, and 14 each said, in their own section, that
# a probe "remain[ed] untested by any live run", "was never observed live", or
# "which was not run" - true when S9 shipped, false once a later S10 probe (B,
# C, D, E, F, or G) actually ran it, and docs/ACCEPTANCE.md was not updated to
# match .build-checkpoint.md's own probe log. Fixed for those three
# (criteria 11 and 14 moved to `observed`; criterion 10 stayed `manual`,
# correctly - see its own section for the one branch that genuinely remains
# untested). This guards the CLASS: a future probe that closes a `manual`
# criterion, but whose docs/ACCEPTANCE.md update misses one stale
# not-run/never-observed sentence elsewhere in that same criterion's section,
# is caught rather than shipped silently self-contradictory. Scoped to only
# the criteria whose own "**Status:**" line says `observed` - a `manual`
# criterion is explicitly allowed to say a specific sub-case was not run
# (that is the honest, correct thing for it to say), so this must not scan
# those.
#
# UPDATED (S10 review cycle 2, AC3, BLOCKER-class evasion). This scan used to
# run `grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"` directly against a criterion's
# multi-line section text, piped line by line - `grep` matches WITHIN one
# line, never across a newline, so any evasion that puts a newline in the
# middle of the banned wording defeated it outright: reproduced for a
# line-break mid-phrase and for a two-sentence rewrite whose second sentence
# still carries the retired wording split across a line - both left the real
# suite at 34/0 (34 assertions for this invariant, zero failures - the scan
# did not fire on either). Fixed by FLATTENING each criterion's section -
# joining its lines and squeezing whitespace to single spaces - before the
# regex ever runs, via flatten_acceptance_section() below. This closes both
# evasions mechanically: once every line-break-shaped whitespace run becomes
# one space, the banned phrase's words are contiguous again regardless of
# where in the source text they happened to wrap, whether that wrap was a
# bare mid-phrase break or the byproduct of splitting one sentence into two.
#
# WHAT THIS DOES NOT CATCH, STATED PLAINLY: a genuine PARAPHRASE - different
# words carrying the identical retired claim, with no literal overlap with
# any alternative in ACCEPTANCE_NOT_RUN_REGEX at all (e.g. "nobody has yet
# watched this happen live" for "was never observed") - is not something a
# literal-phrase regex can ever catch, flattened or not, and no amount of
# narrowing this pattern changes that. This is a permanent limitation of the
# mechanism, not a gap this cycle's fix closes; see the demonstration below,
# which documents it as an accepted, tested boundary rather than an implicit
# claim of completeness. Catching a paraphrase is a job for the four-check
# review policy, not for grep.
ACCEPTANCE_NOT_RUN_REGEX="was not run|never observed|not observed|remains? untested by any (live )?run|was never (run|observed|reached)|has not (yet )?(been )?(run|observed)|no probe (has )?(ever )?ran"

get_acceptance_section() {
  # get_acceptance_section <content> <n> - the lines of a docs/ACCEPTANCE.md-
  # shaped criterion <n>'s own section: from its "## <n>. " heading
  # (inclusive) to the next "## " heading (exclusive) or EOF. Takes CONTENT
  # (not a path) so this doubles as the mutation-proof extractor below,
  # never re-reading the tracked file for the fixture case.
  content=$1
  n=$2
  printf '%s\n' "$content" | awk -v want="$n" '
    $0 ~ ("^## " want "\\. ") { in_sec = 1; print; next }
    in_sec && /^## / { in_sec = 0 }
    in_sec { print }
  '
}

flatten_acceptance_section() {
  # flatten_acceptance_section <section-text> - flattens PER PARAGRAPH, not
  # per whole section: each blank-line-separated paragraph becomes its own
  # single output LINE, with runs of whitespace (including the newlines
  # just introduced by joining that one paragraph's own lines) squeezed to
  # a single space. Every call site below pipes this function's output
  # into a line-oriented `grep -qiE` - which never matches across a
  # newline - so bounding to one paragraph per output line makes the
  # not-run/never-observed scan immune to a line-break landing in the
  # middle of the banned wording WITHIN one paragraph (a bare mid-phrase
  # wrap and a two-sentence rewrite that happens to wrap there are
  # indistinguishable to this function, deliberately - see AC3 below),
  # while never joining text from two DIFFERENT paragraphs together at
  # all - see AD4 below for why that boundary matters.
  #
  # UPDATED (S10 review cycle 3 final gate, AD4 - UNDISCLOSED FALSE-
  # POSITIVE CLASS). The original version of this function (S10 review
  # cycle 2, AC3) joined the ENTIRE section - every paragraph, table row,
  # and list item in a criterion, with no boundary anywhere - into ONE
  # line before scanning. That closed the two real evasions (below) but
  # opened an undisclosed hole: joining a criterion's lines can spell a
  # banned phrase across a PARAGRAPH boundary that has nothing to do with
  # either evasion. Concretely: a paragraph ending "...confidence in this
  # feature has not" followed by a blank line and an UNRELATED paragraph
  # beginning "run into any blockers so far..." flattens, whole-section,
  # to "...has not run into any blockers..." - which matches
  # ACCEPTANCE_NOT_RUN_REGEX's "has not (yet )?(been )?(run|observed)"
  # alternative even though the actual claim is the opposite of untested
  # (the feature has NOT run into any blockers). That is a coincidental
  # false positive against a criterion that claims nothing, not a defeated
  # evasion - and the failure mode is a BLOCKED BUILD, not a shipped
  # defect, so this was disclosed rather than silently left as a risk (see
  # the demonstration mutant below).
  #
  # THE FIX, and what it does and does not close. Flattening is now scoped
  # to one paragraph at a time (`awk 'BEGIN{RS=""} ...'` - "paragraph
  # mode", where a record is everything between blank lines - splits the
  # section into paragraphs BEFORE any whitespace-squeezing happens), so
  # text can never be joined across a blank line - the exact mechanism the
  # false positive above depends on. Both real evasions still live
  # entirely WITHIN one paragraph (the retired sentence is inserted as a
  # single block with no blank line inside it, whether hard-wrapped
  # mid-phrase or split into two sentences), so bounding to the paragraph
  # they are already inside changes nothing about catching them - proven
  # below by re-running both existing failure-proof mutants unchanged.
  # What this does NOT close, disclosed rather than left implicit: a
  # coincidental match can still occur WITHIN a single paragraph - an
  # ordinary line-wrap landing between two unrelated sentences that share
  # one paragraph, or a wrap in the middle of one sentence with no blank
  # line involved at all. That narrower residual predates this whole
  # mechanism: a banned phrase already sitting on ONE physical line,
  # unwrapped, was always a coincidental-match risk this literal-phrase
  # regex could produce, flattened or not, paragraph-bounded or not - it
  # is not something flattening introduced and paragraph-bounding cannot
  # remove it. Closing it fully would need bounding to a SENTENCE instead
  # of a paragraph, which was considered and rejected: sentence boundaries
  # are not mechanically detectable the way a blank line is (a
  # period-based splitter would also fire on abbreviations, decimal
  # version numbers, and markdown's own "1. " list syntax), and a narrower
  # heuristic with its own undisclosed holes is the exact anti-pattern
  # this project has hit and rejected repeatedly elsewhere (Layer 3's
  # realpath comparison, the sed-based nested-JSON isolation this build
  # eventually removed rather than narrowed again). A false positive here
  # blocks a build rather than shipping a defect, so disclosure is the
  # proportionate response to the residual, not a fourth narrowing.
  printf '%s\n' "$1" | awk '
    BEGIN { RS = "" }
    {
      gsub(/[\n\t]/, " ")
      gsub(/  +/, " ")
      print
    }
  '
}

acceptance_content=$(cat "$acceptance_file")
observed_not_run_criteria=""
n13=1
while [ "$n13" -le 19 ]; do
  section13=$(get_acceptance_section "$acceptance_content" "$n13")
  status13_line=$(printf '%s\n' "$section13" | grep '^\*\*Status:\*\*' | head -n 1)
  section13_flat=$(flatten_acceptance_section "$section13")
  # shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status value in the case pattern below, not command substitution.
  case "$status13_line" in
    *'`observed`'*)
      if printf '%s\n' "$section13_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
        observed_not_run_criteria="$observed_not_run_criteria $n13"
      fi
      ;;
  esac
  n13=$((n13 + 1))
done
assert_eq "" "$observed_not_run_criteria" "no docs/ACCEPTANCE.md criterion marked \`observed\` may also contain a sentence claiming its own probe was not run or never observed (S10 AB3 class guard; AC3: matched on the FLATTENED section text, immune to a line-break or two-sentence split inside the banned wording)"

# Sanity: at least one criterion must actually BE `observed` for the loop
# above to mean anything (vacuous-pass guard - a typo in the status-line
# pattern that matched nothing would make this invariant pass trivially).
observed_count13=0
n13=1
while [ "$n13" -le 19 ]; do
  section13=$(get_acceptance_section "$acceptance_content" "$n13")
  status13_line=$(printf '%s\n' "$section13" | grep '^\*\*Status:\*\*' | head -n 1)
  # shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status value in the case pattern below, not command substitution.
  case "$status13_line" in
    *'`observed`'*) observed_count13=$((observed_count13 + 1)) ;;
  esac
  n13=$((n13 + 1))
done
if [ "$observed_count13" -gt 0 ]; then
  observed_nonempty13=yes
else
  observed_nonempty13=no
fi
assert_eq "yes" "$observed_nonempty13" "sanity (invariant 13): at least one docs/ACCEPTANCE.md criterion must be marked \`observed\` for the not-run/never-observed scan above to be exercising anything"

# FAILURE PROOF (invariant 13): re-inject criterion 14's own ORIGINAL S9
# "which was not run" sentence back INTO criterion 14's own section of an
# in-memory mutant (criterion 14 is now `observed`) - must be caught.
# Inserted immediately after criterion 14's real, current, unique status
# line via awk (not appended at the end of the whole document, which would
# land past every "## " heading including criterion 14's own next-heading
# boundary and never be seen by get_acceptance_section at all). Uses the
# exact retired sentence, not a paraphrase, since that is the literal
# regression this invariant exists to prevent.
RETIRED_C14_SENTENCE="proving that needs a probe that first declares a task (e.g. \"help me refactor this function\") and then drifts from it, which was not run."
acceptance_mutant13=$(awk -v ins="$RETIRED_C14_SENTENCE" '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ins; done = 1 }
' "$acceptance_file")

# Sanity: the insertion anchor must actually have been found (a stale
# anchor - e.g. after a future rewording of criterion 14's status line -
# would make the mutant byte-identical to the real file and the failure
# proof below would vacuously "pass" by finding nothing to catch).
if printf '%s\n' "$acceptance_mutant13" | grep -qF "$RETIRED_C14_SENTENCE"; then
  mutant13_anchor_found=yes
else
  mutant13_anchor_found=no
fi
assert_eq "yes" "$mutant13_anchor_found" "sanity (invariant 13): the FAILURE PROOF's insertion anchor (criterion 14's current status line) must actually be found in the real file, or the mutant below is not a real mutation"

mutant13_section14=$(get_acceptance_section "$acceptance_mutant13" 14)
mutant13_status14=$(printf '%s\n' "$mutant13_section14" | grep '^\*\*Status:\*\*' | head -n 1)
mutant13_section14_flat=$(flatten_acceptance_section "$mutant13_section14")
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status value in the case pattern below, not command substitution.
case "$mutant13_status14" in
  *'`observed`'*)
    if printf '%s\n' "$mutant13_section14_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
      mutant13_caught=yes
    else
      mutant13_caught=no
    fi
    ;;
  *)
    mutant13_caught=no
    ;;
esac
assert_eq "yes" "$mutant13_caught" "FAILURE PROOF (invariant 13): re-inserting criterion 14's original S9 'which was not run' sentence back into its own (now \`observed\`) section, in an in-memory mutant, must be caught by the not-run/never-observed scan"

# Sanity: the same mutant must NOT flag any OTHER criterion - the
# insertion is scoped to criterion 14's own section only, so a naive
# whole-document scan (rather than a per-section one) would over-flag
# every criterion after it in file order, which this invariant's per-
# section design must not do.
mutant13_others=""
n13m=1
while [ "$n13m" -le 19 ]; do
  if [ "$n13m" != "14" ]; then
    section13m=$(get_acceptance_section "$acceptance_mutant13" "$n13m")
    status13m=$(printf '%s\n' "$section13m" | grep '^\*\*Status:\*\*' | head -n 1)
    section13m_flat=$(flatten_acceptance_section "$section13m")
    # shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status value in the case pattern below, not command substitution.
    case "$status13m" in
      *'`observed`'*)
        if printf '%s\n' "$section13m_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
          mutant13_others="$mutant13_others $n13m"
        fi
        ;;
    esac
  fi
  n13m=$((n13m + 1))
done
assert_eq "" "$mutant13_others" "sanity (invariant 13): inserting the fixture sentence into criterion 14's own section only must not cause any OTHER criterion to be flagged"

# ==========================================================================
# FAILURE PROOF (invariant 13, AC3 #1) - LINE-BREAK SPLIT. The retired
# sentence's own wording, UNCHANGED, with a single raw newline inserted in
# the middle of the banned phrase "was not run." (between "not" and "run.")
# - the exact evasion the tech lead reproduced, which left the old,
# unflattened scan at 34/0. Same insertion anchor and mechanism as the
# FAILURE PROOF above (criterion 14's real, current, unique status line),
# so this mutant is independent of, not derived from, acceptance_mutant13.
# ==========================================================================
LINEBREAK_C14_SENTENCE='proving that needs a probe that first declares a task (e.g. "help me refactor this function") and then drifts from it, which was not
run.'
# INS goes through ENVIRON, not `awk -v` - the BWK "one true awk" shipped
# as /usr/bin/awk on macOS rejects a multi-line value in `-v name=value`
# outright ("newline in string"), and this value deliberately contains a
# real embedded newline (the evasion under test). ENVIRON reads the
# process environment directly, with no such restriction.
acceptance_mutant_linebreak13=$(INS="$LINEBREAK_C14_SENTENCE" awk '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ENVIRON["INS"]; done = 1 }
' "$acceptance_file")

# The anchor check searches for the inserted text's FIRST LINE only
# (a `case` pattern match, not a grep pipe: piping the WHOLE multi-
# thousand-line mutant through `grep -q`, which exits the instant it
# finds a match, can race a still-writing `printf` on the other end of
# the pipe into a harmless but noisy SIGPIPE/"Broken pipe" - a pure shell
# `case` test has no subprocess pipe to race at all). Quoting the
# variable inside the pattern makes its content literal, not a glob, per
# POSIX - the same technique this codebase's own `${var#"$prefix"}` uses
# elsewhere for the identical reason.
linebreak13_first_line=$(printf '%s\n' "$LINEBREAK_C14_SENTENCE" | head -n 1)
case "$acceptance_mutant_linebreak13" in
  *"$linebreak13_first_line"*) mutant_linebreak13_anchor_found=yes ;;
  *) mutant_linebreak13_anchor_found=no ;;
esac
assert_eq "yes" "$mutant_linebreak13_anchor_found" "sanity (invariant 13, AC3 #1): the line-break FAILURE PROOF's insertion anchor must actually be found in the real file, or this mutant is not a real mutation"

mutant_linebreak13_section14=$(get_acceptance_section "$acceptance_mutant_linebreak13" 14)

# The OLD mechanism, reproduced inline for comparison: grep -qiE run
# DIRECTLY against the unflattened, multi-line section text - exactly what
# this invariant's scan did before this cycle's fix. Must MISS the
# line-break-split evasion - this is the vulnerability itself, demonstrated,
# not merely asserted in a comment.
if printf '%s\n' "$mutant_linebreak13_section14" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_linebreak13_old_mechanism_caught=yes
else
  mutant_linebreak13_old_mechanism_caught=no
fi
assert_eq "no" "$mutant_linebreak13_old_mechanism_caught" "DEMONSTRATION (invariant 13, AC3 #1): the OLD mechanism - grep run directly against the unflattened section - must MISS a line-break inserted in the middle of 'was not run.', reproducing the exact evasion the tech lead verified left the real suite at 34/0"

# The NEW (current, shipped) mechanism: flatten first, then scan. Must
# CATCH it.
mutant_linebreak13_flat=$(flatten_acceptance_section "$mutant_linebreak13_section14")
if printf '%s\n' "$mutant_linebreak13_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_linebreak13_new_mechanism_caught=yes
else
  mutant_linebreak13_new_mechanism_caught=no
fi
assert_eq "yes" "$mutant_linebreak13_new_mechanism_caught" "FAILURE PROOF (invariant 13, AC3 #1): the NEW mechanism - flatten, then scan - must CATCH the identical line-break-split evasion the OLD mechanism just missed, above"

# ==========================================================================
# FAILURE PROOF (invariant 13, AC3 #2) - TWO-SENTENCE SPLIT. A second,
# distinct construction: an inert LEAD-IN sentence is added first ("This
# probe sits apart from the others already covered above." - a real second
# sentence, not a fragment), and the retired claim becomes the SECOND
# sentence rather than the whole inserted text - itself then wrapped by a
# line break in the middle of "has not yet\nbeen run" (a different
# alternative of ACCEPTANCE_NOT_RUN_REGEX than #1 used, so this is not
# merely #1 repeated under a new name). This is the shape a genuine
# two-sentence rewrite of a retired disclosure would plausibly take: the
# claim is no longer the sole content of the inserted text, and the line
# wrap that defeats a per-line scan falls inside the SECOND sentence.
# ==========================================================================
TWOSENTENCE_C14_SENTENCE='This probe sits apart from the others already covered above. It has not yet
been run.'
# INS goes through ENVIRON for the identical reason the line-break mutant
# above does - this value also contains a real embedded newline.
acceptance_mutant_twosentence13=$(INS="$TWOSENTENCE_C14_SENTENCE" awk '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ENVIRON["INS"]; done = 1 }
' "$acceptance_file")

# Anchor on the inserted text's FIRST LINE only, via a `case` pattern
# match, for the identical reason the line-break mutant's own anchor
# check above does.
twosentence13_first_line=$(printf '%s\n' "$TWOSENTENCE_C14_SENTENCE" | head -n 1)
case "$acceptance_mutant_twosentence13" in
  *"$twosentence13_first_line"*) mutant_twosentence13_anchor_found=yes ;;
  *) mutant_twosentence13_anchor_found=no ;;
esac
assert_eq "yes" "$mutant_twosentence13_anchor_found" "sanity (invariant 13, AC3 #2): the two-sentence FAILURE PROOF's insertion anchor must actually be found in the real file, or this mutant is not a real mutation"

mutant_twosentence13_section14=$(get_acceptance_section "$acceptance_mutant_twosentence13" 14)

# OLD mechanism: must MISS it too - the second sentence's own claim is
# still split by a raw newline, the same underlying weakness as #1, now
# demonstrated for a genuinely two-sentence passage rather than a single
# sentence hard-wrapped.
if printf '%s\n' "$mutant_twosentence13_section14" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_twosentence13_old_mechanism_caught=yes
else
  mutant_twosentence13_old_mechanism_caught=no
fi
assert_eq "no" "$mutant_twosentence13_old_mechanism_caught" "DEMONSTRATION (invariant 13, AC3 #2): the OLD mechanism must MISS a two-sentence rewrite whose second sentence carries the retired claim split by a line break ('has not yet\\nbeen run'), the two-sentence evasion the tech lead verified also left the real suite at 34/0"

mutant_twosentence13_flat=$(flatten_acceptance_section "$mutant_twosentence13_section14")
if printf '%s\n' "$mutant_twosentence13_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_twosentence13_new_mechanism_caught=yes
else
  mutant_twosentence13_new_mechanism_caught=no
fi
assert_eq "yes" "$mutant_twosentence13_new_mechanism_caught" "FAILURE PROOF (invariant 13, AC3 #2): the NEW mechanism - flatten, then scan - must CATCH the two-sentence-split evasion the OLD mechanism just missed, above"

# ==========================================================================
# DEMONSTRATION (invariant 13, AD4) - CROSS-PARAGRAPH FALSE POSITIVE. Two
# ORDINARY, UNRELATED paragraphs (a real blank line between them, not a
# raw mid-phrase wrap like AC3 #1/#2 above), whose text happens to abut
# into a banned-phrase shape when joined: paragraph A ends "...has not"
# and paragraph B - after the blank line - begins "run into any blockers
# so far...". Neither paragraph, alone, claims anything about testing or
# observation; the coincidence only appears if the two are joined across
# their own paragraph boundary. This is AD4's own finding: the OLD
# (whole-SECTION flatten, AC3-era) mechanism joins them and wrongly
# matches; the NEW (per-PARAGRAPH flatten) mechanism, fixed this cycle,
# keeps them apart and correctly does not.
# ==========================================================================
FALSEPOS_C14_TEXT='The team says confidence in this feature has not

run into any blockers so far, so it should ship on schedule.'
# INS goes through ENVIRON, the same reason the line-break and
# two-sentence mutants above do - this value contains real embedded
# newlines, including a genuine BLANK line between the two paragraphs,
# which `awk -v` cannot carry on every awk this project has to run under.
acceptance_mutant_falsepos13=$(INS="$FALSEPOS_C14_TEXT" awk '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ENVIRON["INS"]; done = 1 }
' "$acceptance_file")

falsepos13_first_line=$(printf '%s\n' "$FALSEPOS_C14_TEXT" | head -n 1)
case "$acceptance_mutant_falsepos13" in
  *"$falsepos13_first_line"*) mutant_falsepos13_anchor_found=yes ;;
  *) mutant_falsepos13_anchor_found=no ;;
esac
assert_eq "yes" "$mutant_falsepos13_anchor_found" "sanity (invariant 13, AD4): the cross-paragraph FAILURE-POSITIVE demonstration's insertion anchor must actually be found in the real file, or this mutant is not a real mutation"

mutant_falsepos13_section14=$(get_acceptance_section "$acceptance_mutant_falsepos13" 14)

# The OLD (AC3-era) mechanism: flatten the WHOLE section into one line,
# with no paragraph boundary respected, then scan - reproduced inline for
# comparison (not a call to the shipped function, which no longer behaves
# this way). Must WRONGLY MATCH: this is the undisclosed false-positive
# class AD4 found, demonstrated, not merely asserted in a comment.
old_whole_section_flatten() {
  printf '%s\n' "$1" | tr '\n\t' '  ' | tr -s ' '
}
mutant_falsepos13_old_flat=$(old_whole_section_flatten "$mutant_falsepos13_section14")
if printf '%s\n' "$mutant_falsepos13_old_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_falsepos13_old_mechanism_caught=yes
else
  mutant_falsepos13_old_mechanism_caught=no
fi
assert_eq "yes" "$mutant_falsepos13_old_mechanism_caught" "DEMONSTRATION (invariant 13, AD4): the OLD (AC3-era, whole-section) flatten mechanism must WRONGLY MATCH two unrelated paragraphs whose text abuts into a banned-phrase shape across their own paragraph boundary - this is the undisclosed false positive AD4 found and this cycle fixed"

# The NEW (current, shipped) mechanism: flatten_acceptance_section, now
# scoped per paragraph. Must NOT match - the fix.
mutant_falsepos13_new_flat=$(flatten_acceptance_section "$mutant_falsepos13_section14")
if printf '%s\n' "$mutant_falsepos13_new_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_falsepos13_new_mechanism_caught=yes
else
  mutant_falsepos13_new_mechanism_caught=no
fi
assert_eq "no" "$mutant_falsepos13_new_mechanism_caught" "FIX PROOF (invariant 13, AD4): the NEW (per-paragraph) flatten mechanism must NOT match the same cross-paragraph false-positive construction the OLD mechanism just wrongly matched, above - the two halves now stay in separate paragraph records and are scanned independently"

# Sanity: prove the fix above is not a vacuous "matches nothing at all"
# accident by confirming the two halves actually landed on DIFFERENT
# lines of the NEW mechanism's own output (one line per paragraph) -
# rather than relying on a fragile embedded-newline grep pattern (POSIX
# grep's handling of a literal newline inside a single -F pattern is not
# something to depend on) to check the blank line survived extraction.
if printf '%s\n' "$mutant_falsepos13_new_flat" | grep -F "has not" | grep -qF "run into"; then
  mutant_falsepos13_merged_onto_one_line=yes
else
  mutant_falsepos13_merged_onto_one_line=no
fi
assert_eq "no" "$mutant_falsepos13_merged_onto_one_line" "sanity (invariant 13, AD4): 'has not' and 'run into' must land on DIFFERENT paragraph-flattened output lines, proving the blank line between them survived section extraction as a real paragraph boundary (not merely that the regex happens not to match for some unrelated reason)"

# ==========================================================================
# DEMONSTRATION, not a defect (invariant 13, AC3 #3) - PARAPHRASE. Stated
# plainly, per the task's own instruction: a paraphrase carrying the
# identical retired claim in different words is NOT caught, flattened or
# not, because ACCEPTANCE_NOT_RUN_REGEX matches literal phrases, not
# meaning. This mutant's inserted sentence shares no literal wording with
# any alternative in the regex at all. Asserted in the direction that
# documents the limitation (does not falsely claim coverage), so a future
# change that accidentally started catching this - or, more likely, a
# future reader assuming this scan is a substitute for the four-check
# review policy - has something concrete to reconcile against, rather than
# an unfalsifiable comment.
# ==========================================================================
PARAPHRASE_C14_SENTENCE="Nobody has watched this happen live yet, in any session."
acceptance_mutant_paraphrase13=$(awk -v ins="$PARAPHRASE_C14_SENTENCE" '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ins; done = 1 }
' "$acceptance_file")

mutant_paraphrase13_section14=$(get_acceptance_section "$acceptance_mutant_paraphrase13" 14)
mutant_paraphrase13_flat=$(flatten_acceptance_section "$mutant_paraphrase13_section14")
if printf '%s\n' "$mutant_paraphrase13_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_paraphrase13_caught=yes
else
  mutant_paraphrase13_caught=no
fi
assert_eq "no" "$mutant_paraphrase13_caught" "DEMONSTRATION, not a defect (invariant 13, AC3 #3): a paraphrase of the retired claim ('Nobody has watched this happen live yet') is NOT caught by ACCEPTANCE_NOT_RUN_REGEX, flattened or not - grep matches literal phrases, not meaning, and this is a permanent, stated limitation of this mechanism, not a gap this cycle's fix was asked to close"

assert_report
