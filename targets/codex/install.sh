#!/bin/sh
# install.sh - installs squirrel-mode's Codex artifacts into the user's
# home directory. The only files it creates or modifies are under
# $HOME. It never writes inside any project repository:
#
#   1. ~/.codex/AGENTS.md - a delimited block (BEGIN/END markers below)
#      is appended (new file, or an existing file with no block yet) or
#      replaced in place (an existing file that already has the block).
#      Content OUTSIDE the block - the user's own AGENTS.md instructions,
#      almost certainly already there - is never touched, never
#      truncated, and is byte-exact after both an install and an
#      uninstall. Marker detection is FENCE-AWARE: a BEGIN/END-shaped
#      line inside a ``` or ~~~ fenced code block (for example, a user's
#      own example of what this block looks like) is never mistaken for
#      the real thing - see marker_scan below.
#   2. ~/.agents/skills/<name>/SKILL.md for digest, plan, init, tune -
#      copied from targets/codex/skills/<name>/SKILL.md next to this
#      script. Ownership of an existing file at that exact path is
#      decided by an EXACT, FULL-LINE match against that specific
#      artifact's own GENERATED FILE banner line - read fresh from the
#      bundled source file next to this script, never hardcoded (see
#      banner_line_for/classify_dedicated_file below), so a future
#      change to scripts/build.sh's banner format cannot desynchronise
#      this installer from what it is actually comparing against. A
#      file that merely CONTAINS the substring "<!-- GENERATED FILE.
#      Source:" somewhere - e.g. a user's own skill that quotes
#      squirrel-mode's own docs - is foreign, not ours, and is never
#      overwritten on install or removed on uninstall. The asymmetry is
#      deliberate: a false "foreign" verdict only ever skips an install
#      (safe, and reported in one line); a false "ours" verdict would
#      destroy user data on the next uninstall. Every check here is
#      biased toward "foreign" whenever there is any doubt.
#   3. ~/.codex/.squirrel-install.lock - a mutex directory, created
#      immediately before any AGENTS.md read-then-write work begins and
#      held for the rest of this run - released by the EXIT trap on
#      every exit path, including the skills loop further below, a
#      failure, or a caught signal (see CONCURRENCY below), never the
#      instant AGENTS.md's own work ends. Created ONLY during a real
#      write (--yes) - a dry run never
#      touches it; see DRY RUN BY DEFAULT below.
#
# It also uses a short-lived, self-cleaning staging directory under
# $TMPDIR on every invocation, including a dry run (mktemp -d, removed
# on every exit path, including a caught signal - see the cleanup trap
# below). That directory is never under $HOME and is not one of the
# three items enumerated above.
#
# SYMLINK REFUSAL: if ~/.codex/AGENTS.md or an
# ~/.agents/skills/<name>/SKILL.md destination is itself a symlink, this
# script REFUSES (fails loudly, changes nothing) instead of writing
# through it - on both install and uninstall. squirrel-mode replaces a
# destination atomically via `mv` (rename(2)), which replaces the
# DIRECTORY ENTRY at that path; if that entry is a symlink, `mv` severs
# it instead of writing through it, and whatever it pointed to - very
# plausibly a dotfiles-managed file, since chezmoi/stow/yadm routinely
# place a symlink at exactly a path like this - is left stale forever
# with no warning. This mirrors the trust boundary in
# scripts/allow-checkpoint.sh and ADR-0002: a symlink AT the exact
# artifact path a script owns is never legitimate for that script's own
# write to pass through, and is rejected rather than silently followed
# or replaced. See fail_if_symlink below.
#
# DRY RUN BY DEFAULT: with no flags, this script prints exactly what it
# WOULD change and writes nothing under $HOME - not even the lock
# directory in item 3 above. Pass --yes to actually write. This was
# chosen over an interactive y/n prompt because this is a POSIX sh
# script with no guarantee of a TTY on stdin (piped input, CI, a test
# harness) - a prompt that silently reads EOF as "no" (or hangs) is a
# worse default than a script that is simply inert until told, in one
# unambiguous flag, to act.
#
# IDEMPOTENT: every write below is preceded by rendering the exact new
# content into a temp file and comparing it, byte for byte, against
# what is already on disk. If they already match, nothing is written
# at all - not even a no-op move that would bump the file's mtime.
# Running this script twice (with --yes both times) changes the
# filesystem only on the first run.
#
# CONCURRENCY: a second install.sh (any action) started with --yes
# while one is already writing against the same $HOME fails loudly with
# a clear message instead of racing the first one's read-then-write
# sequence - see the mkdir-based lock acquired below, right before any
# AGENTS.md work begins. Only acquired for a REAL write (--yes) - a dry
# run changes nothing, so it needs no mutex and never acquires the
# lock; two concurrent dry runs (or a dry run alongside a real install)
# never contend with each other.
#
# UNINSTALL: pass --uninstall (with --yes to act on it) to remove the
# AGENTS.md block and the four skill files this script installed. If
# ~/.codex has since been removed, the AGENTS.md step is skipped (there
# is nothing there to clean) but the four skill files under
# ~/.agents/skills/ are still removed - they do not live under
# ~/.codex, and stranding them forever just because ~/.codex is gone
# would be a worse outcome than removing them anyway.
#
# POSIX sh, no network calls, no telemetry, never truncates a file it
# does not fully own.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line before this script
# ever gets to parse its own arguments. Unset unconditionally, before
# that `cd` runs, rather than trust the invoking shell's environment.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)

BEGIN_MARKER="<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->"
END_MARKER="<!-- END SQUIRREL-MODE -->"
GENERATED_TAG="<!-- GENERATED FILE. Source:"

fail() {
  echo "install.sh: ERROR: $1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: targets/codex/install.sh [--yes] [--uninstall] [--help]

Installs squirrel-mode's Codex artifacts:
  - a delimited block inside ~/.codex/AGENTS.md
  - the four ported command skills, copied to
    ~/.agents/skills/<name>/SKILL.md (digest, plan, init, tune)

With no flags, this is a DRY RUN: it prints exactly what would change
and writes nothing.

  --yes         Perform the install (or, with --uninstall, the
                uninstall) for real. Without this flag, nothing is
                ever written.
  --uninstall   Remove squirrel-mode's block from AGENTS.md and its
                four skill files, instead of installing them.
  --help        Show this message and exit.

The only files this script creates or modifies are under $HOME - which
includes a short-lived lock directory, ~/.codex/.squirrel-install.lock,
created and removed only during a real --yes write (a dry run never
creates it). It also uses a short-lived, self-cleaning staging
directory under $TMPDIR on every invocation, including a dry run. It
never writes inside a project repository, makes no network calls, and
sends no telemetry. A destination that is itself a symlink is refused,
not written through - see this script's own header comment
(SYMLINK REFUSAL).
USAGE
}

