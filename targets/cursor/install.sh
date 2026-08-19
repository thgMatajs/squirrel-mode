#!/bin/sh
# install.sh - installs squirrel-mode's Cursor plugin subset into the
# user's home directory. The only things it creates or modifies are
# under $HOME:
#
#   1. ~/.cursor/plugins/local/squirrel-mode/ - a repo-shaped COPY (never
#      a symlink) of the Cursor plugin subset, so .cursor-plugin/plugin.json
#      relative paths (targets/cursor/squirrel-mode.mdc, targets/cursor/
#      skills/, hooks.json, "${CURSOR_PLUGIN_ROOT}"/scripts/...) resolve.
#      Subset: .cursor-plugin/plugin.json, the four scripts
#      load-profile/check-off-flag/allow-checkpoint/hoard-search.sh, and
#      every regular file under targets/cursor/. Copying only .mdc + two
#      skills into ~/.cursor/skills/ would duplicate slash commands when
#      the plugin loads; this script no longer writes that old layout as
#      the payload. Ownership of an existing file at an allowlisted dest
#      is decided as follows. Generated files (those whose bundled source
#      carries a GENERATED FILE banner): an EXACT, FULL-LINE match against
#      that artifact's own banner line - read fresh from the bundled
#      source, never hardcoded (see banner_line_for/classify_dedicated_file
#      below). Files with no banner (plugin.json, the four scripts,
#      install.sh, hooks.json): ours iff byte-identical to the bundled
#      file; otherwise foreign. A file that merely CONTAINS the substring
#      "<!-- GENERATED FILE. Source:" somewhere is foreign, not ours, and
#      is never overwritten on install or removed on uninstall. Every
#      check here is biased toward "foreign" whenever there is any doubt.
#   2. On install AND uninstall, leftover old-layout files at
#      ~/.cursor/rules/squirrel-mode.mdc and
#      ~/.cursor/skills/squirrel-*/SKILL.md are removed IFF they classify
#      as ours (exact-full-line banner). A foreign leftover at those paths
#      is left alone and does NOT fail the new plugin install.
#   3. ~/.cursor/.squirrel-install.lock - a mutex directory, created
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
# items enumerated above.
#
# SYMLINK REFUSAL: if any managed plugin destination is itself a
# symlink, this script REFUSES (fails loudly, changes nothing) instead
# of writing through it, on both install and uninstall. See
# targets/codex/install.sh's identical header note (SYMLINK REFUSAL)
# for the full rationale - fail_if_symlink below. After a successful
# --yes, installed files are regular files and byte-identical to the
# bundled sources.
#
#   4. Cursor's project-scoped COMMANDS (digest.md, plan.md) are NOT
#      installed into a project by this script. Every install run still
#      prints the two command files' paths, for a user who wants /digest
#      and /plan as project commands in one specific repository as well.
#
# DRY RUN BY DEFAULT: with no flags, this script prints exactly what it
# WOULD change and writes nothing under $HOME - not even the lock
# directory in item 3 above. Pass --yes to actually write - see
# targets/codex/install.sh's header comment for the full reasoning
# (no guaranteed TTY on stdin, so a flag beats an interactive prompt).
#
# IDEMPOTENT: the new content is compared byte for byte against what is
# already on disk before anything is written. Running this script twice
# (with --yes both times) changes the filesystem only on the first run.
#
# CONCURRENCY: a second install.sh (any action) started with --yes
# while one is already writing against the same $HOME fails loudly with
# a clear message instead of racing the first one's read-then-write
# sequence - see the mkdir-based lock acquired below. Only acquired for
# a REAL write (--yes) - a dry run changes nothing, so it needs no
# mutex and never acquires the lock.
#
# UNINSTALL: pass --uninstall (with --yes to act on it) to remove only
# the allowlisted relative paths under the plugin copy when classified
# ours; then rmdir empty parents (squirrel-mode, plugins/local) only
# when empty. Never remove ~/.cursor, ~/.cursor/plugins, or a sibling
# plugin. Also removes ~/.cursor/rules/squirrel-profile.mdc if it
# carries the frozen projection banner as an exact full line (hooks
# write that file; this installer does not). Uninstall never rm -rf's
# the plugin dir.
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
# Frozen: same string as CURSOR_PROFILE_PROJECTION_BANNER in
# scripts/load-profile.sh. Do not derive it from that file (it may be
# missing). Exact-full-line match only.
CURSOR_PROFILE_PROJECTION_BANNER='<!-- GENERATED FILE. Source: ~/.squirrel/profile.md (squirrel-profile projection) -->'

fail() {
  echo "install.sh: ERROR: $1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: targets/cursor/install.sh [--yes] [--uninstall] [--help]

Installs squirrel-mode's Cursor plugin subset as a local copy at
~/.cursor/plugins/local/squirrel-mode (repo-shaped: .cursor-plugin/
plugin.json, scripts/, and targets/cursor/). After a real install,
reload the Cursor window (Reload Window). GitHub shortcut:
/add-plugin https://github.com/thgMatajs/squirrel-mode (pins a commit;
the local copy is the stable path).

