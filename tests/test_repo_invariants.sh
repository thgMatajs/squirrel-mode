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

# --- Cleanup ----------------------------------------------------------
#
# ONE list, ONE EXIT trap, declared here before the first scratch
# directory is created. This file used to give each scratch directory its
# own `trap ... EXIT`, and `trap` REPLACES the previous handler in POSIX
# sh rather than stacking with it: the second declaration silently
# disinherited $z1_scratch, which was then never removed on any run. Two
# comments further down this file described that as pre-existing residue
# and worked around it by reusing an already-trapped directory; both now
# describe this list instead.
#
# Every scratch path in this file is created at the TOP LEVEL, so
# appending here is enough - no helper here builds one inside a `$( )`
# subshell, which is the failure tests/test_hoard.sh, tests/test_hooks.sh
# and tests/test_skills.sh each had to close with a registered parent
# directory. The SCRATCH-LEAK assertion at the bottom of this file is
# what keeps that true.
cleanup_paths=""
trap 'rm -rf $cleanup_paths' EXIT

scratch_before=$(scratch_snapshot)

# --- Known, documented exclusions ------------------------------------
#
# 1) There are now FIVE word-content scans below — visibility claims,
#    TODO/FIXME/XXX markers, the glossary-avoid-term scan, the
#    /plugin+/clear same-sentence scan, and the profile-is-verbatim scan
#    (PROFILE_VERBATIM_REGEX) — and FOUR of the five skip everything
#    under `tests/` (via the single `continue` in the main loop, right
#    before the visibility-scan case statement). Without this, the
#    assertion messages and comments in THIS file — which necessarily
#    name the very markers/phrases/terms they check for, to describe
#    what the checks do — would trip the checks they implement. This is
#    a self-reference problem specific to these content scans (this
#    comment block itself was stale at "the two WORD-CONTENT scans" for
#    a while after the third and fourth were added — fixed in S9's
#    sweep; the count is now five, and if a sixth is ever added here,
#    update this again rather than letting it drift a third time).
#
#    THE FIFTH SCAN IS THE EXCEPTION, and deliberately so: the
#    profile-is-verbatim scan runs over `tests/` too, because the
#    instance that made it necessary was IN `tests/test_hooks.sh` — an
#    assertion MESSAGE, not a comment. A scan that skipped `tests/`
#    could not have caught its own reason for existing. It carries the
#    narrowest self-reference carve-out that leaves it able to do that:
#    this ONE file, which has to spell the banned phrasing to check for
#    it. The residual is stated where the scan is: a reintroduction
#    inside THIS file is not caught, and nothing but review covers that.
#    It does NOT apply to the executable-bit or JSON-validity checks below:
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
#         narrow to.
#         [Hoard docs fix] docs/specs/* and docs/plans/* ARE on this denylist, for the GLOSSARY scan
#         only, and the difference from the ACCEPTANCE.md case above is the whole justification: this
#         exemption protects against real hits, not against none. Both files carry a copy of the
#         glossary's own `_Avoid_` vocabulary — docs/specs/2026-08-13-hoard-design.md §3's naming
#         table, whose last column IS an avoid list, and docs/plans/2026-08-13-hoard-phase-1.md's
#         task text specifying what CONTEXT.md's entries should say — so they trip on the avoided
#         term for the same reason CONTEXT.md does: they are quoting the rule, not breaking it. They
#         are also the same CATEGORY the denylist already names (internal design records, like
#         PLAN.md and docs/adr/*), not a new one invented to make a term pass.
#         WHAT IT GIVES UP, stated because an exemption that does not say so is the half-true
#         guarantee this file exists to stop: those two files, both still edited, are no longer
#         scanned for ANY of the terms in GLOSSARY_AVOID_REGEX, not just the
#         two that made the exemption necessary. How much text that is:
#           `glossary-denylist-lines docs/specs/2026-08-13-hoard-design.md: 631`
#           `glossary-denylist-lines docs/plans/2026-08-13-hoard-phase-1.md: 1986`
#         (The spec figure shipped as 579 — the size that file had BEFORE the 38 lines the same
#         commit added to it. Both are re-derived by the GLOSSARY-COST scenario at the bottom of
#         this file now, so neither can drift again without saying so.) Measured before it shipped:
#         `grep -cwiE` with the
#         pre-fix regex returns 0 on both, so nothing was being caught today; what is given up is
#         future coverage, not present coverage. It is deliberately NOT extended to the visibility
#         scan's denylist a few lines below, which keeps both files in scope — they have zero
#         visibility hits, so exempting them there would be an exemption protecting nothing, which
#         is exactly what the deleted ACCEPTANCE.md precedent forbids. The two lists diverging is
#         the point, not an oversight.
#         The exemption is also self-enforcing in one direction: delete it and the real scan reddens
#         immediately on those two files' avoid lines, so it cannot rot into a line nobody can
#         explain.
#         `.sh` files are excluded structurally (not by denylist) because this project's
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
#         [Hoard docs fix] CONTEXT.md's three hoard entries (hoard / Memory / Layer) added SEVEN
#         avoid-terms, and none of them was in this regex — which is exactly the gap the comment at
#         the end of this block forbids leaving open. All seven were run through the check this
#         comment records, with the scan's own scope and flags (`grep -nwiE`, `*.md`/`*.mdc`, tests/
#         skipped, this denylist applied). Two passed and are now in the regex; five collide and
#         stay out, each with its cost written down here in the same form as the entries above.
#         [Count fix] EVERY FIGURE IN THE FIVE BULLETS BELOW IS RE-DERIVED ON EVERY RUN and compared
#         against what is written here, by the GLOSSARY-COST scenario at the bottom of this file.
#         The shape it reads is `glossary-cost <term>: <hits> hits across <files> in-scope files`,
#         and the scope it recounts in is not a copy of the rules above — it is the very list of
#         files the scan loop below put in `glossary_scope_files` as it ran, so the two cannot
#         disagree about what "in scope" means. This is not decoration: four of the five bullets
#         shipped counts measured BEFORE docs/specs/* and docs/plans/* joined the denylist a few
#         lines up, in the same commit that added them, under a comment claiming "this denylist
#         applied"; the fifth ("fact": 22) matched no reading of the repo at all. A number nobody
#         rechecks rots, and these rotted inside their own commit.
#           - "memory bank", "knowledge base" (hoard) — PASS, and now enforced. Every occurrence of
#             either phrase in tracked markdown is the avoid list itself being quoted, in CONTEXT.md
#             (the glossary), in docs/specs/2026-08-13-hoard-design.md §3's naming table and in
#             docs/plans/2026-08-13-hoard-phase-1.md's task text — all three denylisted for this
#             scan (see 4a above, which states what that costs). Nowhere else in the repo produces
#             either phrase; two-word phrases specific enough that ordinary prose has no reason to.
#             The GLOSSARY-COST scenario pins that set of three, by file and line, so "nowhere else"
#             is a check rather than a memory.
#           - "note" (Memory) — glossary-cost note: 26 hits across 10 in-scope files. Ordinary
#             English, and none of them is a memory being called a note: README.md's "see the note
#             at the end of this section", skills/digest/SKILL.md's "a rambling ticket, email,
#             pasted note" (the digest command's own shipped subject list), and 14 lines of
#             docs/ACCEPTANCE.md using the ordinary word. NOT CAUGHT, therefore: a document that
#             calls a hoard memory "a note".
#           - "entry" (Memory) — glossary-cost entry: 24 hits across 5 in-scope files, and the
#             collisions are this project's own vocabulary for other things entirely:
#             skills/pickup/SKILL.md's "Done log entries" / "drop an entry that repeats one you
#             already have" (shipped, correct, about the checkpoint), the Cursor-generated
#             targets/cursor/skills/squirrel-pickup/SKILL.md copy of those same sentences,
#             and docs/RESEARCH.md's citation entries. NOT CAUGHT: "entry" used for a memory.
#           - "fact" (Memory) — glossary-cost fact: 13 hits across 4 in-scope files, and the decisive
#             ones are shipped skill text: skills/stash/SKILL.md's `reference` type is DEFINED as "A
#             fact, a state, or a pointer", and its "When a fact changed, supersede instead of
#             editing" heading is the supersede rule's own name. The Cursor-generated
#             targets/cursor/skills/squirrel-stash/SKILL.md copy carries those same four lines.
#             Banning the word would fail on the file that teaches it. NOT CAUGHT: "fact" used as a
#             synonym for the memory rather than for what it records.
#           - "record" (Memory) — glossary-cost record: 33 hits across 9 in-scope files, the worst
#             of the five, because it is a VERB in shipped product text: skills/stash/SKILL.md's
#             frontmatter description opens "Record one durable memory" (and the Cursor
#             squirrel-stash copy of that same line), and rules/base-rules.md
#             (plus every artifact scripts/build.sh generates from it — output-styles/,
#             targets/codex/AGENTS.md, targets/cursor/*.mdc) says "a checkpoint, a plan, or any
#             other record". NOT CAUGHT: "record" used as a noun for a memory.
#           - "namespace" (Layer) — glossary-cost namespace: 2 hits across 2 in-scope files, and
#             both are a true statement about a real product surface, not a synonym for a hoard
#             layer: README.md and docs/OTHER-TOOLS.md each say "Cursor has no command namespace",
#             which is why the Cursor skills are named `squirrel-digest` rather than
#             `/squirrel:digest`. Same shape as the "/config" collision recorded above. NOT CAUGHT:
#             "namespace" used for `global` or `projects/<slug>`.
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
# do this, and `/reload-plugins` alone is not documented to either. [Audit correction] That last
# clause used to justify itself with "its own reload list never names output styles", which is
# false: the plugins reference's skills-directory-plugin section names `output-styles/` among the
# components `/reload-plugins` picks up. It reloads a component's CONTENT; nothing documents it as
# deactivating a style already applied to the running session, and nobody here has tested it. The
# guarantee the pins rest on is unchanged, but it now rests on absence of a documented claim rather
# than on a wrong one. Update the constants deliberately, only after re-checking that guarantee
# still holds, never just to make a failing assertion pass.
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
#
# WHAT THE docs/adr/ PREFIX GIVES UP FOR THE GLOSSARY SCAN, COUNTED
# RATHER THAN LEFT AS A CATEGORY. A category comment says why a class is
# exempt; it does not say what the exemption is letting through, and this
# repo's rule is that an exemption has to say what it gives up. Counted
# against the real files with the scan's own `grep -nwiE`, the prefix is
# NOT empty — SIX lines in three ADRs match GLOSSARY_AVOID_REGEX today.
#
# [Count fix] The list below is no longer maintained by hand. Each entry
# carries an `adr-glossary-hit <path>:<line>` tag, and the GLOSSARY-COST
# scenario at the bottom of this file re-runs the grep and compares the
# two sets exactly — a hit here that the grep does not produce, or a hit
# the grep produces that is not here, fails and names it. It also checks
# each cited line still contains the phrase quoted for it. Both halves
# were needed: the list shipped saying "five lines" when the grep found
# six (the `client` entry below was never declared at all), and its one
# line-number citation pointed 136 lines above the sentence it quoted,
# because the ADR grew after the citation was written.
#   - `adr-glossary-hit docs/adr/0008-hoard-auto-allow.md:221` — "the
#     skill's own instruction not to write one is the only thing in front
#     of it". `the skill` is in the regex. Defensible: that paragraph is
#     reasoning about one specific skill file (skills/stash/SKILL.md) and
#     its point is that an instruction is not enforcement — it is not
#     standing in for the base rules, which is what CONTEXT.md reserves
#     the phrase against.
#   - `adr-glossary-hit docs/adr/0005-session-flag-off-switch.md:5`,
#     `adr-glossary-hit docs/adr/0005-session-flag-off-switch.md:49`,
#     `adr-glossary-hit docs/adr/0005-session-flag-off-switch.md:62` —
#     three more `the skill`, all of them about `/squirrel:off`'s own
#     skill file. Same shape, same judgement.
#   - `adr-glossary-hit docs/adr/0008-hoard-auto-allow.md:240` — "Google
#     OAuth client secrets", in the list of token families the secret
#     scanner has no arm for. `client` is in the regex because
#     CONTEXT.md's Target entry reserves it, and this is not that word at
#     all: it is the literal, correct name of a Google credential type.
#     An ordinary-English collision of exactly the kind exclusion 4b
#     records for "note" and "record" — which is why it needs saying, not
#     why it can be left unsaid: it went undeclared for the whole life of
#     this comment, and an exemption list that quietly omits one of its
#     own entries is the half-true guarantee this file exists to stop.
#   - `adr-glossary-hit docs/adr/0004-tiered-parity-across-targets.md:3` —
#     "each gets the deepest integration its host actually supports".
#     This one is NOT defensible on the same grounds: `host` is exactly
#     the word CONTEXT.md's Target entry reserves, and this is the
#     reserved word standing where the canonical name belongs — the same
#     defect as the README.md regression this whole scan was written
#     against. It is inside the exemption, so the scan is silent about
#     it. Left standing rather than corrected here because ADR-0004
#     belongs to the trail this file only measures, and a test file is
#     the wrong place to rewrite a decision record from.
# So the honest statement of the giveaway is not "an ADR might one day
# drift": one already has, the exemption is why nothing says so, and the
# cost of keeping it is that the ADR trail is checked by review alone.
# These are counts against what those files say today, not a permanent
# property — and the GLOSSARY-COST scenario re-runs the grep for you,
# rather than trusting anyone to remember to.

# GLOSSARY_AVOID_REGEX — [U6 fix] the hand-picked, hand-collision-checked subset of CONTEXT.md's
# `_Avoid_` vocabulary this scan actually enforces (see exclusion 4 above for exactly which terms
# were left out and why). `grep -w` (word-regexp) bounds every alternative, single-word or
# multi-word, at both ends by a non-word character or string boundary — "host" cannot match inside
# "hosted" or "hostile", and "squirrel mode" (a literal space) cannot match "squirrel-mode" (a
# literal hyphen) regardless of -w, since the two are different characters to begin with.
#
# [Hoard docs fix] `memory bank` and `knowledge base` are the two terms CONTEXT.md's hoard entry
# added that survive the by-hand collision check — see exclusion 4b above for all seven that were
# checked and the cost of the five that stay out, and 4a for what denylisting the two files that
# quote the avoid list gives up.
GLOSSARY_AVOID_REGEX="host|platform|client|IDE|formatting rules|style rules|the skill|state file|session file|context file|changelog|completed tasks|backlog|icebox|drift detection|focus check|nag|onboarding|wizard|plugin name|package name|squirrel mode|memory bank|knowledge base"

# PROFILE_VERBATIM_REGEX — no tracked file may assert that the quoted
# profile body can spell any line squirrel-mode injects.
#
# WHY A GUARD RATHER THAN CARE. Task 7b made that premise false:
# `neutralise_forged_lines` in scripts/load-profile.sh marks any line of
# the quoted profile body that begins with one of squirrel-mode's own
# injected prefixes, so such a line no longer reaches the model beginning
# that way. The premise had been written into rationale comments all over
# the repo, including the rationale of the very guards it justified. THREE
# separate manual sweeps each reported themselves complete and each missed
# an instance: the original change said such comments "were corrected
# where they are now false" and left two; the next sweep found a third,
# extended to tests/, and declared the class closed while this file's own
# first run found two more - one an assertion MESSAGE in tests/test_hooks.sh
# (the sweep before it had filtered to comment lines only) and one in
# docs/adr/0002-checkpoint-auto-allow.md. A human cannot be trusted to
# find the last instance of a phrase; that is what a scan is for. This
# comment says why rather than only what, so the next person to find it
# inconvenient knows what it replaced.
#
# WHAT IT MATCHES, AND WHY THAT IS NARROW ENOUGH TO BE HONEST. Only the
# UNQUALIFIED, present-tense assertion. The corrected form in this repo is
# "COULD otherwise spell", which states the same fact as a hypothetical
# the neutralisation closes, and it deliberately does NOT match: the word
# before "spell" is what separates a live claim from a counterfactual.
# Nor does "a profile body can spell one", of a token VALUE - a profile
# genuinely still can spell any token it likes, which is exactly why
# checkpoint_file_lines derives its token from the session_id rather than
# trusting the body, so barring that sentence would bar a true statement.
# Both of those pass today and are asserted to keep passing below.
#
# WHAT IT DOES NOT CATCH, stated rather than implied: a reworded assertion
# ("free to write whatever line it pleases") escapes it, exactly as
# MARKER_REGEX cannot catch a marker spelled some new way. A phrase scan
# bounds a class of recurrences; it does not decide what a sentence means.
# It is here because the recurrences were LITERAL - the same handful of
# words, copied from one rationale to the next - which is the shape a
# phrase scan does close.
PROFILE_VERBATIM_REGEX="(can|may|is free to|are free to) spell any line|(is|are) free to hold a line spelled|body (is|are) verbatim"

# BASH_ANY_HOOK_REGEX - no tracked file may say that NO hook, or no hook AT
# ALL, can auto-approve a `Bash` call.
#
# The claim is false about Claude Code and this repo's own ADR-0002 says so
# in as many words: "Auto-approving `Bash` would mean returning
# permissionDecision: "allow" for a tool whose argument is an arbitrary
# command string" - possible, weighed, and REFUSED. A `PreToolUse` hook may
# match `Bash` and may answer `allow`. What is true is narrower and is the
# whole point: squirrel-mode registers its own `PreToolUse` hook for
# `Write|Edit|Read` and nothing else, so no hook OF THIS PLUGIN'S ever runs
# on a `Bash` call. That is a choice of configuration, and every prompt
# count in the docs follows from the choice rather than from a limit of the
# tool.
#
# WHY A SCAN AND NOT A SWEEP. The false form was corrected in README.md,
# docs/OTHER-TOOLS.md and docs/ACCEPTANCE.md, and NINE copies survived that
# correction - one of them skills/dig/SKILL.md, i.e. text the model reads at
# run time, and two of them assertion MESSAGES, which no docs-only sweep
# looks at. The recurrences are literal - the same handful of words copied
# from one rationale into the next - which is the shape a phrase scan does
# close. It does not decide what a sentence means; it bounds a class of
# recurrence.
#
# WHAT IT DELIBERATELY DOES NOT MATCH, because these are true and must stay
# sayable: a claim about a NAMED script ("scripts/allow-checkpoint.sh can
# never auto-approve a Bash call" - true of that script, which only ever
# sees Write/Edit/Read), and a claim scoped to this plugin ("this plugin's
# hook is never invoked for a `Bash` call and cannot auto-approve one, at
# any path"). The negative half below asserts all four live keep-sites pass,
# because a guard that also bars the correct wording is one this repo
# deletes rather than ships.
#
# Scanned over EVERY tracked file, tests/ included and with no path
# denylist, for the reason PROFILE_VERBATIM_REGEX gives for itself: the
# copies lived in tests/, in docs/plans/* and in docs/adr/* - three places
# the other scans' denylists exempt. THE ONE CARVE-OUT is this file, which
# must spell the banned phrasing to check for it.
BASH_ANY_HOOK_REGEX="no hook (can|could|may|will|would)( ever)? auto-approve|by any hook|any hook can( ever)? auto-approve|hooks (can ?not|can never|cannot) auto-approve"

