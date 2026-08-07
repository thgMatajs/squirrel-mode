#!/bin/sh
# Repo-wide invariants that must hold now and keep holding through every
# later build step (S2-S9). See tests/lib/assert.sh for why `set -eu`
# here does not abort on the first failed assertion.
set -eu

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

# Path-level denylist for the visibility scan ONLY (see exclusion 2
# above). Category comment, not four per-file justifications: these are
# internal design records; the rule scopes to shipped instructions and
# user-facing docs (PLAN.md Section 5). docs/adr/ is excluded as a
# directory prefix, not as part of a blanket docs/* exclusion — files
# like docs/RESEARCH.md and docs/OTHER-TOOLS.md are user-facing and
# stay in scope.

visibility_hits=""
marker_hits=""
non_exec_hits=""
invalid_json_hits=""

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

assert_report