Cursor's PROJECT-scoped /digest and /plan commands are a separate
mechanism and are NOT installed by this script - it prints where to
find them and how to add them to one specific project instead (see
below).

With no flags, this is a DRY RUN: it prints exactly what would change
and writes nothing.

  --yes         Perform the install (or, with --uninstall, the
                uninstall) for real. Without this flag, nothing is
                ever written.
  --uninstall   Remove the local plugin copy (allowlisted paths that
                classify as ours), old-layout leftovers that classify
                as ours, and the profile projection if it is ours,
                instead of installing.
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
plugin_root="$cursor_home/plugins/local/squirrel-mode"
source_commands_dir="$repo_root/targets/cursor/commands"
old_layout_rule="$cursor_home/rules/squirrel-mode.mdc"
old_layout_skills_dir="$cursor_home/skills"
projection_file="$cursor_home/rules/squirrel-profile.mdc"
# Derived from the on-disk skill folders rather than a hardcoded name
# list: a literal `squirrel-dig` token is a false NETWORK_COMMAND_REGEX
# hit (`grep -w` treats `-` as a word boundary, so the suffix matches
# `dig`).
old_layout_skill_folders=""
for skill_dir in "$repo_root/targets/cursor/skills"/*; do
  [ -d "$skill_dir" ] || continue
  old_layout_skill_folders="$old_layout_skill_folders $(basename "$skill_dir")"
done
old_layout_skill_folders=${old_layout_skill_folders# }

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
# Unlike Codex, Cursor has nothing this script manages OUTSIDE
# ~/.cursor: the plugin copy lives at ~/.cursor/plugins/local/, INSIDE
# this very directory. So this gate applies identically to both install
# and uninstall: if ~/.cursor is gone, every path this script could
# clean went with it, and there is never anything left to strand.
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
  # directory, since a symlinked ~/.cursor/plugins is a legitimate
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
  # for the full rationale.
  path=$1
  desc=$2
  fail_if_symlink "$path" "$desc"
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    fail "$desc ($path) exists but is not a regular file (a directory or other special file is there instead) - refusing to touch it. Remove or rename it by hand, then re-run."
  fi
}

list_plugin_rel_paths() {
  # Allowlisted repo-root-relative paths that make up the Cursor plugin
  # subset. Order is load-bearing for pre-flight: plugin.json is first
  # so a refusal at a later dest cannot have already written it.
  printf '%s\n' \
    ".cursor-plugin/plugin.json" \
    "scripts/load-profile.sh" \
    "scripts/check-off-flag.sh" \
    "scripts/allow-checkpoint.sh" \
    "scripts/hoard-search.sh"
  (cd "$repo_root" && find targets/cursor -type f ! -name '.*' | LC_ALL=C sort)
}

plugin_rel_paths=$(list_plugin_rel_paths)
[ -n "$plugin_rel_paths" ] || fail "could not enumerate the Cursor plugin subset under $repo_root - this checkout looks incomplete."

# PRE-FLIGHT, for EVERY managed plugin destination path, for BOTH
# install and uninstall, before this script writes anything whatsoever
# - not even the lock directory or the $TMPDIR staging directory have
# been created yet. A symlink or a directory sitting at a later path
# must refuse before an earlier path has already been written.
while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  src="$repo_root/$rel"
  [ -f "$src" ] || fail "the bundled source $src is missing - this checkout looks incomplete. Re-run 'sh scripts/build.sh' from the repo root to regenerate generated files, then re-run this installer."
  dest="$plugin_root/$rel"
  validate_destination "$dest" "\$HOME/.cursor/plugins/local/squirrel-mode/$rel"
  if [ -f "$dest" ] && [ ! -r "$dest" ]; then
    fail "$dest exists but is not readable (permission denied) - squirrel-mode needs to read its current content before it can decide whether it owns it. Fix its permissions (e.g. chmod u+r $dest) and re-run."
  fi
done <<EOF
$plugin_rel_paths
EOF

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

classify_plugin_file() {
  # classify_plugin_file <path> <source_path>: absent | ours | foreign.
  # Generated sources (banner present): exact-full-line banner match.
  # Sources with no banner: ours iff byte-identical to the bundled file.
  path=$1
  source_path=$2
  [ -f "$path" ] || { printf 'absent\n'; return 0; }
  if grep -q -F "$GENERATED_TAG" "$source_path" 2>/dev/null; then
    expected=$(banner_line_for "$source_path")
    classify_dedicated_file "$path" "$expected"
  elif cmp -s "$source_path" "$path"; then
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

removed_own_plugin_file=no
removed_old_layout_skill=no
removed_from_rules=no

install_or_remove_plugin_file() {
  # install_or_remove_plugin_file <rel>: one allowlisted dest, using the
  # same validate/classify/write helpers as the rest of this script.
  rel=$1
  src="$repo_root/$rel"
  dest="$plugin_root/$rel"

  validate_destination "$dest" "\$HOME/.cursor/plugins/local/squirrel-mode/$rel"
  kind=$(classify_plugin_file "$dest" "$src")

  if [ "$action" = "install" ]; then
    case "$kind" in
      foreign)
        echo "Skipping $dest: a file already exists there that is not a squirrel-mode file. Remove it by hand first if you want squirrel-mode's copy installed."
        ;;
      absent)
        echo "Would create $dest"
        if [ "$do_write" = "yes" ]; then
          mkdir -p "$(dirname "$dest")"
          write_destination "$dest" "$src"
          if [ -x "$src" ]; then
            chmod +x "$dest"
          fi
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
            if [ -x "$src" ]; then
              chmod +x "$dest"
            fi
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
          removed_own_plugin_file=yes
          rmdir "$(dirname "$dest")" 2>/dev/null || true
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
}

while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  install_or_remove_plugin_file "$rel"
done <<EOF
$plugin_rel_paths
EOF

# Empty-parent cleanup for the plugin copy: rmdir only, never rm -rf,
# and only after this run actually removed one of our files. Walk
# remaining empty dirs under plugin_root deepest-first, then plugin_root
# itself, then plugins/local. Never rmdir ~/.cursor/plugins or ~/.cursor.
if [ "$action" = "uninstall" ] && [ "$do_write" = "yes" ] && [ "$removed_own_plugin_file" = "yes" ]; then
  if [ -d "$plugin_root" ]; then
    # POSIX: -depth visits children before parents so a now-empty
    # targets/cursor/skills/<name> is removed before skills/.
    find "$plugin_root" -depth -type d -exec rmdir {} \; 2>/dev/null || true
  fi
  rmdir "$plugin_root" 2>/dev/null || true
  rmdir "$cursor_home/plugins/local" 2>/dev/null || true
fi

# --- Old-layout leftovers: ~/.cursor/rules/squirrel-mode.mdc and
# ~/.cursor/skills/squirrel-*/SKILL.md. Removed on install AND uninstall
# when classified ours. Foreign leftovers survive and do not fail the
# plugin copy. A symlink or directory at an old-layout path is left
# alone (bias toward foreign) rather than failing the new install.
clean_old_layout_file() {
  dest=$1
  src=$2
  if [ -L "$dest" ]; then
    return 0
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    return 0
  fi
  [ -f "$dest" ] || return 0
  if [ ! -r "$dest" ]; then
    return 0
  fi
  kind=$(classify_plugin_file "$dest" "$src")
  if [ "$kind" != "ours" ]; then
    return 0
  fi
  echo "Would remove $dest (old-layout leftover)"
  if [ "$do_write" = "yes" ]; then
    rm -f "$dest"
    echo "Removed old-layout leftover: $dest"
    parent=$(dirname "$dest")
    rmdir "$parent" 2>/dev/null || true
    case "$dest" in
      */.cursor/skills/*)
        removed_old_layout_skill=yes
        ;;
      */.cursor/rules/squirrel-mode.mdc)
        removed_from_rules=yes
        ;;
    esac
  fi
}