visibility_hits=""
profile_verbatim_hits=""
bash_any_hook_hits=""
marker_hits=""
non_exec_hits=""
invalid_json_hits=""
glossary_avoid_hits=""
same_sentence_hits=""
# The files the glossary scan actually looked at, captured AS IT RAN.
# The GLOSSARY-COST scenario at the bottom recounts exclusion 4b's five
# published per-term costs over this exact list rather than re-deriving
# the scope from the rules in the comments - a second copy of the scope
# is a second thing to keep in step, and the counts it published were
# wrong precisely because the denylist moved and they did not.
glossary_scope_files=""

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

  # PROFILE-IS-VERBATIM scan: EVERY tracked file, tests/ included, and
  # with NO path denylist. Placed here, ABOVE the tests/* `continue`, on
  # purpose - see exclusion 1: the instance that made this scan necessary
  # was an assertion MESSAGE in tests/test_hooks.sh, so a scan sitting
  # below that `continue` could not catch its own reason for existing.
  #
  # It also deliberately does not reuse the PLAN.md/docs/adr/CONTEXT.md
  # path denylist the visibility and glossary scans use, for the reason
  # PLUGIN_CLEAR_SAME_SENTENCE_REGEX already records for itself: a real
  # occurrence of this defect lived INSIDE that denylist
  # (docs/adr/0002-checkpoint-auto-allow.md), so reusing it would exempt
  # precisely the file that carried the bug. An ADR is the worst place to
  # leave the premise standing, not the safest - it is what the next task
  # reasons from, which is how Task 7 came to ship a rule whose premise
  # hooks/hooks.json had already falsified.
  #
  # THE ONE CARVE-OUT is this file, which must spell the banned phrasing
  # to check for it. Residual, stated: a reintroduction inside
  # tests/test_repo_invariants.sh itself is not caught by anything but
  # review. Writing the regex in split literals to dodge even that was
  # considered and rejected - it would make the guard depend on nobody
  # ever re-joining a string, and it reads as a trick rather than a rule.
  case "$f" in
    tests/test_repo_invariants.sh)
      ;;
    *)
      if grep -qwiE "$PROFILE_VERBATIM_REGEX" "$repo_root/$f" 2>/dev/null; then
        profile_verbatim_hits="$profile_verbatim_hits $f"
      fi
      ;;
  esac

  # NO-HOOK-CAN-AUTO-APPROVE-BASH scan: same placement, same scope and the
  # same single carve-out as the scan above, for the same reasons - see
  # BASH_ANY_HOOK_REGEX. Above the tests/* `continue` because two of the nine
  # surviving copies were assertion messages in tests/, and with no path
  # denylist because four more were in docs/plans/* and docs/adr/*.
  case "$f" in
    tests/test_repo_invariants.sh)
      ;;
    *)
      if grep -qiE "$BASH_ANY_HOOK_REGEX" "$repo_root/$f" 2>/dev/null; then
        bash_any_hook_hits="$bash_any_hook_hits $f"
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
  # docs/SKILLS-ADAPTATION.md joins the denylist for the same reason CONTEXT.md is on it: it is an
  # internal design record whose subject matter IS the reserved vocabulary. It names an external
  # source skill literally called `wizard` three times (rows for /squirrel:walk), and discusses a
  # SKILL.md's own `description` field as "the skill's own description" once. Both are the literal
  # sense, not the banned synonym -- `wizard` for the calibration interview, "the skill" for the
  # base rules. WHAT THIS GIVES UP: that file is no longer scanned for any reserved term at all, so
  # a genuine misuse inside it will not be caught here. Accepted because it plans commands rather
  # than shipping them; if it ever becomes user-facing guidance, take it back off this list.
  #
  # [Hoard docs fix] docs/specs/* and docs/plans/* are on THIS denylist and NOT on the visibility
  # scan's a few lines above, and the divergence is deliberate: they carry a copy of the glossary's
  # own `_Avoid_` vocabulary (a naming table and the task text that specified it), which is the
  # CONTEXT.md situation exactly, and they have zero visibility hits, which is the ACCEPTANCE.md
  # situation exactly. Exempting them here protects against something real; exempting them there
  # would protect against nothing. Exclusion 4a above states what this one costs.
  case "$f" in
    *.md | *.mdc)
      case "$f" in
        PLAN.md | docs/adr/* | CONTEXT.md | .build-checkpoint.md | docs/SKILLS-ADAPTATION.md | docs/specs/* | docs/plans/*)
          ;;
        *)
          glossary_scope_files="$glossary_scope_files $f"
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
cleanup_paths="$cleanup_paths $z1_scratch"

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
cleanup_paths="$cleanup_paths $glossary_avoid_scratch"
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

# [Hoard docs fix] FAILURE PROOFS for the two terms CONTEXT.md's hoard entry added and this fix
# enforces. Each is appended to a copy of a REAL in-scope file (README.md, whose privacy section is
# where a memory would most plausibly be miscalled), not to a hand-written fixture, and each mutant
# is `cmp`-checked first: an append that produced a byte-identical file would leave a proof that
# reports clean while proving nothing.
for glossary_new_term in "memory bank" "knowledge base"; do
  glossary_new_fixture="$glossary_avoid_scratch/README_$(printf '%s' "$glossary_new_term" | tr ' ' '_').md"
  cp "$repo_root/README.md" "$glossary_new_fixture"
  printf '\nThe hoard is squirrel-mode'"'"'s %s, and it is read in every future session.\n' "$glossary_new_term" >>"$glossary_new_fixture"
  if cmp -s "$repo_root/README.md" "$glossary_new_fixture"; then
    glossary_new_differs=no
  else
    glossary_new_differs=yes
  fi
  assert_eq "yes" "$glossary_new_differs" "FAILURE PROOF (invariant 7, '$glossary_new_term'), control: the mutant must genuinely differ from README.md"
  if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$glossary_new_fixture" 2>/dev/null; then
    glossary_new_caught=yes
  else
    glossary_new_caught=no
  fi
  assert_eq "yes" "$glossary_new_caught" "FAILURE PROOF (invariant 7): calling the hoard a '$glossary_new_term' in a scratch copy of README.md must be caught — CONTEXT.md's hoard entry reserves both phrases and this scan now enforces them"
done

# [Hoard docs fix] And the other half of that exemption, asserted rather than asserted-in-a-comment:
# docs/specs/2026-08-13-hoard-design.md must REALLY match the regex, because its section 3 naming
# table quotes the avoid list. That is what makes its place on the glossary denylist an exemption
# protecting something real rather than the empty one docs/ACCEPTANCE.md's used to be — the
# distinction the exclusion-4a comment draws, kept honest by a check instead of by memory. Delete
# the denylist entry and the scan reddens here; delete this assertion's subject line from the spec
# and this assertion reddens instead.
if grep -qwiE "$GLOSSARY_AVOID_REGEX" "$repo_root/docs/specs/2026-08-13-hoard-design.md" 2>/dev/null; then
  spec_quotes_avoid_list=yes
else
  spec_quotes_avoid_list=no
fi
assert_eq "yes" "$spec_quotes_avoid_list" "docs/specs/2026-08-13-hoard-design.md must still contain the avoid-list terms its section 3 naming table quotes — that is the whole justification for its glossary-scan exemption, and an exemption protecting nothing is the one this file already deleted once"

# 7b. No tracked file may assert that the quoted profile body can spell any line squirrel-mode
#     injects. See PROFILE_VERBATIM_REGEX above for why this is a scan and not a sweep - the
#     premise was falsified by neutralise_forged_lines, and three manual sweeps each reported
#     themselves complete while missing an instance. Scanned over EVERY tracked file, tests/
#     included and with no path denylist, because the two instances this scan found on its first
#     run were an assertion MESSAGE in tests/test_hooks.sh and a paragraph in docs/adr/0002 -
#     one in a directory the other scans skip entirely, one in a directory their path denylist
#     exempts.
assert_eq "" "$profile_verbatim_hits" "no tracked file may assert that the quoted profile body can spell any line squirrel-mode injects - that premise was falsified by neutralise_forged_lines in scripts/load-profile.sh; state it as a counterfactual (\"COULD otherwise spell\") and say what closes it, the way scripts/load-profile.sh and docs/adr/0002 now do"

# FAILURE PROOF (invariant 7b): the exact phrasing this scan was written against, reintroduced into
# a scratch copy of a REAL tracked file, must be caught. The fixture is a copy of
# scripts/load-profile.sh with its corrected counterfactual reverted to the assertion it replaced -
# not a hand-written sentence - so this proves the scan catches the regression it exists for rather
# than catching a string invented to be caught.
#
# The `diff` is asserted, not assumed: eight variants of the transform-matches-nothing trap have
# been found in this plan, two of them inside probes, and a `sed` that matched nothing here would
# leave the fixture byte-identical to a file the scan correctly passes - a proof that reports clean
# while proving the opposite of what it claims. Reuses $glossary_avoid_scratch because it is already
# there and this fixture needs nothing of its own; a fresh `mktemp -d` appended to $cleanup_paths
# would be equally safe now that this file has one trap and one list (see the cleanup header at the
# top). It was NOT safe before that: each scratch directory carried its own `trap ... EXIT`, and
# `trap` REPLACES the previous handler in POSIX sh.
pv_fixture="$glossary_avoid_scratch/load-profile-verbatim.sh"
sed 's/block COULD otherwise spell any line it likes/block is verbatim and can spell any line it likes/' \
  "$repo_root/scripts/load-profile.sh" >"$pv_fixture"
if cmp -s "$repo_root/scripts/load-profile.sh" "$pv_fixture"; then
  pv_fixture_differs=no
else
  pv_fixture_differs=yes
fi
assert_eq "yes" "$pv_fixture_differs" "FAILURE PROOF (invariant 7b), control: the mutation must genuinely change the file - a sed that matched nothing would leave a byte-identical copy, which the scan correctly passes, and this proof would then report clean while testing nothing at all"
if grep -qwiE "$PROFILE_VERBATIM_REGEX" "$pv_fixture" 2>/dev/null; then
  pv_fixture_caught=yes
else
  pv_fixture_caught=no
fi
assert_eq "yes" "$pv_fixture_caught" "FAILURE PROOF (invariant 7b): reverting scripts/load-profile.sh's counterfactual back to 'is verbatim and can spell any line it likes' in a scratch copy must be caught by PROFILE_VERBATIM_REGEX"

# THE NEGATIVE HALF - without it this guard could be one that bars correct work. Three wordings
# that must all pass: the counterfactual the repo now uses; the statement that a profile can spell
# a token VALUE, which is TRUE (nothing stops a profile naming any token, which is precisely why
# checkpoint_file_lines derives its own from the session_id) and is the live wording at
# tests/test_hooks.sh's checkpoint_list_marker helper; and the past-tense form describing the
# defect as history.
pv_safe_fixture="$glossary_avoid_scratch/profile_verbatim_safe.md"
{
  printf '# Sample doc\n\n'
  printf 'The profile body quoted above this block COULD otherwise spell any line it likes.\n'
  printf 'A header carrying any other token - a profile body can spell one - is not this hook.\n'
  printf 'Before that change a profile was free to hold a line spelled like one of them.\n'
} >"$pv_safe_fixture"
if grep -qwiE "$PROFILE_VERBATIM_REGEX" "$pv_safe_fixture" 2>/dev/null; then
  pv_safe_caught=yes
else
  pv_safe_caught=no
fi
assert_eq "no" "$pv_safe_caught" "sanity check (invariant 7b): the counterfactual 'COULD otherwise spell', the TRUE statement that a profile can spell a token VALUE, and the past-tense 'was free to hold' must all pass - a guard that flagged any of these would be barring correct statements, which is worse than the manual sweep it replaces"

# And the same negative half against the REAL file that carries the token-value wording, so this
# rests on the shipped text rather than only on a fixture that paraphrases it.
if grep -qwiE "$PROFILE_VERBATIM_REGEX" "$repo_root/tests/test_hooks.sh" 2>/dev/null; then
  pv_hooks_caught=yes
else
  pv_hooks_caught=no
fi
assert_eq "no" "$pv_hooks_caught" "sanity check (invariant 7b): tests/test_hooks.sh must pass this scan as it actually stands - it is in scope (no tests/ skip for this one scan) and it contains the legitimate 'a profile body can spell one' wording about a token value"

# 7c. No tracked file may claim that NO hook can auto-approve a `Bash` call. See
#     BASH_ANY_HOOK_REGEX above for why the claim is false (this repo's own ADR-0002 records
#     auto-approving `Bash` as possible and REFUSED), what the true scoped form is, and why nine
#     copies survived the sweep that corrected README.md, docs/OTHER-TOOLS.md and
#     docs/ACCEPTANCE.md.
assert_eq "" "$bash_any_hook_hits" "no tracked file may say that no hook - or no hook at all, or none by any hook - can auto-approve a \`Bash\` call. A PreToolUse hook may match \`Bash\` and may answer permissionDecision \"allow\"; docs/adr/0002 records squirrel-mode REFUSING to register one. Say what is true instead: this plugin's PreToolUse matcher is \`Write|Edit|Read\`, so no hook of this plugin's runs on a \`Bash\` call - a choice of configuration, not a limit of the tool"

# FAILURE PROOF (invariant 7c): the exact sentence this scan was written against, put back into a
# scratch copy of the REAL file that carried it - skills/dig/SKILL.md, the copy that mattered most
# because the model reads it at run time. Not a hand-written sentence: the mutation reverts the
# corrected wording to the wording that shipped.
bah_fixture="$glossary_avoid_scratch/dig-no-hook.md"
# shellcheck disable=SC2016 # single-quoted deliberately: literal skill text, backticks and all.
sed 's/squirrel-mode registers no hook that runs on a `Bash` call - its `PreToolUse` matcher names `Write`, `Edit` and `Read` and nothing else -/no hook can auto-approve a `Bash` call,/' \
  "$repo_root/skills/dig/SKILL.md" >"$bah_fixture"
if cmp -s "$repo_root/skills/dig/SKILL.md" "$bah_fixture"; then
  bah_fixture_differs=no
else
  bah_fixture_differs=yes
fi
assert_eq "yes" "$bah_fixture_differs" "FAILURE PROOF (invariant 7c), control: the mutation must genuinely change skills/dig/SKILL.md - a sed that matched nothing would leave a byte-identical copy, which the scan correctly passes, and this proof would report clean while testing nothing"
if grep -qiE "$BASH_ANY_HOOK_REGEX" "$bah_fixture" 2>/dev/null; then
  bah_fixture_caught=yes
else
  bah_fixture_caught=no
fi
assert_eq "yes" "$bah_fixture_caught" "FAILURE PROOF (invariant 7c): reverting skills/dig/SKILL.md's disclosure to 'no hook can auto-approve a \`Bash\` call' in a scratch copy must be caught by BASH_ANY_HOOK_REGEX"

# And the second shape, the one that reached a test COMMENT rather than shipped prose, so the proof
# is not tuned to a single sentence.
bah_fixture2="$glossary_avoid_scratch/base-rules-any-hook.sh"
sed "s/so no hook OF THIS PLUGIN'S runs on a \`Bash\` call at/and ADR-0002 records that a \`Bash\` call is never auto-approved at any path by any hook, at/" \
  "$repo_root/tests/test_base_rules.sh" >"$bah_fixture2"
if cmp -s "$repo_root/tests/test_base_rules.sh" "$bah_fixture2"; then
  bah_fixture2_differs=no
else
  bah_fixture2_differs=yes
fi
assert_eq "yes" "$bah_fixture2_differs" "FAILURE PROOF (invariant 7c, second shape), control: the mutation must genuinely change tests/test_base_rules.sh"
if grep -qiE "$BASH_ANY_HOOK_REGEX" "$bah_fixture2" 2>/dev/null; then
  bah_fixture2_caught=yes
else
  bah_fixture2_caught=no
fi
assert_eq "yes" "$bah_fixture2_caught" "FAILURE PROOF (invariant 7c, second shape): the 'never auto-approved at any path by any hook' wording, restored into a scratch copy of tests/test_base_rules.sh, must be caught too - the scan bounds a class, not one sentence"

# THE NEGATIVE HALF - without it this guard bars the correct wording as readily as the wrong one,
# which is the failure mode this repo deletes a guard over. Four wordings that must ALL pass: a
# claim about the NAMED script (true - allow-checkpoint.sh only ever sees Write/Edit/Read), the
# same claim in the past tense, the plugin-scoped form README.md now uses, and the
# docs/ACCEPTANCE.md form that says "at any path" about THIS plugin's hook.
bah_safe_fixture="$glossary_avoid_scratch/bash_any_hook_safe.md"
{
  printf '# Sample doc\n\n'
  printf 'allow-checkpoint.sh can never auto-approve a Bash call.\n'
  printf 'scripts/allow-checkpoint.sh could never auto-approve a Bash call, and the session stopped.\n'
  printf "No hook of this plugin's is ever invoked for a \`Bash\` call and none of them can auto-approve one.\n"
  # shellcheck disable=SC2016 # single-quoted deliberately: literal doc text, backticks and all.
  printf 'This plugin hook is never invoked for a `Bash` call and cannot auto-approve one, at any path.\n'
} >"$bah_safe_fixture"
if grep -qiE "$BASH_ANY_HOOK_REGEX" "$bah_safe_fixture" 2>/dev/null; then
  bah_safe_caught=yes
else
  bah_safe_caught=no
fi
assert_eq "no" "$bah_safe_caught" "sanity check (invariant 7c): the four TRUE wordings - the named script, its past tense, the plugin-scoped form, and 'at any path' said about this plugin's own hook - must all pass. A guard that flagged them would bar the correct statement, and this repo deletes such a guard rather than narrowing it a third time"

# And the same negative half against the REAL files that carry those wordings today, so it rests on
# shipped text rather than only on a fixture that paraphrases it.
for bah_safe_path in scripts/load-profile.sh tests/test_skills.sh tests/test_hooks.sh README.md docs/ACCEPTANCE.md; do
  if grep -qiE "$BASH_ANY_HOOK_REGEX" "$repo_root/$bah_safe_path" 2>/dev/null; then
    bah_real_caught=yes
  else
    bah_real_caught=no
  fi
  assert_eq "no" "$bah_real_caught" "sanity check (invariant 7c): $bah_safe_path must pass this scan as it actually stands - it carries a correctly scoped statement about which hook does not run on a \`Bash\` call, and the scan must not touch it"
done

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

# AN OPERAND IS NOT AN INVOCATION, AND THE CUT THAT SAYS SO IS ONE TOKEN
# WIDE (added by the hard-link audit; NARROWED by the cycle-2 audit).
# `grep -w` treats "-" as a word boundary, so a flag or operand that ENDS
# in a listed name matches as though the command had been invoked. That
# is not hypothetical: scripts/allow-checkpoint.sh's hard-link refusal
# calls `find "$leaf" -links +1`, and `-links` matched the `links` text
# browser, turning a POSIX `find` predicate into a reported network call.
# POSIX find offers no other spelling of that predicate, so the check is
# what had to change.
#
# WHAT THE FIRST REPAIR DID, AND WHY IT WAS THE WRONG CUT. It removed
# EVERY token beginning with whitespace-then-"-" before the word scan
# ran, and justified that with "no command is ever invoked by a name
# starting with '-'". That argument is about the FIRST token of a
# command; the sed was applied to every token of every line, so it also
# deleted the text a network call was hiding INSIDE. Measured, not
# reasoned: appending `foo -mode-curl https://example.com/exfiltrate` -
# a real, working network call - to a real shipped script left this
# invariant reporting zero hits and the whole file green at 133 pass /
# 0 fail. `foo -x-wget https://x`, `sh -c-python3 -m http.server`,
# `cmd | -filter-ssh host` and `aws s3 -no-verify-ssh https://x` all
# went the same way. Every one of them was caught before that repair,
# and none of the three fixtures it shipped with covers the class it
# deleted - the three cover only the cases that still worked.
#
# WHAT IS CUT NOW: the literal `-links` predicate, and nothing else. It
# is the only false positive this repo has, it is silenced by name, and
# every other space-dash token reaches the word scan exactly as it did
# before the hard-link layer existed. `curl -s https://x` still reports
# `curl`; `lwp-request` is untouched, because its hyphen is not preceded
# by whitespace and it is the command name itself; and
# `foo -mode-curl https://x` is reported again, which is the class the
# blind cut lost. All of those directions are proved below against real
# scratch copies rather than argued here, the recovered class included.
#
# THE NARROWING IS SAFE FOR THIS REPO'S OTHER `find` USES, checked the
# same way rather than assumed: the only other predicates any shipped
# script passes to `find` are `-mtime` and `-newer`, neither of which
# ends in a listed name, and the real-repo scan below reports zero hits
# under this rule.
strip_links_predicate() {
  sed -E 's/[[:space:]]-links([[:space:]]|$)/ /g'
}

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
  code_only=$(grep -vE '^[[:space:]]*#' "$repo_root/$f" 2>/dev/null | strip_links_predicate || true)
  if printf '%s\n' "$code_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
    network_hits="$network_hits $f"
  fi
done
IFS=$old_ifs
assert_eq "" "$network_hits" "no shipped script (scripts/*.sh, targets/*/install.sh) may invoke a network-capable command (see NETWORK_COMMAND_REGEX, above)"

network_code_fixture="$glossary_avoid_scratch/network_code.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_code_fixture"
printf '\ncurl https://example.com/exfiltrate >/dev/null 2>&1\n' >>"$network_code_fixture"
fixture_code_only=$(grep -vE '^[[:space:]]*#' "$network_code_fixture" 2>/dev/null | strip_links_predicate || true)
if printf '%s\n' "$fixture_code_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_code_fixture_caught=yes
else
  network_code_fixture_caught=no
fi
assert_eq "yes" "$network_code_fixture_caught" "FAILURE PROOF (invariant 10, code line): a real curl invocation appended as a genuine code line to a real shipped script must be caught"

network_comment_fixture="$glossary_avoid_scratch/network_comment.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_comment_fixture"
printf '\n# example of what NOT to do: curl https://example.com/exfiltrate would be a network call\n' >>"$network_comment_fixture"
fixture_comment_only=$(grep -vE '^[[:space:]]*#' "$network_comment_fixture" 2>/dev/null | strip_links_predicate || true)
if printf '%s\n' "$fixture_comment_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_comment_fixture_caught=yes
else
  network_comment_fixture_caught=no
fi
assert_eq "no" "$network_comment_fixture_caught" "sanity check: the identical text placed inside a full-line comment must NOT be caught — this check scans CODE, not the prose that happens to describe an attack path (e.g. this very file's own '.ssh/id_rsa' comment, or allow-checkpoint.sh's identical comment)"

# --- strip_links_predicate must not become a way to smuggle a network
#     call past this check. Two fixtures, both against a real shipped
#     script: a command that takes a flag (the flag is left alone now,
#     and the COMMAND was always the first token, so it must still be
#     reported), and a command whose own name contains a hyphen (nothing
#     to strip, still reported). Without these, tolerating `find -links`
#     would be an unproved loosening of the one invariant that keeps this
#     plugin network-free.
network_flag_fixture="$glossary_avoid_scratch/network_flag.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_flag_fixture"
printf '\nnc -l 1234 >/dev/null 2>&1\n' >>"$network_flag_fixture"
fixture_flag_only=$(grep -vE '^[[:space:]]*#' "$network_flag_fixture" 2>/dev/null | strip_links_predicate || true)
if printf '%s\n' "$fixture_flag_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_flag_fixture_caught=yes
else
  network_flag_fixture_caught=no
fi
assert_eq "yes" "$network_flag_fixture_caught" "FAILURE PROOF (invariant 10, operand stripping): a real network command invoked WITH a flag must still be caught - stripping ' -l' must never take the command name with it"

network_hyphen_fixture="$glossary_avoid_scratch/network_hyphen.sh"
cp "$repo_root/scripts/allow-checkpoint.sh" "$network_hyphen_fixture"
printf '\nlwp-request -m GET https://example.com >/dev/null 2>&1\n' >>"$network_hyphen_fixture"
fixture_hyphen_only=$(grep -vE '^[[:space:]]*#' "$network_hyphen_fixture" 2>/dev/null | strip_links_predicate || true)
if printf '%s\n' "$fixture_hyphen_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_hyphen_fixture_caught=yes
else
  network_hyphen_fixture_caught=no
fi
assert_eq "yes" "$network_hyphen_fixture_caught" "FAILURE PROOF (invariant 10, hyphenated command name): lwp-request must still be caught - its hyphen is not preceded by whitespace, so operand stripping must leave it whole"

# And the case that motivated the change, asserted directly rather than
# only through the real-repo scan above: a `find` predicate that ends in
# a listed name is an OPERAND and must not be reported.
network_operand_fixture="$glossary_avoid_scratch/network_operand.sh"
# shellcheck disable=SC2016 # single-quoted deliberately: literal fixture source text, not substitution.
printf '#!/bin/sh\nif [ -n "$(find "$1" -links +1 2>/dev/null)" ]; then\n  exit 1\nfi\n' >"$network_operand_fixture"
fixture_operand_only=$(grep -vE '^[[:space:]]*#' "$network_operand_fixture" 2>/dev/null | strip_links_predicate || true)
if printf '%s\n' "$fixture_operand_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
  network_operand_fixture_caught=yes
else
  network_operand_fixture_caught=no
fi
assert_eq "no" "$network_operand_fixture_caught" "sanity check (invariant 10): \`find <file> -links +1\` is a POSIX predicate, not the \`links\` browser - this is the false positive that made the operand stripping necessary, and it is asserted here so a future change to the regex cannot silently reintroduce it"

# --- THE CLASS THE BLIND CUT DELETED, PINNED SO IT CANNOT BE REOPENED IN
#     SILENCE. A network command spelled so that its name is the tail of a
#     space-dash token - `foo -mode-curl https://x` - is a working
#     invocation of nothing at all on its own, but the TEXT is what this
#     invariant scans, and every one of these was reported before the
#     hard-link audit and by none of the fixtures above. Reproduced
#     against a real shipped script: with the token-wide cut in place the
#     whole file stayed green at 133 pass / 0 fail with a live
#     `https://example.com/exfiltrate` sitting in scripts/check-off-flag.sh.
#     Four spellings, because one of them could be silenced by an
#     accident of the regex and four cannot.
smuggled_lines_10='foo -mode-curl https://example.com/exfiltrate
foo -x-wget https://example.com/x
sh -c-python3 -m http.server
aws s3 -no-verify-ssh https://example.com/x'
old_ifs_10=$IFS
IFS='
'
for smuggled_10 in $smuggled_lines_10; do
  IFS=$old_ifs_10
  network_smuggle_fixture="$glossary_avoid_scratch/network_smuggle.sh"
  cp "$repo_root/scripts/check-off-flag.sh" "$network_smuggle_fixture"
  printf '\n%s\n' "$smuggled_10" >>"$network_smuggle_fixture"
  fixture_smuggle_only=$(grep -vE '^[[:space:]]*#' "$network_smuggle_fixture" 2>/dev/null | strip_links_predicate || true)
  if printf '%s\n' "$fixture_smuggle_only" | grep -qwE "$NETWORK_COMMAND_REGEX" 2>/dev/null; then
    network_smuggle_caught=yes
  else
    network_smuggle_caught=no
  fi
  assert_eq "yes" "$network_smuggle_caught" "FAILURE PROOF (invariant 10, the class a token-wide cut deletes): '$smuggled_10' appended to a real shipped script must be reported - a cut that removes every space-dash token removes the network command's own name along with the flag it is hiding behind, and this repo shipped exactly that with the suite green"
  IFS='
