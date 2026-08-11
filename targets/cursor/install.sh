#!/bin/sh
# install.sh - installs squirrel-mode's Cursor artifacts into the
# user's home directory. The only things it creates or modifies are
# under $HOME:
#
#   1. ~/.cursor/rules/squirrel-mode.mdc - a copy of
#      targets/cursor/squirrel-mode.mdc next to this script. This is a
#      squirrel-mode-owned file at a squirrel-mode-owned path (Cursor's
#      rules directory holds one file per independent rule, unlike
#      Codex's single shared AGENTS.md, so there is no "merge into a
#      shared file" step here at all). Ownership of an existing file at
#      that exact path is decided by an EXACT, FULL-LINE match against
#      this specific artifact's own GENERATED FILE banner line - read
#      fresh from the bundled source file next to this script, never
#      hardcoded (see banner_line_for/classify_dedicated_file below),
#      so a future change to scripts/build.sh's banner format cannot
#      desynchronise this installer from what it is actually comparing
#      against. A file that merely CONTAINS the substring "<!--
#      GENERATED FILE. Source:" somewhere - e.g. a user's own rule that
#      quotes squirrel-mode's own docs - is foreign, not ours, and is
#      never overwritten on install or removed on uninstall. The
#      asymmetry is deliberate: a false "foreign" verdict only ever
#      skips an install (safe, and reported in one line); a false
#      "ours" verdict would destroy user data on the next uninstall.
#      Every check here is biased toward "foreign" whenever there is
#      any doubt.
#   2. ~/.cursor/.squirrel-install.lock - a mutex directory, created
#      immediately before any read-then-write work begins and held for
#      the rest of this run - released by the EXIT trap on every exit
#      path, including a failure or a caught signal (see CONCURRENCY
#      below), never the instant that work ends. Created ONLY during a
#      real write (--yes) - a dry run never touches it; see
#      DRY RUN BY DEFAULT below.
#
# It also uses a short-lived, self-cleaning staging directory under
# $TMPDIR on every invocation, including a dry run (mktemp -d, removed
# on every exit path, including a caught signal - see the cleanup trap
# below). That directory is never under $HOME and is not one of the
# two items enumerated above.
#
# SYMLINK REFUSAL: if ~/.cursor/rules/squirrel-mode.mdc is itself a
# symlink, this script REFUSES (fails loudly, changes nothing) instead
# of writing through it - on both install and uninstall. See
# targets/codex/install.sh's identical header note (SYMLINK REFUSAL)
# for the full rationale (a symlink at the exact managed path is never
# legitimate for this script's own atomic-rename write to pass through
# - scripts/allow-checkpoint.sh and ADR-0002 reject the same thing at
# their own artifact path) - fail_if_symlink below.
#
# Cursor's COMMANDS (digest.md, plan.md) are NOT installed anywhere by
# this script. Cursor loads commands from a PROJECT-scoped
# .cursor/commands/*.md directory (ADR-0004; PLAN.md's verified host
# paths) - there is no user-level equivalent. Writing them into some
# project on this machine would mean guessing which project, and this
# script only ever touches paths under $HOME. Instead, it prints the
# two source files' paths and the one-line instruction for copying them
# into a specific project when the user wants /digest or /plan there.
#
# DRY RUN BY DEFAULT: with no flags, this script prints exactly what it
# WOULD change and writes nothing under $HOME - not even the lock
# directory in item 2 above. Pass --yes to actually write - see
# targets/codex/install.sh's header comment for the full reasoning
# (no guaranteed TTY on stdin, so a flag beats an interactive prompt).
#
# IDEMPOTENT: the new content is rendered into a temp file and compared
# byte for byte against what is already on disk before anything is
# written. Running this script twice (with --yes both times) changes
# the filesystem only on the first run.
#
# CONCURRENCY: a second install.sh (any action) started with --yes
# while one is already writing against the same $HOME fails loudly with
# a clear message instead of racing the first one's read-then-write
# sequence - see the mkdir-based lock acquired below. Only acquired for
# a REAL write (--yes) - a dry run changes nothing, so it needs no
# mutex and never acquires the lock.
#
# UNINSTALL: pass --uninstall (with --yes to act on it) to remove
# ~/.cursor/rules/squirrel-mode.mdc, if and only if it is squirrel-mode's
# own file.
#
# POSIX sh, no network calls, no telemetry, never touches a file it
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