clean_old_layout_file "$old_layout_rule" "$repo_root/targets/cursor/squirrel-mode.mdc"
for folder in $old_layout_skill_folders; do
  clean_old_layout_file "$old_layout_skills_dir/$folder/SKILL.md" "$repo_root/targets/cursor/skills/$folder/SKILL.md"
done
if [ "$do_write" = "yes" ] && [ "$removed_old_layout_skill" = "yes" ]; then
  rmdir "$old_layout_skills_dir" 2>/dev/null || true
fi

# Projection: hooks write ~/.cursor/rules/squirrel-profile.mdc. This
# installer never writes it. Uninstall removes it only when the frozen
# banner is an exact full line.
if [ "$action" = "uninstall" ]; then
  if [ -L "$projection_file" ]; then
    :
  elif [ -f "$projection_file" ]; then
    if grep -qFx -- "$CURSOR_PROFILE_PROJECTION_BANNER" "$projection_file" 2>/dev/null; then
      echo "Would remove $projection_file"
      if [ "$do_write" = "yes" ]; then
        rm -f "$projection_file"
        removed_from_rules=yes
        echo "Uninstalled: removed $projection_file"
      fi
    else
      echo "Not removing $projection_file: it is not a squirrel-mode projection."
    fi
  else
    echo "$projection_file does not exist - nothing to uninstall there."
  fi
fi
if [ "$do_write" = "yes" ] && [ "$removed_from_rules" = "yes" ]; then
  rmdir "$cursor_home/rules" 2>/dev/null || true
fi

if [ "$action" = "install" ]; then
  echo ""
  echo "Installed a local Cursor plugin copy at $plugin_root. Reload the Cursor window (Reload Window) so Cursor picks it up."
  echo "Cursor's PROJECT-scoped commands are a separate mechanism and are not installed here. If you also want /digest and /plan as project commands in one specific repository, copy these two files into that project's .cursor/commands/ directory:"
  echo "  $source_commands_dir/digest.md"
  echo "  $source_commands_dir/plan.md"
fi

if [ "$do_write" = "no" ]; then
  echo ""
  echo "This was a dry run. Nothing was written. Re-run with --yes to apply the changes above."
fi