'
done
IFS=$old_ifs_10

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
# means for the other 21.
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
assert_eq "22" "$plan_criteria_count" "sanity check: PLAN.md Section 5 must itself contain exactly 22 checklist items (protects the derivation, not docs/ACCEPTANCE.md's text)"

acceptance_numbers=$(extract_acceptance_numbers "$acceptance_file")
acceptance_number_sequence=$(printf '%s\n' "$acceptance_numbers" | tr '\n' ' ' | sed 's/ *$//')
assert_eq "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22" "$acceptance_number_sequence" "docs/ACCEPTANCE.md's criterion headings must be numbered 1..22, in order, no gaps, no duplicates (protects the derivation)"

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
# follow below. That is now a convenience rather than a necessity: this file has ONE `trap ... EXIT`
# and one $cleanup_paths list (see the cleanup header at the top), so a fresh `mktemp -d` appended to
# that list would be cleaned up too. Until it did, the note here was right about the mechanism and
# wrong about the residue it dismissed: `trap` REPLACES the previous handler in POSIX sh, the second
# declaration had already disinherited $z1_scratch, and that directory was leaking on every single
# run — one per run, forever, not a one-off. It is on the list now, and the SCRATCH-LEAK assertion at
# the bottom of this file fails if any scratch path here goes unscheduled again.
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
  # coincidental match can still occur WITHIN a single paragraph, from an
  # ordinary line-wrap in the middle of ONE sentence with no blank line
  # involved at all. That residual predates this whole mechanism: a
  # banned phrase already sitting on ONE physical line, unwrapped, was
  # always a coincidental-match risk this literal-phrase regex could
  # produce, flattened or not, paragraph-bounded or not - it is not
  # something flattening introduced and paragraph-bounding cannot remove
  # it. A false positive here blocks a build rather than shipping a
  # defect, so disclosure is the proportionate response, not a fourth
  # narrowing.
  #
  # TWO CORRECTIONS TO THAT DISCLOSURE (P4 item 6, measured against this
  # function as shipped, not reasoned about). Both were overstatements in
  # the paragraph above, and both are removed from it rather than left
  # standing next to a hedge:
  #
  #   (1) It used to also name "an ordinary line-wrap landing between two
  #   unrelated SENTENCES that share one paragraph" as part of the same
  #   residual. That shape does NOT match, and cannot: for the flattened
  #   text to spell a banned phrase, the two fragments have to end up
  #   ADJACENT, and anything that separates two sentences - the sentence's
  #   own terminal period, a "- " list marker, a table "|" - survives
  #   flattening and sits between them. Tried against this function, all
  #   no-match: "...adoption has not." / "Run into any blockers..." as two
  #   real sentences; the same words as two abutting list items; as two
  #   abutting table rows; and as a sentence followed by a list item. The
  #   ONLY within-paragraph shape that does match is a single sentence
  #   hard-wrapped mid-phrase - and there the flattened text is that
  #   sentence's own true reading, so flattening invented no adjacency at
  #   all. What is left is therefore not a flattening defect: it is
  #   ACCEPTANCE_NOT_RUN_REGEX being unable to tell "has not run into any
  #   blockers" from "has not run [the probe]", which is the same
  #   literal-phrase-versus-meaning limit the AC3 #3 paraphrase
  #   DEMONSTRATION below already pins from the opposite direction.
  #
  #   (2) It used to say "closing it fully would need bounding to a
  #   SENTENCE instead of a paragraph". It would not - that remedy does
  #   not work, which is a stronger reason to reject it than the
  #   detectability argument that used to be given for it. The one shape
  #   that matches is INSIDE one sentence, so a sentence-bounded flatten
  #   still joins it and still matches: verified by running a
  #   sentence-splitting variant over all three constructions, which
  #   matched every time the shipped version did. The detectability
  #   objection was true as far as it went (a period-based splitter fires
  #   on abbreviations, decimal version numbers, and markdown's own "1. "
  #   list syntax) but it was arguing against a remedy that would not have
  #   helped anyway, which is exactly the "narrower guard, same bug"
  #   pattern this project has rejected elsewhere (Layer 3's realpath
  #   comparison; the sed-based nested-JSON isolation that was removed
  #   rather than narrowed a fourth time).
  #
  # See the "P4 item 6" DEMONSTRATION block after the AD4 proofs below for
  # the assertions that pin both corrections, so neither can rot back into
  # a comment nobody re-ran.
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
while [ "$n13" -le 22 ]; do
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
while [ "$n13" -le 22 ]; do
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
while [ "$n13m" -le 22 ]; do
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
# DEMONSTRATION (P4 item 6) - pins the two corrections in
# flatten_acceptance_section's header. Measured against the shipped
# function, not reasoned about in a comment alone.
#
#   (1) Two unrelated SENTENCES sharing one paragraph, whose words would
#       abut into a banned phrase only if the sentence terminator were
#       dropped, do NOT match after flattening - the period survives and
#       sits between them. This is why "line-wrap between two sentences"
#       was removed from the residual disclosure.
#   (2) The ONE within-paragraph shape that DOES match - a single sentence
#       hard-wrapped mid-phrase - still matches under a sentence-splitting
#       flatten variant too, so "bound to a sentence instead" is not a
#       working remedy for that residual.
# ==========================================================================
P4I6_TWO_SENTENCES='Feature adoption has not. Run into any blockers so far and the answer is no.'
acceptance_mutant_p4i6_sent=$(INS="$P4I6_TWO_SENTENCES" awk '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ENVIRON["INS"]; done = 1 }
' "$acceptance_file")
mutant_p4i6_sent_section=$(get_acceptance_section "$acceptance_mutant_p4i6_sent" 14)
mutant_p4i6_sent_flat=$(flatten_acceptance_section "$mutant_p4i6_sent_section")
if printf '%s\n' "$mutant_p4i6_sent_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_p4i6_sent_caught=yes
else
  mutant_p4i6_sent_caught=no
fi
assert_eq "no" "$mutant_p4i6_sent_caught" "DEMONSTRATION (P4 item 6, correction 1): two unrelated sentences in ONE paragraph ('has not.' / 'Run into any blockers...') must NOT match after per-paragraph flatten - the period keeps them from abutting into the banned phrase"

P4I6_MIDPHRASE='Confidence in this feature has not
run into any blockers of its own yet.'
acceptance_mutant_p4i6_wrap=$(INS="$P4I6_MIDPHRASE" awk '
  { print }
  /^\*\*Status:\*\* `observed`, on probes E and F\./ && !done { print ENVIRON["INS"]; done = 1 }
' "$acceptance_file")
mutant_p4i6_wrap_section=$(get_acceptance_section "$acceptance_mutant_p4i6_wrap" 14)
mutant_p4i6_wrap_flat=$(flatten_acceptance_section "$mutant_p4i6_wrap_section")
if printf '%s\n' "$mutant_p4i6_wrap_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_p4i6_wrap_caught=yes
else
  mutant_p4i6_wrap_caught=no
fi
assert_eq "yes" "$mutant_p4i6_wrap_caught" "DEMONSTRATION (P4 item 6, correction 2 setup): a single sentence hard-wrapped mid-phrase ('has not' / 'run into') MUST match under the shipped per-paragraph flatten - that is the residual that remains"

# Sentence-splitting variant of flatten: split on ". " before squeezing.
# If this still matches the mid-phrase wrap, bounding to a sentence is not
# a remedy for the residual (correction 2).
mutant_p4i6_wrap_sentence_flat=$(printf '%s\n' "$mutant_p4i6_wrap_section" | awk '
  BEGIN { RS = "" }
  {
    n = split($0, sentences, /\. /)
    for (i = 1; i <= n; i++) {
      line = sentences[i]
      gsub(/[\n\t]/, " ", line)
      gsub(/  +/, " ", line)
      print line
    }
  }
')
if printf '%s\n' "$mutant_p4i6_wrap_sentence_flat" | grep -qiE "$ACCEPTANCE_NOT_RUN_REGEX"; then
  mutant_p4i6_wrap_sentence_caught=yes
else
  mutant_p4i6_wrap_sentence_caught=no
fi
assert_eq "yes" "$mutant_p4i6_wrap_sentence_caught" "DEMONSTRATION (P4 item 6, correction 2): the same mid-phrase wrap must ALSO match under a sentence-splitting flatten - proving 'bound to a sentence' would not close the residual, so disclosure (not a narrower guard) is the right response"

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

# --- 14. No tracked file references the pre-S11 data-directory path
# (~/.claude/squirrel) any more, except three narrowly, structurally scoped
# exceptions (S11) --------------------------------------------------------
#
# S11 moved every runtime data path from ~/.claude/squirrel/ to ~/.squirrel/
# (docs/adr/0003's Amendment (S11); the reason is docs/adr/0002's own
# Amendment (S11): `.claude` is a protected path Claude Code checks before
# any hook's `allow`, so the auto-approval ADR-0002 designs can never apply
# there). This closes the loop the task itself named: a whole-file denylist
# is how a BLOCKER survived TWICE in this repo already (the docs/ACCEPTANCE.md
# visibility-scan exemption, S9's Y1 and then S9 review cycle 2's Z1) — so
# none of the three exceptions below is "this whole file doesn't count";
# each is a narrow, structural, content-based rule that a real edit can
# still trip.
#
# The three exceptions, and why each is legitimate:
#
#   (a) tests/* — self-reference, the identical reasoning the four
#       word-content scans above already use (see "Known, documented
#       exclusions" #1 at the top of this file): THIS check's own pattern
#       constant, comments, and mutation-proof fixtures below must contain
#       the literal old-path text to describe and test it, and
#       tests/test_hooks.sh legitimately builds old-path fixtures on
#       purpose to exercise scripts/load-profile.sh's migration-detection
#       feature. This does NOT excuse tests/*.sh from actually testing the
#       new ~/.squirrel/ boundary — that correctness is enforced by
#       tests/test_hooks.sh's own decision-outcome assertions (the allow
#       JSON, and the empty-stdout-plus-exit-0 no-opinion outcome, both
#       against the real, current checkpoints_dir), not by this scan.
#
#   (b) scripts/load-profile.sh's migration notice — the ONE place this
#       plugin is allowed to name the old path at runtime, because telling
#       the user where their old data is IS the feature (see that script's
#       own "S11 MIGRATION NOTICE" header paragraph and its
#       detect_old_data_dir function). Scoped structurally, not by
#       exempting the whole file: an old-path line is allowed only if it
#       falls INSIDE one of two bounded regions — (i) the header's own
#       "S11 MIGRATION NOTICE:" paragraph (bounded: starts at that exact
#       marker, ends at the next lone "#" paragraph-separator line,
#       matching this file's own existing convention for separating
#       header paragraphs), or (ii) the "# --- S11 migration notice ---"
#       section (bounded: starts at that divider, ends at the next
#       "# ---" divider — the existing, established shape of every
#       section boundary in this file). Any other line naming the old
#       path in this file is a violation, REGARDLESS of what else that
#       line says.
#       [AE2, review cycle 1 fix] A prior version of this rule also
#       allowed a THIRD, standalone alternative: a same-line "migrat"
#       co-occurrence, with no requirement that the line be inside either
#       region above. That was the actual defect: a stray comment placed
#       ANYWHERE in this file, mentioning the old path and the word
#       "migrat" together on one line, evaded detection outright — proven
#       by the reviewer, 0 failures. Region membership is now mandatory;
#       a same-line keyword no longer substitutes for it. (Nothing in
#       this file currently needs "migrat" to additionally NARROW within
#       a region — every line inside either region is legitimate content
#       of the migration feature itself — but the rule permits doing so
#       later without weakening this fix: co-occurrence may narrow inside
#       a region, it may never stand in for the region check.)
#
#   (c) docs/adr/0002-checkpoint-auto-allow.md and
#       docs/adr/0003-profile-outside-plugin-data.md's own "## Amendment
#       (S11)" sections — the decision record of the move itself, which
#       cannot honestly describe what changed without naming what it
#       changed FROM. Scoped structurally: anything BEFORE the file's own
#       "## Amendment (S11)" heading is the frozen, pre-existing decision
#       text (docs/adr/0002 already has four earlier "## Amendment" sections
#       that never touched that original body across this whole build, S10-1
#       through AD1 — the established, existing convention this reuses, not
#       a new one invented for this task) and is exempt unconditionally, by
#       position, not content. From the "## Amendment (S11)" heading onward,
#       a PARAGRAPH (blank-line-delimited, matching the AC3/AD4 precedent
#       already in invariant 13 above) naming the old path is allowed only
#       if that SAME paragraph also names the new path (~/.squirrel),
#       ANCHORED to a real path boundary — the literal text "~/.squirrel"
#       must be immediately followed by "/", by a character that is not a
#       letter, digit, underscore, dot, or hyphen, or by the end of the
#       paragraph, never by an arbitrary character — proving it is
#       stating a "moved from X to Y" fact, not a bare, unexplained
#       repetition of the retired claim.
#       [AE3, review cycle 1 fix] A prior version of this rule checked for
#       the new path as an UNANCHORED substring, `$0 !~ /~\/\.squirrel/`.
#       A decoy such as "~/.squirrel-old-notes-backup.txt" contains that
#       exact substring while naming a completely different path, so a
#       paragraph pairing the real old path with only that decoy read as
#       if it had named the new path too — proven by the reviewer, 0
#       failures. The anchor closes this: "~/.squirrel-old-notes-..." no
#       longer satisfies the new-path check, because the character right
#       after "~/.squirrel" ("-") is not "/" and not in the allowed
#       boundary set. A first version of the anchor excluded only
#       letters/digits/"_"/"-" from that boundary set, which still
#       admitted a second decoy shape, "~/.squirrel.old-notes-....txt"
#       ("." left as a valid boundary character) — caught before shipping
#       and closed by also excluding "." from the boundary set, since a
#       dot is exactly as much a part of one unbroken filename token as a
#       hyphen or underscore is.
#
# DISCLOSED, NOT FIXED: exception (c)'s "before the heading" half is a
# positional rule, not a content rule — a new paragraph inserted into the
# pre-existing, frozen portion of either ADR would not be caught by this
# scan. Tightening it to "byte-identical to some frozen baseline" would need
# a baseline commit reference this ongoing build does not have, and would be
# its own source of fragility (which commit IS the baseline, forever?) — the
# same class of overreach this project has already rejected for narrower
# guards (AC1's removed sed fallback, AD4's rejected sentence-bounding).
# Demonstrated, not silently ignored, below.

OLD_DATA_DIR_PATTERN='\.claude/squirrel'
# The new-path marker (a literal `~/.squirrel` occurrence) is checked
# directly inside the two awk functions below, not hoisted into its own
# shell variable: passing a pattern containing `~` through an unquoted
# shell variable risks exactly the tilde-expansion confusion shellcheck's
# SC2088 warns about, for no benefit here since both call sites are awk
# regex literals, never shell-expanded paths.

check_load_profile_old_path_lines() {
  # Prints one "NR: line" per disqualifying old-path line in
  # scripts/load-profile.sh — see exception (b) above for the exact rule.
  # [AE2 fix] Region membership (r1 or r2) is now the ONLY path to
  # exemption — no standalone same-line keyword check. A same-line
  # "migrat" match is deliberately NOT computed here any more: keeping an
  # unused co-occurrence check around, even if never OR'd into `exempt`,
  # would be exactly the kind of latent, easy-to-misuse building block
  # that produced the original defect.
  awk '
    BEGIN { r1 = 0; r2 = 0 }
    {
      line = $0
      if (r1 == 0 && index(line, "S11 MIGRATION NOTICE:") > 0) { r1 = 1 }
      else if (r1 == 1 && line == "#") { r1 = 0 }

      if (r2 == 0 && line ~ /^# --- S11 migration notice/) { r2 = 1 }
      else if (r2 == 1 && line ~ /^# ---/) { r2 = 0 }

      exempt = (r1 == 1 || r2 == 1)
      if (line ~ /\.claude\/squirrel/ && !exempt) { print NR": "line }
    }
  ' "$1"
}

# [AE2 fix] The OLD (vulnerable) exemption mechanism, reproduced inline for
# comparison only — never called against the real script, only against
# scratch fixtures in the failure-proof mutants below. Region membership OR
# a standalone same-line "migrat" match, exactly as this file used to ship.
check_load_profile_old_path_lines_OLD_VULNERABLE() {
  awk '
    BEGIN { r1 = 0; r2 = 0 }
    {
      line = $0
      if (r1 == 0 && index(line, "S11 MIGRATION NOTICE:") > 0) { r1 = 1 }
      else if (r1 == 1 && line == "#") { r1 = 0 }

      if (r2 == 0 && line ~ /^# --- S11 migration notice/) { r2 = 1 }
      else if (r2 == 1 && line ~ /^# ---/) { r2 = 0 }

      same_line_migrat = (line ~ /[Mm][Ii][Gg][Rr][Aa][Tt]/)
      exempt = (r1 == 1 || r2 == 1 || same_line_migrat)
      if (line ~ /\.claude\/squirrel/ && !exempt) { print NR": "line }
    }
  ' "$1"
}

check_adr_s11_old_path_paragraphs() {
  # Prints one flattened-paragraph record per disqualifying old-path
  # paragraph in an ADR file — see exception (c) above for the exact rule.
  # [AE3 fix] The new-path check is ANCHORED to a real path boundary: the
  # literal text "~/.squirrel" must be followed by "/" or by a
  # non-identifier character (anything other than a letter, digit,
  # underscore, dot, or hyphen), or sit at the very end of the paragraph.
  # An unanchored substring match (the old, vulnerable form) would treat a
  # decoy like "~/.squirrel-old-notes-backup.txt" as if it were a genuine
  # mention of the new path, because "~/.squirrel" is a literal substring
  # of that decoy too — proven by the reviewer, 0 failures. "." is
  # EXCLUDED from the set of valid boundary characters, not just
  # letters/digits/"_"/"-": a first attempt at this anchor treated "."
  # as a boundary too, which left a second decoy shape,
  # "~/.squirrel.old-notes-backup.txt", satisfying the check for the
  # identical reason the hyphenated one did — "." is exactly as much a
  # part of an unbroken filename token as "-" or "_" is, so it cannot be
  # treated as a token separator here either.
  awk -v RS="" '
    BEGIN { seen = 0 }
    {
      if (index($0, "## Amendment (S11)") > 0) { seen = 1 }
      if (seen && $0 ~ /\.claude\/squirrel/ && $0 !~ /~\/\.squirrel([^A-Za-z0-9_.-]|$)/) {
        print "---"
        print $0
      }
    }
  ' "$1"
}

# [AE3 fix] The OLD (vulnerable) new-path check, reproduced inline for
# comparison only — never called against the real ADR files, only against
# scratch fixtures in the failure-proof mutants below. Unanchored substring
# match, exactly as this file used to ship.
check_adr_s11_old_path_paragraphs_OLD_VULNERABLE() {
  awk -v RS="" '
    BEGIN { seen = 0 }
    {
      if (index($0, "## Amendment (S11)") > 0) { seen = 1 }
      if (seen && $0 ~ /\.claude\/squirrel/ && $0 !~ /~\/\.squirrel/) {
        print "---"
        print $0
      }
    }
  ' "$1"
}

old_path_hits=""
for f in $(git -C "$repo_root" ls-files); do
  case "$f" in
    tests/*)
      continue
      ;;
    scripts/load-profile.sh)
      hits=$(check_load_profile_old_path_lines "$repo_root/$f")
      [ -z "$hits" ] || old_path_hits="$old_path_hits $f"
      ;;
    docs/adr/0002-checkpoint-auto-allow.md | docs/adr/0003-profile-outside-plugin-data.md)
      hits=$(check_adr_s11_old_path_paragraphs "$repo_root/$f")
      [ -z "$hits" ] || old_path_hits="$old_path_hits $f"
      ;;
    *)
      if grep -qE "$OLD_DATA_DIR_PATTERN" "$repo_root/$f" 2>/dev/null; then
        old_path_hits="$old_path_hits $f"
      fi
      ;;
  esac
done

assert_eq "" "$old_path_hits" "no tracked file (outside tests/, self-referential) may still reference the pre-S11 path ~/.claude/squirrel, except scripts/load-profile.sh's migration-notice region and docs/adr/0002 + docs/adr/0003's own S11 amendments, each checked under its own narrow, structural rule above rather than a whole-file exemption"

# Sanity: each of the three exceptions is actually exercised against the
# real, current repo — none of the rules above is passing vacuously because
# the file it protects happens to contain no old-path text at all right now.
real_lp_old_path_count=$(grep -cE "$OLD_DATA_DIR_PATTERN" "$repo_root/scripts/load-profile.sh")
assert_eq "yes" "$([ "$real_lp_old_path_count" -gt 0 ] && echo yes || echo no)" "sanity (invariant 14): scripts/load-profile.sh must genuinely contain the old path today (in its migration notice), or exception (b) above is protecting nothing"

real_adr2_old_path_count=$(grep -cE "$OLD_DATA_DIR_PATTERN" "$repo_root/docs/adr/0002-checkpoint-auto-allow.md")
assert_eq "yes" "$([ "$real_adr2_old_path_count" -gt 0 ] && echo yes || echo no)" "sanity (invariant 14): docs/adr/0002-checkpoint-auto-allow.md must genuinely contain the old path today, or exception (c) above is protecting nothing"

real_adr3_old_path_count=$(grep -cE "$OLD_DATA_DIR_PATTERN" "$repo_root/docs/adr/0003-profile-outside-plugin-data.md")
assert_eq "yes" "$([ "$real_adr3_old_path_count" -gt 0 ] && echo yes || echo no)" "sanity (invariant 14): docs/adr/0003-profile-outside-plugin-data.md must genuinely contain the old path today, or exception (c) above is protecting nothing"

# FAILURE PROOF 1: an ordinary tracked file, outside every exception, gets a
# stray old-path reference — must be caught.
old_path_scratch="$glossary_avoid_scratch"
fp1_fixture="$old_path_scratch/ordinary_stray_old_path.md"
printf '# Sample doc\n\nSome stray reference to ~/.claude/squirrel/profile.md here.\n' >"$fp1_fixture"
if grep -qE "$OLD_DATA_DIR_PATTERN" "$fp1_fixture" 2>/dev/null; then
  fp1_caught=yes
else
  fp1_caught=no
fi
assert_eq "yes" "$fp1_caught" "FAILURE PROOF (invariant 14, #1): an ordinary file outside every exception must be caught the moment it names the old path"

# FAILURE PROOF 2: scripts/load-profile.sh gets a stray old-path reference
# INSIDE build_context (real code, far from both marker regions, no
# "migrat" word nearby) — must be caught.
fp2_fixture="$old_path_scratch/load-profile_stray.sh"
awk '{ print } /home_dir="\$\{HOME:-\}"/ && !done { print "  # stray reference to $home_dir/.claude/squirrel/profile.md here"; done = 1 }' "$repo_root/scripts/load-profile.sh" >"$fp2_fixture"
fp2_hits=$(check_load_profile_old_path_lines "$fp2_fixture")
assert_eq "yes" "$([ -n "$fp2_hits" ] && echo yes || echo no)" "FAILURE PROOF (invariant 14, #2): a stray old-path line inside scripts/load-profile.sh's real code, outside both marker regions and with no 'migrat' co-occurring on the same line, must be caught"

# FAILURE PROOF 3: the SAME stray line, placed immediately after the NEXT
# section divider following the migration-notice function (i.e. just past
# where exception (b)'s region (ii) ends) — must ALSO be caught, proving
# that region is bounded rather than open-ended once entered.
fp3_fixture="$old_path_scratch/load-profile_stray_boundary.sh"
awk '{ print } /^# --- JSON escaping/ && !done { print "# stray $HOME/.claude/squirrel mention right after the next divider"; done = 1 }' "$repo_root/scripts/load-profile.sh" >"$fp3_fixture"
fp3_hits=$(check_load_profile_old_path_lines "$fp3_fixture")
assert_eq "yes" "$([ -n "$fp3_hits" ] && echo yes || echo no)" "FAILURE PROOF (invariant 14, #3): a stray old-path line placed just past exception (b)'s region-(ii) end boundary must still be caught — the region does not leak past its own next divider"

# ==========================================================================
# DEMONSTRATION + FIX PROOF (invariant 14, AE2) — the review's exact
# evasion for exception (b): a stray line placed OUTSIDE both bounded
# regions (the same insertion point FAILURE PROOF 2 above uses — real code
# inside build_context, far from either marker region), but this one also
# names "migrat" on that SAME line. Under the OLD (region-OR-same-line-
# keyword) exemption this evaded detection outright, reported by the
# reviewer at 0 failures against the real check. The NEW (region-only) rule
# catches it, because region membership is now the only path to exemption.
# ==========================================================================
ae2_fixture="$old_path_scratch/load-profile_stray_migrat_outside_region.sh"
awk '{ print } /home_dir="\$\{HOME:-\}"/ && !done { print "  # stray note: migrated users may still have data at $home_dir/.claude/squirrel/profile.md"; done = 1 }' "$repo_root/scripts/load-profile.sh" >"$ae2_fixture"

if grep -qE "$OLD_DATA_DIR_PATTERN" "$ae2_fixture" 2>/dev/null && grep -qiE 'migrat' "$ae2_fixture" 2>/dev/null; then
  ae2_fixture_has_both=yes
else
  ae2_fixture_has_both=no
fi
assert_eq "yes" "$ae2_fixture_has_both" "sanity (invariant 14, AE2): the fixture must genuinely contain both the old path and the word 'migrat' on the inserted line, or this is not testing the reviewer's evasion at all"

ae2_old_hits=$(check_load_profile_old_path_lines_OLD_VULNERABLE "$ae2_fixture")
assert_eq "" "$ae2_old_hits" "DEMONSTRATION (invariant 14, AE2): the OLD (region-OR-same-line-keyword) exemption must MISS a stray old-path line placed outside both bounded regions merely because it also says 'migrat' on the same line — the reviewer's exact evasion, reproduced here against the OLD mechanism for comparison only; never called against the real script"

ae2_new_hits=$(check_load_profile_old_path_lines "$ae2_fixture")
assert_eq "yes" "$([ -n "$ae2_new_hits" ] && echo yes || echo no)" "FIX PROOF (invariant 14, AE2): the NEW (region-only) rule must CATCH the identical stray line the OLD mechanism just missed, above"

# FAILURE PROOF 4: a new paragraph inserted AFTER docs/adr/0002's own "##
# Amendment (S11)" heading, naming the old path with no accompanying new-path
# mention in the same paragraph — must be caught.
fp4_fixture="$old_path_scratch/adr0002_stray_after_heading.md"
awk '{ print } /## Amendment \(S11\)/ && !done { print ""; print "Stray sentence mentioning ~/.claude/squirrel/ with no accompanying new-path note in this same paragraph."; done = 1 }' "$repo_root/docs/adr/0002-checkpoint-auto-allow.md" >"$fp4_fixture"
fp4_hits=$(check_adr_s11_old_path_paragraphs "$fp4_fixture")
assert_eq "yes" "$([ -n "$fp4_hits" ] && echo yes || echo no)" "FAILURE PROOF (invariant 14, #4): a new paragraph after docs/adr/0002's Amendment (S11) heading naming the old path with no new-path mention in the same paragraph must be caught"

# FAILURE PROOF 5: the identical construction against docs/adr/0003 — proves
# the same function catches it there too, not just in docs/adr/0002.
fp5_fixture="$old_path_scratch/adr0003_stray_after_heading.md"
awk '{ print } /## Amendment \(S11\)/ && !done { print ""; print "Another stray sentence mentioning ~/.claude/squirrel/ with no accompanying new-path note in this same paragraph."; done = 1 }' "$repo_root/docs/adr/0003-profile-outside-plugin-data.md" >"$fp5_fixture"
fp5_hits=$(check_adr_s11_old_path_paragraphs "$fp5_fixture")
assert_eq "yes" "$([ -n "$fp5_hits" ] && echo yes || echo no)" "FAILURE PROOF (invariant 14, #5): the identical construction against docs/adr/0003 must also be caught"

# ==========================================================================
# DEMONSTRATION + FIX PROOF (invariant 14, AE3) — the review's exact
# evasion for exception (c): a paragraph naming the real old path plus a
# DECOY that merely contains "~/.squirrel" as a substring
# ("~/.squirrel-old-notes-backup.txt"), with no genuine new-path mention
# anywhere in it. Under the OLD (unanchored substring) new-path check the
# decoy satisfied `$0 ~ /~\/\.squirrel/` and the paragraph read as if it
# had named the new path — reported by the reviewer at 0 failures against
# the real check. The NEW (anchored) check requires "~/.squirrel" to be
# followed by "/", a non-identifier character, or paragraph-end, so the
# decoy's own trailing "-" defeats it.
# ==========================================================================
ae3_fixture="$old_path_scratch/adr0002_decoy_after_heading.md"
awk '{ print } /## Amendment \(S11\)/ && !done { print ""; print "Stray sentence mentioning ~/.claude/squirrel/ alongside an unrelated backup file at ~/.squirrel-old-notes-backup.txt, naming no real new-path location anywhere in this same paragraph."; done = 1 }' "$repo_root/docs/adr/0002-checkpoint-auto-allow.md" >"$ae3_fixture"

# shellcheck disable=SC2088 # single-quoted deliberately: this is a
# literal needle grep searches the fixture's TEXT for, never a path this
# shell opens or expands - a leading "~" here is not tilde-expansion gone
# wrong.
if grep -qE "$OLD_DATA_DIR_PATTERN" "$ae3_fixture" 2>/dev/null && grep -qF -- '~/.squirrel-old-notes-backup.txt' "$ae3_fixture" 2>/dev/null; then
  ae3_fixture_has_decoy=yes
else
  ae3_fixture_has_decoy=no
fi
assert_eq "yes" "$ae3_fixture_has_decoy" "sanity (invariant 14, AE3): the fixture must genuinely contain both the old path and the decoy string, or this is not testing the reviewer's evasion at all"

ae3_old_hits=$(check_adr_s11_old_path_paragraphs_OLD_VULNERABLE "$ae3_fixture")
assert_eq "" "$ae3_old_hits" "DEMONSTRATION (invariant 14, AE3): the OLD (unanchored substring) new-path check must MISS a paragraph pairing the real old path with only a decoy like '~/.squirrel-old-notes-backup.txt' — the reviewer's exact evasion, reproduced here against the OLD mechanism for comparison only; never called against the real ADR files"

ae3_new_hits=$(check_adr_s11_old_path_paragraphs "$ae3_fixture")
assert_eq "yes" "$([ -n "$ae3_new_hits" ] && echo yes || echo no)" "FIX PROOF (invariant 14, AE3): the NEW (anchored) new-path check must CATCH the identical decoy paragraph the OLD mechanism just missed, above"

# ==========================================================================
# FIX PROOF (invariant 14, AE3 dot-decoy variant) — a SECOND decoy shape,
# caught only because "." is also excluded from the anchor's boundary set.
# A first draft of the anchor excluded letters/digits/"_"/"-" but left "."
# as a valid boundary character, which would have let
# "~/.squirrel.old-notes-backup.txt" through for the identical reason the
# hyphenated decoy did: a dot is exactly as much a part of one unbroken
# filename token as a hyphen or underscore. Caught before this fix shipped
# — pinned here so it cannot come back unnoticed.
# ==========================================================================
ae3_dot_fixture="$old_path_scratch/adr0002_dot_decoy_after_heading.md"
awk '{ print } /## Amendment \(S11\)/ && !done { print ""; print "Stray sentence mentioning ~/.claude/squirrel/ alongside an unrelated backup file at ~/.squirrel.old-notes-backup.txt, naming no real new-path location anywhere in this same paragraph."; done = 1 }' "$repo_root/docs/adr/0002-checkpoint-auto-allow.md" >"$ae3_dot_fixture"

# shellcheck disable=SC2088 # single-quoted deliberately: literal needle
# text, never a path this shell opens or expands.
if grep -qE "$OLD_DATA_DIR_PATTERN" "$ae3_dot_fixture" 2>/dev/null && grep -qF -- '~/.squirrel.old-notes-backup.txt' "$ae3_dot_fixture" 2>/dev/null; then
  ae3_dot_fixture_has_decoy=yes
else
  ae3_dot_fixture_has_decoy=no
fi
assert_eq "yes" "$ae3_dot_fixture_has_decoy" "sanity (invariant 14, AE3 dot-decoy): the fixture must genuinely contain both the old path and the dot-decoy string, or this is not testing anything"

ae3_dot_old_hits=$(check_adr_s11_old_path_paragraphs_OLD_VULNERABLE "$ae3_dot_fixture")
assert_eq "" "$ae3_dot_old_hits" "DEMONSTRATION (invariant 14, AE3 dot-decoy): the OLD (unanchored substring) new-path check must also MISS the dot-decoy variant — the identical class of evasion, a different separator character"

ae3_dot_new_hits=$(check_adr_s11_old_path_paragraphs "$ae3_dot_fixture")
assert_eq "yes" "$([ -n "$ae3_dot_new_hits" ] && echo yes || echo no)" "FIX PROOF (invariant 14, AE3 dot-decoy): the NEW anchor, which excludes \".\" from the boundary set in addition to letters/digits/\"_\"/\"-\", must CATCH the dot-decoy paragraph — a narrower anchor that left \".\" as a valid boundary would NOT catch this"

# DEMONSTRATION, not a defect (invariant 14, exception (c)'s disclosed
# limitation): a stray old-path sentence inserted BEFORE either ADR's own
# "## Amendment (S11)" heading — inside the frozen, pre-existing decision
# text — is NOT caught, because exception (c) exempts that region by
# position, not content. Stated plainly per this project's own convention
# (AC3's paraphrase limitation, AD4's within-one-paragraph residual): this
# is a known, bounded gap, not an oversight.
fp6_fixture="$old_path_scratch/adr0003_stray_before_heading.md"
awk '{ print } /^Claude Code provides/ && !done { print "Another stray sentence: ~/.claude/squirrel/ mentioned again here, no new path nearby."; done = 1 }' "$repo_root/docs/adr/0003-profile-outside-plugin-data.md" >"$fp6_fixture"
fp6_hits=$(check_adr_s11_old_path_paragraphs "$fp6_fixture")
assert_eq "no" "$([ -n "$fp6_hits" ] && echo yes || echo no)" "DEMONSTRATION, not a defect (invariant 14): a stray old-path sentence inserted BEFORE docs/adr/0003's own Amendment (S11) heading is NOT caught — exception (c) is positional, not content-based, for the frozen pre-existing decision text, a disclosed and bounded limitation, not an oversight"

# --- 15. docs/ACCEPTANCE.md's status word must agree across its three
# recording places: each criterion's own **Status:** line, its row in the
# ## Summary table, and the counts stated in the tally paragraph right
# after that table ------------------------------------------------------
#
# WHY THIS EXISTS. Nothing before this invariant ever checked that these
# three places agree with each other, and they silently drifted: criterion
# 12 was `observed` in its own Status line and in the summary table while
# criteria 10 and 12 were scored under two different, undocumented
# conventions for a criterion whose heading names several branches (see
# "How to read the status column"'s new "Multi-branch criteria" bullet,
# and criterion 12's own "Judgment call" note, for the full history). A
# human happened to catch that one by re-reading the document closely.
# This invariant makes the mechanical half of that class impossible to
# ship unnoticed a second time: it does NOT adjudicate which convention is
# correct (that is a judgment call for a human, recorded in prose, not a
# fact a script can derive) — it only checks that the three places that
# record whatever the current judgment call decided stay byte-for-byte
# consistent with each other from here on.
#
# WHAT THIS CHECKS, exactly:
#   (a) for every one of the 22 criteria, the status word on its own
#       "**Status:**" line equals the status word in its own row of the
#       "## Summary table";
#   (b) the three counts stated in the tally paragraph immediately after
#       that table (the met-count, the observed-count, the manual-count)
#       each equal the actual number of criteria whose own "**Status:**"
#       line says so;
#   (c) [FIX 1] every one of the 22 criteria's section contains EXACTLY
#       ONE "**Status:**" line — neither zero (missing) nor two-or-more
#       (duplicated, whether or not the duplicate contradicts the real
#       one). Found by review: a second, CONTRADICTING "**Status:**" line
#       placed AFTER the real one is invisible to (a) above, because
#       extract_status_word()'s `head -n 1` still returns the correct,
#       first line — the criterion's own line and its table row still
#       agree, so (a) never fires. A duplicate placed BEFORE the real one
#       IS caught by (a) (the wrong, first-found word disagrees with the
#       table row) — that direction was already covered before this fix;
#       proving only it would have been the exact "guard that could not
#       fail for its own target" trap named below, so the embedded FAILURE
#       PROOF targets the AFTER direction specifically. As of cycle 3, the
#       "**Status:**" marker itself may be preceded by leading whitespace
#       (a second review finding: an indented duplicate was invisible to
#       the literal, unindented anchor) — see extract_status_word()'s own
#       header comment for exactly what that tolerance covers and, just as
#       deliberately, does not;
#   (d) [FIX 2] the tally paragraph's `observed` parenthetical enumerates
#       EXACTLY the SET of criterion numbers whose own "**Status:**" line
#       says `observed` — not merely the same COUNT as (b) already checks.
#       Found by review: rewriting the observed clause to name a wrong
#       criterion while leaving the leading count untouched (e.g. "4
#       (criteria 4, 5, 11, 16) are `observed`" when 16 is actually `met`)
#       passes (b) outright; the `manual` prose has the identical gap. The
#       `manual` span's own check is deliberately NOT the same equality,
#       as of cycle 3 — see "FIX 2'S OWN ENUMERATION CHECK, SCOPED
#       DELIBERATELY" below for why containment replaced it there.
#
# WHAT THIS DOES NOT CHECK, stated plainly per this project's own
# convention of disclosing a guard's limits rather than implying it is
# complete: it does not check that a status word is the RIGHT one for the
# evidence a criterion's section actually describes (that is exactly the
# judgment call above) — only that the three places recording whatever
# word was chosen agree. A `not met` criterion is supported structurally
# (case-matched below like the other three words) but none exist today, so
# no live assertion below exercises that branch; if one is ever added,
# invariant 12 (byte-identical headings) and this invariant's own
# not-met/total-19 sanity check both still apply to it unchanged.
#
# ACCEPTED RESIDUE (reviewed and deliberately left as-is, not a gap this
# cycle closes):
#   - A status word whose CASE is flipped IDENTICALLY in both the
#     "**Status:**" line and the summary-table row (e.g. both say `Manual`
#     instead of `manual`) is not named by (a) — the two sides still agree
#     with each other, byte-for-byte, so there is nothing for a per-
#     criterion diff to report. It IS still caught, LOUDLY, by MULTIPLE
#     mechanisms at once — empirically reconfirmed against the CURRENT
#     text (not just reasoned about, and RE-run after the cycle 3
#     containment change below, since that change alters this residue's
#     own shape) by flipping criterion 8 to `Manual` in both places, in a
#     scratch copy. THREE are PURPOSE-BUILT detectors: the
#     per-criterion-counts-sum-to-19 sanity check fails (18, not 19, since
#     the flipped word matches none of the four `case` branches in
#     compute_status_and_counts()); the tally's own manual-count (15b)
#     fails (the real count drops to 7 while the prose still says 8); and
#     the manual-span CONTAINMENT check (Fix 2, cycle 3, below) fails too
#     — and, unlike cycle 2's set-EQUALITY version, now NAMES the
#     criterion directly: its own "actual" field prints exactly "8", since
#     8 stays in the tally's enumerated set while dropping out of the real
#     one. A FOURTH thing also goes red in the same scratch copy, and this
#     is the one worth saying plainly is NOT a fourth purpose-built
#     detector: it is this invariant's own embedded FAILURE PROOF for the
#     13->11 mis-enumeration case (below), breaking as INCIDENTAL
#     COLLATERAL, not designed detection. That proof's "actual" field,
#     which should read exactly "11" (the number it exists to catch),
#     instead reads "8 11" in this scratch copy — its own containment
#     check runs against the SAME real manual set, which just lost "8" for
#     a reason that proof was never written to detect. This is not
#     systematic, and saying so is part of being honest about it: two of
#     the four LEGITIMATE-REWORDING self-tests for the manual span
#     (below) — the ones whose own fixture text happens to name criterion
#     8 (the plain reordering and the added-sentence ones) — go red the
#     same collateral way, while the other two (the range and semicolon
#     reworks, whose severe under-extraction never reaches "8" at all)
#     stay green throughout. Whether a given embedded self-test breaks
#     this way depends on whether its own fixture happens to reference the
#     same criterion number, not on any of them being designed to catch a
#     case flip. Deliberately not case-normalized: normalizing would make
#     a genuinely flipped, wrong-cased status word compare as if it
#     matched, turning a real drift into a silent pass — worse than
#     today's "fails loudly, several times over, and by name at least
#     once" residue.
#   - A rewording that changes the tally paragraph's SHAPE enough to break
#     one of this invariant's own anchor phrases (the three in point (b)
#     above, reused by point (d) for the `observed`/`manual` enumeration
#     checks) produces a LOUD, NAMED false positive, not a silent pass —
#     but not all by the SAME mechanism, and stating that precisely is the
#     Fix 3 correction: the two "found all 22" sanity checks, the "exactly
#     one tally paragraph" check, and the two Fix-2 "must yield at least
#     one criterion number" checks each have their OWN dedicated
#     vacuousness assertion, exactly as this paragraph used to claim for
#     everything below. The three bare tally-COUNT anchors (met/
#     observed/manual, point (b)) have no such dedicated assertion at
#     all, yet are equally safe, for a different reason: each is compared
#     against a real, independently-computed count that is never itself
#     empty, so a broken anchor there produces "expected: 7, actual: "
#     (a genuine, named mismatch) — never "" == "" comparing something it
#     never tested. What was FALSE here before Fix 3, for exactly one
#     function, named plainly rather than left implicit: the general claim
#     "an anchor that stops matching returns empty and fails that sanity
#     check by name" was NOT true for extract_observed_number_set() — its
#     own inner pipeline ended in a `grep` that, on no match, could ABORT
#     THE WHOLE SCRIPT under `set -eu`, skipping every remaining assertion
#     in this file rather than failing one check by name. See that
#     function's own header comment for the fix and the exact hazard.
#     After Fix 3, every extraction below genuinely degrades to a graceful,
#     named failure (by one of the two mechanisms above); none can abort
#     the run, and none can pass by comparing two empty strings.
#
# NARROWED TO THE MECHANICAL FACT, DELIBERATELY (per this build's own
# "guard that blocks correct work" warning). The tally-count extraction
# below is anchored on the three phrases "N of 22 criteria are `met`", "N
# (criteria ...) are `observed`", and "N remain `manual`" — not because
# those exact eleven words are sacred, but because SOME numeral has to sit
# next to SOME status word for a tally paragraph to state a count at all;
# any future rewording of this paragraph that keeps stating "how many
# criteria are met/observed/manual" will keep producing text these
# patterns can find. A rewrite that drops the count sentences entirely
# would make the extraction below return empty — caught by the "exactly
# one tally paragraph found" sanity check below, not silently ignored — at
# which point a human updates this invariant's anchors deliberately,
# rather than the check quietly rotting into a vacuous pass. What this
# invariant intentionally does NOT pin: a criterion legitimately changing
# status (met legitimately becoming manual because a regression is found;
# a manual criterion legitimately becoming observed because a new live
# probe closes it) is not rejected by anything below — the three places
# just have to agree about whatever the new, true status is.
#
# FIX 2's OWN ENUMERATION CHECK, SCOPED DELIBERATELY, AND — as of cycle 3
# — COMPARED DIFFERENTLY ON EACH SIDE. The `observed` parenthetical is a
# clean, machine-shaped list ("N (criteria a, b, c, d) are `observed`")
# and is compared by set EQUALITY: the real `observed` set and the
# enumerated one must match exactly, in both directions.
#
# The `manual` span is free-form prose spread across several sentences (a
# main list, a per-branch aside, cross-references like "see criterion 10's
# own section," the history of criterion 12's two moves) — collecting
# every criterion-introduced number from the anchor phrase "N remain
# `manual`" to the END of the tally paragraph (never past it:
# get_tally_paragraph flattens per PARAGRAPH, so this can never spill into
# unrelated text elsewhere in the document). Cycle 2 also compared this
# side by set equality; the review reproduced two legitimate rewordings of
# the identical true facts — an elliptical range ("criteria 3 and 6
# through 9, plus 13, in full") and a semicolon restructure ("criteria 3;
# 6; 7; 8; 9; and 13") — that equality REJECTED, because
# extract_criteria_numbers()'s own comma/"and"-joined grammar cannot
# expand either shape and so legitimately extracts a proper SUBSET of the
# true set. A guard that rejects correct work is worse than no guard, so
# cycle 3 replaced equality with CONTAINMENT for this span only, via
# set_subset_violations() (defined above, near sorted_unique_set()): every
# number the manual span's prose enumerates must genuinely be `manual`;
# the real `manual` set is no longer required to appear here IN FULL.
# This tolerates re-sentencing, reordering, incidental repeated mentions,
# AND now under-extraction, all for the same reason — proved by the four
# embedded LEGITIMATE REWORDING assertions below (reordering; the range
# wording; the semicolon restructure; an added explanatory sentence).
#
# The one thing this wide-but-paragraph-bounded, containment-based scope
# does NOT close, stated plainly: an incidental mention of a NON-manual
# criterion anywhere after the anchor, still inside the same paragraph,
# would be swept into the set too and would then legitimately fail the
# containment check — a loud false positive that NAMES the offending
# number directly (the same disclosed class as the anchor-rewording
# residue above, but more precisely reported than equality's "compare two
# whole sets" ever was), not a silent miss. Today's real text has no such
# stray mention after the anchor (every number named there — 3, 6, 7, 8,
# 9, 13, 10, 12 — is genuinely `manual`); see extract_manual_number_set()'s
# and set_subset_violations()'s own header comments for the full
# reasoning.
#
# Symmetrically, and just as plainly: this same containment scope does not
# close FALSE EXCLUSION either — silently DROPPING a genuinely-`manual`
# criterion number from this span's enumeration, while leaving the count
# at (b) untouched, passes clean, because containment only forbids naming
# a criterion that is not `manual` and never requires naming every one
# that is — and that is acceptable here, not a second defect, because the
# dropped criterion's own recorded status stays fully pinned regardless of
# what this prose omits, by the section-vs-table check (15a) and the
# tally's own count check (15b); only this span's self-enumeration
# COMPLETENESS goes unverified, never any criterion's actual status.
# P4 item 5 — REAFFIRM: omission of a manual number from this span does
# not go red by itself (reviewer-confirmed: drop a listed number, leave
# the count — containment and 15b stay green); 15a/15b still pin that
# criterion's status. Closing with set equality was already rejected
# (cycle 3): it bars legitimate rewordings.

get_section_between() {
  # get_section_between <content> <start-heading-regex> - lines from the
  # first line matching <start-heading-regex> (inclusive) to the next
  # "^## " heading (exclusive) or EOF. A generic, named-heading version of
  # get_acceptance_section (invariant 13, above) for a section identified
  # by its heading text rather than a criterion number.
  content=$1
  start_re=$2
  printf '%s\n' "$content" | awk -v start="$start_re" '
    $0 ~ start { insec = 1; print; next }
    insec && /^## / { insec = 0 }
    insec { print }
  '
}

extract_status_word() {
  # extract_status_word <section-text> - the status word inside a
  # criterion's own "**Status:**" line's FIRST backtick pair (e.g. "met",
  # "observed", "manual", "not met"). Empty if no such line exists in the
  # given text.
  #
  # DELIBERATELY FIRST-MATCH-ONLY, and that is exactly the gap
  # count_status_lines() (below) exists to close: this function alone
  # cannot tell "exactly one Status line" apart from "two or more, with
  # every line after the first silently ignored." A duplicate, contradicting
  # "**Status:**" line placed AFTER the real one is invisible to this
  # function specifically because `head -n 1` still returns the correct,
  # first line's word - the criterion's own Status line and its summary-
  # table row still agree, so invariant 15a's cross-check does not fire
  # either. See count_status_lines() and its own FAILURE PROOF for the
  # mechanism that catches that direction.
  #
  # [FIX 1] Anchored on "^[[:space:]]*\*\*Status:\*\*" - leading whitespace
  # before the marker is now tolerated, so a duplicate, contradicting
  # "**Status:**" line indented by even a single space is still found by
  # this function (and, more importantly, counted by count_status_lines()
  # below) instead of being invisible to both. STATED PLAINLY, what this
  # does NOT cover, on purpose, not by oversight: the marker itself must
  # still be the literal text "**Status:**" - that exact word, that exact
  # colon, bold with double asterisks. A hand-written variant spelling of
  # the same idea - "__Status:__", "*Status:*", or any other Markdown
  # emphasis syntax around the same word - is NOT matched, deliberately not
  # widened to catch it. This guard exists to catch ACCIDENTAL drift, and
  # accidental drift copies the shape of the surrounding line, because
  # that is what a human editor is looking at when they duplicate, indent,
  # or reflow a line near one that already reads "**Status:**" - leading
  # whitespace is exactly that class of accident. A hand-crafted
  # "__Status:__" duplicate is not; it is a deliberately different
  # spelling, and chasing every Markdown emphasis variant this invariant
  # could imagine buys nothing against the threat model this guard is
  # actually for.
  # P4 item 3 — REAFFIRM: leave "__Status:__" / other emphasis spellings
  # unmatched. Accidental drift copies neighbouring "**Status:**" shape;
  # widening to every Markdown emphasis variant buys nothing against that
  # threat model (PLAN: deliberate decision).
  # Also out of scope, by design: a status-shaped line
  # sitting OUTSIDE all 22 numbered criterion sections (e.g. loose prose
  # above criterion 1's own heading, or after criterion 19's) is never fed
  # to this function at all - get_acceptance_section (invariant 13) bounds
  # every call site's input to one criterion's own section, so nothing
  # outside every section is checked by invariant 15. That is a correct
  # scope boundary, not a gap: this invariant's whole job is comparing the
  # three places a CRITERION records ITS OWN status, and text outside every
  # criterion's section is not any criterion's status record.
  # P4 item 4 — REAFFIRM: status-format lines outside the 19 sections stay
  # out of scope. Limit already written above; this invariant compares a
  # criterion's own three recording places, not free-floating prose.
  # shellcheck disable=SC2016 # single-quoted deliberately: literal
  # backtick-quoted markdown syntax in the sed pattern, never substitution.
  printf '%s\n' "$1" | grep -E '^[[:space:]]*\*\*Status:\*\*' | head -n 1 \
    | sed -n 's/^[[:space:]]*\*\*Status:\*\* `\([a-zA-Z ]*\)`.*/\1/p'
}

count_status_lines() {
  # count_status_lines <section-text> - how many lines in <section-text>
  # begin with the literal "**Status:**" marker, leading whitespace
  # tolerated [FIX 1] (see extract_status_word()'s own comment,
  # immediately above, for exactly what "tolerated" covers - leading
  # spaces/tabs only, never a different Markdown emphasis spelling of the
  # same marker, and never text outside a criterion's own section): 0
  # (missing), 1 (correct), or 2+ (duplicated - possibly contradicting each
  # other, possibly not; this function does not care which, only that
  # there must be exactly one). `|| true`: under `set -eu`, `grep -c` with
  # zero matches exits 1, which would abort the whole script from inside a
  # command-substitution assignment rather than reporting a single named
  # failure - the same guard-rail every other grep-in-assignment in this
  # invariant already uses (see get_tally_paragraph's own comment on the
  # identical hazard).
  printf '%s\n' "$1" | grep -c -E '^[[:space:]]*\*\*Status:\*\*' || true
}

get_summary_table_line() {
  # get_summary_table_line <content> <n> - the "| N | ... | ... | status |"
  # row of the "## Summary table" section whose FIRST column, trimmed,
  # equals <n> EXACTLY (so criterion "1" can never match rows "10".."19").
  # Scoped to that one named section (via get_section_between) so a
  # coincidentally numbered first column in some unrelated table elsewhere
  # in this document (several mutation-proof tables further down use
  # "| Mutation | Result | Assertion |" rows) can never be mistaken for a
  # criterion row.
  content=$1
  n=$2
  section=$(get_section_between "$content" '^## Summary table')
  printf '%s\n' "$section" | awk -F'|' -v want="$n" '
    NF >= 5 {
      col1 = $2
      gsub(/^[ \t]+|[ \t]+$/, "", col1)
      if (col1 == want) { print; exit }
    }
  '
}

extract_table_status() {
  # extract_table_status <table-row-line> - the LAST non-empty,
  # whitespace-trimmed column of a "| ... | ... |" markdown table row (the
  # Status column, for a summary-table row — found by position from the
  # right, not by counting from the left, so it is immune to the
  # Verification column's own free-text width).
  printf '%s\n' "$1" | awk -F'|' '
    {
      n = NF
      while (n > 0 && $n ~ /^[ \t]*$/) n--
      s = $n
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      print s
    }
  '
}

mutate_table_status() {
  # mutate_table_status <table-row-line> <new-status> - <table-row-line>
  # with its LAST non-empty column replaced by <new-status>, every other
  # column and the pipe structure left byte-identical.
  printf '%s\n' "$1" | awk -F'|' -v new=" $2 " '
    {
      n = NF
      while (n > 0 && $n ~ /^[ \t]*$/) n--
      $n = new
      out = $1
      for (i = 2; i <= NF; i++) out = out "|" $i
      print out
    }
  '
}

get_tally_paragraph() {
  # get_tally_paragraph <content> - the single, flattened paragraph inside
  # the "## Summary table" section that states the met/observed/manual
  # counts, identified by containing the literal substring "of 22
  # criteria" (the one phrase any version of this tally has had to use, to
  # say "out of a fixed total of 22" at all). Flattened per-paragraph via
  # flatten_acceptance_section (defined above, for invariant 13), so a
  # re-wrap at a different column width never changes which words the
  # regexes below see adjacent to each other.
  # `|| true`: if the "## Summary table" heading itself is missing or
  # renamed, $section is empty and this grep legitimately finds nothing —
  # under `set -eu`, an unguarded failing grep inside a command
  # substitution assignment (the call sites below all do
  # `x=$(get_tally_paragraph ...)`) would abort the WHOLE script before
  # assert_report ever runs, hiding every other assertion rather than
  # reporting one clean, named failure. The sanity check right after every
  # call site below (tally_paragraphs_found15 must be exactly 1) is what
  # actually catches this case, as a real assertion instead of a crash.
  section=$(get_section_between "$1" '^## Summary table')
  flatten_acceptance_section "$section" | grep 'of 22 criteria' || true
}

extract_criteria_numbers() {
  # extract_criteria_numbers <text> - every integer immediately introduced
  # by the word "criterion" or "criteria" (case-insensitive on the leading
  # letter only, so a sentence-initial "Criterion 7 is `manual`..." is
  # matched the same as a mid-sentence "criteria 3, 6, ..." — duplicates
  # from the two forms mentioning the same number are harmless, since every
  # caller below runs this through sorted_unique_set), including a natural-
  # English list joined by commas and/or "and" ("criteria 3, 6, 7, 8, 9,
  # and 13", "criteria 10 and 12"), one number per output line, in the
  # order they appear. A bare number with no "criterion"/"criteria"
  # immediately before it — the "22" inside "of 22 criteria", a turn
  # count, an S-cycle number like "S10" — is never matched, because the
  # introducing word must come first, immediately adjacent to the number,
  # and the numbers grabbed out of the match are only the ones the list-
  # continuation group actually consumed (never a stray digit run the
  # surrounding prose happens to contain right after the match, e.g. an
  # "S10" immediately following one of these clauses in real prose).
  printf '%s' "$1" \
    | grep -oE '[Cc]riteri(on|a) [0-9]+([, ]+(and )?[0-9]+)*' \
    | grep -oE '[0-9]+'
}

sorted_unique_set() {
  # sorted_unique_set <comma/space-separated numbers, or "-"> - the same
  # numbers, sorted numerically, deduplicated, space-joined — the
  # canonical form both "the real set of criteria holding a status" (from
  # compute_status_and_counts's own comma-joined list fields) and "the set
  # the tally paragraph's prose enumerates" (from extract_criteria_numbers)
  # are put in before either a plain string-equality comparison (the
  # `observed` parenthetical) or a per-element containment check (the
  # `manual` span, see set_subset_violations() below), so neither order
  # nor an incidental repeated mention (e.g. "criterion 10" named both in
  # the main manual list and again inside its own parenthetical aside)
  # changes the result. "-" (this file's own empty-list sentinel,
  # elsewhere turned into "" by csv_to_display) is treated as empty here
  # too, so a genuinely empty set on either side of a comparison reads as
  # "" on both sides, never as the literal string "-".
  val=$1
  if [ "$val" = "-" ]; then
    val=""
  fi
  # Two SEPARATE single-character `tr` calls (comma -> newline, then
  # space -> newline), not one `tr ', ' '\n\n'` call — shellcheck's SC2020
  # correctly flags a single `tr` invocation whose second character set
  # repeats a character as likely not doing what it looks like it does;
  # two single-char-to-single-char calls says the same thing unambiguously
  # and needs no override.
  printf '%s' "$val" | tr ',' '\n' | tr ' ' '\n' | grep -v '^$' | sort -n | uniq | tr '\n' ' ' | sed 's/ *$//'
}

set_subset_violations() {
  # set_subset_violations <candidate-set> <superset> - FIX 2 (cycle 3).
  # Both arguments are sorted_unique_set()'s own output shape (numbers,
  # sorted, deduplicated, space-joined, "" if empty). Returns every number
  # in <candidate-set> that does NOT appear in <superset>, same shape, ""
  # if there are none - i.e. "" means <candidate-set> is fully CONTAINED
  # in <superset>. Deliberately NOT set equality: the caller (the
  # `manual`-span check, below) needs "every number the tally paragraph's
  # manual prose enumerates is genuinely `manual`," not "the tally
  # paragraph's prose enumerates every `manual` criterion" - see
  # extract_manual_number_set()'s own header comment for why the second
  # half of that would reject legitimate reworded prose. An empty
  # <candidate-set> vacuously returns "" (nothing to violate), which is
  # exactly right for a rewording that legitimately extracts fewer numbers
  # than the true full set, e.g. "6 through 9" collapsing four numbers
  # into a range no regex here expands - see the FAILURE PROOF and
  # LEGITIMATE REWORDING assertions below for the empirical proof of both
  # directions.
  candidate=$1
  superset=$2
  bad=""
  for n in $candidate; do
    found=no
    for m in $superset; do
      if [ "$n" = "$m" ]; then
        found=yes
        break
      fi
    done
    if [ "$found" = no ]; then
      if [ -z "$bad" ]; then
        bad=$n
      else
        bad="$bad $n"
      fi
    fi
  done
  printf '%s' "$bad"
}

extract_observed_number_set() {
  # extract_observed_number_set <flattened-tally-text> - FIX 2. The set of
  # criterion numbers enumerated inside the "(criteria ...)" parenthetical
  # of the tally paragraph's own "N (criteria ...) are `observed`" clause —
  # a clean, machine-shaped list, isolated by reusing the EXACT anchor
  # regex the leading-count extraction (tally_observed15, above) already
  # relies on, so the two never drift out of lock-step with each other.
  # Narrowed to just the parenthetical's own contents (via the second
  # grep, on "(...)") before running extract_criteria_numbers, so the
  # leading count digit itself (e.g. the "4" in "4 (criteria 4, 5, 11,
  # 14)") is never swept in as if it were one more enumerated criterion.
  # [FIX 3] `|| true` on the assignment: unlike every other extraction in
  # this invariant, the LAST stage of this pipeline is itself a `grep`
  # (the "(...)" one) - if the anchor phrase ahead of it does not match at
  # all, that final grep receives empty input and exits 1 as the whole
  # pipeline's own exit status. Under `set -eu`, an unguarded failure
  # inside a `var=$(...)` assignment aborts the ENTIRE script right here,
  # skipping every remaining assertion in this file, not just this one
  # check - the identical hazard get_tally_paragraph() and
  # count_status_lines() (both above) already guard against with the same
  # `|| true`. Without this, "sanity (invariant 15, Fix 2): the tally
  # paragraph's `observed` parenthetical must actually yield at least one
  # criterion number" (below) would never even get the chance to fail by
  # name - the run would already be dead.
  # shellcheck disable=SC2016 # single-quoted deliberately: literal
  # backtick-quoted status word, not substitution.
  paren=$(printf '%s\n' "$1" | grep -oE '[0-9]+ \(criteria[^)]*\) are `observed`' | head -n 1 | grep -oE '\([^)]*\)' || true)
  sorted_unique_set "$(extract_criteria_numbers "$paren")"
}

extract_manual_number_set() {
  # extract_manual_number_set <flattened-tally-text> - FIX 2. The set of
  # criterion numbers enumerated in the tally paragraph's "manual" span:
  # from (and including) the FIRST match of "N remain `manual`" through
  # the end of this SAME text. Because get_tally_paragraph flattens per
  # PARAGRAPH (never joining two different paragraphs — see
  # flatten_acceptance_section's own header), "end of this text" is "end
  # of the tally paragraph," never spilling into an unrelated paragraph
  # elsewhere in the document.
  #
  # Deliberately NOT bounded to one sentence. The real manual discussion
  # spans several sentences — a main list, a per-branch aside for
  # criterion 10, a cross-reference to "criterion 10's own section," the
  # history of criterion 12's two moves, a closing note on criterion 7 —
  # and bounding to one sentence would reject a legitimate future
  # re-sentencing of the identical true facts (splitting the semicolon-
  # joined list into several short sentences, for instance) purely because
  # it changed shape, not because any number became wrong. That is exactly
  # the "guard that blocks correct work" trap named in this build's own
  # history.
  #
  # CYCLE 3 CORRECTION: the caller no longer compares this function's
  # output against the real `manual` set for EQUALITY. It checks
  # CONTAINMENT instead, via set_subset_violations() (above): every number
  # this function extracts must genuinely be `manual`; the real `manual`
  # set is no longer required to appear here IN FULL. Cycle 2 shipped
  # equality, which the review reproduced as rejecting two legitimate
  # rewordings ("criteria 3 and 6 through 9, plus 13, in full" and a
  # semicolon restructure) that state the identical true facts but cause
  # this function's own regex to extract fewer numbers than the full set —
  # a guard that blocks correct work. Containment tolerates that
  # under-extraction on purpose: see set_subset_violations()'s own header
  # comment, and the FAILURE PROOF / LEGITIMATE REWORDING assertions below,
  # for the mutation-proved boundary.
  #
  # THE RESIDUAL RISK THIS ACCEPTS, STATED PLAINLY, UNCHANGED BY THAT
  # CORRECTION: an incidental mention of a NON-manual criterion appearing
  # anywhere after the anchor, still inside this same paragraph, would be
  # swept into the set too and would then legitimately fail the
  # containment check in compute_status_and_counts's caller — a loud
  # false positive that NAMES the offending number directly (via
  # set_subset_violations()'s own return value), not a silent miss, and
  # not the same "compare two whole strings and spot the diff yourself"
  # experience equality gave. Today's real text has no such stray mention
  # after the anchor (verified against the CURRENT document, v0.3.1: the
  # numbers named after "N remain `manual`" are 6, 8, 9, 10, 12 and 13,
  # every one of them genuinely `manual`. The list this comment carried
  # before — 3, 6, 7, 8, 9, 13, 10, 12 — described the PREVIOUS document,
  # in which 3 and 7 were still `manual`; both have since moved to
  # `observed` and both dropped out of this span, which is why the
  # containment check did not start firing when they moved), so this does
  # not fire against the shipped
  # document; a future edit that introduces one would need to either fix
  # the wrong reference or move the anchor/comment deliberately, exactly
  # the same remedy this file's header already prescribes for the
  # narrower anchor-phrase-rewording case.
  # shellcheck disable=SC2016 # single-quoted deliberately: literal
  # backtick-quoted status word, not substitution.
  span=$(printf '%s\n' "$1" | grep -oE '[0-9]+ remain `manual`.*$' | head -n 1)
  sorted_unique_set "$(extract_criteria_numbers "$span")"
}

mutate_criterion_status_line() {
  # mutate_criterion_status_line <content> <n> <new-status-line> -
  # <content> with criterion <n>'s own FIRST "**Status:**" line replaced,
  # verbatim, by <new-status-line>. Scoped by POSITION (inside criterion
  # <n>'s own "## <n>. " ... "## " boundary), never by matching the old
  # line's text — several criteria below share the byte-identical status
  # line "**Status:** `met`.", so a text-content-based replace would hit
  # every one of them instead of just the intended criterion.
  content=$1
  n=$2
  new_line=$3
  printf '%s\n' "$content" | awk -v want="$n" -v newline="$new_line" '
    BEGIN { insec = 0; done = 0 }
    $0 ~ ("^## " want "\\. ") { insec = 1; print; next }
    insec && /^## / { insec = 0 }
    insec && /^\*\*Status:\*\*/ && !done { print newline; done = 1; next }
    { print }
  '
}

duplicate_status_line_after() {
  # duplicate_status_line_after <content> <n> <extra-status-line> -
  # <content> with a SECOND "**Status:**" line (<extra-status-line>)
  # inserted immediately AFTER criterion <n>'s own real, first one, still
  # inside that criterion's own section. Scoped by POSITION exactly like
  # mutate_criterion_status_line above, for the same reason (shared status
  # line text across criteria). Models Fix 1's exact defect class: a
  # duplicate placed AFTER the canonical line is invisible to
  # extract_status_word()'s `head -n 1`, which still returns the correct,
  # first line — so the criterion's own Status line and its summary-table
  # row still agree, and 15a's cross-check does not fire. Only
  # count_status_lines() (now 2, not 1) can see this.
  content=$1
  n=$2
  extra_line=$3
  printf '%s\n' "$content" | awk -v want="$n" -v extra="$extra_line" '
    BEGIN { insec = 0; done = 0 }
    $0 ~ ("^## " want "\\. ") { insec = 1; print; next }
    insec && /^## / { insec = 0 }
    insec && /^\*\*Status:\*\*/ && !done { print; print extra; done = 1; next }
    { print }
  '
}

mutate_first_literal() {
  # mutate_first_literal <content> <old> <new> - <content> with the FIRST
  # occurrence of the literal string <old> replaced by <new>. Uses awk's
  # index()/substr() rather than sed, so <old>/<new> need no regex-
  # special-character escaping — the phrases this invariant mutates
  # contain backticks and parentheses verbatim.
  content=$1
  old=$2
  new=$3
  printf '%s' "$content" | awk -v old="$old" -v new="$new" '
    BEGIN { done = 0 }
    {
      if (!done) {
        i = index($0, old)
        if (i > 0) {
          $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
          done = 1
        }
      }
      print
    }
  '
}

compute_status_and_counts() {
  # compute_status_and_counts <content> - runs the full per-criterion scan
  # (own Status line vs. summary-table row, tallying each status word, and
  # counting how many "**Status:**" lines each criterion's section actually
  # has) over <content> and prints exactly ONE line of 10 space-separated
  # fields:
  #   mismatched-criteria(comma-joined, or "-" if none) met observed
  #   manual not-met status-lines-found table-rows-found
  #   bad-status-line-count-criteria(comma-joined, or "-" if none)
  #   observed-criteria(comma-joined, or "-" if none)
  #   manual-criteria(comma-joined, or "-" if none)
  # A single-line, fixed-field-count output — rather than one shell
  # variable per call site — is what lets the FAILURE PROOFS below re-run
  # this exact logic against an in-memory MUTATED copy of the document
  # without duplicating the scan. Every comma-joined list uses "-" (never
  # empty string) when it has no members, specifically so the fixed-field
  # IFS-space split at every call site below never silently collapses a
  # missing field into its neighbour.
  #
  # FIX 1 (bad-status-line-count-criteria): a criterion whose section
  # contains anything other than exactly one "**Status:**" line is flagged
  # here regardless of what extract_status_word() returns for it - this is
  # the check that can see a duplicated, AFTER-the-real-one contradicting
  # Status line, which extract_status_word()'s first-match-only design and
  # the mismatch check built on it (15a, below) structurally cannot.
  #
  # FIX 2 (observed-criteria / manual-criteria): the actual set of
  # criterion numbers holding each status, derived the same way the counts
  # already were - so a call site can compare this REAL set against the
  # set the tally paragraph's own prose ENUMERATES, not just compare counts.
  content=$1
  c_met=0
  c_observed=0
  c_manual=0
  c_notmet=0
  c_status_found=0
  c_table_found=0
  c_mismatched=""
  c_badcount=""
  c_observed_list=""
  c_manual_list=""
  cn=1
  while [ "$cn" -le 22 ]; do
    csec=$(get_acceptance_section "$content" "$cn")
    cstatus=$(extract_status_word "$csec")
    cstatus_lines=$(count_status_lines "$csec")
    if [ -n "$cstatus" ]; then
      c_status_found=$((c_status_found + 1))
    fi
    case "$cstatus" in
      met) c_met=$((c_met + 1)) ;;
      observed)
        c_observed=$((c_observed + 1))
        if [ -z "$c_observed_list" ]; then
          c_observed_list=$cn
        else
          c_observed_list="$c_observed_list,$cn"
        fi
        ;;
      manual)
        c_manual=$((c_manual + 1))
        if [ -z "$c_manual_list" ]; then
          c_manual_list=$cn
        else
          c_manual_list="$c_manual_list,$cn"
        fi
        ;;
      "not met") c_notmet=$((c_notmet + 1)) ;;
    esac

    ctable_line=$(get_summary_table_line "$content" "$cn")
    ctable_status=$(extract_table_status "$ctable_line")
    if [ -n "$ctable_status" ]; then
      c_table_found=$((c_table_found + 1))
    fi

    if [ "$cstatus" != "$ctable_status" ]; then
      if [ -z "$c_mismatched" ]; then
        c_mismatched=$cn
      else
        c_mismatched="$c_mismatched,$cn"
      fi
    fi

    if [ "$cstatus_lines" -ne 1 ]; then
      if [ -z "$c_badcount" ]; then
        c_badcount=$cn
      else
        c_badcount="$c_badcount,$cn"
      fi
    fi

    cn=$((cn + 1))
  done
  if [ -z "$c_mismatched" ]; then
    c_mismatched="-"
  fi
  if [ -z "$c_badcount" ]; then
    c_badcount="-"
  fi
  if [ -z "$c_observed_list" ]; then
    c_observed_list="-"
  fi
  if [ -z "$c_manual_list" ]; then
    c_manual_list="-"
  fi
  printf '%s %s %s %s %s %s %s %s %s %s\n' "$c_mismatched" "$c_met" "$c_observed" "$c_manual" "$c_notmet" "$c_status_found" "$c_table_found" "$c_badcount" "$c_observed_list" "$c_manual_list"
}

csv_to_display() {
  # csv_to_display <csv-or-dash> - "-" becomes "" (no mismatches); any
  # other value has its commas turned into spaces, matching the "" ==
  # empty / "N M ..." == a list convention assert_eq is used with
  # elsewhere in this file.
  if [ "$1" = "-" ]; then
    printf ''
  else
    printf '%s' "$1" | tr ',' ' '
  fi
}

# --- The real-repo run -----------------------------------------------
result15=$(compute_status_and_counts "$acceptance_content")
old_ifs=$IFS
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting: $result15 is
# compute_status_and_counts's own fixed-format, single-line, 10-field
# output with no embedded IFS characters (every comma-joined list field
# uses "-" for "no members" rather than an empty string, precisely so this
# splits into exactly 10 words every time, never fewer).
set -- $result15
IFS=$old_ifs
s15_mismatched=$1
s15_met=$2
s15_observed=$3
s15_manual=$4
s15_notmet=$5
s15_status_found=$6
s15_table_found=$7
s15_badcount=$8
s15_observed_list=$9
s15_manual_list=${10}

assert_eq "" "$(csv_to_display "$s15_mismatched")" "every docs/ACCEPTANCE.md criterion's own **Status:** line must state the same status word as its row in the ## Summary table (invariant 15a)"

# FIX 1. Every criterion's section must have EXACTLY ONE "**Status:**"
# line - zero (missing) and two-or-more (duplicated, whether or not the
# duplicate contradicts the real one) are both defects. This is a
# DIFFERENT check from 15a immediately above: 15a compares the FIRST status
# line extract_status_word() finds against the summary-table row, so a
# duplicate placed AFTER the real, correct line is invisible to it (the
# first-found word is still the correct one, so 15a's own comparison still
# agrees) - see the FAILURE PROOF below for the live demonstration.
assert_eq "" "$(csv_to_display "$s15_badcount")" "every docs/ACCEPTANCE.md criterion's section must contain exactly one \`**Status:**\` line - neither zero nor two-or-more (invariant 15, Fix 1)"

# Sanity, per the tech lead's own instruction: prove the parser actually
# found all 22 criteria and all 22 table rows, so a regex matching nothing
# could not make the assertion above pass trivially.
assert_eq "22" "$s15_status_found" "sanity (invariant 15): a **Status:** line must be found for all 22 criteria, or the agreement check above would be vacuous"
assert_eq "22" "$s15_table_found" "sanity (invariant 15): a ## Summary table row must be found for all 22 criterion numbers, or the agreement check above would be vacuous"
assert_eq "22" "$((s15_met + s15_observed + s15_manual + s15_notmet))" "sanity (invariant 15): every one of the 22 criteria's own Status line must resolve to exactly one of met/observed/manual/not met, with none left unrecognized"

tally_flat15=$(get_tally_paragraph "$acceptance_content")
tally_paragraphs_found15=$(printf '%s\n' "$tally_flat15" | grep -c '.' || true)
assert_eq "1" "$tally_paragraphs_found15" "sanity (invariant 15): exactly one paragraph containing 'of 22 criteria' must be found inside the ## Summary table section, or the tally-count extraction below is not testing anything real"

# shellcheck disable=SC2016 # single-quoted deliberately, all three below:
# literal backtick-quoted status words in the -E patterns, never substitution.
tally_met15=$(printf '%s\n' "$tally_flat15" | grep -oE '[0-9]+ of 22 criteria are `met`' | head -n 1 | awk '{print $1}')
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
tally_observed15=$(printf '%s\n' "$tally_flat15" | grep -oE '[0-9]+ \(criteria[^)]*\) are `observed`' | head -n 1 | awk '{print $1}')
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
tally_manual15=$(printf '%s\n' "$tally_flat15" | grep -oE '[0-9]+ remain `manual`' | head -n 1 | awk '{print $1}')

assert_eq "$s15_met" "$tally_met15" "the tally paragraph's met-count must equal the actual number of criteria whose own Status line says \`met\` (invariant 15b)"
assert_eq "$s15_observed" "$tally_observed15" "the tally paragraph's observed-count must equal the actual number of criteria whose own Status line says \`observed\` (invariant 15b)"
assert_eq "$s15_manual" "$tally_manual15" "the tally paragraph's manual-count must equal the actual number of criteria whose own Status line says \`manual\` (invariant 15b)"

# FIX 2. 15b above only ever compared COUNTS. It cannot see a false
# ENUMERATION that keeps the count correct — the tech lead's own
# reproduction: rewriting the observed clause to name criterion 16 (which
# is `met`) instead of 14, while leaving the leading count at "4", passes
# 15b outright. Compare the actual SET of criterion numbers holding each
# status against the SET the tally paragraph's own prose enumerates for
# it, not just how many — but the TWO spans are checked with DIFFERENT
# comparisons, deliberately (cycle 3 correction; cycle 2 shipped equality
# for both):
#   - `observed` (below): SET EQUALITY. The parenthetical is a clean,
#     machine-shaped list ("N (criteria a, b, c, d) are `observed`") and
#     equality costs nothing there.
#   - `manual` (below): CONTAINMENT, via set_subset_violations() (defined
#     above, near sorted_unique_set()). The real manual discussion is
#     free-form prose spread across several sentences, and a review-
#     reproduced defect showed equality rejects legitimate rewordings of
#     it ("6 through 9" instead of spelling out every number; a semicolon
#     restructure) purely because they extract a SUBSET of the true set,
#     not because any number is wrong. Containment only requires that
#     whatever IS extracted be genuinely `manual` — see
#     extract_manual_number_set()'s and set_subset_violations()'s own
#     header comments for the full reasoning, and the FAILURE PROOF /
#     LEGITIMATE REWORDING assertions below for the mutation-proved
#     boundary of what this still catches and what it, by design, does
#     not.
s15_observed_set=$(sorted_unique_set "$s15_observed_list")
s15_manual_set=$(sorted_unique_set "$s15_manual_list")
tally_observed_set15=$(extract_observed_number_set "$tally_flat15")
tally_manual_set15=$(extract_manual_number_set "$tally_flat15")

# Sanity: neither extraction above may be vacuous, or a broken anchor
# comparing "" == "" would pass the enumeration checks below without
# testing anything real (the identical hazard get_tally_paragraph's own
# comment already names for the count extraction, applying here too).
assert_eq "yes" "$([ -n "$tally_observed_set15" ] && echo yes || echo no)" "sanity (invariant 15, Fix 2): the tally paragraph's \`observed\` parenthetical must actually yield at least one criterion number"
assert_eq "yes" "$([ -n "$tally_manual_set15" ] && echo yes || echo no)" "sanity (invariant 15, Fix 2): the tally paragraph's \`manual\` span must actually yield at least one criterion number"

assert_eq "$s15_observed_set" "$tally_observed_set15" "the tally paragraph's \`observed\` parenthetical must enumerate EXACTLY the criteria whose own Status line says \`observed\` — the same set, not merely the same count (invariant 15, Fix 2)"

tally_manual_violations15=$(set_subset_violations "$tally_manual_set15" "$s15_manual_set")
assert_eq "" "$tally_manual_violations15" "every criterion number the tally paragraph's \`manual\` span enumerates must genuinely hold \`manual\` status — CONTAINMENT, not set equality (invariant 15, Fix 2 cycle 3): the manual span is not required to name every \`manual\` criterion, only to never misname one that is not"

# ==========================================================================
# FAILURE PROOF (invariant 15, mutation 1) — flip ONE summary-table cell to
# a DIFFERENT status, leaving that criterion's own Status line untouched.
# Criterion 4's real row ends "| observed |"; mutated to "| manual |" here,
# in-memory only, never touching the tracked file.
# ==========================================================================
row15_4=$(get_summary_table_line "$acceptance_content" "4")
assert_eq "yes" "$([ -n "$row15_4" ] && echo yes || echo no)" "sanity (invariant 15, mutation 1): criterion 4's real summary-table row must actually be found, or this mutation proof is not well-defined"

mutated_row15_4=$(mutate_table_status "$row15_4" "manual")
mutant15_table=$(printf '%s\n' "$acceptance_content" | awk -v old="$row15_4" -v new="$mutated_row15_4" '{ if ($0 == old) { print new } else { print } }')


# `case`, not a `printf ... | grep -qF` pipe: the same pipe-race the
# invariant-13 anchor check above avoids (a grep that can exit the instant
# it finds a match can race a still-writing printf on a several-thousand-
# line variable into a harmless but noisy SIGPIPE/"Broken pipe" message —
# a pure shell `case` test has no subprocess pipe to race at all).
mutant15_old_row_present=no
case "$mutant15_table" in
  *"$row15_4"*) mutant15_old_row_present=yes ;;
esac
mutant15_new_row_present=no
case "$mutant15_table" in
  *"$mutated_row15_4"*) mutant15_new_row_present=yes ;;