do_write=no
action=install

while [ $# -gt 0 ]; do
  case "$1" in
    --yes | -y)
      do_write=yes
      ;;
    --uninstall)
      action=uninstall
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

home_dir="${HOME:-}"
# shellcheck disable=SC2016 # single-quoted deliberately: this message
# names the literal environment variable $HOME, not an expression to
# expand in this shell.
[ -n "$home_dir" ] || fail '$HOME is not set - cannot determine where to install.'

codex_home="$home_dir/.codex"
agents_file="$codex_home/AGENTS.md"
agents_skills_dir="$home_dir/.agents/skills"

# --- Host detection, scoped to the AGENTS.md step only ------------------
#
# ~/.codex existing is this script's signal that Codex has been RUN at
# least once on this machine (PLAN.md's own verified fact: Codex reads
# AGENTS.md layered from ~/.codex/ down to cwd, so ~/.codex/ is where
# its global layer lives). It is deliberately not read as a signal that
# Codex is or is not installed: Codex creates that directory on first
# run, so an installed-but-never-launched Codex looks identical to an
# absent one here, and the message below names the condition this check
# can actually distinguish rather than the one it cannot.
#
# For INSTALL, its absence is reported, not treated as a failure: exit
# 0, do nothing at all (including the skills below), so a machine that
# has no Codex layer to install into is not blocked by running this
# script by mistake (or as part of a script that installs into every
# target unconditionally). This is unchanged from before.
#
# For UNINSTALL, its absence must NOT exit the whole script: a user who
# removed ~/.codex after installing squirrel-mode still has four skill
# files sitting under ~/.agents/skills/, which do not live under
# ~/.codex and are not affected by its removal. Exiting early here used
# to strand those four files forever with no way to remove them through
# this script again. The AGENTS.md step is skipped (there is nothing
# there to clean), and codex_home_present below gates exactly that one
# step - everything after it, in particular the skills loop, still runs.
codex_home_present=no
if [ -d "$codex_home" ]; then
  codex_home_present=yes
fi

if [ "$action" = "install" ] && [ "$codex_home_present" = "no" ]; then
  echo "Codex home directory not found at $codex_home - Codex creates that directory the first time it runs, so it has not been run on this machine yet (installing Codex is not enough on its own). There is nothing to install into: run Codex once, then re-run this script."
  exit 0
fi

fail_if_symlink() {
  # fail_if_symlink <path> <description>: refuses (fail()s) if <path> is
  # itself a symlink, checked with the POSIX `[ -L ]` builtin - no
  # `realpath`/`readlink`, so this holds even with neither on PATH.
  # write_destination below replaces a destination atomically via `mv`
  # (rename(2)), which replaces the DIRECTORY ENTRY at <path> - if that
  # entry is a symlink, `mv` severs it instead of writing through it,
  # leaving whatever it pointed to stale forever with no warning. A
  # symlink here means the user (or a dotfiles manager - chezmoi, stow,
  # yadm all do this routinely) deliberately pointed this exact path
  # elsewhere; the only safe response is to refuse and say so, never to
  # silently follow or replace it. This mirrors
  # scripts/allow-checkpoint.sh's identical trust-boundary precedent
  # (ADR-0002): a symlink AT the exact artifact path a script owns is
  # rejected there too.
  #
  # Deliberately checks ONLY <path> itself, never an ancestor directory:
  # a symlinked ~/.agents/skills/<name> or ~/.codex directory is a
  # legitimate dotfiles setup (the same ADR-0002 precedent trusts a
  # symlinked ~/.claude for exactly this reason), and `mv` through a
  # symlinked ancestor still correctly lands the file wherever the user
  # pointed that directory - only a symlink AT the managed leaf path
  # itself is ever a problem. Do not "harden" this into an ancestor walk.
  #
  # Uses `[ -L ]` FIRST, before any `[ -e ]`-gated check: a DANGLING
  # symlink (pointing at a since-removed target) is still a symlink that
  # must be refused, but `[ -e ]` on a dangling symlink is false, so any
  # check gated behind `[ -e ]` first would silently miss it entirely.
  path=$1
  desc=$2
  if [ -L "$path" ]; then
    fail "$desc ($path) is a symlink - squirrel-mode replaces a destination atomically by rename, which would sever the link rather than write through it, leaving whatever it points to stale forever with no warning. Remove the symlink and let squirrel-mode create a real file there, or point it at the real file's own path directly, then re-run."
  fi
}

validate_destination() {
  # validate_destination <path> <description>: EVERY destination-refusal
  # condition that must hold BEFORE this script writes anything at all,
  # for a single managed path, expressed exactly ONCE. Today that is two
  # checks - fail_if_symlink (above) and the not-a-regular-file guard
  # below (a directory or other special file sitting at <path> must
  # never be silently treated as if it were the file this script
  # manages - the old behaviour reported a false "Installed:" while
  # leaving a fully-rendered temp file orphaned inside $HOME). A future
  # third pre-flight condition is added HERE, in this one function, and
  # every call site below - both the pre-flight pass and its single
  # TOCTOU re-check inside the skills loop further down - automatically
  # picks it up with no further edits.
  #
  # G1 (S7 review cycle 3, BLOCKER): before this function existed, the
  # symlink check alone had been hoisted into a pre-flight pass while
  # this not-a-regular-file check stayed inside the skills loop further
  # below, checked only once that loop actually reached each skill's own
  # turn. A directory at ~/.agents/skills/tune/SKILL.md therefore let
  # AGENTS.md and three of the four skill files be written for real
  # before the loop ever reached tune's own check - this script's own
  # "refuses, changing nothing" promise was false for that case, even
  # though the identical scenario with a symlink at that exact path
  # correctly wrote nothing. Reproduced and fixed by giving both
  # conditions exactly one pre-flight call site, never a second,
  # divergent copy of either rule.
  path=$1
  desc=$2
  fail_if_symlink "$path" "$desc"
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    fail "$desc ($path) exists but is not a regular file (a directory or other special file is there instead) - refusing to touch it. Remove or rename it by hand, then re-run."
  fi
}