GENERATED_TAG="<!-- GENERATED FILE. Source:"

fail() {
  echo "install.sh: ERROR: $1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: targets/cursor/install.sh [--yes] [--uninstall] [--help]

Installs squirrel-mode's Cursor artifacts:
  - ~/.cursor/rules/squirrel-mode.mdc (the always-on base rules)

Cursor's /digest and /plan commands are project-scoped and are NOT
installed by this script - it prints where to find them and how to
add them to a specific project instead (see below).

With no flags, this is a DRY RUN: it prints exactly what would change
and writes nothing.

  --yes         Perform the install (or, with --uninstall, the
                uninstall) for real. Without this flag, nothing is
                ever written.
  --uninstall   Remove squirrel-mode.mdc, instead of installing it.
  --help        Show this message and exit.

The only things this script creates or modifies are under $HOME -
which includes a short-lived lock directory,
~/.cursor/.squirrel-install.lock, created and removed only during a
real --yes write (a dry run never creates it). It also uses a
short-lived, self-cleaning staging directory under $TMPDIR on every
invocation, including a dry run. It never writes inside a project
repository, makes no network calls, and sends no telemetry. A
destination that is itself a symlink is refused, not written through -
see this script's own header comment (SYMLINK REFUSAL).
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

cursor_home="$home_dir/.cursor"
rules_dir="$cursor_home/rules"
rule_file="$rules_dir/squirrel-mode.mdc"
source_rule_file="$repo_root/targets/cursor/squirrel-mode.mdc"
source_commands_dir="$repo_root/targets/cursor/commands"

# --- Host detection --------------------------------------------------
#
# ~/.cursor existing is this script's signal that Cursor has been RUN
# at least once on this machine - not that it is installed, which this
# check cannot tell apart: Cursor creates that directory on first run,
# so an installed-but-never-opened Cursor looks identical to an absent
# one here, and the message below names only the condition the check
# can actually distinguish. Its absence is reported, not treated as a
# failure: exit 0, do nothing. Because this gate covers uninstall too
# (see below), the message covers both actions.
# Unlike Codex, Cursor has nothing this script
# manages OUTSIDE ~/.cursor (there is no separate skills tree the way
# Codex has ~/.agents/skills/), so - unlike targets/codex/install.sh -
# this gate applies identically to both install and uninstall: there is
# never anything left to strand.
if [ ! -d "$cursor_home" ]; then
  echo "Cursor home directory not found at $cursor_home - Cursor creates that directory the first time it runs, so it has not been run on this machine yet (installing Cursor is not enough on its own). There is nothing here to install into, and nothing to uninstall; if you are installing, open Cursor once, then re-run this script."
  exit 0
fi

fail_if_symlink() {
  # fail_if_symlink <path> <description>: see
  # targets/codex/install.sh's identical helper for the full rationale
  # (a symlink AT the exact managed path is never legitimate for this
  # script's own atomic-rename `mv` to pass through - ADR-0002 and
  # scripts/allow-checkpoint.sh reject the same thing at their own
  # artifact path; only <path> itself is checked, never an ancestor
  # directory, since a symlinked ~/.cursor/rules is a legitimate
  # dotfiles setup; `[ -L ]` runs before any `[ -e ]`-gated check so a
  # dangling symlink is still caught).
  path=$1
  desc=$2
  if [ -L "$path" ]; then
    fail "$desc ($path) is a symlink - squirrel-mode replaces a destination atomically by rename, which would sever the link rather than write through it, leaving whatever it points to stale forever with no warning. Remove the symlink and let squirrel-mode create a real file there, or point it at the real file's own path directly, then re-run."
  fi
}

validate_destination() {
  # validate_destination <path> <description>: EVERY destination-refusal
  # condition that must hold BEFORE this script writes anything at all,
  # for a single managed path, expressed exactly ONCE - see
  # targets/codex/install.sh's identical helper (G1, S7 review cycle 3)
  # for the full rationale. Cursor manages only one destination
  # (squirrel-mode.mdc), so there is no loop to diverge from here the
  # way Codex's four skill paths could, but the helper is still
  # factored out identically: a future third pre-flight condition is
  # added HERE, in this one function, never duplicated inline again at
  # this call site.
  path=$1
  desc=$2
  fail_if_symlink "$path" "$desc"
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    fail "$desc ($path) exists but is not a regular file (a directory or other special file is there instead) - refusing to touch it. Remove or rename it by hand, then re-run."
  fi
}

validate_destination "$rule_file" "\$HOME/.cursor/rules/squirrel-mode.mdc"

# F6 class-closure (see targets/codex/install.sh's identical guard's
# comment near codex_home_present for the full rationale): a
# pre-existing squirrel-mode.mdc this script cannot READ must fail
# loudly, at the top level, naming the REAL path - never surface a raw
# permission-denied error from deep inside classify_dedicated_file or
# write_destination naming an internal staging path instead.
if [ -f "$rule_file" ] && [ ! -r "$rule_file" ]; then
  fail "$rule_file exists but is not readable (permission denied) - squirrel-mode needs to read its current content before it can decide whether it owns it. Fix its permissions (e.g. chmod u+r $rule_file) and re-run."
fi

[ -f "$source_rule_file" ] || fail "the bundled source $source_rule_file is missing - this checkout looks incomplete. Re-run 'sh scripts/build.sh' from the repo root to regenerate it, then re-run this installer."

banner_line_for() {
  # banner_line_for <source_path>: prints the exact, full GENERATED
  # FILE banner line as it CURRENTLY appears in <source_path> - see
  # targets/codex/install.sh's identical helper for the full rationale
  # (derived fresh from the bundled source, never hardcoded, so a
  # future change to scripts/build.sh's banner format cannot
  # desynchronise this installer). A missing banner line is a loud
  # failure, never "assume ours".
  source_path=$1
  line=$(grep -m1 -F "$GENERATED_TAG" "$source_path" 2>/dev/null || true)
  [ -n "$line" ] || fail "could not find a '$GENERATED_TAG' banner line inside $source_path - this installer cannot tell its own files apart from foreign ones without it. Re-run 'sh scripts/build.sh' from the repo root to regenerate it, then re-run this installer."
  printf '%s\n' "$line"
}

classify_dedicated_file() {
  # classify_dedicated_file <path> <expected_banner_line>: prints one of
  # absent | ours | foreign - see targets/codex/install.sh's identical
  # helper for the full rationale (exact FULL-LINE match against the
  # artifact-specific banner, never a bare substring search - a foreign
  # file that merely contains "<!-- GENERATED FILE. Source:" somewhere
  # must classify as foreign, not ours). Duplicated rather than shared
  # from a common lib on purpose: each installer stays independently
  # readable and runnable without assuming the other exists.
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
  # <destination>'s content with <content_file>'s content, preserving
  # <destination>'s current file MODE across the replacement when it
  # already exists - see targets/codex/install.sh's identical helper
  # for the full rationale (cp-then-redirect, never `chmod --reference`
  # or a `stat` format flag, neither of which is portable). Also tracks
  # the global current_staging_path so a signal mid-write leaves
  # nothing behind - see the cleanup trap below.
  #
  # F6 class-closure: if <destination> exists but is not writable, fail
  # loudly HERE (naming the real path) instead of letting the
  # cp-then-redirect trick below crash with a raw permission-denied
  # naming $temp - an internal staging path - see
  # targets/codex/install.sh's identical guard for the full mechanics.
  # Checked inside the function, not hoisted above it, so a call that
  # never needed to write (content already matches) still exits 0.
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
    # G3: see targets/codex/install.sh's identical branch for the full
    # rationale - `: >"$temp"` creates an EMPTY file first and
    # `chmod go-w` clamps its mode immediately, before a single byte of
    # real content exists there, closing the TOCTOU window the previous
    # `cp "$content_file" "$temp"` (mode AND full content in one step,
    # clamped only afterwards) left open: under umask 000 that used to
    # leave $temp sitting at 666, world-writable, while it already held
    # squirrel-mode's real content. Clamping (never SETTING) leaves a
    # stricter umask's own result (e.g. 600) completely alone.
    : >"$temp"
    chmod go-w "$temp"
    cat "$content_file" >"$temp"
  fi
  mv "$temp" "$destination"
  current_staging_path=""
}

# --- Execution ----------------------------------------------------------
#
# Ordering below mirrors targets/codex/install.sh's: the cleanup trap is
# installed before the lock is acquired and before work_dir is created,
# so a failure at either step (lock contention, or a failed mktemp right
# after a successful lock) still releases whatever was actually
# acquired and nothing more - see that script's Execution-section
# comment for the two leak scenarios this ordering avoids.
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
# script (matching scripts/build.sh's on_hup/on_int/on_term pattern).
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
# one's classify-then-write sequence.
#
# F1: only acquired for a REAL write (do_write=yes) - see
# targets/codex/install.sh's identical guard for the full rationale (a
# dry run writes nothing under $HOME, so it needs no mutex; taking one
# anyway let two concurrent previews lock each other out, and a
# SIGKILLed preview - untrappable, unlike HUP/INT/TERM - would wedge
# every future real install behind a lock nothing real ever held).
#
# F5: `mkdir`'s own two failure modes are different problems - see
# targets/codex/install.sh's identical guard for the full rationale.
# Existing lock directory = genuine contention, reported as before. Any
# OTHER mkdir failure (most commonly EACCES on a read-only
# $cursor_home) is NOT contention and must say so, with mkdir's own
# stderr embedded rather than swallowed.
if [ "$do_write" = "yes" ]; then
  candidate_lock_dir="$cursor_home/.squirrel-install.lock"
  if mkdir_output=$(mkdir "$candidate_lock_dir" 2>&1); then
    lock_dir="$candidate_lock_dir"
  elif [ -d "$candidate_lock_dir" ]; then
    fail "another squirrel-mode Cursor install/uninstall appears to be running (lock directory exists at $candidate_lock_dir). If you are certain no other run is in progress - for example, a previous run crashed before cleaning up - remove that directory by hand and re-run."
  else
    fail "could not create the lock directory at $candidate_lock_dir - mkdir reported: $mkdir_output. Its parent directory ($cursor_home) may not be writable; check its permissions and re-run."
  fi
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-cursor-install.XXXXXX")

expected_banner=$(banner_line_for "$source_rule_file")

if [ "$action" = "install" ]; then
  kind=$(classify_dedicated_file "$rule_file" "$expected_banner")
  case "$kind" in
    foreign)
      echo "Skipping $rule_file: a file already exists there that is not a squirrel-mode file. Remove it by hand first if you want squirrel-mode's rules installed."
      ;;
    absent)
      echo "Would create $rule_file"
      if [ "$do_write" = "yes" ]; then
        mkdir -p "$rules_dir"
        write_destination "$rule_file" "$source_rule_file"
        echo "Installed: $rule_file"
      fi
      ;;
    ours)
      if cmp -s "$source_rule_file" "$rule_file"; then
        echo "$rule_file already up to date - nothing to do."
      else
        echo "Would update $rule_file"
        if [ "$do_write" = "yes" ]; then
          write_destination "$rule_file" "$source_rule_file"
          echo "Updated: $rule_file"
        fi
      fi
      ;;
  esac

  echo ""
  echo "Cursor commands are project-scoped - there is nowhere under \$HOME to install /digest and /plan once for every project. To add them to a specific project, copy these two files into that project's .cursor/commands/ directory:"
  echo "  $source_commands_dir/digest.md"
  echo "  $source_commands_dir/plan.md"
else
  kind=$(classify_dedicated_file "$rule_file" "$expected_banner")
  case "$kind" in
    ours)
      echo "Would remove $rule_file"
      if [ "$do_write" = "yes" ]; then
        rm -f "$rule_file"
        rmdir "$rules_dir" 2>/dev/null || true
        echo "Uninstalled: removed $rule_file"
      fi
      ;;
    foreign)
      echo "Not removing $rule_file: it is not a squirrel-mode file."
      ;;
    absent)
      echo "$rule_file does not exist - nothing to uninstall there."
      ;;
  esac
fi

if [ "$do_write" = "no" ]; then
  echo ""
  echo "This was a dry run. Nothing was written. Re-run with --yes to apply the changes above."
fi