esac
if [ "$mutant15_old_row_present" = no ] && [ "$mutant15_new_row_present" = yes ]; then
  mutant15_table_changed=yes
else
  mutant15_table_changed=no
fi
assert_eq "yes" "$mutant15_table_changed" "sanity (invariant 15, mutation 1): the table-cell mutation must actually replace criterion 4's real row with a genuinely different one"

result15_p1=$(compute_status_and_counts "$mutant15_table")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_p1
IFS=$old_ifs
p1_mismatched=$1
assert_eq "4" "$(csv_to_display "$p1_mismatched")" "FAILURE PROOF (invariant 15, mutation 1): flipping ONLY criterion 4's summary-table Status cell from \`observed\` to \`manual\` (its own Status line left at \`observed\`) must be caught, naming criterion 4 and nothing else"

# ==========================================================================
# FAILURE PROOF (invariant 15, mutation 2) — flip ONE criterion's own
# **Status:** line to a DIFFERENT status, leaving its summary-table row
# untouched. Targets criterion 15 (`met`, mutated to `manual`) specifically
# BECAUSE several other criteria (1, 2, 16, 17, 18, 19) share the
# byte-identical status line "**Status:** `met`." — proving the mutation
# is scoped by SECTION POSITION, not by matching that shared text, is part
# of this proof, not an assumption.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status line text, not substitution.
mutant15_section=$(mutate_criterion_status_line "$acceptance_content" "15" '**Status:** `manual`.')