# PRE-FLIGHT, for EVERY managed destination path, for BOTH install and
# uninstall, before this script writes anything whatsoever - not even
# the lock directory or the $TMPDIR staging directory have been created
# yet at this point. Deliberately UNGUARDED by codex_home_present for
# the four skill paths, matching the skills loop's own unguarded
# execution further below (see the host-detection comment above
# codex_home_present: on uninstall, the skills loop runs even after
# ~/.codex is gone, because the four skill files do not live under
# ~/.codex). AGENTS.md is guarded by codex_home_present because
# $agents_file is only meaningful (and, for install, only reachable at
# all - see the early exit above) once ~/.codex exists.
if [ "$codex_home_present" = "yes" ]; then
  validate_destination "$agents_file" "\$HOME/.codex/AGENTS.md"
fi
for cmd_name in digest plan init tune; do
  validate_destination "$agents_skills_dir/$cmd_name/SKILL.md" "\$HOME/.agents/skills/$cmd_name/SKILL.md"
done

# F6: a pre-existing AGENTS.md this script cannot READ is a loud,
# top-level failure naming the REAL path - never a raw permission-denied
# error surfacing an internal staging path deep inside render_agents_install
# below (see that function's own comment for the specific crash this
# guard prevents). Checked before any lock or temp directory exists, so
# failing here needs no cleanup, and applies to both install and
# uninstall - both need to read this file's current content.
if [ "$codex_home_present" = "yes" ] && [ -f "$agents_file" ] && [ ! -r "$agents_file" ]; then
  fail "$agents_file exists but is not readable (permission denied) - squirrel-mode needs to read its current content before it can compute what would change. Fix its permissions (e.g. chmod u+r $agents_file) and re-run."
fi

# --- Shared helpers ----------------------------------------------------

ensure_trailing_newline() {
  # ensure_trailing_newline <file>: appends a single "\n" to <file>
  # in place, but ONLY if its last byte is not already one. Never
  # touches any other byte, so a file that already ends cleanly is
  # left completely untouched (not even rewritten).
  f=$1
  [ -s "$f" ] || return 0
  last_byte=$(tail -c 1 "$f" | od -An -tu1 | tr -d ' \n')
  if [ "$last_byte" != "10" ]; then
    printf '\n' >>"$f"
  fi
}

print_first_n_lines() {
  # print_first_n_lines <file> <n>: prints the first <n> lines of
  # <file>, or nothing at all when <n> is 0 or negative. A plain `head
  # -n 0` is REJECTED outright by BSD head (macOS: "illegal line
  # count"), while GNU head accepts it and prints nothing - this
  # happens for real whenever the squirrel-mode block sits at the very
  # start of AGENTS.md (before_n = 0 lines precede it), which is
  # exactly the CREATE case. Special-casing n<=0 here, before head is
  # ever invoked, is what keeps both render_agents_install and
  # render_agents_uninstall working on both.
  f=$1
  n=$2
  [ "$n" -gt 0 ] || return 0
  head -n "$n" "$f"
}

marker_scan() {
  # marker_scan <file>: a SINGLE awk pass over <file> that tracks
  # fenced-code-block state and prints exactly one line, "<begin_line>
  # <end_line> <begin_count> <end_count> <eof_in_fence> <fenced_hits>"
  # (1-indexed, 0 meaning "not found"; <eof_in_fence> is 1 when the
  # file's last line is still inside an unterminated fence, 0 otherwise;
  # <fenced_hits> - F7 - is the count of BEGIN_MARKER/END_MARKER-SHAPED
  # lines seen WHILE inside a fence, i.e. exactly the lines this scan
  # correctly ignored as non-real - used by marker_lines_in_fence below
  # so both install's and uninstall's user-facing messages can say so,
  # instead of silently ignoring them with no trace in the output),
  # counting and locating BEGIN_MARKER/END_MARKER lines ONLY OUTSIDE
  # fences. This is what makes marker detection fence-aware: a
  # BEGIN/END-shaped line sitting inside a ``` or ~~~ fenced code block
  # (a user's own example of what this block looks like, quoted in
  # their own AGENTS.md) is skipped over by this scan entirely, exactly
  # as it would be by a Markdown renderer - it is never treated as the
  # real thing, so install/uninstall can never apply themselves to the
  # example instead of the actual block.
  #
  # Fence recognition: a line whose content, after stripping 0-3
  # leading spaces (CommonMark: 4+ leading spaces makes it an indented
  # code block, not a fence - not specially handled here beyond this
  # cap, since squirrel-mode never emits indented-code-block markers
  # and this scan only needs to be at least as strict as a renderer,
  # never looser), starts with three or more backticks or three or more
  # tildes opens a fence; an info string may follow on the same line and
  # is ignored. The fence stays open until a line whose content (after
  # the same leading-space strip) is that many-or-more of the SAME
  # fence character and nothing else but trailing whitespace - matching
  # CommonMark's own closing-fence rule (same character, at least as
  # long as the opener, no other content). An opened fence that never
  # finds a matching close runs to end of file, exactly like a Markdown
  # renderer treats an unterminated fence - nothing after it, including
  # a genuine-looking marker line, is ever scanned as real content.
  file=$1
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    function fence_run(s, ch,    i, n) {
      n = 0
      for (i = 1; i <= length(s); i++) {
        if (substr(s, i, 1) == ch) { n++ } else { break }
      }
      return n
    }
    {
      line = $0
      # CommonMark allows up to 3 leading SPACES before a fence marker
      # (4+ makes it an indented code block instead) - a single bounded
      # sub strips exactly that many, never more, so a heavily-indented
      # line that only coincidentally starts with backticks/tildes
      # after 4+ spaces is correctly left alone (its first non-stripped
      # character stays a space, which matches neither fence-open nor
      # fence-close below). Leading TABS are not specially converted to
      # spaces here (unlike a full CommonMark tab-stop implementation) -
      # squirrel-mode never emits a tab-indented fence, and this scan
      # only needs to be at least as strict as a renderer, never looser.
      trimmed = line
      sub(/^ {0,3}/, "", trimmed)
      if (in_fence) {
        if (line == b || line == e) { fenced_hits++ }
        first = substr(trimmed, 1, 1)
        if (first == fence_char) {
          clen = fence_run(trimmed, fence_char)
          rest = substr(trimmed, clen + 1)
          gsub(/[ \t]/, "", rest)
          if (clen >= fence_open_len && rest == "") {
            in_fence = 0
          }
        }
        next
      }
      first = substr(trimmed, 1, 1)
      if (first == "`" || first == "~") {
        olen = fence_run(trimmed, first)
        if (olen >= 3) {
          in_fence = 1
          fence_char = first
          fence_open_len = olen
          next
        }
      }
      if (line == b && !begin_count) { begin_line = NR }
      if (line == b) { begin_count++ }
      if (line == e && !end_count) { end_line = NR }
      if (line == e) { end_count++ }
    }
    END { printf "%d %d %d %d %d %d\n", begin_line, end_line, begin_count, end_count, in_fence, fenced_hits }
  ' "$file"
}