sanity_sec15=$(get_acceptance_section "$mutant15_section" "15")
sanity_status15=$(extract_status_word "$sanity_sec15")
assert_eq "manual" "$sanity_status15" "sanity (invariant 15, mutation 2): the section-status mutation must actually change criterion 15's own Status line to \`manual\`"

siblings_ok15=yes
for sib15 in 1 2 16 17 18 19; do
  sib_sec15=$(get_acceptance_section "$mutant15_section" "$sib15")
  sib_status15=$(extract_status_word "$sib_sec15")
  if [ "$sib_status15" != "met" ]; then
    siblings_ok15=no
  fi
done
assert_eq "yes" "$siblings_ok15" "sanity (invariant 15, mutation 2): mutating ONLY criterion 15's status line must leave every sibling \`met\` criterion (1, 2, 16, 17, 18, 19) untouched — proving the mutation is scoped by section position, not by matching text content those criteria happen to share"

result15_p2=$(compute_status_and_counts "$mutant15_section")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_p2
IFS=$old_ifs
p2_mismatched=$1
assert_eq "15" "$(csv_to_display "$p2_mismatched")" "FAILURE PROOF (invariant 15, mutation 2): flipping ONLY criterion 15's own **Status:** line from \`met\` to \`manual\` (its summary-table row left at \`met\`) must be caught, naming criterion 15 and nothing else"

# ==========================================================================
# FAILURE PROOF (invariant 15, mutation 3) — change ONE number in the
# tally paragraph, leaving every criterion's actual status untouched.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately, both below: literal backtick-quoted phrases, not substitution.
tally_old_met_phrase='7 of 22 criteria are `met`'
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted phrase, not substitution.
tally_new_met_phrase='6 of 22 criteria are `met`'

tally_anchor_hits15=$(printf '%s' "$acceptance_content" | grep -oF -- "$tally_old_met_phrase" | wc -l | tr -d ' ')
assert_eq "1" "$tally_anchor_hits15" "sanity (invariant 15, mutation 3): the tally paragraph's met-count phrase must appear exactly once in the real file, or this mutation proof is not well-defined"

mutant15_tally=$(mutate_first_literal "$acceptance_content" "$tally_old_met_phrase" "$tally_new_met_phrase")

mutant15_tally_flat=$(get_tally_paragraph "$mutant15_tally")
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
mutant15_tally_met=$(printf '%s\n' "$mutant15_tally_flat" | grep -oE '[0-9]+ of 22 criteria are `met`' | head -n 1 | awk '{print $1}')
assert_eq "6" "$mutant15_tally_met" "sanity (invariant 15, mutation 3): the mutated tally paragraph must now read a met-count of 6, or the mutation did not apply"

result15_p3=$(compute_status_and_counts "$mutant15_tally")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_p3
IFS=$old_ifs
p3_met=$2
p3_mismatch_yesno=$([ "$p3_met" = "$mutant15_tally_met" ] && echo yes || echo no)
assert_eq "no" "$p3_mismatch_yesno" "FAILURE PROOF (invariant 15, mutation 3): changing ONLY the tally paragraph's met-count number (every criterion's actual status left untouched) must be caught — the real met-count must no longer equal the mutated tally's stated met-count"

# ==========================================================================
# FAILURE PROOF (invariant 15, sanity) — the "found all 22" guards above
# are not vacuous always-22 assertions: deleting a table row, or deleting a
# Status line, actually drops the corresponding found-count below 22.
# ==========================================================================
mutant15_missing_row=$(printf '%s\n' "$acceptance_content" | awk -v old="$row15_4" 'BEGIN { skipped = 0 } { if (!skipped && $0 == old) { skipped = 1; next } print }')
result15_p4=$(compute_status_and_counts "$mutant15_missing_row")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_p4
IFS=$old_ifs
p4_table_found=$7
assert_eq "21" "$p4_table_found" "FAILURE PROOF (invariant 15, sanity): deleting criterion 4's summary-table row entirely must drop the found-row count to 21, proving the 'found all 22 table rows' sanity check is not a vacuous always-22 assertion"