marker_lines_in_fence() {
  # marker_lines_in_fence <file>: prints "yes" if marker_scan (F7) found
  # at least one BEGIN_MARKER/END_MARKER-SHAPED line while inside a
  # fence - i.e. a fence-internal example that was correctly ignored -
  # "no" otherwise (including a nonexistent file). Used to add a fence
  # note to install's "would append" message and uninstall's "no block"
  # message, so a user whose own fenced example happens to look like
  # the real thing is told why it was ignored, on both paths - not just
  # the separate, stricter file_ends_inside_open_fence guard above.
  file=$1
  [ -f "$file" ] || { printf 'no\n'; return 0; }
  # shellcheck disable=SC2046 # marker_scan's six-integer output,
  # deliberately word-split - see find_marker_lines above.
  set -- $(marker_scan "$file")
  fenced_hits=$6
  if [ "${fenced_hits:-0}" -gt 0 ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

find_marker_lines() {
  # find_marker_lines <file>: prints "<begin_line> <end_line>"
  # (1-indexed) for the FIRST fence-external line equal to BEGIN_MARKER
  # and the FIRST fence-external line equal to END_MARKER, or 0 for
  # either not found. A thin wrapper over marker_scan, kept as its own
  # function because render_agents_install/render_agents_uninstall only
  # ever need these first two of its six values.
  file=$1
  # shellcheck disable=SC2046 # marker_scan prints exactly six
  # space-separated integers on one line; deliberately unquoted so they
  # become six separate positional values, of which only the first two
  # are kept.
  set -- $(marker_scan "$file")
  printf '%s %s\n' "$1" "$2"
}

file_ends_inside_open_fence() {
  # file_ends_inside_open_fence <file>: prints "yes" if <file>'s last
  # line is still inside an unterminated ``` or ~~~ fence (marker_scan's
  # fifth value), "no" otherwise (including a nonexistent file). This
  # is what render_agents_install's "none" branch below guards against:
  # appending the real BEGIN/END block onto a file whose trailing
  # content is an unterminated fence would place that new block INSIDE
  # the very fence marker_scan's own fence-awareness (correctly) treats
  # as non-marker content until end of file - a marker_scan of the
  # RESULT would then also report "none" (the newly-appended real
  # markers are now themselves inside that fence), so the block can
  # never be found again by a later install or by uninstall: a second
  # install would append ANOTHER block instead of updating the first,
  # and uninstall could never find any block to remove. Failing loudly
  # here, before ever appending, is what keeps this a user problem to
  # fix in their own file rather than a squirrel-mode-created dead end.
  file=$1
  [ -f "$file" ] || { printf 'no\n'; return 0; }
  # shellcheck disable=SC2046 # marker_scan's six-integer output,
  # deliberately word-split - see find_marker_lines above; only the
  # fifth value (eof_in_fence) is used here.
  set -- $(marker_scan "$file")
  eof_in_fence=$5
  if [ "$eof_in_fence" = "1" ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

markers_state() {
  # markers_state <file>: prints one of:
  #   none    - neither marker present outside a fence (or file absent)
  #   ok      - exactly one fence-external BEGIN, exactly one
  #             fence-external END, BEGIN before END
  #   corrupt - anything else (missing partner, duplicated, out of
  #             order) - always among fence-external occurrences only
  file=$1
  [ -f "$file" ] || { printf 'none\n'; return 0; }
  # shellcheck disable=SC2046 # marker_scan's six-integer output,
  # deliberately word-split - see find_marker_lines above; only the
  # first four values are used here.
  set -- $(marker_scan "$file")
  b=$1
  e=$2
  bc=$3
  ec=$4
  if [ "$b" -eq 0 ] && [ "$e" -eq 0 ]; then
    printf 'none\n'
    return 0
  fi
  if [ "$b" -gt 0 ] && [ "$e" -gt "$b" ] && [ "$bc" -eq 1 ] && [ "$ec" -eq 1 ]; then
    printf 'ok\n'
  else
    printf 'corrupt\n'
  fi
}

banner_line_for() {
  # banner_line_for <source_path>: prints the exact, full GENERATED
  # FILE banner line as it CURRENTLY appears in <source_path> - the
  # repo's own bundled, freshly-generated copy of the artifact this
  # installer is about to compare a destination against. Deriving the
  # expected line from this file, rather than hardcoding a literal
  # string that mirrors scripts/build.sh's current banner format, means
  # a future change to that format cannot silently desynchronise this
  # installer from what it is actually comparing against - the
  # installer and the generator can never disagree about what "ours"
  # means, because both ultimately read it from the same generated
  # artifact. If the expected line cannot be found at all, that is a
  # loud failure (a broken or incomplete checkout), never treated as
  # "assume ours" - see classify_dedicated_file's own comment for why a
  # false "ours" is the dangerous direction to err in.
  source_path=$1
  line=$(grep -m1 -F "$GENERATED_TAG" "$source_path" 2>/dev/null || true)
  [ -n "$line" ] || fail "could not find a '$GENERATED_TAG' banner line inside $source_path - this installer cannot tell its own files apart from foreign ones without it. Re-run 'sh scripts/build.sh' from the repo root to regenerate it, then re-run this installer."
  printf '%s\n' "$line"
}

classify_dedicated_file() {
  # classify_dedicated_file <path> <expected_banner_line>: prints one of
  #   absent  - nothing at <path>
  #   ours    - exists and its content contains a line that is an
  #             EXACT, FULL-LINE match for <expected_banner_line> (a
  #             previous run of this script, or scripts/build.sh's own
  #             output, put it there)
  #   foreign - exists and does NOT contain that exact line (something
  #             else already occupies this exact path - never
  #             overwritten, never removed)
  #
  # This is an exact full-line match (grep -Fx), never a substring
  # search: a foreign file that merely CONTAINS the text "<!--
  # GENERATED FILE. Source:" somewhere - e.g. a user's own skill that
  # quotes squirrel-mode's docs - must classify as foreign, not ours.
  # The asymmetry that justifies erring toward "foreign" on any doubt:
  # a false "foreign" only ever skips an install, safely, with one line
  # reported; a false "ours" destroys user data on the very next
  # uninstall.
  path=$1
  expected=$2
  [ -f "$path" ] || { printf 'absent\n'; return 0; }
  if grep -qFx -- "$expected" "$path" 2>/dev/null; then
    printf 'ours\n'
  else
    printf 'foreign\n'
  fi
}

write_destination() {
  # write_destination <destination> <content_file>: atomically replaces
  # <destination>'s content with <content_file>'s content - a temp file
  # in the SAME DIRECTORY as <destination> (so the final `mv` is a
  # same-filesystem rename, atomic), then `mv`'d into place.
  #
  # FILE MODE PRESERVATION (no `chmod --reference` - GNU-only - and no
  # `stat` format flag - its format string is not portable between BSD
  # and GNU stat): when <destination> already exists, the temp file is
  # first created with `cp "$destination" "$temp"`, which copies
  # <destination>'s CURRENT MODE onto the temp file along with its old
  # content; that content is then overwritten in place via redirection,
  # `cat "$content_file" >"$temp"` - redirecting INTO an existing file
  # preserves that file's mode, this is POSIX shell redirection
  # semantics, not something `cat` itself does. The final `mv` replaces
  # <destination> with a file carrying <destination>'s own former mode,
  # not a fresh umask-default one. When <destination> does not exist
  # yet, there is no prior mode to preserve, so the temp file is simply
  # a fresh copy of <content_file> - exactly as before this fix.
  #
  # STAGING PATH TRACKING (for the signal-cleanup trap below): the
  # global current_staging_path is set to the temp file's path before
  # any write to it begins, and cleared only after the `mv` that
  # retires it has completed. A signal delivered at any point while
  # this function is running therefore always finds current_staging_path
  # pointing at a real, removable leftover (or already cleared, if the
  # `mv` had already completed) - never a stale path from a previous
  # call.
  #
  # F6 (class closure beyond render_agents_install's own fix below): if
  # <destination> exists but this process cannot WRITE to it, the
  # cp-then-redirect trick above cannot work AT ALL - `cp "$destination"
  # "$temp"` inherits <destination>'s own unwritable mode onto a brand
  # new $temp (verified empirically: cp copies the SOURCE's mode when
  # the destination path does not yet exist, regardless of umask), and
  # the following `cat >"$temp"` then dies with a raw permission-denied
  # naming $temp - an internal staging path the user never created and
  # cannot act on. Checked HERE, inside the function, not hoisted to a
  # top-level pre-check: a call that never reaches this point (the
  # cmp -s short-circuit above found nothing to change) must keep
  # exiting 0 even for a locked-down file - only a call that actually
  # needs to write should ever see this failure.
  destination=$1
  content_file=$2
  if [ -e "$destination" ] && [ ! -w "$destination" ]; then
    fail "$destination is not writable (permission denied) - squirrel-mode cannot update it in place. Fix its permissions (e.g. chmod u+w $destination) and re-run."
  fi
  dest_dir=$(dirname "$destination")
  base=$(basename "$destination")
  temp="$dest_dir/.$base.tmp.$$"
  current_staging_path="$temp"
  if [ -f "$destination" ]; then
    cp "$destination" "$temp"
    cat "$content_file" >"$temp"
  else
    # G3: a freshly created destination has no prior mode to preserve,
    # so the ONLY goal here is to never let $temp sit, even briefly, at
    # a permissive mode WHILE it already holds real content. The
    # previous version created $temp via `cp "$content_file" "$temp"` -
    # which writes the mode and the full content in the very same
    # step - and only clamped the mode with `chmod go-w` afterwards;
    # under umask 000 that left a window, for as long as it took that
    # `chmod` to run, during which $temp already held squirrel-mode's
    # real content (for AGENTS.md specifically, instructions Codex
    # treats as trusted input every session) at mode 666,
    # world-writable, sitting in the real destination directory.
    # `: >"$temp"` creates an EMPTY file first (mode governed by this
    # process's umask, exactly like every other fresh-redirection target
    # in this script); `chmod go-w` clamps it immediately, before a
    # single byte of real content exists there; only then does `cat`
    # stream the actual content in. Clamping (never SETTING) leaves the
    # user's own umask read policy alone - a umask 077 user gets 600
    # here, never a forced 644 - while closing the write-access hole
    # regardless of which caller, AGENTS.md or a skill file, is creating
    # this particular destination.
    #
    # Side effect, deliberately accepted: a freshly created SKILL file
    # (whose content_file is the repo's own committed source, normally
    # mode 644 under git) previously inherited that 644 via `cp`
    # regardless of this process's umask; it now follows THIS umask
    # instead; e.g. under umask 077, a fresh skill file lands 600, not
    # 644. Stricter, never looser, and consistent with this same
    # clamp's own "never a forced 644" stance for AGENTS.md above - no
    # test in tests/test_targets.sh pins the old 644-regardless-of-umask
    # behaviour for a skill file (scenario 27's skill/mdc cases are
    # explicitly "class coverage, not mutation-discriminating").
    : >"$temp"
    chmod go-w "$temp"
    cat "$content_file" >"$temp"
  fi
  mv "$temp" "$destination"
  current_staging_path=""
}

# --- AGENTS.md: render the desired INSTALL content into a temp file ----

render_agents_install() {
  # render_agents_install <out>: writes the full desired content of
  # $agents_file (create, append, or replace - see the file header
  # comment) into <out>. Never reads $agents_file into a shell
  # variable for the parts being preserved verbatim - command
  # substitution strips trailing newlines, which would silently corrupt
  # a byte-exact round trip - only head/tail/cat on the file directly.
  out=$1
  bundled_agents="$repo_root/targets/codex/AGENTS.md"
  [ -f "$bundled_agents" ] || fail "the bundled source $bundled_agents is missing - this checkout looks incomplete. Re-run 'sh scripts/build.sh' from the repo root to regenerate it, then re-run this installer."
  if [ ! -f "$agents_file" ]; then
    {
      printf '%s\n' "$BEGIN_MARKER"
      cat "$bundled_agents"
      printf '%s\n' "$END_MARKER"
    } >"$out"
    return 0
  fi
  state=$(markers_state "$agents_file")
  case "$state" in
    none)
      # Guard against a real hazard of the fence-aware scan itself
      # (A1): if $agents_file's own trailing content is an
      # UNTERMINATED ``` / ~~~ fence, appending the real BEGIN/END
      # block below would place it INSIDE that fence - marker_scan
      # would then never see it either, on this run's own result or on
      # any later run, so a second install would append yet another
      # copy instead of updating it, and uninstall would find nothing
      # to remove. See
      # file_ends_inside_open_fence's own comment for the full
      # mechanics. Failing loudly here, before ever appending, keeps
      # this the user's problem to fix in their own file (close the
      # fence) rather than a squirrel-mode-created dead end.
      if [ "$(file_ends_inside_open_fence "$agents_file")" = "yes" ]; then
        fail "$agents_file ends inside an unterminated \`\`\` or ~~~ fenced code block (the fence is never closed before end of file). Appending squirrel-mode's block now would place it inside that same fence, where install could never find it again on a later run, and uninstall could never remove it. Close the fence (add a matching closing \`\`\`/~~~ line) in $agents_file, then re-run."
      fi
      # The separator is deliberately made ASYMMETRIC on whether
      # $agents_file already ended with a newline, checked BEFORE any
      # modification below - this is what keeps install and uninstall
      # able to tell the two cases apart later purely from the file's
      # OWN current content (see the extended note on
      # render_agents_uninstall below). If it already ended with \n,
      # one full blank line is inserted as the separator (the common,
      # ordinary case). If it did NOT, only the ONE newline needed to
      # terminate its dangling last line is added - no blank line - so
      # the line immediately before BEGIN is real content, never
      # blank, in this case specifically.
      already_had_trailing_newline=no
      if [ -s "$agents_file" ]; then
        last_byte=$(tail -c 1 "$agents_file" | od -An -tu1 | tr -d ' \n')
        [ "$last_byte" = "10" ] && already_had_trailing_newline=yes
      fi
      # F6: stream the CONTENT of $agents_file into <out>, never `cp`
      # it - <out> is a disposable staging file inside $work_dir, and
      # write_destination (the only thing that ever decides a real
      # destination's final mode) has not even been called yet at this
      # point. `cp "$agents_file" "$out"`, when <out> does not already
      # exist, copies $agents_file's OWN MODE onto <out> (verified
      # empirically - true regardless of umask), so a read-only (e.g.
      # chmod 444) AGENTS.md made <out> read-only too, and the `>>`
      # appends immediately below then died with a raw permission-denied
      # naming <out> - an internal $work_dir path the user never created
      # and this function's caller runs unconditionally, even on a dry
      # run with no --yes at all. `: >"$out"` creates a fresh, ordinarily
      # writable file (mode governed by THIS process's umask, exactly
      # like every other branch below that creates <out> via
      # redirection), and `cat >>"$out"` then only ever needs READ
      # access to $agents_file - already verified up front, before this
      # function is ever called (see the top-level readability guard
      # near codex_home_present above).
      : >"$out"
      cat "$agents_file" >>"$out"
      if [ "$already_had_trailing_newline" = "yes" ]; then
        printf '\n' >>"$out"
      else
        ensure_trailing_newline "$out"
      fi
      {
        printf '%s\n' "$BEGIN_MARKER"
        cat "$bundled_agents"
        printf '%s\n' "$END_MARKER"
      } >>"$out"
      ;;
    ok)
      # shellcheck disable=SC2046 # see markers_state above: two
      # space-separated integers, deliberately word-split.
      set -- $(find_marker_lines "$agents_file")
      b=$1
      e=$2
      before_n=$((b - 1))
      print_first_n_lines "$agents_file" "$before_n" >"$out"
      printf '%s\n' "$BEGIN_MARKER" >>"$out"
      cat "$bundled_agents" >>"$out"
      printf '%s\n' "$END_MARKER" >>"$out"
      tail -n +"$((e + 1))" "$agents_file" >>"$out"
      ;;
    corrupt)
      fail "$agents_file has a squirrel-mode marker in an unexpected shape (a duplicated or out-of-order BEGIN/END line, outside any fenced code block) - refusing to guess which part is which. Remove the '$BEGIN_MARKER' / '$END_MARKER' lines by hand and re-run."
      ;;
  esac
}

render_agents_uninstall() {
  # render_agents_uninstall <out>: writes what $agents_file should
  # contain with squirrel-mode's block removed into <out>, byte-exact
  # even when the original AGENTS.md had no trailing newline at all.
  # <out> being EMPTY afterwards means the block was the file's only
  # content - the Execution section below decides what to do with that
  # (see the empty-file handling note there: the file is truncated, not
  # deleted - A5).
  #
  # The line immediately before BEGIN (B-1) tells this function, from
  # the file's CURRENT content alone, which of render_agents_install's
  # two asymmetric separator shapes was used - no need to remember
  # which of CREATE/APPEND/REPLACE ever happened, or track any state
  # between runs of this script:
  #
  #   - B-1 is BLANK: the original content already ended with its own
  #     "\n", and this blank line is exactly the one-line separator
  #     render_agents_install added on top of it. Drop that one blank
  #     line; everything on lines 1..(B-2) is the original, unchanged,
  #     complete with its own trailing "\n" - printed normally.
  #   - B-1 is NOT blank (real content, or B-1 does not exist because
  #     the block sits at the very start of the file): the original
  #     had NO trailing newline of its own (render_agents_install used
  #     NO blank-line separator in that case - see its comment), and
  #     line B-1 IS the original's true last line. What becomes of the
  #     ONE newline render_agents_install added to terminate that
  #     dangling last line then depends on whether anything at all
  #     FOLLOWS the block in the file as it stands today:
  #       * nothing follows (the block really is at end of file): that
  #         newline is squirrel-mode's own addition and nothing else
  #         needs it, so it is stripped - via `$(...)`, safe
  #         specifically because head's own output never contains more
  #         than that one trailing newline to strip - restoring the
  #         original's bytes exactly, trailing-newline-less as they
  #         were.
  #       * something follows: the user has since written their own
  #         content BELOW the block, an entirely ordinary thing to do
  #         to a file they keep using. That newline is now the ONLY
  #         thing separating their last own line from their first line
  #         under the block, so stripping it JOINS TWO OF THEIR OWN
  #         LINES INTO ONE - silently, while this script prints
  #         "leaving the rest of the file byte-identical to before it
  #         was ever installed". `print_first_n_lines` (head) is used
  #         instead, which preserves the terminator of every line it
  #         prints. This branch used to treat "B-1 is not blank" as if
  #         it also implied "and therefore the block ends the file";
  #         nothing has ever enforced that, and merging two lines of a
  #         user's own instructions is what the unchecked assumption
  #         cost. Whether the block ends the file is now MEASURED, not
  #         assumed - see after_block below.
  out=$1
  # shellcheck disable=SC2046 # see markers_state above.
  set -- $(find_marker_lines "$agents_file")
  b=$1
  e=$2
  before_n=$((b - 1))
  line_before=""
  if [ "$before_n" -gt 0 ]; then
    line_before=$(sed -n "${before_n}p" "$agents_file")
  fi
  # Everything BELOW the END marker is materialised FIRST, because
  # whether it is empty is what decides how the content ABOVE the BEGIN
  # marker has to be terminated (third branch below). Written to a file
  # rather than captured into a variable for exactly the reason this
  # function never reads $agents_file into one either: command
  # substitution strips trailing newlines, which is the corruption this
  # whole function exists to avoid. The file lives beside <out> inside
  # the caller's $TMPDIR staging directory - never under $HOME - and is
  # removed as soon as it has been appended.
  after_block="$out.after"
  tail -n +"$((e + 1))" "$agents_file" >"$after_block"
  if [ "$before_n" -le 0 ]; then
    : >"$out"
  elif [ -z "$line_before" ]; then
    print_first_n_lines "$agents_file" "$((before_n - 1))" >"$out"
  elif [ -s "$after_block" ]; then
    print_first_n_lines "$agents_file" "$before_n" >"$out"
  else
    before_content=$(print_first_n_lines "$agents_file" "$before_n")
    printf '%s' "$before_content" >"$out"
  fi
  cat "$after_block" >>"$out"
  rm -f "$after_block"
}

# --- Execution ----------------------------------------------------------
#
# Ordering below is deliberate, to avoid two leak scenarios reviewed
# for: (1) if the lock mkdir fails because another run already holds
# it, this run must never remove THAT lock - lock_dir is only ever
# assigned AFTER this run's own mkdir succeeds, and the cleanup trap
# checks it is non-empty before touching anything; (2) if mktemp for
# work_dir fails right after a successful lock acquisition, the trap
# must already be installed so the just-acquired lock still gets
# released - the trap is installed before either the lock or work_dir
# is created, and cleanup_all tolerates both being empty.
lock_dir=""
work_dir=""
current_staging_path=""

cleanup_all() {
  if [ -n "$work_dir" ]; then
    rm -rf "$work_dir"
  fi
  if [ -n "$current_staging_path" ]; then
    rm -f "$current_staging_path"
  fi
  if [ -n "$lock_dir" ]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
trap cleanup_all EXIT
# POSIX sh does not reliably run an EXIT trap on a caught signal -
# explicit HUP/INT/TERM handlers are required to actually stop the
# script (matching scripts/build.sh's on_hup/on_int/on_term pattern):
# each one cleans up and then calls `exit` itself, with the conventional
# 128+signum status, rather than merely cleaning up and letting
# execution fall through to resume on the next statement as if nothing
# had interrupted it.
on_hup() {
  cleanup_all
  exit 129
}
on_int() {
  cleanup_all
  exit 130
}
on_term() {
  cleanup_all
  exit 143
}
trap on_hup HUP
trap on_int INT
trap on_term TERM

# --- Concurrency lock: mkdir is atomic on POSIX filesystems (flock is
# not portable to every target of this script), so two concurrent runs
# racing to mkdir the same path can never both "win" - exactly one
# proceeds, the other fails loudly here instead of racing the first
# one's markers_state-read-then-mv sequence and wedging AGENTS.md with
# a duplicated block.
#
# F1: only acquired when BOTH $codex_home exists AND this is a REAL
# write (do_write=yes). A dry run reads and prints a preview but writes
# nothing at all under $HOME (see the file header's DRY RUN BY DEFAULT
# note) - it needs no mutex, and taking one anyway had two real costs:
# two concurrent PREVIEWS would lock each other out for no reason, and a
# preview killed by SIGKILL (which cannot be trapped, unlike
# HUP/INT/TERM above) would wedge every future REAL install behind a
# lock the user has no way to know was ever taken by a run that wrote
# nothing.
#
# F5: `mkdir`'s own two failure modes are NOT the same problem and must
# not share one message. If the lock directory already exists, that
# really is contention - report it as such, as before. Any OTHER
# mkdir failure (most commonly EACCES: a read-only $codex_home) is NOT
# contention - nothing is running, nothing was created, and sending the
# user to remove a lock directory that never existed is actively
# misleading. mkdir's own stderr, captured via the `if var=$(...)`
# form (so `set -e` does not fire on the expected failure branch), is
# embedded verbatim rather than swallowed, so the underlying OS error is
# never hidden from a case this script's own guess does not cover.
if [ "$codex_home_present" = "yes" ] && [ "$do_write" = "yes" ]; then
  candidate_lock_dir="$codex_home/.squirrel-install.lock"
  if mkdir_output=$(mkdir "$candidate_lock_dir" 2>&1); then
    lock_dir="$candidate_lock_dir"
  elif [ -d "$candidate_lock_dir" ]; then
    fail "another squirrel-mode Codex install/uninstall appears to be running (lock directory exists at $candidate_lock_dir). If you are certain no other run is in progress - for example, a previous run crashed before cleaning up - remove that directory by hand and re-run."
  else
    fail "could not create the lock directory at $candidate_lock_dir - mkdir reported: $mkdir_output. Its parent directory ($codex_home) may not be writable; check its permissions and re-run."
  fi
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-codex-install.XXXXXX")

agents_tmp="$work_dir/AGENTS.md.new"

if [ "$codex_home_present" = "yes" ]; then
  if [ "$action" = "install" ]; then
    render_agents_install "$agents_tmp"
    if [ -f "$agents_file" ] && cmp -s "$agents_tmp" "$agents_file"; then
      echo "$agents_file already has an up-to-date squirrel-mode block - nothing to do."
    else
      if [ ! -f "$agents_file" ]; then
        echo "Would create $agents_file with a new squirrel-mode block (no existing file found)."
      elif [ "$(markers_state "$agents_file")" = "ok" ]; then
        echo "Would update the existing squirrel-mode block inside $agents_file (everything outside the block is preserved unchanged)."
      else
        echo "Would append a new squirrel-mode block to the end of $agents_file (your existing content there is kept, byte-for-byte, above the block)."
        # F7: markers_state's "none" here can mean either "no BEGIN/END
        # at all" or "the only BEGIN/END-shaped lines are inside a
        # fenced code block, correctly ignored" - the latter is easy for
        # a user to mistake for a bug when they can plainly see a
        # BEGIN/END-looking block in their own file. Say so explicitly
        # when marker_scan actually found one, rather than silently
        # treating it exactly like "no block at all".
        if [ "$(marker_lines_in_fence "$agents_file")" = "yes" ]; then
          echo "(Note: $agents_file contains a BEGIN/END SQUIRREL-MODE-shaped line inside a fenced code block - correctly treated as an example, not the real block, and left untouched.)"
        fi
      fi
      if [ "$do_write" = "yes" ]; then
        mkdir -p "$codex_home"
        write_destination "$agents_file" "$agents_tmp"
        echo "Installed: $agents_file"
      fi
    fi
  else
    state=$(markers_state "$agents_file")
    case "$state" in
      none)
        echo "$agents_file has no squirrel-mode block - nothing to uninstall there."
        # F7: same fence-awareness note as install's "would append"
        # message above - install already explained this case; uninstall
        # used to say nothing about it at all for the identical file.
        if [ "$(marker_lines_in_fence "$agents_file")" = "yes" ]; then
          echo "(Note: $agents_file contains a BEGIN/END SQUIRREL-MODE-shaped line inside a fenced code block - correctly treated as an example, not a real block, so there is nothing to uninstall there.)"
        fi
        ;;
      corrupt)
        fail "$agents_file has a squirrel-mode marker in an unexpected shape - refusing to guess. Remove the '$BEGIN_MARKER' / '$END_MARKER' lines by hand."
        ;;
      ok)
        render_agents_uninstall "$agents_tmp"
        if [ -s "$agents_tmp" ]; then
          echo "Would remove the squirrel-mode block from $agents_file, leaving the rest of the file byte-identical to before it was ever installed."
          if [ "$do_write" = "yes" ]; then
            write_destination "$agents_file" "$agents_tmp"
            echo "Uninstalled: squirrel-mode block removed from $agents_file"
          fi
        else
          # A5: the computed remainder is empty - the squirrel-mode
          # block was $agents_file's only content. Install cannot tell
          # "the user had an empty AGENTS.md before we ever touched it"
          # apart from "we ourselves created this file" - both look
          # identical by the time uninstall runs. Deleting is the wrong
          # default for that ambiguity: it is a user-visible path under
          # $HOME, and the fail-safe direction is to never delete a
          # file we are not certain we created ourselves. Truncating to
          # 0 bytes (via write_destination, which also preserves
          # whatever mode the file already had) leaves exactly as much
          # as install could have safely assumed, and says so plainly.
          echo "Would leave $agents_file empty (0 bytes) rather than delete it - the squirrel-mode block was its only content, but this script cannot tell a file you created empty yourself apart from one it created, so the safe default is to never delete a user-visible file under \$HOME that it is not certain it created."
          if [ "$do_write" = "yes" ]; then
            write_destination "$agents_file" "$agents_tmp"
            echo "Uninstalled: squirrel-mode block removed from $agents_file. The file is now empty (0 bytes) and was intentionally left in place, not deleted - remove it by hand if you don't want it."
          fi
        fi
        ;;
    esac
  fi
else
  echo "$agents_file does not exist ($codex_home not found) - nothing to uninstall there."
fi

# --- The four ported skills: ~/.agents/skills/<name>/SKILL.md ----------

for cmd_name in digest plan init tune; do
  src="$repo_root/targets/codex/skills/$cmd_name/SKILL.md"
  dest="$agents_skills_dir/$cmd_name/SKILL.md"
  [ -f "$src" ] || continue

  # G1: re-validated here, immediately before this path's own
  # read/write work, as a narrow TOCTOU guard - the pre-flight pass
  # above already checked this exact path, but earlier iterations of
  # this same loop (and, for AGENTS.md, the read/render/write work
  # above it) have since done real filesystem I/O, so a symlink or a
  # directory could in principle have been swapped into place at $dest
  # in between. Calls the SAME validate_destination used in the
  # pre-flight pass - never a second, divergent copy of either rule -
  # so the two checks can never disagree about what they refuse.
  validate_destination "$dest" "\$HOME/.agents/skills/$cmd_name/SKILL.md"

  expected_banner=$(banner_line_for "$src")
  kind=$(classify_dedicated_file "$dest" "$expected_banner")

  if [ "$action" = "install" ]; then
    case "$kind" in
      foreign)
        echo "Skipping $dest: a file already exists there that is not a squirrel-mode file. Remove it by hand first if you want squirrel-mode's $cmd_name skill installed."
        ;;
      absent)
        echo "Would create $dest"
        if [ "$do_write" = "yes" ]; then
          mkdir -p "$agents_skills_dir/$cmd_name"
          write_destination "$dest" "$src"
          echo "Installed: $dest"
        fi
        ;;
      ours)
        if cmp -s "$src" "$dest"; then
          echo "$dest already up to date - nothing to do."
        else
          echo "Would update $dest"
          if [ "$do_write" = "yes" ]; then
            write_destination "$dest" "$src"
            echo "Updated: $dest"
          fi
        fi
        ;;
    esac
  else
    case "$kind" in
      ours)
        echo "Would remove $dest"
        if [ "$do_write" = "yes" ]; then
          rm -f "$dest"
          rmdir "$agents_skills_dir/$cmd_name" 2>/dev/null || true
          echo "Uninstalled: removed $dest"
        fi
        ;;
      foreign)
        echo "Not removing $dest: it is not a squirrel-mode file."
        ;;
      absent)
        echo "$dest does not exist - nothing to uninstall there."
        ;;
    esac
  fi
done

if [ "$action" = "uninstall" ] && [ "$do_write" = "yes" ]; then
  rmdir "$agents_skills_dir" 2>/dev/null || true
fi

if [ "$do_write" = "no" ]; then
  echo ""
  echo "This was a dry run. Nothing was written. Re-run with --yes to apply the changes above."
fi