mutant15_missing_status=$(printf '%s\n' "$acceptance_content" | awk '
  BEGIN { insec = 0; removed = 0 }
  $0 ~ "^## 15\\. " { insec = 1; print; next }
  insec && /^## / { insec = 0 }
  insec && /^\*\*Status:\*\*/ && !removed { removed = 1; next }
  { print }
')
result15_p5=$(compute_status_and_counts "$mutant15_missing_status")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_p5
IFS=$old_ifs
p5_status_found=$6
assert_eq "21" "$p5_status_found" "FAILURE PROOF (invariant 15, sanity): deleting criterion 15's own **Status:** line entirely must drop the found-status-lines count to 21, proving the 'found all 22 criteria' sanity check is not a vacuous always-22 assertion"

# ==========================================================================
# FAILURE PROOF (invariant 15, Fix 1, AFTER-duplicate direction) — insert a
# SECOND, CONTRADICTING "**Status:**" line immediately AFTER criterion 6's
# own real one, leaving the real line itself untouched. The BEFORE-duplicate
# direction (a contradicting duplicate placed BEFORE the real line) is
# already implicitly covered by 15a above: extract_status_word()'s
# `head -n 1` would then return the duplicate's (wrong) word first, which
# disagrees with the summary-table row and trips 15a on its own — proving
# only that direction would be exactly the "guard that could not fail for
# its own target" trap this build has hit repeatedly. This proof targets
# the direction 15a structurally cannot see.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# backtick-quoted status line text, not substitution.
mutant15_dup=$(duplicate_status_line_after "$acceptance_content" "6" '**Status:** `met`.')

sanity_dupsec15=$(get_acceptance_section "$mutant15_dup" "6")
sanity_dupcount15=$(count_status_lines "$sanity_dupsec15")
assert_eq "2" "$sanity_dupcount15" "sanity (invariant 15, Fix 1 proof): the after-duplicate mutation must actually leave criterion 6's section with TWO \`**Status:**\` lines, or this proof is not well-defined"

sanity_dupword15=$(extract_status_word "$sanity_dupsec15")
assert_eq "manual" "$sanity_dupword15" "sanity (invariant 15, Fix 1 proof): extract_status_word()'s head -n 1 must still return criterion 6's REAL, first word (\`manual\`) unchanged, not the appended duplicate's (\`met\`) — this is exactly why 15a's own mismatch check cannot see this direction at all"

result15_dup=$(compute_status_and_counts "$mutant15_dup")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_dup
IFS=$old_ifs
dup_mismatched=$1
dup_badcount=$8
assert_eq "" "$(csv_to_display "$dup_mismatched")" "DEMONSTRATION (invariant 15, Fix 1 proof): 15a's own mismatch check (unchanged) must stay CLEAN against the after-duplicate mutation — proving this specific defect class was invisible to it before Fix 1 existed"
assert_eq "6" "$(csv_to_display "$dup_badcount")" "FAILURE PROOF (invariant 15, Fix 1): a SECOND, contradicting \`**Status:**\` line placed AFTER criterion 6's real one must be caught by the new status-line-count check, naming criterion 6 and nothing else, even though 15a's mismatch check (immediately above) sees nothing wrong at all"

# ==========================================================================
# FAILURE PROOF (invariant 15, Fix 1, leading-whitespace duplicate) — the
# review's exact reproduction: a duplicate, contradicting "**Status:**"
# line indented by a SINGLE LEADING SPACE, placed AFTER criterion 9's own
# real one. Before this fix, the literal anchor "^\*\*Status:\*\*" would
# not match the indented line at all - invisible to count_status_lines()
# too, not just to extract_status_word() - unlike the flush-left duplicate
# proof immediately above (which was already visible to
# count_status_lines() even before Fix 1; that proof exists to demonstrate
# 15a's blind spot, not this one). Targets criterion 9, distinct from
# criterion 6 above, so this cannot be mistaken for re-running the same
# case.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# backtick-quoted status line text, not substitution.
mutant15_wsdup=$(duplicate_status_line_after "$acceptance_content" "9" ' **Status:** `met`.')

sanity_wsdupsec15=$(get_acceptance_section "$mutant15_wsdup" "9")
sanity_wsdupcount15=$(count_status_lines "$sanity_wsdupsec15")
assert_eq "2" "$sanity_wsdupcount15" "sanity (invariant 15, Fix 1 leading-whitespace proof): the indented-duplicate mutation must actually leave criterion 9's section with TWO \`**Status:**\` lines (one flush-left, one indented by one space), or this proof is not well-defined"

result15_wsdup=$(compute_status_and_counts "$mutant15_wsdup")
IFS=' '
# shellcheck disable=SC2086 # deliberate word-splitting, see the real-run comment above.
set -- $result15_wsdup
IFS=$old_ifs
wsdup_badcount=$8
assert_eq "9" "$(csv_to_display "$wsdup_badcount")" "FAILURE PROOF (invariant 15, Fix 1, leading whitespace): a SECOND, contradicting \`**Status:**\` line indented by ONE LEADING SPACE, placed after criterion 9's real one, must be caught by the status-line-count check, naming criterion 9 and nothing else - before this fix, the literal \`^\*\*Status:\*\*\` anchor would not match the indented line at all, and this exact mutation would have passed silently"

# ==========================================================================
# FAILURE PROOF (invariant 15, extract_status_word()'s OWN leading-
# whitespace tolerance, isolated from count_status_lines()) — every proof
# above this line that exercises [FIX 1]'s leading-whitespace tolerance
# does so through a DUPLICATE line, and a duplicate changes the section's
# "**Status:**"-line COUNT before it changes what gets EXTRACTED, so every
# one of those proofs is, structurally, a count_status_lines() proof:
# extract_status_word()'s own copy of the identical tolerant anchor
# (both its grep AND its sed pattern) never has to fire to make any of
# them go red. This proof targets criterion 17's SOLE, real "**Status:**"
# line instead — indented by ONE LEADING SPACE, nothing else changed, no
# duplicate introduced. The line count stays exactly 1 either way, so
# count_status_lines() has nothing to report; only extract_status_word()
# decides whether the status word is still read at all.
# A/B-verified in a scratch copy (never the tracked file): with
# extract_status_word()'s anchors as shipped (tolerant), the second
# assertion below is green, reading `met`; reverting BOTH its grep and its
# sed pattern to the literal, unindented `^\*\*Status:\*\*` turns that same
# assertion red (empty, not `met`) while every other assertion in this
# file — including count_status_lines()'s own leading-whitespace proof
# immediately above — stays green.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# backtick-quoted status line text, not substitution.
mutant15_indented=$(mutate_criterion_status_line "$acceptance_content" "17" ' **Status:** `met`.')

sanity_indsec15=$(get_acceptance_section "$mutant15_indented" "17")
sanity_indcount15=$(count_status_lines "$sanity_indsec15")
assert_eq "1" "$sanity_indcount15" "sanity (invariant 15, extract_status_word FAILURE PROOF): indenting criterion 17's SOLE **Status:** line by one leading space, changing nothing else, must leave count_status_lines() reporting exactly 1 - proving this proof is invisible to Fix 1's line-count check and isolates extract_status_word() as the only function whose own anchor can decide the outcome below"

sanity_indword15=$(extract_status_word "$sanity_indsec15")
assert_eq "met" "$sanity_indword15" "FAILURE PROOF (invariant 15, extract_status_word()'s own leading-whitespace tolerance): criterion 17's real, sole \`**Status:**\` line, indented by ONE LEADING SPACE and otherwise byte-identical, must still be read as \`met\` by extract_status_word() itself - unlike every leading-whitespace proof above it, this one depends on extract_status_word()'s OWN anchor tolerance, not count_status_lines()'s (see this block's own header comment for the A/B: reverting extract_status_word()'s grep and sed anchors to the literal, unindented form in a scratch copy turns this exact assertion red)"

# ==========================================================================
# FAILURE PROOF (invariant 15, Fix 2, `observed`) — the tech lead's exact
# reproduction: rewrite the parenthetical to name a WRONG criterion (16,
# which is `met`) in place of a real one (14), leaving the leading count
# untouched so 15b's count-only check stays green. All four mutations
# below run against $tally_flat15 (the ALREADY-FLATTENED tally text, the
# exact input extract_observed_number_set()/extract_manual_number_set()
# themselves consume) rather than against the raw, multi-line
# $acceptance_content — the real document hard-wraps the tally paragraph
# at whatever column the prose happens to reach (see the tally paragraph
# near the end of docs/ACCEPTANCE.md, in the "Summary" section, whose
# `observed` clause currently breaks mid-sentence immediately after the
# parenthetical), and pinning a literal string to an incidental wrap
# point would make this proof brittle to the next unrelated re-wrap,
# exactly the fragility this build's own history warns against. Testing
# at the flattened-text level still exercises the real functions under
# test end-to-end; get_tally_paragraph()/flatten_acceptance_section()'s
# own line-join behavior is separately proved elsewhere (invariant 13's
# mutation proofs, and this invariant's own mutation 3 above).
#
# RE-PINNED (v0.3.1): every literal below quoted the PREVIOUS tally text
# and rotted the moment docs/ACCEPTANCE.md's statuses and tally were
# rewritten - 13 assertions went red while every real check (15a's
# section-vs-table agreement, 15b's counts, the `observed` set equality,
# the `manual` containment, invariants 12/13, the glossary scans) stayed
# green. That split is the point, and it is exactly what this fixture's
# own comment predicts: the rot was confined to the mutation fixtures'
# hardcoded anchors, which by construction must quote the document
# verbatim to mutate it, and never reached anything that checks the
# document's actual truth. The literals are re-derived from the current
# document below; the fixture's SHAPE - what each mutation does and why -
# is unchanged, and each one is re-verified to still fail for its own
# original reason rather than merely to parse.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately, both below:
# literal backtick-quoted phrases, not substitution.
tally_old_observed_phrase='9 (criteria 3, 4, 5, 7, 11, 14, 20, 21, 22) are `observed`'
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted phrase, not substitution.
tally_falseenum_observed_phrase='9 (criteria 3, 4, 5, 7, 11, 16, 20, 21, 22) are `observed`'

tally_observed_anchor_hits15=$(printf '%s' "$tally_flat15" | grep -oF -- "$tally_old_observed_phrase" | wc -l | tr -d ' ')
assert_eq "1" "$tally_observed_anchor_hits15" "sanity (invariant 15, Fix 2 proof, observed): the tally paragraph's observed clause must appear exactly once in the flattened tally text, or this mutation proof is not well-defined"

mutant15_falseenum_observed_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_observed_phrase" "$tally_falseenum_observed_phrase")
mutant15_falseenum_observed_changed=$([ "$mutant15_falseenum_observed_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_falseenum_observed_changed" "sanity (invariant 15, Fix 2 proof, observed): the false-enumeration mutation must actually change the flattened tally text, or this proof is not well-defined"

# 15b (count-only) must NOT catch this — the count is still "9" — proving
# the gap Fix 2 exists to close, not merely re-demonstrating 15b.
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
mutant15_falseenum_observed_count=$(printf '%s\n' "$mutant15_falseenum_observed_flat" | grep -oE '[0-9]+ \(criteria[^)]*\) are `observed`' | head -n 1 | awk '{print $1}')
assert_eq "9" "$mutant15_falseenum_observed_count" "sanity (invariant 15, Fix 2 proof, observed): the false-enumeration mutation must leave the leading count at 9, or this is not the count-preserving defeat it claims to be"

mutant15_falseenum_observed_set=$(extract_observed_number_set "$mutant15_falseenum_observed_flat")
falseenum_observed_caught=$([ "$mutant15_falseenum_observed_set" != "$s15_observed_set" ] && echo yes || echo no)
assert_eq "yes" "$falseenum_observed_caught" "FAILURE PROOF (invariant 15, Fix 2): renaming ONE number inside the \`observed\` parenthetical (14 -> 16, count left at 7) must be caught — the mutated tally's enumerated set must no longer equal the real \`observed\` set"

# LEGITIMATE REWORDING, same true facts, must still pass. Reorders the
# parenthetical's numbers (descending instead of ascending) — a plausible
# future copy-edit that changes nothing about which criteria are
# `observed`.
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted phrase, not substitution.
tally_reworded_observed_phrase='9 (criteria 22, 21, 20, 14, 11, 7, 5, 4, 3) are `observed`'
mutant15_reword_observed_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_observed_phrase" "$tally_reworded_observed_phrase")
mutant15_reword_observed_changed=$([ "$mutant15_reword_observed_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_reword_observed_changed" "sanity (invariant 15, Fix 2 proof, observed): the legitimate-rewording mutation must actually change the flattened tally text, or this proof is not well-defined"
mutant15_reword_observed_set=$(extract_observed_number_set "$mutant15_reword_observed_flat")
assert_eq "$s15_observed_set" "$mutant15_reword_observed_set" "LEGITIMATE REWORDING (invariant 15, Fix 2, observed): reordering the SAME nine numbers in the parenthetical (descending instead of ascending) must still be recognized as the identical \`observed\` set — a guard that rejects this is a guard that blocks correct work"

# ==========================================================================
# FAILURE PROOF (invariant 15, Fix 2, `manual`) — the tech lead's exact
# reproduction applied to the manual span: swap ONE real manual criterion
# number (13) for a criterion that is NOT manual (11, which is `observed`),
# leaving the leading count and every other number untouched. Same
# flattened-text scoping rationale as the `observed` block above, and the
# same v0.3.1 re-pinning note.
#
# The anchor below deliberately stops at the number list rather than
# extending into the sentence that follows it: the current document's
# manual clause reads "6 remain `manual`: criteria 6, 8, 9, 10, 12, and
# 13." and that number list appears exactly once in the flattened tally
# text (asserted immediately below, not assumed), which is all this
# fixture's shape needs.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately, both below:
# literal backtick-quoted phrases, not substitution.
tally_old_manual_phrase='criteria 6, 8, 9, 10, 12, and 13'
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted phrase, not substitution.
tally_falseenum_manual_phrase='criteria 6, 8, 9, 10, 12, and 11'

tally_manual_anchor_hits15=$(printf '%s' "$tally_flat15" | grep -oF -- "$tally_old_manual_phrase" | wc -l | tr -d ' ')
assert_eq "1" "$tally_manual_anchor_hits15" "sanity (invariant 15, Fix 2 proof, manual): the tally paragraph's manual list phrase must appear exactly once in the flattened tally text, or this mutation proof is not well-defined"

mutant15_falseenum_manual_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_manual_phrase" "$tally_falseenum_manual_phrase")
mutant15_falseenum_manual_changed=$([ "$mutant15_falseenum_manual_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_falseenum_manual_changed" "sanity (invariant 15, Fix 2 proof, manual): the false-enumeration mutation must actually change the flattened tally text, or this proof is not well-defined"

# 15b (count-only) must NOT catch this — still 6 numbers in the clause and
# the leading "6 remain `manual`" count is untouched — proving the gap Fix
# 2 closes, not merely re-demonstrating 15b.
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
mutant15_falseenum_manual_count=$(printf '%s\n' "$mutant15_falseenum_manual_flat" | grep -oE '[0-9]+ remain `manual`' | head -n 1 | awk '{print $1}')
assert_eq "6" "$mutant15_falseenum_manual_count" "sanity (invariant 15, Fix 2 proof, manual): the false-enumeration mutation must leave the leading count at 6, or this is not the count-preserving defeat it claims to be"

mutant15_falseenum_manual_set=$(extract_manual_number_set "$mutant15_falseenum_manual_flat")
mutant15_falseenum_manual_violations=$(set_subset_violations "$mutant15_falseenum_manual_set" "$s15_manual_set")
assert_eq "11" "$mutant15_falseenum_manual_violations" "FAILURE PROOF (invariant 15, Fix 2, manual containment): renaming ONE number inside the \`manual\` list (13 -> 11, count left at 6) must be caught and NAMED - 11 is genuinely \`observed\`, not \`manual\`, so the containment check names 11 directly, rather than reporting two whole sets and leaving a human to diff them"

# LEGITIMATE REWORDING 1/4 (reordering), same true facts, must still pass
# CLEAN under containment. Reorders the same six numbers in the main
# manual list (13 moved to the front) — a plausible future copy-edit that
# changes nothing about which criteria are `manual`; the rest of the span
# (the criterion-10 aside, the criterion-12 history, the closing
# criterion-7 note) is untouched. This one would also have passed under
# cycle 2's set EQUALITY — it is re-run here so all four legitimate cases
# are proved together, against the SAME comparison the shipped code uses.
tally_reworded_manual_phrase='criteria 13, 6, 8, 9, 10, and 12'
mutant15_reword_manual_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_manual_phrase" "$tally_reworded_manual_phrase")
mutant15_reword_manual_changed=$([ "$mutant15_reword_manual_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_reword_manual_changed" "sanity (invariant 15, Fix 2 proof, manual, reordering): the legitimate-rewording mutation must actually change the flattened tally text, or this proof is not well-defined"
mutant15_reword_manual_set=$(extract_manual_number_set "$mutant15_reword_manual_flat")
mutant15_reword_manual_violations=$(set_subset_violations "$mutant15_reword_manual_set" "$s15_manual_set")
assert_eq "" "$mutant15_reword_manual_violations" "LEGITIMATE REWORDING 1/4 (invariant 15, Fix 2, manual, reordering): reordering the SAME six numbers in the main manual list (13 moved to the front), leaving the rest of the span alone, must pass CLEAN under containment — a guard that rejects this is a guard that blocks correct work"

# LEGITIMATE REWORDING 2/4 (elliptical range) — the review's own
# reproduction, re-derived for the current manual set. "8 through 10"
# collapses THREE literal numbers (8, 9, 10) into a phrase
# extract_criteria_numbers() cannot expand — its regex only ever consumes
# digits it can literally see, joined by ", "/" and "; the word "through"
# is not a joiner it recognizes — so the extracted set legitimately
# SHRINKS to a proper subset of the true set (verified below, not
# assumed). Set EQUALITY (cycle 2) rejected this outright; CONTAINMENT
# (cycle 3) does not, because every number the under-extraction DOES find
# is still genuinely `manual`.
tally_reworded2_manual_phrase='criteria 6 and 8 through 10, plus 12 and 13'
mutant15_reword2_manual_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_manual_phrase" "$tally_reworded2_manual_phrase")
mutant15_reword2_manual_changed=$([ "$mutant15_reword2_manual_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_reword2_manual_changed" "sanity (invariant 15, Fix 2 proof, manual, range wording): the '6 through 9' rewording must actually change the flattened tally text, or this proof is not well-defined"
mutant15_reword2_manual_set=$(extract_manual_number_set "$mutant15_reword2_manual_flat")

# WHERE THE UNDER-EXTRACTION IS NOW OBSERVABLE, and why this sanity check
# moved (v0.3.1 re-pinning). This assertion used to measure the range
# wording's under-extraction against the WHOLE flattened tally paragraph,
# and that worked only because of an accident of the document's prose at
# the time. It stopped working, and the reason is worth recording rather
# than papering over: the current manual span names every one of its six
# criteria AGAIN, individually, in the sentences that follow the list
# ("Criteria 8 and 13 are `manual` in full...", "Criterion 6's
# seven-question interview...", "Criterion 9's off-switch...", "Criterion
# 10 is held...", "criterion 12 **moved twice**"). extract_manual_number_set
# deliberately reads to the END OF THE PARAGRAPH (see its own header for
# why one-sentence bounding would itself be a guard that blocks correct
# work), so it recovers every number from that prose no matter what the
# list says - collapsing numbers in the LIST can no longer shrink the
# PARAGRAPH's extracted set at all.
#
# That does not weaken containment; it is containment working. But it does
# mean the whole-paragraph text can no longer demonstrate under-extraction,
# so the sanity check is applied where under-extraction is real: to the
# reworded CLAUSE in isolation, wearing the same "N remain `manual`" anchor
# extract_manual_number_set keys on. Verified, not assumed - the clause
# alone yields {6, 8}, because "through" is not a joiner the extraction
# grammar recognizes. The containment assertion immediately below still
# runs against the FULL flattened text, unchanged, because "a legitimate
# rewording of the real document must not be rejected" is a claim about
# the real document.
# shellcheck disable=SC2016 # single-quoted deliberately: literal backtick-quoted status word, not substitution.
mutant15_reword2_isolated='6 remain `manual`: criteria 6 and 8 through 10, plus 12 and 13.'
mutant15_reword2_isolated_set=$(extract_manual_number_set "$mutant15_reword2_isolated")
mutant15_reword2_manual_underextracts=$([ -n "$mutant15_reword2_isolated_set" ] && [ "$mutant15_reword2_isolated_set" != "$s15_manual_set" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_reword2_manual_underextracts" "sanity (invariant 15, Fix 2 proof, manual, range wording): '8 through 10' must genuinely extract a NON-EMPTY PROPER SUBSET of the real set when the reworded clause is read on its own — otherwise this proof is not exercising containment's own reason to exist, since set equality would already pass a full-set match trivially"
mutant15_reword2_isolated_violations=$(set_subset_violations "$mutant15_reword2_isolated_set" "$s15_manual_set")
assert_eq "" "$mutant15_reword2_isolated_violations" "LEGITIMATE REWORDING 2/4 (invariant 15, Fix 2, manual, range wording, isolated): the under-extracted set the range wording actually produces must pass CLEAN under containment — this is the assertion set EQUALITY would have failed, and the whole reason containment replaced it"

mutant15_reword2_manual_violations=$(set_subset_violations "$mutant15_reword2_manual_set" "$s15_manual_set")
assert_eq "" "$mutant15_reword2_manual_violations" "LEGITIMATE REWORDING 2/4 (invariant 15, Fix 2, manual, range wording): 'criteria 6 and 8 through 10, plus 12 and 13' — a legitimate rewording set EQUALITY would have rejected because it under-extracts — must pass CLEAN under containment, since every number it DOES find is genuinely \`manual\`"

# LEGITIMATE REWORDING 3/4 (semicolon restructure) — extract_criteria_numbers()'s
# continuation grammar only recognizes ", "/" and " as joiners, never ";",
# so this under-extracts even harder than the range wording above (down to
# a single number, "6" — verified below to be non-empty, not assumed).
# Same containment argument, taken further.
tally_reworded3_manual_phrase='criteria 6; 8; 9; 10; 12; and 13'
mutant15_reword3_manual_flat=$(mutate_first_literal "$tally_flat15" "$tally_old_manual_phrase" "$tally_reworded3_manual_phrase")
mutant15_reword3_manual_changed=$([ "$mutant15_reword3_manual_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_reword3_manual_changed" "sanity (invariant 15, Fix 2 proof, manual, semicolon restructure): the semicolon rewording must actually change the flattened tally text, or this proof is not well-defined"
mutant15_reword3_manual_set=$(extract_manual_number_set "$mutant15_reword3_manual_flat")
assert_eq "yes" "$([ -n "$mutant15_reword3_manual_set" ] && echo yes || echo no)" "sanity (invariant 15, Fix 2 proof, manual, semicolon restructure): the semicolon rewording must still yield at least one criterion number, or this proof is not well-defined"
mutant15_reword3_manual_violations=$(set_subset_violations "$mutant15_reword3_manual_set" "$s15_manual_set")
assert_eq "" "$mutant15_reword3_manual_violations" "LEGITIMATE REWORDING 3/4 (invariant 15, Fix 2, manual, semicolon restructure): 'criteria 6; 8; 9; 10; 12; and 13' — semicolons instead of commas, states the same true facts — must pass CLEAN under containment even though this under-extracts far more severely than the range wording above"

# LEGITIMATE REWORDING 4/4 (added explanatory sentence) — appended at the
# end of the same paragraph, mentioning ANOTHER criterion by number (8) —
# already genuinely `manual`, just re-mentioned by a new sentence. Models
# a realistic future copy edit (an added cross-reference), not a pure
# reordering of the same six numbers like 1/4 above. This is the
# genuinely-manual counterpart to the disclosed residue in
# extract_manual_number_set()'s own header comment (mentioning a
# NON-manual criterion this way WOULD legitimately fail; this sentence
# deliberately mentions a criterion that IS manual, so it must not).
# Criterion 8 is still genuinely `manual` in the current document, so this
# variant needed no re-derivation in the v0.3.1 re-pinning - re-verified
# against the new manual set (6, 8, 9, 10, 12, 13) rather than assumed to
# have survived.
mutant15_addsentence_manual_flat="$tally_flat15 This same shape of gap recurs in criterion 8's own section as well."
mutant15_addsentence_manual_changed=$([ "$mutant15_addsentence_manual_flat" != "$tally_flat15" ] && echo yes || echo no)
assert_eq "yes" "$mutant15_addsentence_manual_changed" "sanity (invariant 15, Fix 2 proof, manual, added sentence): appending the explanatory sentence must actually change the flattened tally text, or this proof is not well-defined"
mutant15_addsentence_manual_set=$(extract_manual_number_set "$mutant15_addsentence_manual_flat")
mutant15_addsentence_manual_violations=$(set_subset_violations "$mutant15_addsentence_manual_set" "$s15_manual_set")
assert_eq "" "$mutant15_addsentence_manual_violations" "LEGITIMATE REWORDING 4/4 (invariant 15, Fix 2, manual, added sentence): an added explanatory sentence mentioning criterion 8 (already genuinely \`manual\`) by number must pass CLEAN — mentioning a criterion that genuinely holds the status being checked is not a defect"

# --- 16. NO TRACKED FILE MAY CLAIM THAT THIS PLUGIN CREATES EITHER
# GOVERNED ROOT --------------------------------------------------------------
#
# The claim: "a symlink at `checkpoints/` is never legitimate because only the plugin creates that
# directory". It is false, and `grep -rn mkdir` over this repo is the whole disproof — no shipped
# script, skill or rule creates `~/.squirrel/checkpoints/` or `~/.squirrel/hoard/`. `/squirrel:init`
# creates `~/.squirrel/` and writes `profile.md` into it, nothing deeper; both roots come into
# existence implicitly, as the parent directory the model's first `Write` inside them creates. The
# conclusion survives — a plain file write never produces a symlink — but the stated reason did not.
#
# WHY IT IS SCANNED REPO-WIDE AND NOT IN ONE FILE. `tests/test_hooks.sh`'s HOARD-18 already forbids
# this claim by needle, and its scope is `scripts/allow-checkpoint.sh` — one file. So the identical
# sentence sat untouched in `docs/adr/0002-checkpoint-auto-allow.md`, which is the document a reader
# of the ADR trail reaches FIRST, for a whole audit cycle after the script was corrected. A guard
# whose scope is narrower than the claim's reach is a guard the claim walks around. This one covers
# every tracked file outside `tests/` — the exclusion those content scans all take, for the
# self-reference reason the top of this file sets out: this very block has to name the phrase it
# forbids.
# IT IS SCANNED FLATTENED, NOT LINE BY LINE, AND THAT IS THE SECOND FIX. The scan used to be
# `git grep -lF`, which matches inside ONE line, so the identical claim written across two lines of
# the same comment passed clean. Proved by mutation rather than argued: with the sentence on a
# single line the suite reported `pass=141 fail=1`; with the SAME sentence broken across two comment
# lines it reported `pass=142 fail=0`. That is not a hypothetical shape either — the file this
# invariant most needs to cover, `scripts/allow-checkpoint.sh`, wraps its comments at about 72
# columns, so a claim of this length is MORE likely to be split than not. That both original
# occurrences happened to sit on one line each was luck, and a guard resting on luck about line
# breaks is a guard that reports on formatting rather than on content.
#
# So each tracked file is flattened first — leading indentation and any comment or list marker
# stripped from every line, runs of blank space squashed, the whole file joined into one line — and
# the needles are matched against that. What that costs is stated rather than implied: the flattened
# form can join two genuinely unrelated sentences across a paragraph break, so a file that ended one
# sentence with "…plugin creates" and began the next with "that directory…" would be reported. No
# tracked file does, the needles are long enough to make it unlikely, and a false report here costs
# one reader one minute — while a false pass costs a whole cycle, which is what happened.
NO_PLUGIN_CREATES_ROOT_NEEDLES='plugin creates that directory
plugin creates both directories'

plugin_creates_scan() {
  # plugin_creates_scan <root> <newline-separated relative paths> — prints one "<needle>:<path>"
  # line per hit, reading each file FLATTENED.
  #
  # A FUNCTION, AND THAT IS THE THIRD FIX. The live assertion and the failure proof must run THE
  # SAME CODE, or the proof does not prove anything about the assertion. The previous proof only
  # showed that `grep -F` could match the stale sentence in a scratch file — a fact about `grep`,
  # not about this invariant. It never once showed the assertion going red, so a scan that skipped
  # every file, or read the wrong tree, would have satisfied it exactly as well.
  pcs_root=$1
  pcs_files=$2
  printf '%s\n' "$pcs_files" | while IFS= read -r pcs_f; do
    [ -n "$pcs_f" ] || continue
    [ -f "$pcs_root/$pcs_f" ] || continue
    # `sed | tr | tr` rather than an awk accumulator: appending to one string per line is quadratic
    # in the awks this repo ships to, and some tracked files run to thousands of lines. Each stage
    # here is a linear stream. The marker class covers shell comments, Markdown blockquotes and
    # Markdown list bullets, which is every way a wrapped claim is spelled in this tree.
    pcs_flat="$glossary_avoid_scratch/flat.$$"
    sed -e 's/^[[:space:]]*//' -e 's/^[#>*-][#>*-]*[[:space:]]*//' "$pcs_root/$pcs_f" 2>/dev/null \
      | tr '\n' ' ' | tr -s ' ' >"$pcs_flat" 2>/dev/null || continue
    pcs_old_ifs=$IFS
    IFS='
'
    for pcs_needle in $NO_PLUGIN_CREATES_ROOT_NEEDLES; do
      IFS=$pcs_old_ifs
      if grep -qF -- "$pcs_needle" "$pcs_flat" 2>/dev/null; then
        printf '%s:%s\n' "$pcs_needle" "$pcs_f"
      fi
      IFS='
'
    done
    IFS=$pcs_old_ifs
    rm -f "$pcs_flat"
  done
}

plugin_creates_tracked=$(git -C "$repo_root" ls-files 2>/dev/null | grep -v '^tests/' || true)
assert_eq "yes" "$([ -n "$plugin_creates_tracked" ] && echo yes || echo no)" "control (invariant 16): the tracked-file list outside tests/ must be non-empty — an empty list makes the scan below pass by reading nothing at all, which is the exact way a repo-wide negative goes quietly vacuous"
plugin_creates_hits=$(plugin_creates_scan "$repo_root" "$plugin_creates_tracked" | tr '\n' ' ')
assert_eq "" "$plugin_creates_hits" "no tracked file outside tests/ may say this plugin creates either governed root — nothing does; both come into existence as the parent directory of the model's first Write, and the symlink boundary rests on 'a plain file write never produces a symlink' instead"

# FAILURE PROOF. A negative that could never match anything is the "guard that cannot fail for its
# own target" class this repo has been bitten by repeatedly. Both needles are proved against real
# document text with the stale sentence restored — and, unlike the version this replaces, proved by
# running THE ASSERTION'S OWN SCAN over a corpus containing the mutant and watching it come back
# NON-EMPTY. "The needle matches in a scratch file" was the old proof and it is not the same claim.
plugin_creates_corpus="$glossary_avoid_scratch/inv16-corpus"
mkdir -p "$plugin_creates_corpus/docs/adr" "$plugin_creates_corpus/scripts"

# Mutant one: ADR-0002 with the stale clause restored, ON ONE LINE — the shape the old scan could
# see, kept so the new scan is proved to be a superset of the old one and not a replacement that
# lost a case.
sed "s|the only mechanism that ever creates that directory is a plain file write through this plugin's own flow, and a plain file write never produces a symlink|only the plugin creates that directory|" \
  "$repo_root/docs/adr/0002-checkpoint-auto-allow.md" >"$plugin_creates_corpus/docs/adr/0002-checkpoint-auto-allow.md"
if cmp -s "$repo_root/docs/adr/0002-checkpoint-auto-allow.md" "$plugin_creates_corpus/docs/adr/0002-checkpoint-auto-allow.md"; then
  plugin_creates_mutant_differs=no
else
  plugin_creates_mutant_differs=yes
fi
assert_eq "yes" "$plugin_creates_mutant_differs" "FAILURE PROOF (invariant 16), control: restoring the stale clause must genuinely change docs/adr/0002-checkpoint-auto-allow.md — a sed that matched nothing would leave a byte-identical copy and prove nothing"

# Mutant two: allow-checkpoint.sh with the both-roots spelling restored and BROKEN ACROSS TWO
# COMMENT LINES at roughly the column that file actually wraps at. This is the case the old scan
# missed entirely, written the way the real file would have written it.
# The replacement carries a BACKSLASH FOLLOWED BY A REAL NEWLINE, which is how POSIX sed spells
# "insert a line break here". `\n` in a replacement is NOT portable - BSD sed writes a literal "n",
# which would put the whole phrase back on one line and make the control below fail loudly. It did,
# on the first attempt; kept as a real newline rather than as an escape for exactly that reason.
#
# THE BREAK FALLS INSIDE THE NEEDLE, not merely somewhere in the sentence, and that is the whole
# construction. A first attempt broke the line just BEFORE the phrase, which left
# "plugin creates both directories" sitting contiguously on line two - and a plain grep found it,
# so the mutant proved nothing about flattening. The needle has to straddle the boundary:
# "…plugin creates" ends one line and "both directories…" opens the next.
plugin_creates_split_repl='legitimate, because this plugin creates\
# both directories itself - see'
sed "s|legitimate, because the only thing that ever creates either root is a|$plugin_creates_split_repl|" \
  "$repo_root/scripts/allow-checkpoint.sh" >"$plugin_creates_corpus/scripts/allow-checkpoint.sh"
if cmp -s "$repo_root/scripts/allow-checkpoint.sh" "$plugin_creates_corpus/scripts/allow-checkpoint.sh"; then
  plugin_creates_mutant2_differs=no
else
  plugin_creates_mutant2_differs=yes
fi
assert_eq "yes" "$plugin_creates_mutant2_differs" "FAILURE PROOF (invariant 16), control: restoring the both-roots spelling must genuinely change scripts/allow-checkpoint.sh"
assert_eq "no" "$(grep -qF -- 'plugin creates both directories' "$plugin_creates_corpus/scripts/allow-checkpoint.sh" 2>/dev/null && echo yes || echo no)" "FAILURE PROOF (invariant 16), control: and the split mutant must be INVISIBLE to a plain line-wise grep — if a contiguous grep could still see it, the row below would not be measuring the flattening fix at all. This is the mutation that turned pass=141 fail=1 into pass=142 fail=0 under the old scan"

plugin_creates_proof_hits=$(plugin_creates_scan "$plugin_creates_corpus" 'docs/adr/0002-checkpoint-auto-allow.md
scripts/allow-checkpoint.sh')
assert_contains "$plugin_creates_proof_hits" "plugin creates that directory:docs/adr/0002-checkpoint-auto-allow.md" "FAILURE PROOF (invariant 16): the assertion's OWN scan must REPORT the one-line stale clause — this is the sentence that survived a whole cycle because the guard that forbade it only ever read one script"
assert_contains "$plugin_creates_proof_hits" "plugin creates both directories:scripts/allow-checkpoint.sh" "FAILURE PROOF (invariant 16): and it must report the clause BROKEN ACROSS TWO COMMENT LINES, which a line-wise grep cannot see. Two needles, two live proofs, and both run the scan the live assertion runs rather than a grep typed beside it"
assert_eq "2" "$(printf '%s\n' "$plugin_creates_proof_hits" | grep -c 'plugin creates' || true)" "FAILURE PROOF (invariant 16), the tally: exactly two hits, so the scan returns non-empty for the corpus that violates the invariant — which is the thing the previous proof never showed. A scan that read nothing would report zero here and still pass the live assertion above"

# ==========================================================================
# GLOSSARY-COST. Every figure the exclusion-4 comment publishes, re-derived.
#
#     Exclusion 4 states what the glossary scan does NOT catch, and states it
#     in numbers: five per-term costs (4b), the length of the two files 4a
#     exempts, and the lines inside docs/adr/* the prefix hides. Every one of
#     those was written by hand, and by the time anyone rechecked them:
#
#       - four of the five per-term counts (note 27, entry 30, record 38,
#         namespace 5) were measurements of the scope as it stood BEFORE
#         docs/specs/* and docs/plans/* joined the denylist — added by the
#         very commit that wrote the counts, under a sentence claiming "this
#         denylist applied";
#       - the fifth, "fact: 22", matched no reading of this repo at all: 9 in
#         the declared scope, 24 in the old one;
#       - "579 and 1986 lines" gave the spec its pre-commit length, 38 lines
#         short of what the same commit left on disk;
#       - "five lines in three ADRs" was six, with the sixth never declared;
#       - and the one line-number citation in that list, 0008:63, pointed at
#         a sentence about `Read`, `Write` and `Edit` — 136 lines above the
#         sentence it claimed to quote, because the ADR grew underneath it.
#
#     Nothing here is a better number. Every figure is recomputed on each run
#     and compared against what the comment publishes, and each comparison
#     PRINTS the recomputed value, so updating the comment is mechanical.
#     Modelled on RENAME-COUNT in tests/test_hooks.sh, including its two
#     controls: the claims must be readable in their documented shape, and
#     the recount must find something — a broken counter agreeing with a
#     broken comment is the failure this exists to prevent.
#
#     IT IS EXPECTED TO FAIL WHENEVER THE REPO GROWS INTO IT. That is the
#     design: the comment is a snapshot, and a snapshot with nothing checking
#     it is what this replaces.
# ==========================================================================
# THE FILE ACTUALLY RUNNING, not the tracked path spelled out by hand.
# Written as "$script_dir/test_repo_invariants.sh" first, and it made every
# comparison below unfalsifiable: a scratch copy with a rotted figure put
# back read the REAL file's figures and passed clean. That is the "guard
# that cannot fail for its own target" this repo has now hit seven times,
# and it is caught here only because the mutation proof was run before the
# scenario was believed. Deriving it from $0 means a mutated copy checks
# the mutated copy.
invariants_file_GC="$script_dir/$(basename "$0")"

claimed_glossary_cost_GC() {
  # claimed_glossary_cost_GC <term> -> "<hits> <files>" as exclusion 4b
  # publishes them, or empty if that bullet is missing or reshaped. The
  # tag is spelled with a literal term name only inside the comment; every
  # mention below builds it from $gc_term, so this sed can never read its
  # own caller's text back as a claim.
  sed -n "s/.*glossary-cost $1: \\([0-9][0-9]*\\) hits across \\([0-9][0-9]*\\) in-scope files.*/\\1 \\2/p" "$invariants_file_GC"
}

count_glossary_term_GC() {
  # count_glossary_term_GC <term> -> "<hits> <files>" over the scan's OWN
  # scope: $glossary_scope_files, filled by the scan loop above as it ran,
  # with the scan's own `grep -wiE`. Deliberately not a second copy of the
  # denylist - the published counts rotted because the denylist moved and a
  # hand-maintained copy of the scope did not move with it.
  cgt_lines=0
  cgt_files=0
  for cgt_f in $glossary_scope_files; do
    cgt_n=$(grep -cwiE "$1" "$repo_root/$cgt_f" 2>/dev/null) || cgt_n=0
    [ -n "$cgt_n" ] || cgt_n=0
    if [ "$cgt_n" -gt 0 ]; then
      cgt_files=$((cgt_files + 1))
      cgt_lines=$((cgt_lines + cgt_n))
    fi
  done
  printf '%s %s' "$cgt_lines" "$cgt_files"
}

assert_eq "yes" "$([ -n "$glossary_scope_files" ] && echo yes || echo no)" "GLOSSARY-COST, control: the scan loop must have recorded the files it looked at - an empty scope list would make every per-term recount below 0 and agree with nothing"

gc_claims_readable="yes"
gc_recount_nonzero="yes"
for gc_term in note entry fact record namespace; do
  gc_claim=$(claimed_glossary_cost_GC "$gc_term")
  [ -n "$gc_claim" ] || gc_claims_readable="no"
  gc_actual=$(count_glossary_term_GC "$gc_term")
  case "$gc_actual" in
    0\ *) gc_recount_nonzero="no" ;;
  esac
done
assert_eq "yes" "$gc_claims_readable" "GLOSSARY-COST, control: all five per-term cost lines must be readable out of exclusion 4b in the documented shape - a reworded bullet would otherwise be silently compared against nothing"
assert_eq "yes" "$gc_recount_nonzero" "GLOSSARY-COST, control: every recount must find something - a zero would mean the counter is broken, and each of these five terms is documented as colliding with real, shipped text"

for gc_term in note entry fact record namespace; do
  gc_claim=$(claimed_glossary_cost_GC "$gc_term")
  gc_actual=$(count_glossary_term_GC "$gc_term")
  assert_eq "$gc_actual" "$gc_claim" "GLOSSARY-COST: exclusion 4b publishes '$gc_claim' (hits, files) as the cost of leaving '$gc_term' out of GLOSSARY_AVOID_REGEX; recounted over the scan's own scope it is '$gc_actual'. Update that bullet"
done

# --- The two files the 4a denylist exempts, and how long they are.
claimed_denylist_lines_GC() {
  # claimed_denylist_lines_GC <path> -> the length exclusion 4a publishes.
  sed -n "s|.*glossary-denylist-lines $1: \\([0-9][0-9]*\\).*|\\1|p" "$invariants_file_GC"
}

for gc_path in docs/specs/2026-08-13-hoard-design.md docs/plans/2026-08-13-hoard-phase-1.md; do
  gc_len_claim=$(claimed_denylist_lines_GC "$gc_path")
  gc_len_actual=$(awk 'END { print NR }' "$repo_root/$gc_path")
  assert_eq "yes" "$([ -n "$gc_len_claim" ] && echo yes || echo no)" "GLOSSARY-COST, control: exclusion 4a must publish a length for $gc_path in the documented shape"
  assert_eq "$gc_len_actual" "$gc_len_claim" "GLOSSARY-COST: exclusion 4a publishes $gc_path as $gc_len_claim lines; it is $gc_len_actual. Update that figure"
done

# --- The docs/adr/ prefix: the two hit sets must match exactly.
adr_hits_actual_GC=$(grep -nwiE "$GLOSSARY_AVOID_REGEX" "$repo_root"/docs/adr/*.md 2>/dev/null \
  | sed "s|^$repo_root/||" | cut -d: -f1,2 | sort)
adr_hits_claimed_GC=$(sed -n 's/.*adr-glossary-hit \(docs\/adr\/[^ :`]*:[0-9][0-9]*\).*/\1/p' "$invariants_file_GC" | sort -u)
adr_hits_actual_count_GC=$(printf '%s\n' "$adr_hits_actual_GC" | grep -c . || true)
adr_hits_actual_files_GC=$(printf '%s\n' "$adr_hits_actual_GC" | cut -d: -f1 | sort -u | grep -c . || true)

assert_eq "yes" "$([ -n "$adr_hits_claimed_GC" ] && echo yes || echo no)" "GLOSSARY-COST, control: the docs/adr/ giveaway list must be readable in its documented tag shape - an unreadable list would compare an empty set against an empty set and pass while proving nothing"
assert_eq "$adr_hits_actual_GC" "$adr_hits_claimed_GC" "GLOSSARY-COST: the docs/adr/ giveaway list must name exactly the lines the scan's own grep finds under that prefix. Recounted set is above; the comment's set is below"
assert_eq "6" "$adr_hits_actual_count_GC" "GLOSSARY-COST: the comment says SIX lines match GLOSSARY_AVOID_REGEX under docs/adr/; the grep finds $adr_hits_actual_count_GC. It said five for as long as it was six"
assert_eq "3" "$adr_hits_actual_files_GC" "GLOSSARY-COST: the comment says those lines sit in three ADRs; the grep finds $adr_hits_actual_files_GC"

# Each phrase the list QUOTES must still live on the line the list cites.
# The line number is not written twice: it is looked up from the phrase and
# then required to be present in the claimed set above. That is what closes
# the specific rot found here - 0008:63 named a real line of a real file,
# and quoted a sentence that had moved 136 lines down.
gc_quote_probe() {
  # gc_quote_probe <path> <phrase> - "<path>:<line>" of the first line
  # holding <phrase>, or empty.
  gqp_n=$(grep -nF -- "$2" "$repo_root/$1" 2>/dev/null | head -n 1 | cut -d: -f1) || gqp_n=""
  [ -n "$gqp_n" ] || return 0
  printf '%s:%s' "$1" "$gqp_n"
}

gc_probe_0008a=$(gc_quote_probe "docs/adr/0008-hoard-auto-allow.md" "the skill's own instruction not to write one is the only thing in front of it")
gc_probe_0008b=$(gc_quote_probe "docs/adr/0008-hoard-auto-allow.md" "Google OAuth client secrets")
gc_probe_0004=$(gc_quote_probe "docs/adr/0004-tiered-parity-across-targets.md" "each gets the deepest integration its host actually supports")
for gc_probe in "$gc_probe_0008a" "$gc_probe_0008b" "$gc_probe_0004"; do
  assert_eq "yes" "$([ -n "$gc_probe" ] && echo yes || echo no)" "GLOSSARY-COST, control: every sentence the docs/adr/ giveaway list quotes must still be findable in the ADR it is attributed to - a vanished quote would make the citation check below vacuous"
  assert_contains "$adr_hits_claimed_GC" "$gc_probe" "GLOSSARY-COST: the giveaway list quotes a sentence that lives at $gc_probe, but cites a different line for it. Cite $gc_probe"
done

# --- "Nowhere else in the repo produces either phrase", as a check.
# Stated without naming the three files, deliberately: what the claim means
# is that every tracked markdown file carrying "memory bank" or "knowledge
# base" is one the glossary denylist exempts, i.e. none of them is in
# $glossary_scope_files. Naming them would be a fourth hand-maintained list.
mbkb_files_GC=""
mbkb_in_scope_GC=""
for f in $(git -C "$repo_root" ls-files); do
  case "$f" in
    *.md | *.mdc) ;;
    *) continue ;;
  esac
  grep -qwiE "memory bank|knowledge base" "$repo_root/$f" 2>/dev/null || continue
  mbkb_files_GC="$mbkb_files_GC $f"
  case " $glossary_scope_files " in
    *" $f "*) mbkb_in_scope_GC="$mbkb_in_scope_GC $f" ;;
  esac
done
assert_eq "yes" "$([ -n "$mbkb_files_GC" ] && echo yes || echo no)" "GLOSSARY-COST, control: some tracked markdown file must carry 'memory bank' or 'knowledge base' - CONTEXT.md's own avoid list does, and a repo where none did would make the check below vacuous"
assert_eq "" "$mbkb_in_scope_GC" "GLOSSARY-COST: every file carrying 'memory bank' or 'knowledge base' must be one the glossary denylist exempts (it is quoting the avoid list, not breaking it). A file in the scan's own scope carrying either phrase is the violation the two terms were added to catch"

# ==========================================================================
# PROFILE-CAP-COUNT. PLAN.md's profile cap figure, re-derived from the hook.
#
#     PLAN.md said "The SessionStart hook caps what it injects at 100 lines
#     / 4 KB". It caps the profile BODY at those, and two fixed additions
#     were deliberately moved OUTSIDE that budget when the per-line/
#     per-stream byte bug was fixed: the truncation notice, and the
#     "[profile] " marker neutralise_forged_lines puts in front of any body
#     line spelling a reserved prefix - PROFILE_MAX_LINES of them in the
#     worst case. So the sentence understated the real ceiling by about a
#     kilobyte, and understated it in the one document a reader goes to for
#     the budget.
#
#     scripts/load-profile.sh already carries the arithmetic beside
#     PROFILE_MAX_LINES, and tests/test_hooks.sh 34b-G already asserts the
#     1000-byte marker cost against the real hook. What was missing is
#     anything tying PLAN.md to either. This recomputes the ceiling from
#     the script's own three constants and requires both documents to
#     publish it, so the two cannot drift apart again - and, like
#     GLOSSARY-COST, it fails and prints the right number rather than
#     needing anyone to remember to recheck.
#
#     KB here is 1000 bytes, not 1024, because that is the unit
#     scripts/load-profile.sh's own comment uses ("About 5.1 KB, against
#     4.1 KB before"); the point of the figure is the order of magnitude
#     and the fact that neither addition scales with profile.md.
# ==========================================================================
lp_file_PC="$repo_root/scripts/load-profile.sh"
plan_body_PC=$(cat "$repo_root/PLAN.md" 2>/dev/null || printf '')
lp_body_PC=$(cat "$lp_file_PC" 2>/dev/null || printf '')

max_lines_PC=$(sed -n 's/^PROFILE_MAX_LINES=\([0-9][0-9]*\)$/\1/p' "$lp_file_PC")
max_bytes_PC=$(sed -n 's/^PROFILE_MAX_BYTES=\([0-9][0-9]*\)$/\1/p' "$lp_file_PC")
marker_len_PC=$(sed -n "s/^PROFILE_LINE_MARKER='\\(.*\\)'\$/\\1/p" "$lp_file_PC" | awk '{ print length($0) }')

assert_eq "yes" "$([ -n "$max_lines_PC" ] && [ -n "$max_bytes_PC" ] && [ -n "$marker_len_PC" ] && [ "$marker_len_PC" -gt 0 ] && echo yes || echo no)" "PROFILE-CAP-COUNT, control: PROFILE_MAX_LINES, PROFILE_MAX_BYTES and PROFILE_LINE_MARKER must all be readable out of scripts/load-profile.sh - a renamed or reshaped constant would otherwise make every figure below compare against an empty string"

marker_cost_PC=$((max_lines_PC * marker_len_PC))
# LC_ALL=C on the awk: `printf "%.1f"` honours the locale's decimal
# separator, so under pt_BR/de_DE/fr_FR this produced "5,1" and reported a
# drift that was really a comma. Caught on the machine this was written on,
# which is exactly the kind of environment-shaped false failure a fixed
# figure must not have.
ceiling_kb_PC=$(LC_ALL=C awk -v b="$max_bytes_PC" -v m="$marker_cost_PC" 'BEGIN { printf "%.1f", (b + m) / 1000 }')

assert_contains "$plan_body_PC" "$max_lines_PC × $marker_len_PC" "PROFILE-CAP-COUNT: PLAN.md must show where the marker budget comes from - PROFILE_MAX_LINES × the marker's length, $max_lines_PC × $marker_len_PC as the hook defines them today"
assert_contains "$plan_body_PC" "= $marker_cost_PC bytes" "PROFILE-CAP-COUNT: PLAN.md must publish the marker budget itself, $marker_cost_PC bytes"
assert_contains "$plan_body_PC" "$ceiling_kb_PC KB" "PROFILE-CAP-COUNT: PLAN.md must publish the real worst case, about $ceiling_kb_PC KB (PROFILE_MAX_BYTES $max_bytes_PC + $marker_cost_PC bytes of markers + one notice line), not the body cap alone"
assert_contains "$lp_body_PC" "$ceiling_kb_PC KB" "PROFILE-CAP-COUNT: scripts/load-profile.sh must publish the same worst case beside its own constants - two documents naming one ceiling is how they stay in step"
assert_not_contains "$plan_body_PC" "caps what it injects at $max_lines_PC lines" "PROFILE-CAP-COUNT: PLAN.md must not describe the cap as bounding what the hook INJECTS. It bounds the profile BODY; the truncation notice and the markers are added after the cut, on purpose, and saying otherwise understates the ceiling by about a kilobyte"

# ==========================================================================
# SCRATCH-LEAK. Every path this run put in $TMPDIR is on the trap's list.
# This file's own leak was one directory per run, caused by a second
# `trap ... EXIT` replacing the first — see the cleanup header at the top.
# Runs BEFORE the trap fires, so it asserts that each path is SCHEDULED,
# not that it is already gone.
# ==========================================================================
assert_no_scratch_leak "$scratch_before" "$cleanup_paths" "SCRATCH-LEAK: every scratch directory this file creates must be appended to \$cleanup_paths, which the single EXIT trap removes - giving one its own \`trap ... EXIT\` disinherits every path registered before it"

assert_report
