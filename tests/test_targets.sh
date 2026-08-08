#!/bin/sh
# Coverage for S7: the ported command artifacts
# (targets/codex/skills/*/SKILL.md, targets/cursor/commands/*.md),
# both targets/{codex,cursor}/install.sh, and docs/OTHER-TOOLS.md.
#
# Every installer scenario below runs against a throwaway, freshly
# created $HOME (mktemp -d) - never the real ~/.codex, ~/.cursor,
# ~/.agents, or ~/.claude. Every build.sh scratch scenario copies
# scripts/build.sh, rules/base-rules.md, and skills/*/SKILL.md into a
# throwaway directory (make_full_scratch) and runs the COPY there -
# never the real repo's own generated artifacts, except as a read-only
# comparison target.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion.
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

build_script="$repo_root/scripts/build.sh"
codex_install="$repo_root/targets/codex/install.sh"
cursor_install="$repo_root/targets/cursor/install.sh"
other_tools_doc="$repo_root/docs/OTHER-TOOLS.md"
cursor_mdc="$repo_root/targets/cursor/squirrel-mode.mdc"

cleanup_dirs=""
trap 'rm -rf $cleanup_dirs' EXIT

read_file() {
  # read_file <path> - prints file content, or empty string if missing.
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf ''
  fi
}

make_temp_home() {
  # make_temp_home - creates and prints a throwaway directory to use
  # as $HOME for one installer scenario. Registered for cleanup by the
  # caller (cleanup_dirs="$cleanup_dirs $result").
  mktemp -d "${TMPDIR:-/tmp}/squirrel-target-home.XXXXXX"
}

make_full_scratch() {
  # make_full_scratch - creates a throwaway directory containing
  # scripts/build.sh, rules/base-rules.md, AND skills/{digest,plan,init,tune}/
  # SKILL.md - the same ingredients tests/test_build.sh's own
  # make_build_scratch() now also copies (S7's B1 fix removed
  # build.sh's tolerance for a missing skills/<name>/SKILL.md, so every
  # scratch fixture in this repo must supply real sources now, not omit
  # them). A copy running from scratch/scripts/build.sh therefore
  # regenerates all ten artifacts, never touching the real repo.
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-full-scratch.XXXXXX")
  mkdir -p "$scratch/scripts" "$scratch/rules" "$scratch/skills"
  cp "$build_script" "$scratch/scripts/build.sh"
  chmod +x "$scratch/scripts/build.sh"
  cp "$repo_root/rules/base-rules.md" "$scratch/rules/base-rules.md"
  for cmd_name in digest plan init tune; do
    mkdir -p "$scratch/skills/$cmd_name"
    cp "$repo_root/skills/$cmd_name/SKILL.md" "$scratch/skills/$cmd_name/SKILL.md"
  done
  printf '%s\n' "$scratch"
}

tree_snapshot() {
  # tree_snapshot <dir>: a deterministic, sorted "<cksum> <size> <path>"
  # line per regular file under <dir>. cksum is used (not md5/md5sum)
  # because it is POSIX-mandated and behaves identically on both BSD
  # and GNU userlands, unlike md5's flags or md5sum's mere presence.
  dir=$1
  find "$dir" -type f -exec cksum {} \; 2>/dev/null | sort
}

full_tree_listing() {
  # full_tree_listing <dir>: a deterministic, sorted list of EVERY path
  # (files AND directories, unlike tree_snapshot above, which is
  # files-only) under <dir>, one per line. F1: a dry run must leave
  # $HOME completely unchanged, including any directory it might
  # create-then-remove (e.g. a lock directory) - a files-only `find
  # -type f` snapshot is blind to a directory that was left behind (or
  # never existed) by mistake.
  dir=$1
  find "$dir" 2>/dev/null | LC_ALL=C sort
}

sed_inplace() {
  # sed_inplace <expr> <file>: in-place edit that works with both BSD
  # sed (macOS: `sed -i '' expr file`) and GNU sed (`sed -i expr file`)
  # - detected via whether `sed --version` succeeds (GNU-only flag).
  expr=$1
  file=$2
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

extract_frontmatter_line() {
  # extract_frontmatter_line <file> <key> - prints the raw line for
  # <key> inside the frontmatter block (between the first two "---"
  # lines). Same technique tests/test_build.sh already uses.
  awk -v key="$2" '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && $0 ~ ("^" key ":") { print; exit }
  ' "$1"
}

# ==========================================================================
# 1. build.sh generates exactly the four Codex skills and two Cursor
#    commands. pickup/off/on are absent from BOTH targets, and
#    init/tune are absent from Cursor specifically (only digest/plan
#    port there).
# ==========================================================================
for cmd_name in digest plan init tune; do
  assert_file_exists "$repo_root/targets/codex/skills/$cmd_name/SKILL.md" "targets/codex/skills/$cmd_name/SKILL.md must exist"
done
for cmd_name in digest plan; do
  assert_file_exists "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must exist"
done
for cmd_name in pickup off on; do
  assert_file_absent "$repo_root/targets/codex/skills/$cmd_name/SKILL.md" "targets/codex/skills/$cmd_name/SKILL.md must NOT exist ($cmd_name is not ported to Codex - see PLAN.md's parity table)"
  assert_file_absent "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must NOT exist ($cmd_name is not ported to Cursor)"
done
for cmd_name in init tune; do
  assert_file_absent "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must NOT exist ($cmd_name is not ported to Cursor - it writes the profile file, which has nowhere to live on a project-scoped command)"
done

codex_skill_dir_count=$(find "$repo_root/targets/codex/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "4" "$codex_skill_dir_count" "targets/codex/skills/ must contain exactly 4 command directories"

cursor_command_count=$(find "$repo_root/targets/cursor/commands" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "2" "$cursor_command_count" "targets/cursor/commands/ must contain exactly 2 command files"

# ==========================================================================
# 2. Every generated artifact carries the GENERATED marker, naming
#    skills/<name>/SKILL.md as its source and scripts/build.sh as its
#    generator.
# ==========================================================================
for cmd_name in digest plan init tune; do
  content=$(read_file "$repo_root/targets/codex/skills/$cmd_name/SKILL.md")
  assert_contains "$content" "GENERATED FILE" "Codex $cmd_name skill must carry a GENERATED marker"
  assert_contains "$content" "skills/$cmd_name/SKILL.md" "Codex $cmd_name skill's marker must name skills/$cmd_name/SKILL.md as its source"
  assert_contains "$content" "scripts/build.sh" "Codex $cmd_name skill's marker must name scripts/build.sh as the generator"
done
for cmd_name in digest plan; do
  content=$(read_file "$repo_root/targets/cursor/commands/$cmd_name.md")
  assert_contains "$content" "GENERATED FILE" "Cursor $cmd_name command must carry a GENERATED marker"
  assert_contains "$content" "skills/$cmd_name/SKILL.md" "Cursor $cmd_name command's marker must name skills/$cmd_name/SKILL.md as its source"
  assert_contains "$content" "scripts/build.sh" "Cursor $cmd_name command's marker must name scripts/build.sh as the generator"
done

# ==========================================================================
# 3. No generated Codex or Cursor artifact mentions a mechanism its
#    host lacks: injected-context lines, hooks, sentinels, PENDING,
#    CLEAR, or ~/.claude/squirrel/off/. Case-SENSITIVE throughout -
#    PENDING/CLEAR specifically (the sentinel filename prefixes), not
#    the ordinary English words "clear"/"unclear"/"clearly" that
#    legitimately appear in this prose (e.g. init's "a clearly
#    labelled Extra").
# ==========================================================================
forbidden_terms="hook sentinel PENDING CLEAR SessionStart UserPromptSubmit"
# shellcheck disable=SC2088 # single-quoted deliberately: this is a
# literal needle assert_not_contains searches generated file TEXT for
# (the documented path as written in prose), never a path this shell
# opens or expands - a leading "~" here is not tilde-expansion gone
# wrong.
off_flag_dir_needle='~/.claude/squirrel/off/'
for cmd_name in digest plan init tune; do
  content=$(read_file "$repo_root/targets/codex/skills/$cmd_name/SKILL.md")
  for term in $forbidden_terms; do
    assert_not_contains "$content" "$term" "Codex $cmd_name skill must not mention '$term' (a mechanism Codex lacks)"
  done
  assert_not_contains "$content" "$off_flag_dir_needle" "Codex $cmd_name skill must not mention the off-flag directory"
  assert_not_contains "$content" "Session working directory" "Codex $cmd_name skill must not mention the injected 'Session working directory:' line"
  assert_not_contains "$content" "Project checkpoint path" "Codex $cmd_name skill must not mention the injected 'Project checkpoint path:' line"
done
for cmd_name in digest plan; do
  content=$(read_file "$repo_root/targets/cursor/commands/$cmd_name.md")
  for term in $forbidden_terms; do
    assert_not_contains "$content" "$term" "Cursor $cmd_name command must not mention '$term' (a mechanism Cursor lacks)"
  done
  assert_not_contains "$content" "$off_flag_dir_needle" "Cursor $cmd_name command must not mention the off-flag directory"
  assert_not_contains "$content" "Session working directory" "Cursor $cmd_name command must not mention the injected 'Session working directory:' line"
  assert_not_contains "$content" "Project checkpoint path" "Cursor $cmd_name command must not mention the injected 'Project checkpoint path:' line"
done

# ==========================================================================
# 4. init and tune (Codex) reference the exact shared profile path.
# ==========================================================================
# shellcheck disable=SC2088 # same reasoning as off_flag_dir_needle above.
profile_path_needle='~/.claude/squirrel/profile.md'
for cmd_name in init tune; do
  content=$(read_file "$repo_root/targets/codex/skills/$cmd_name/SKILL.md")
  assert_contains "$content" "$profile_path_needle" "Codex $cmd_name skill must reference the shared squirrel-mode profile path (the same file Claude Code and Cursor read)"
done

# ==========================================================================
# 5. Codex skill frontmatter has name + description. Cursor command
#    files carry NO frontmatter at all - verified against Cursor's own
#    documented format: plain Markdown, filename is the command name.
# ==========================================================================
for cmd_name in digest plan init tune; do
  f="$repo_root/targets/codex/skills/$cmd_name/SKILL.md"
  name_line=$(extract_frontmatter_line "$f" "name")
  assert_eq "name: $cmd_name" "$name_line" "Codex $cmd_name skill frontmatter must set name: $cmd_name (must match its own directory name)"
  desc_line=$(extract_frontmatter_line "$f" "description")
  if [ -n "$desc_line" ]; then
    desc_present=yes
  else
    desc_present=no
  fi
  assert_eq "yes" "$desc_present" "Codex $cmd_name skill frontmatter must have a description field"
done
for cmd_name in digest plan; do
  f="$repo_root/targets/cursor/commands/$cmd_name.md"
  first_line=$(head -n 1 "$f")
  assert_not_contains "$first_line" "---" "Cursor $cmd_name command must NOT open with a YAML frontmatter delimiter (Cursor commands take no frontmatter)"
  full_content=$(read_file "$f")
  frontmatter_delim_count=$(printf '%s\n' "$full_content" | grep -c '^---$' || true)
  assert_eq "0" "$frontmatter_delim_count" "Cursor $cmd_name command must contain no '---' frontmatter delimiter line anywhere"
done

# ==========================================================================
# 6. Idempotence and drift for the six ported artifacts.
# ==========================================================================
ported_rel_paths="targets/codex/skills/digest/SKILL.md targets/codex/skills/plan/SKILL.md targets/codex/skills/init/SKILL.md targets/codex/skills/tune/SKILL.md targets/cursor/commands/digest.md targets/cursor/commands/plan.md"

snap_before=""
for rel in $ported_rel_paths; do
  snap_before="$snap_before
$(cksum "$repo_root/$rel")"
done

if idem_build_out=$("$build_script" 2>&1); then
  idem_build_exit=0
else
  idem_build_exit=$?
fi
assert_eq "0" "$idem_build_exit" "scripts/build.sh must exit 0 when re-run against the real repo -- output: $idem_build_out"

snap_after=""
for rel in $ported_rel_paths; do
  snap_after="$snap_after
$(cksum "$repo_root/$rel")"
done
assert_eq "$snap_before" "$snap_after" "the six ported artifacts must be byte-identical across two consecutive build.sh runs (idempotence)"

drift_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $drift_scratch"
if drift_build_out=$("$drift_scratch/scripts/build.sh" 2>&1); then
  drift_build_exit=0
else
  drift_build_exit=$?
fi
assert_eq "0" "$drift_build_exit" "regenerating the ported artifacts into a full scratch directory must succeed -- output: $drift_build_out"

for rel in $ported_rel_paths; do
  if drift_diff=$(diff -u "$repo_root/$rel" "$drift_scratch/$rel" 2>&1); then
    drift_status=identical
  else
    drift_status="DRIFT DETECTED: $drift_diff"
  fi
  assert_eq "identical" "$drift_status" "committed $rel must match a fresh regeneration from skills/*/SKILL.md (no drift)"
done

# ==========================================================================
# 7. Both install.sh are executable and idempotent: running --yes
#    twice against the same temporary $HOME changes nothing on the
#    second run. (POSIX-ness is covered repo-wide by
#    tests/test_shell_dialect.sh's shellcheck sweep, which discovers
#    these two files automatically via `git ls-files`.)
# ==========================================================================
assert_file_exists "$codex_install" "targets/codex/install.sh must exist"
assert_file_exists "$cursor_install" "targets/cursor/install.sh must exist"
if [ -x "$codex_install" ]; then codex_install_exec=yes; else codex_install_exec=no; fi
assert_eq "yes" "$codex_install_exec" "targets/codex/install.sh must be executable"
if [ -x "$cursor_install" ]; then cursor_install_exec=yes; else cursor_install_exec=no; fi
assert_eq "yes" "$cursor_install_exec" "targets/cursor/install.sh must be executable"

home7c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home7c"
mkdir -p "$home7c/.codex"
if run7c1_out=$(HOME="$home7c" "$codex_install" --yes 2>&1); then run7c1_exit=0; else run7c1_exit=$?; fi
assert_eq "0" "$run7c1_exit" "codex install.sh (first --yes run) must exit 0 -- output: $run7c1_out"
snap7c1=$(tree_snapshot "$home7c")
if run7c2_out=$(HOME="$home7c" "$codex_install" --yes 2>&1); then run7c2_exit=0; else run7c2_exit=$?; fi
assert_eq "0" "$run7c2_exit" "codex install.sh (second --yes run) must exit 0 -- output: $run7c2_out"
snap7c2=$(tree_snapshot "$home7c")
if [ "$snap7c1" = "$snap7c2" ]; then idem7c=identical; else idem7c="DIFFERS"; fi
assert_eq "identical" "$idem7c" "codex install.sh must be idempotent: a second --yes run against the same \$HOME must change nothing"

home7u=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home7u"
mkdir -p "$home7u/.cursor"
if run7u1_out=$(HOME="$home7u" "$cursor_install" --yes 2>&1); then run7u1_exit=0; else run7u1_exit=$?; fi
assert_eq "0" "$run7u1_exit" "cursor install.sh (first --yes run) must exit 0 -- output: $run7u1_out"
snap7u1=$(tree_snapshot "$home7u")
if run7u2_out=$(HOME="$home7u" "$cursor_install" --yes 2>&1); then run7u2_exit=0; else run7u2_exit=$?; fi
assert_eq "0" "$run7u2_exit" "cursor install.sh (second --yes run) must exit 0 -- output: $run7u2_out"
snap7u2=$(tree_snapshot "$home7u")
if [ "$snap7u1" = "$snap7u2" ]; then idem7u=identical; else idem7u="DIFFERS"; fi
assert_eq "identical" "$idem7u" "cursor install.sh must be idempotent: a second --yes run against the same \$HOME must change nothing"

# Dry run (no flags at all) must never write anything, on either
# installer, against a completely fresh $HOME. F1 (S7 review cycle 2):
# strengthened from a files-only `find -type f` count (blind to a
# directory - e.g. the A3 lock directory - being created, even
# transiently) to a full before/after tree comparison that also sees
# directories.
home7d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home7d"
mkdir -p "$home7d/.codex" "$home7d/.cursor"
before7d=$(full_tree_listing "$home7d")
HOME="$home7d" "$codex_install" >/dev/null 2>&1
HOME="$home7d" "$cursor_install" >/dev/null 2>&1
after7d=$(full_tree_listing "$home7d")
assert_eq "$before7d" "$after7d" "a dry run (no --yes) on either installer must change nothing at all under \$HOME - not even a directory (F1: files-only find was blind to this)"

# ==========================================================================
# 8. Neither installer truncates an existing file: seed AGENTS.md with
#    user content, install, assert the user content survives verbatim
#    and the block is clearly delimited.
# ==========================================================================
home8=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home8"
mkdir -p "$home8/.codex"
user_content_8="My own personal Codex instructions.
Second line, with real detail that must survive."
printf '%s\n' "$user_content_8" >"$home8/.codex/AGENTS.md"
if run8_out=$(HOME="$home8" "$codex_install" --yes 2>&1); then run8_exit=0; else run8_exit=$?; fi
assert_eq "0" "$run8_exit" "codex install.sh must exit 0 when installing over an existing AGENTS.md -- output: $run8_out"
after8=$(cat "$home8/.codex/AGENTS.md")
case "$after8" in
  "$user_content_8"*)
    survived8=yes
    ;;
  *)
    survived8=no
    ;;
esac
assert_eq "yes" "$survived8" "seeded user content in ~/.codex/AGENTS.md must survive verbatim, unmoved from the start of the file, after install"
assert_contains "$after8" "BEGIN SQUIRREL-MODE" "installed AGENTS.md must contain a BEGIN delimiter"
assert_contains "$after8" "END SQUIRREL-MODE" "installed AGENTS.md must contain an END delimiter"

# ==========================================================================
# 9. Re-install after editing inside the block replaces only the
#    block - a hand-edit inside is gone, content outside survives.
# ==========================================================================
home9=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home9"
mkdir -p "$home9/.codex"
printf 'User content that must never be touched.\n' >"$home9/.codex/AGENTS.md"
HOME="$home9" "$codex_install" --yes >/dev/null 2>&1
sed_inplace 's/### 1. Answer first/### 1. HAND-EDITED-MARKER-9/' "$home9/.codex/AGENTS.md"
sanity9=$(cat "$home9/.codex/AGENTS.md")
assert_contains "$sanity9" "HAND-EDITED-MARKER-9" "sanity: the hand-edit must have landed before re-installing"
HOME="$home9" "$codex_install" --yes >/dev/null 2>&1
after9=$(cat "$home9/.codex/AGENTS.md")
assert_not_contains "$after9" "HAND-EDITED-MARKER-9" "re-installing must replace hand-edited content INSIDE the block"
assert_contains "$after9" "User content that must never be touched." "re-installing must NOT touch content OUTSIDE the block"

# ==========================================================================
# 10. Uninstall removes the block and leaves surrounding content
#     byte-identical to before the block ever existed.
# ==========================================================================
home10=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home10"
mkdir -p "$home10/.codex"
original_content_10="Line one of my own AGENTS.md.
Line two, also mine.
"
printf '%s' "$original_content_10" >"$home10/.codex/AGENTS.md"
HOME="$home10" "$codex_install" --yes >/dev/null 2>&1
if uninstall10_out=$(HOME="$home10" "$codex_install" --uninstall --yes 2>&1); then uninstall10_exit=0; else uninstall10_exit=$?; fi
assert_eq "0" "$uninstall10_exit" "codex install.sh --uninstall --yes must exit 0 -- output: $uninstall10_out"
if printf '%s' "$original_content_10" | cmp -s - "$home10/.codex/AGENTS.md"; then
  byte_status_10=identical
else
  byte_status_10="DIFFERS"
fi
assert_eq "identical" "$byte_status_10" "uninstall must restore ~/.codex/AGENTS.md byte-identical to its content before squirrel-mode was ever installed"

# Cursor's uninstall: the dedicated file is removed entirely, and an
# unrelated file already sitting in the same directory survives.
home10b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home10b"
mkdir -p "$home10b/.cursor/rules"
printf 'unrelated rule, not squirrel-mode' >"$home10b/.cursor/rules/other-rule.mdc"
HOME="$home10b" "$cursor_install" --yes >/dev/null 2>&1
HOME="$home10b" "$cursor_install" --uninstall --yes >/dev/null 2>&1
assert_file_absent "$home10b/.cursor/rules/squirrel-mode.mdc" "cursor uninstall must remove squirrel-mode.mdc"
if [ -f "$home10b/.cursor/rules/other-rule.mdc" ]; then
  other_rule_survived=yes
else
  other_rule_survived=no
fi
assert_eq "yes" "$other_rule_survived" "cursor uninstall must leave an unrelated .mdc file in the same directory untouched"

# ==========================================================================
# 11. Each installer reports, rather than fails, when its host
#     directory is absent, and exits 0.
# ==========================================================================
home11=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home11"
if out11c=$(HOME="$home11" "$codex_install" --yes 2>&1); then exit11c=0; else exit11c=$?; fi
assert_eq "0" "$exit11c" "codex install.sh must exit 0 when ~/.codex does not exist -- output: $out11c"
assert_contains "$out11c" "not appear to be installed" "codex install.sh must report that Codex is not installed, not merely exit silently"
assert_file_absent "$home11/.agents" "codex install.sh must not create ~/.agents when ~/.codex is absent"

if out11u=$(HOME="$home11" "$cursor_install" --yes 2>&1); then exit11u=0; else exit11u=$?; fi
assert_eq "0" "$exit11u" "cursor install.sh must exit 0 when ~/.cursor does not exist -- output: $out11u"
assert_contains "$out11u" "not appear to be installed" "cursor install.sh must report that Cursor is not installed, not merely exit silently"
assert_file_absent "$home11/.cursor" "cursor install.sh must not create ~/.cursor when it does not already exist"

# ==========================================================================
# 12. docs/OTHER-TOOLS.md exists, states what each target loses, and
#     documents how to turn the rules off on Codex and Cursor.
# ==========================================================================
assert_file_exists "$other_tools_doc" "docs/OTHER-TOOLS.md must exist"
other_tools_content=$(read_file "$other_tools_doc")
assert_contains "$other_tools_content" "No calibration interview" "docs/OTHER-TOOLS.md must state plainly that Cursor gets no calibration interview"
assert_contains "$other_tools_content" "Automatic checkpoints" "docs/OTHER-TOOLS.md must state plainly that Codex/Cursor get no automatic checkpoints"
assert_contains "$other_tools_content" "off switch" "docs/OTHER-TOOLS.md must mention the lack of a session off-switch on the other targets"
assert_contains "$other_tools_content" "## Turning the rules off" "docs/OTHER-TOOLS.md must have a section on turning the rules off"
assert_contains "$other_tools_content" "AGENTS.md" "docs/OTHER-TOOLS.md's turn-off section must mention editing AGENTS.md for Codex"
assert_contains "$other_tools_content" "alwaysApply" "docs/OTHER-TOOLS.md's turn-off section must mention Cursor's alwaysApply flag"
assert_contains "$other_tools_content" "No network calls" "docs/OTHER-TOOLS.md must carry the privacy note (no network calls)"
assert_contains "$other_tools_content" "No telemetry" "docs/OTHER-TOOLS.md must carry the privacy note (no telemetry)"
assert_contains "$other_tools_content" "$profile_path_needle" "docs/OTHER-TOOLS.md must state the shared profile path consequence"

# F8 (invariant 6e - "when a fix propagates to two files, a test must
# enforce it"): the lock is documented in FIVE places (both installer
# headers, both usage() blocks, and this doc) - nothing pinned that
# fact before, so a future edit to any one of the five could silently
# desynchronise from the other four with no test noticing, exactly the
# PLAN.md/RESEARCH.md desync class invariant 6e itself records. Pin all
# five here.
assert_contains "$other_tools_content" ".squirrel-install.lock" "docs/OTHER-TOOLS.md must document the .squirrel-install.lock directory (F8)"
codex_header_content=$(read_file "$codex_install")
assert_contains "$codex_header_content" ".squirrel-install.lock" "targets/codex/install.sh's header comment must document the lock (F8)"
cursor_header_content=$(read_file "$cursor_install")
assert_contains "$cursor_header_content" ".squirrel-install.lock" "targets/cursor/install.sh's header comment must document the lock (F8)"

home12help_c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home12help_c"
codex_help_out=$(HOME="$home12help_c" "$codex_install" --help 2>&1)
assert_contains "$codex_help_out" ".squirrel-install.lock" "targets/codex/install.sh's usage()/--help output must mention the lock (F8)"

home12help_u=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home12help_u"
cursor_help_out=$(HOME="$home12help_u" "$cursor_install" --help 2>&1)
assert_contains "$cursor_help_out" ".squirrel-install.lock" "targets/cursor/install.sh's usage()/--help output must mention the lock (F8)"

# G7 (invariant 6e - same class as F8 just above): the lock-release-
# timing wording fix propagated to THREE files (both installer headers
# and docs/OTHER-TOOLS.md). Pinning only the corrected wording in each
# of those three places would not catch a future edit that reintroduces
# the retired sentence as a FOURTH file's own single, unwrapped line -
# the codex-header and docs/OTHER-TOOLS.md shape - which this
# git-tracked, repo-wide grep sweep forecloses, the same way invariant
# 6e's own precedent pins a retired name dead everywhere (S6). This is
# a LINE-BASED sweep, though, with the same reach limit as the pre-G4
# "Claude"/"Code" scanner: the pre-fix cursor header actually had this
# exact sentence wrapped across a `#`-continued comment line break
# ("...and removed" / "the instant that work ends..."), which no
# contiguous-string grep can see. A future reintroduction shaped like
# THAT - re-wrapped across lines - would slip past this sweep too;
# tightening it further is not attempted here (a shorter needle, e.g.
# dropping "removed", false-positives on this fix's own corrected
# cursor wording, "never the instant that work ends").
#
# The retired phrase is built from two halves ($g7_part1$g7_part2)
# rather than written out as one literal string, deliberately: this
# assertion's own source line would otherwise be a live, permanent
# match for its own sweep, `git ls-files` would find THIS file, and the
# assertion would fail forever, against itself, on every future run.
g7_part1="removed the ins"
g7_part2="tant that work ends"
retired_lock_phrase="$g7_part1$g7_part2"
retired_lock_wording_hits=$(cd "$repo_root" && git ls-files -z | xargs -0 grep -l "$retired_lock_phrase" 2>/dev/null || true)
assert_eq "" "$retired_lock_wording_hits" "G7: the retired lock-release-timing wording must not survive in any git-tracked file (found in: $retired_lock_wording_hits)"

# ==========================================================================
# 13. targets/cursor/squirrel-mode.mdc's link to docs/OTHER-TOOLS.md
#     now resolves to a real file (S7 closes the forward reference
#     .build-checkpoint.md notes).
# ==========================================================================
mdc_content=$(read_file "$cursor_mdc")
assert_contains "$mdc_content" "docs/OTHER-TOOLS.md" "targets/cursor/squirrel-mode.mdc must reference docs/OTHER-TOOLS.md"
assert_file_exists "$other_tools_doc" "docs/OTHER-TOOLS.md (referenced by targets/cursor/squirrel-mode.mdc) must actually exist"

# ==========================================================================
# 14. No stray .gitkeep remains in a now-populated directory.
# ==========================================================================
stray_gitkeep=$(find "$repo_root/targets" -name '.gitkeep' 2>/dev/null || true)
assert_eq "" "$stray_gitkeep" "no .gitkeep file must remain under targets/ now that targets/codex/skills/ and targets/cursor/commands/ are populated with real files"

# ==========================================================================
# 15 (C1, BLOCKER). The ownership check must be an EXACT, FULL-LINE match
#    against the artifact-specific GENERATED banner line - never a bare
#    substring search. This is the scenario the S7 review found the
#    suite could not fail on: `classify_dedicated_file` gutted to
#    return "ours" unconditionally, in BOTH installers, still passed
#    every existing scenario (the only prior "foreign" coverage checked
#    an unrelated, differently-named file surviving BESIDE Cursor's
#    .mdc - never a collision at the exact install path, and never the
#    Codex skills at all). Two distinct mutations are pinned here, for
#    BOTH installers, at the EXACT install path:
#      (a) a foreign file with NO marker at all;
#      (b) a foreign file that merely CONTAINS the substring
#          "<!-- GENERATED FILE. Source:" but not the exact banner line
#          for that specific artifact.
#    Both must survive install AND --uninstall --yes byte-for-byte.
# ==========================================================================
assert_foreign_survives_install_and_uninstall() {
  # assert_foreign_survives_install_and_uninstall <home> <installer>
  # <dest_path> <content> <label>: seeds <content> at <dest_path>
  # (already created), runs <installer> --yes then
  # <installer> --uninstall --yes against <home>, and asserts
  # <dest_path>'s content is unchanged after each step.
  # read_file (not a bare `cat`) is used throughout, deliberately: if
  # the mutation this scenario exists to catch is present, an
  # "uninstall" can actually DELETE the seeded foreign file - a bare
  # `cat` on a now-missing file would exit non-zero and, under
  # `set -eu`, abort this whole test FILE right there (no SUMMARY line,
  # every later scenario silently never runs). read_file degrades to an
  # empty string instead, so the mutation shows up as a clean, reported
  # assertion failure ("expected: <content> / actual: ") rather than an
  # opaque crash that hides everything after it.
  home=$1
  installer=$2
  dest=$3
  content=$4
  label=$5
  printf '%s' "$content" >"$dest"
  HOME="$home" "$installer" --yes >/dev/null 2>&1
  after_install=$(read_file "$dest")
  assert_eq "$content" "$after_install" "$label: must survive install byte-for-byte at the exact install path (ownership must be an exact banner-line match, not a substring search)"
  HOME="$home" "$installer" --uninstall --yes >/dev/null 2>&1
  after_uninstall=$(read_file "$dest")
  assert_eq "$content" "$after_uninstall" "$label: must survive --uninstall --yes byte-for-byte at the exact install path"
}

# --- 15a: Codex, no-marker foreign file at the exact skill path --------
home15a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15a"
mkdir -p "$home15a/.codex" "$home15a/.agents/skills/digest"
assert_foreign_survives_install_and_uninstall "$home15a" "$codex_install" "$home15a/.agents/skills/digest/SKILL.md" "This is a foreign file with no squirrel-mode marker at all, sitting at squirrel-mode's exact digest skill path." "Codex ~/.agents/skills/digest/SKILL.md, no marker"

# --- 15b: Codex, substring-but-not-exact-banner foreign file -----------
home15b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15b"
mkdir -p "$home15b/.codex" "$home15b/.agents/skills/digest"
substring_content_15b="This foreign file quotes squirrel-mode's own docs, including the substring: <!-- GENERATED FILE. Source: something-else-entirely.md. Generator: scripts/build.sh. -- but it is not actually squirrel-mode's digest skill."
assert_foreign_survives_install_and_uninstall "$home15b" "$codex_install" "$home15b/.agents/skills/digest/SKILL.md" "$substring_content_15b" "Codex ~/.agents/skills/digest/SKILL.md, substring-only (not exact banner line)"

# --- 15c: Cursor, no-marker foreign file at the exact .mdc path --------
home15c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15c"
mkdir -p "$home15c/.cursor/rules"
assert_foreign_survives_install_and_uninstall "$home15c" "$cursor_install" "$home15c/.cursor/rules/squirrel-mode.mdc" "This is a foreign file with no squirrel-mode marker at all, sitting at squirrel-mode's exact .mdc path." "Cursor ~/.cursor/rules/squirrel-mode.mdc, no marker"

# --- 15d: Cursor, substring-but-not-exact-banner foreign file ----------
home15d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15d"
mkdir -p "$home15d/.cursor/rules"
substring_content_15d="This foreign .mdc quotes squirrel-mode's own docs, including the substring: <!-- GENERATED FILE. Source: something-else-entirely.md. Generator: scripts/build.sh. -- but it is not actually squirrel-mode's rules file."
assert_foreign_survives_install_and_uninstall "$home15d" "$cursor_install" "$home15d/.cursor/rules/squirrel-mode.mdc" "$substring_content_15d" "Cursor ~/.cursor/rules/squirrel-mode.mdc, substring-only (not exact banner line)"

# ==========================================================================
# 16 (C2). Fenced-code-block markers (A1): a BEGIN/END-shaped example
#    quoted inside a ``` fence in the user's own AGENTS.md must never be
#    mistaken for the real block by either install or uninstall - the
#    tech lead's exact B1/A1 repro. Round trip must be byte-identical.
# ==========================================================================
home16=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home16"
mkdir -p "$home16/.codex"
cat >"$home16/.codex/AGENTS.md" <<'FENCE_EOF'
My own instructions.

Example of what the squirrel-mode block looks like, so future contributors recognise it:
```
<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
some fake content that must never be treated as the real block
<!-- END SQUIRREL-MODE -->
```

More of my own content after the example.
FENCE_EOF
fence_original_16=$(read_file "$home16/.codex/AGENTS.md")
if fence_install_out_16=$(HOME="$home16" "$codex_install" --yes 2>&1); then fence_install_exit_16=0; else fence_install_exit_16=$?; fi
assert_eq "0" "$fence_install_exit_16" "install must exit 0 against a fenced BEGIN/END example -- output: $fence_install_out_16"
fence_after_install_16=$(read_file "$home16/.codex/AGENTS.md")
case "$fence_after_install_16" in
  "$fence_original_16"*)
    fence_prefix_survived_16=yes
    ;;
  *)
    fence_prefix_survived_16=no
    ;;
esac
assert_eq "yes" "$fence_prefix_survived_16" "the fenced example (including its own fake BEGIN/END lines) must survive install completely unmodified, as a verbatim prefix of the file (A1: fence-aware marker detection)"
assert_contains "$fence_after_install_16" "GENERATED FILE. Source: rules/base-rules.md" "a REAL squirrel-mode block must still be appended after install - the fenced example must not fool install into thinking the file already has a real block"
if fence_uninstall_out_16=$(HOME="$home16" "$codex_install" --uninstall --yes 2>&1); then fence_uninstall_exit_16=0; else fence_uninstall_exit_16=$?; fi
assert_eq "0" "$fence_uninstall_exit_16" "uninstall must exit 0 against a fenced BEGIN/END example -- output: $fence_uninstall_out_16"
fence_after_uninstall_16=$(read_file "$home16/.codex/AGENTS.md")
if [ "$fence_after_uninstall_16" = "$fence_original_16" ]; then
  fence_roundtrip_16=identical
else
  fence_roundtrip_16=DIFFERS
fi
assert_eq "identical" "$fence_roundtrip_16" "install then uninstall of a file containing a fenced BEGIN/END example must round-trip byte-identical (A1)"

# ==========================================================================
# 17 (C2; G2, S7 review cycle 3). Directory at the destination path (A4)
#    must fail loudly, on both installers, and change NOTHING under
#    $HOME - not just "no orphaned temp file", but the entire $HOME
#    tree (files AND directories) byte-and-path-identical to before the
#    attempt. G2: this full-tree assertion is exactly what was missing
#    when G1's BLOCKER shipped - 17b previously asserted only the exit
#    code, so a directory at a SKILL destination silently let AGENTS.md
#    (and any earlier skills) be written for real before the loop ever
#    reached the directory and refused. 17b now targets `tune`, the
#    LAST command in the digest/plan/init/tune loop, to show the full
#    blast radius the original reviewer reproduced (AGENTS.md plus
#    three of four skill files written before the failure) rather than
#    just the first-iteration case.
# ==========================================================================
home17a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home17a"
mkdir -p "$home17a/.codex/AGENTS.md"
before17a=$(full_tree_listing "$home17a")
if out17a=$(HOME="$home17a" "$codex_install" --yes 2>&1); then exit17a=0; else exit17a=$?; fi
assert_eq "1" "$exit17a" "codex install.sh must exit non-zero (never report a false success) when \$HOME/.codex/AGENTS.md is a directory -- output: $out17a"
assert_not_contains "$out17a" "Installed:" "codex install.sh must not claim 'Installed:' when the destination is a directory"
leftover17a=$(find "$home17a" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover17a" "no orphaned temp file must be left in \$HOME when AGENTS.md is a directory"
after17a=$(full_tree_listing "$home17a")
assert_eq "$before17a" "$after17a" "17a: \$HOME tree (files and directories) must be completely unchanged after the AGENTS.md-is-a-directory refusal"

home17b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home17b"
mkdir -p "$home17b/.codex" "$home17b/.agents/skills/tune/SKILL.md"
before17b=$(full_tree_listing "$home17b")
if out17b=$(HOME="$home17b" "$codex_install" --yes 2>&1); then exit17b=0; else exit17b=$?; fi
assert_eq "1" "$exit17b" "codex install.sh must exit non-zero when a skill destination path is a directory -- output: $out17b"
after17b=$(full_tree_listing "$home17b")
assert_eq "$before17b" "$after17b" "17b (G1/G2): \$HOME tree must be completely unchanged when ONLY the LAST skill destination (tune) is a directory - AGENTS.md and the three earlier skill files (digest/plan/init) must never have been written either"
assert_file_absent "$home17b/.codex/AGENTS.md" "17b (G1): AGENTS.md must not have been created as a side effect before the tune-is-a-directory refusal fired"
for cmd_name in digest plan init; do
  assert_file_absent "$home17b/.agents/skills/$cmd_name/SKILL.md" "17b (G1): $cmd_name's SKILL.md must not have been created before the tune-is-a-directory refusal fired (the pre-flight pass must catch tune before the loop writes any of digest/plan/init)"
done

home17c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home17c"
mkdir -p "$home17c/.cursor/rules/squirrel-mode.mdc"
before17c=$(full_tree_listing "$home17c")
if out17c=$(HOME="$home17c" "$cursor_install" --yes 2>&1); then exit17c=0; else exit17c=$?; fi
assert_eq "1" "$exit17c" "cursor install.sh must exit non-zero when \$HOME/.cursor/rules/squirrel-mode.mdc is a directory -- output: $out17c"
leftover17c=$(find "$home17c" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover17c" "no orphaned temp file must be left in \$HOME when the cursor .mdc destination is a directory"
after17c=$(full_tree_listing "$home17c")
assert_eq "$before17c" "$after17c" "17c: \$HOME tree must be completely unchanged after the cursor .mdc-is-a-directory refusal"

# ==========================================================================
# 18 (C2). A pre-existing EMPTY AGENTS.md (A5): install then uninstall
#    must leave the file in place, truncated to 0 bytes - never deleted.
# ==========================================================================
home18=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home18"
mkdir -p "$home18/.codex"
: >"$home18/.codex/AGENTS.md"
HOME="$home18" "$codex_install" --yes >/dev/null 2>&1
if out18=$(HOME="$home18" "$codex_install" --uninstall --yes 2>&1); then exit18=0; else exit18=$?; fi
assert_eq "0" "$exit18" "uninstalling over a pre-existing empty AGENTS.md must exit 0 -- output: $out18"
assert_file_exists "$home18/.codex/AGENTS.md" "a pre-existing EMPTY AGENTS.md must still exist after uninstall (truncated, not deleted - A5)"
empty_size_18=$(wc -c <"$home18/.codex/AGENTS.md" | tr -d ' ')
assert_eq "0" "$empty_size_18" "AGENTS.md must be exactly 0 bytes after uninstalling a squirrel-mode block that was its only content"

# ==========================================================================
# 19 (C2). File mode preservation (A6): 600 must survive both an
#    install-over-existing and an uninstall, on both installers.
# ==========================================================================
file_mode10() {
  # file_mode10 <path>: prints the first 10 characters of `ls -l`'s
  # permission column for the single, explicit, quoted path given (e.g.
  # "-rw-------") - a portable stand-in for `stat`'s non-portable format
  # flags (BSD vs GNU) and `chmod --reference` (GNU-only).
  # shellcheck disable=SC2012 # deliberately `ls`, not `find`: SC2012's
  # concern is glob-expansion/multiple-file ambiguity, which cannot
  # arise here - the argument is a single, already-quoted, non-glob
  # path, never a pattern.
  ls -l "$1" | cut -c1-10
}

home19a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home19a"
mkdir -p "$home19a/.codex"
printf 'my stuff\n' >"$home19a/.codex/AGENTS.md"
chmod 600 "$home19a/.codex/AGENTS.md"
HOME="$home19a" "$codex_install" --yes >/dev/null 2>&1
mode_after_install_19a=$(file_mode10 "$home19a/.codex/AGENTS.md")
assert_eq "-rw-------" "$mode_after_install_19a" "AGENTS.md file mode 600 must be preserved after install-over-existing (A6)"
HOME="$home19a" "$codex_install" --uninstall --yes >/dev/null 2>&1
mode_after_uninstall_19a=$(file_mode10 "$home19a/.codex/AGENTS.md")
assert_eq "-rw-------" "$mode_after_uninstall_19a" "AGENTS.md file mode 600 must be preserved after uninstall (A6)"

home19c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home19c"
mkdir -p "$home19c/.cursor/rules"
cp "$cursor_mdc" "$home19c/.cursor/rules/squirrel-mode.mdc"
chmod 600 "$home19c/.cursor/rules/squirrel-mode.mdc"
printf '\nstale trailing line to force an update, not a no-op\n' >>"$home19c/.cursor/rules/squirrel-mode.mdc"
HOME="$home19c" "$cursor_install" --yes >/dev/null 2>&1
mode_after_update_19c=$(file_mode10 "$home19c/.cursor/rules/squirrel-mode.mdc")
assert_eq "-rw-------" "$mode_after_update_19c" "cursor .mdc file mode 600 must be preserved after an install-over-existing UPDATE (A6)"

# ==========================================================================
# 20 (C2). Uninstall-orphan path (A7): after ~/.codex is removed,
#    --uninstall --yes must still exit 0 and still remove the four
#    ~/.agents/skills/*/SKILL.md files - never stranding them.
# ==========================================================================
home20=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home20"
mkdir -p "$home20/.codex"
HOME="$home20" "$codex_install" --yes >/dev/null 2>&1
rm -rf "$home20/.codex"
if out20=$(HOME="$home20" "$codex_install" --uninstall --yes 2>&1); then exit20=0; else exit20=$?; fi
assert_eq "0" "$exit20" "codex install.sh --uninstall must exit 0 even after ~/.codex was removed -- output: $out20"
for cmd_name in digest plan init tune; do
  assert_file_absent "$home20/.agents/skills/$cmd_name/SKILL.md" "uninstall after ~/.codex removal must still remove ~/.agents/skills/$cmd_name/SKILL.md, not strand it (A7)"
done

# ==========================================================================
# 21 (C2). No leftover temp files in $HOME after an interrupted
#    (SIGTERM) run (A8). Uses a scratch copy of targets/codex/ so a
#    marker+sleep can be injected into write_destination() the same way
#    tests/test_build.sh injects into scripts/build.sh - the installer
#    resolves its own repo_root as $script_dir/../.., so the copy needs
#    targets/codex/AGENTS.md and targets/codex/skills/*/SKILL.md beside
#    it to run at all.
# ==========================================================================
make_codex_installer_scratch() {
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-codex-installer-scratch.XXXXXX")
  mkdir -p "$scratch/targets/codex/skills/digest" "$scratch/targets/codex/skills/plan" \
    "$scratch/targets/codex/skills/init" "$scratch/targets/codex/skills/tune"
  cp "$repo_root/targets/codex/AGENTS.md" "$scratch/targets/codex/AGENTS.md"
  for cmd_name in digest plan init tune; do
    cp "$repo_root/targets/codex/skills/$cmd_name/SKILL.md" "$scratch/targets/codex/skills/$cmd_name/SKILL.md"
  done
  cp "$codex_install" "$scratch/targets/codex/install.sh"
  chmod +x "$scratch/targets/codex/install.sh"
  printf '%s\n' "$scratch"
}

wait_for_marker_21() {
  marker=$1
  tries=0
  while [ ! -f "$marker" ] && [ "$tries" -lt 10 ]; do
    sleep 1
    tries=$((tries + 1))
  done
  if [ -f "$marker" ]; then
    printf 'seen\n'
  else
    printf 'TIMEOUT\n'
  fi
}

installer_scratch_21=$(make_codex_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_21"
home21=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home21"
mkdir -p "$home21/.codex"
printf 'seed content\n' >"$home21/.codex/AGENTS.md"

# shellcheck disable=SC2016 # single-quoted deliberately: the literal
# source text to grep for in the scratch install.sh copy, not an
# expression to expand in THIS shell.
line21=$(grep -n -F 'mv "$temp" "$destination"' "$installer_scratch_21/targets/codex/install.sh" | head -n 1 | cut -d: -f1)
marker21="$installer_scratch_21/write-marker"
awk -v n="$line21" -v m="$marker21" 'NR == n { print "touch \"" m "\""; print "sleep 3"; print; next } { print }' "$installer_scratch_21/targets/codex/install.sh" >"$installer_scratch_21/targets/codex/install.sh.new"
mv "$installer_scratch_21/targets/codex/install.sh.new" "$installer_scratch_21/targets/codex/install.sh"
chmod +x "$installer_scratch_21/targets/codex/install.sh"

HOME="$home21" "$installer_scratch_21/targets/codex/install.sh" --yes >"$installer_scratch_21/run.out" 2>&1 &
pid21=$!
marker_status_21=$(wait_for_marker_21 "$marker21")
assert_eq "seen" "$marker_status_21" "signal test fixture 21: the write-phase marker must appear before the poll timeout (a fixture problem if not, not an install.sh problem)"

kill -TERM "$pid21" 2>/dev/null || true
if wait "$pid21"; then
  sig_exit_21=0
else
  sig_exit_21=$?
fi
assert_eq "143" "$sig_exit_21" "SIGTERM during an installer write must make it exit 143 (128+SIGTERM) promptly -- install.sh output: $(read_file "$installer_scratch_21/run.out")"

leftover_21=$(find "$home21" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover_21" "no leftover temp file must remain anywhere in \$HOME after a SIGTERM mid-write (A8)"
seed_after_21=$(read_file "$home21/.codex/AGENTS.md")
assert_eq "seed content" "$seed_after_21" "AGENTS.md must be unmodified after a SIGTERM mid-write (A8) - the mv never ran"
assert_file_absent "$home21/.codex/.squirrel-install.lock" "the A3 lock directory must be released (removed) even after a SIGTERM mid-write, not left behind forever"

# --- A3 lock-contention coverage: a pre-existing lock directory must
# make a fresh run fail loudly, naming the lock path, rather than race
# it - and must NOT be removed by the run that failed to acquire it
# (that would let a second racer clean up the first racer's still-active
# lock from underneath it). G2 (S7 review cycle 3): also asserts the
# rest of $HOME - not just the lock directory itself - is completely
# unchanged; lock contention is a refusal like any other.
home21c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home21c"
mkdir -p "$home21c/.codex/.squirrel-install.lock"
before21c=$(full_tree_listing "$home21c")
if out21c=$(HOME="$home21c" "$codex_install" --yes 2>&1); then exit21c=0; else exit21c=$?; fi
assert_eq "1" "$exit21c" "codex install.sh must exit non-zero when its lock directory already exists (A3 contention) -- output: $out21c"
assert_contains "$out21c" ".squirrel-install.lock" "the lock-contention failure message must name the lock path"
if [ -d "$home21c/.codex/.squirrel-install.lock" ]; then
  lock_survived_21c=yes
else
  lock_survived_21c=no
fi
assert_eq "yes" "$lock_survived_21c" "a run that failed to acquire the lock must NOT remove the other run's still-active lock directory"
after21c=$(full_tree_listing "$home21c")
assert_eq "$before21c" "$after21c" "21c (G2): \$HOME tree must be completely unchanged after lock contention (AGENTS.md and the skill files must never have been written)"

home21d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home21d"
mkdir -p "$home21d/.cursor/.squirrel-install.lock"
before21d=$(full_tree_listing "$home21d")
if out21d=$(HOME="$home21d" "$cursor_install" --yes 2>&1); then exit21d=0; else exit21d=$?; fi
assert_eq "1" "$exit21d" "cursor install.sh must exit non-zero when its lock directory already exists (A3 contention) -- output: $out21d"
assert_contains "$out21d" ".squirrel-install.lock" "the cursor lock-contention failure message must name the lock path"
if [ -d "$home21d/.cursor/.squirrel-install.lock" ]; then
  lock_survived_21d=yes
else
  lock_survived_21d=no
fi
assert_eq "yes" "$lock_survived_21d" "cursor: a run that failed to acquire the lock must NOT remove the other run's still-active lock directory"
after21d=$(full_tree_listing "$home21d")
assert_eq "$before21d" "$after21d" "21d (G2): \$HOME tree must be completely unchanged after lock contention (squirrel-mode.mdc must never have been written)"

# --- 21b: same coverage as 21, for the Cursor installer -----------------
make_cursor_installer_scratch() {
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-cursor-installer-scratch.XXXXXX")
  mkdir -p "$scratch/targets/cursor/commands"
  cp "$repo_root/targets/cursor/squirrel-mode.mdc" "$scratch/targets/cursor/squirrel-mode.mdc"
  cp "$repo_root/targets/cursor/commands/digest.md" "$scratch/targets/cursor/commands/digest.md"
  cp "$repo_root/targets/cursor/commands/plan.md" "$scratch/targets/cursor/commands/plan.md"
  cp "$cursor_install" "$scratch/targets/cursor/install.sh"
  chmod +x "$scratch/targets/cursor/install.sh"
  printf '%s\n' "$scratch"
}

installer_scratch_21b=$(make_cursor_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_21b"
home21b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home21b"
mkdir -p "$home21b/.cursor/rules"

# shellcheck disable=SC2016 # single-quoted deliberately: the literal
# source text to grep for in the scratch install.sh copy.
line21b=$(grep -n -F 'mv "$temp" "$destination"' "$installer_scratch_21b/targets/cursor/install.sh" | head -n 1 | cut -d: -f1)
marker21b="$installer_scratch_21b/write-marker"
awk -v n="$line21b" -v m="$marker21b" 'NR == n { print "touch \"" m "\""; print "sleep 3"; print; next } { print }' "$installer_scratch_21b/targets/cursor/install.sh" >"$installer_scratch_21b/targets/cursor/install.sh.new"
mv "$installer_scratch_21b/targets/cursor/install.sh.new" "$installer_scratch_21b/targets/cursor/install.sh"
chmod +x "$installer_scratch_21b/targets/cursor/install.sh"

HOME="$home21b" "$installer_scratch_21b/targets/cursor/install.sh" --yes >"$installer_scratch_21b/run.out" 2>&1 &
pid21b=$!
marker_status_21b=$(wait_for_marker_21 "$marker21b")
assert_eq "seen" "$marker_status_21b" "signal test fixture 21b: the write-phase marker must appear before the poll timeout (a fixture problem if not, not an install.sh problem)"

kill -TERM "$pid21b" 2>/dev/null || true
if wait "$pid21b"; then
  sig_exit_21b=0
else
  sig_exit_21b=$?
fi
assert_eq "143" "$sig_exit_21b" "SIGTERM during a cursor installer write must make it exit 143 (128+SIGTERM) promptly -- install.sh output: $(read_file "$installer_scratch_21b/run.out")"

leftover_21b=$(find "$home21b" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover_21b" "no leftover temp file must remain anywhere in \$HOME after a SIGTERM mid-write on the cursor installer (A8)"
assert_file_absent "$home21b/.cursor/rules/squirrel-mode.mdc" "the cursor .mdc must not exist after a SIGTERM mid-write (the mv never ran, and none existed before)"
assert_file_absent "$home21b/.cursor/.squirrel-install.lock" "the A3 lock directory must be released (removed) even after a SIGTERM mid-write on the cursor installer, not left behind forever (F1/F5 - codex has this coverage at scenario 21; cursor did not)"

# ==========================================================================
# 22 (C2). CDPATH hardening (A10): a CDPATH entry containing "." must
#    not break either installer. Invoked via a RELATIVE path from
#    repo_root (not an absolute one) - CDPATH only affects `cd` when its
#    operand does not already start with "/" or ".", so an absolute
#    invocation would never exercise the bug this guards against.
# ==========================================================================
home22a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home22a"
mkdir -p "$home22a/.codex"
if out22a=$(cd "$repo_root" && CDPATH=. HOME="$home22a" sh targets/codex/install.sh --yes 2>&1); then exit22a=0; else exit22a=$?; fi
assert_eq "0" "$exit22a" "codex install.sh must succeed with CDPATH=. set, invoked via a relative path (A10) -- output: $out22a"

home22b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home22b"
mkdir -p "$home22b/.cursor"
if out22b=$(cd "$repo_root" && CDPATH=. HOME="$home22b" sh targets/cursor/install.sh --yes 2>&1); then exit22b=0; else exit22b=$?; fi
assert_eq "0" "$exit22b" "cursor install.sh must succeed with CDPATH=. set, invoked via a relative path (A10) -- output: $out22b"

# ==========================================================================
# 23 (C3). mtime, not just content, must be unchanged on a second --yes
#    run: asserts the cmp -s short-circuit is actually short-circuiting,
#    not merely rewriting identical content every time (which a content-
#    only cksum snapshot, as scenario 7 uses, could not distinguish).
# ==========================================================================
home23a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home23a"
mkdir -p "$home23a/.codex"
HOME="$home23a" "$codex_install" --yes >/dev/null 2>&1
mtime_ref_23a="$home23a/.mtime-ref"
touch "$mtime_ref_23a"
sleep 1
HOME="$home23a" "$codex_install" --yes >/dev/null 2>&1
newer_agents_23a=$(find "$home23a/.codex/AGENTS.md" -newer "$mtime_ref_23a" 2>/dev/null || true)
assert_eq "" "$newer_agents_23a" "a second --yes run against an already-up-to-date AGENTS.md must not touch its mtime (C3)"
for cmd_name in digest plan init tune; do
  newer_skill_23a=$(find "$home23a/.agents/skills/$cmd_name/SKILL.md" -newer "$mtime_ref_23a" 2>/dev/null || true)
  assert_eq "" "$newer_skill_23a" "a second --yes run must not touch the mtime of an already-up-to-date $cmd_name skill file (C3)"
done
rm -f "$mtime_ref_23a"

home23b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home23b"
mkdir -p "$home23b/.cursor"
HOME="$home23b" "$cursor_install" --yes >/dev/null 2>&1
mtime_ref_23b="$home23b/.mtime-ref"
touch "$mtime_ref_23b"
sleep 1
HOME="$home23b" "$cursor_install" --yes >/dev/null 2>&1
newer_mdc_23b=$(find "$home23b/.cursor/rules/squirrel-mode.mdc" -newer "$mtime_ref_23b" 2>/dev/null || true)
assert_eq "" "$newer_mdc_23b" "a second --yes cursor run against an already-up-to-date .mdc must not touch its mtime (C3)"
rm -f "$mtime_ref_23b"

# ==========================================================================
# 24. An UNTERMINATED fence at end of file must fail install loudly,
#     not append the real block inside the fence. Per marker_scan's own
#     fence-awareness (A1), a fence that never closes runs to end of
#     file - so appending squirrel-mode's block onto a file that ends
#     inside one would place the new block INSIDE that same fence,
#     making it invisible to marker_scan on every later run: a second
#     install would append yet another copy instead of updating the
#     first, and uninstall could never find any block to remove. This
#     pins the guard added specifically to close that gap.
# ==========================================================================
home24=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home24"
mkdir -p "$home24/.codex"
printf 'my own content\n\nHere is an unterminated fence example:\n```\nsome content that never closes the fence\n' >"$home24/.codex/AGENTS.md"
original_24=$(cat "$home24/.codex/AGENTS.md")
before24=$(full_tree_listing "$home24")
if out24=$(HOME="$home24" "$codex_install" --yes 2>&1); then exit24=0; else exit24=$?; fi
assert_eq "1" "$exit24" "install must exit non-zero against an AGENTS.md ending inside an unterminated fence, rather than append the block where it can never be found again -- output: $out24"
assert_contains "$out24" "unterminated" "the failure message must name the unterminated fence as the cause"
after24=$(cat "$home24/.codex/AGENTS.md")
assert_eq "$original_24" "$after24" "AGENTS.md must be byte-unchanged after install refuses an unterminated-fence file"
after_tree24=$(full_tree_listing "$home24")
assert_eq "$before24" "$after_tree24" "24 (G2): \$HOME tree must be completely unchanged after the unterminated-fence refusal (no skill files created either)"
leftover24=$(find "$home24" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover24" "no leftover temp file after install refuses an unterminated-fence file"

# ==========================================================================
# 25. A ~~~ fence (not just ```` ``` ````), with an info string after the
#     opener, quoting the BEGIN/END markers, must round-trip
#     byte-identical too - the same A1 fence-awareness, the other fence
#     character and the info-string case scenario 16 does not cover.
# ==========================================================================
home25=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home25"
mkdir -p "$home25/.codex"
cat >"$home25/.codex/AGENTS.md" <<'TILDE_FENCE_EOF'
My own instructions.

Example, using tildes and an info string this time:
~~~text
<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
some fake content that must never be treated as the real block
<!-- END SQUIRREL-MODE -->
~~~

More of my own content after the example.
TILDE_FENCE_EOF
tilde_original_25=$(cat "$home25/.codex/AGENTS.md")
if tilde_install_out_25=$(HOME="$home25" "$codex_install" --yes 2>&1); then tilde_install_exit_25=0; else tilde_install_exit_25=$?; fi
assert_eq "0" "$tilde_install_exit_25" "install must exit 0 against a ~~~ fenced example with an info string -- output: $tilde_install_out_25"
tilde_after_install_25=$(cat "$home25/.codex/AGENTS.md")
case "$tilde_after_install_25" in
  "$tilde_original_25"*)
    tilde_prefix_survived_25=yes
    ;;
  *)
    tilde_prefix_survived_25=no
    ;;
esac
assert_eq "yes" "$tilde_prefix_survived_25" "the ~~~ fenced example must survive install completely unmodified, as a verbatim prefix of the file (A1: ~~~ fences and info strings)"
if tilde_uninstall_out_25=$(HOME="$home25" "$codex_install" --uninstall --yes 2>&1); then tilde_uninstall_exit_25=0; else tilde_uninstall_exit_25=$?; fi
assert_eq "0" "$tilde_uninstall_exit_25" "uninstall must exit 0 against a ~~~ fenced example -- output: $tilde_uninstall_out_25"
tilde_after_uninstall_25=$(cat "$home25/.codex/AGENTS.md")
if [ "$tilde_after_uninstall_25" = "$tilde_original_25" ]; then
  tilde_roundtrip_25=identical
else
  tilde_roundtrip_25=DIFFERS
fi
assert_eq "identical" "$tilde_roundtrip_25" "install then uninstall of a file containing a ~~~ fenced BEGIN/END example (with an info string) must round-trip byte-identical (A1)"

# ==========================================================================
# 26 (F1, mutation-proof). The lock's mkdir must NEVER be reached during
#    a dry run - proven by injecting a marker immediately after the line
#    that runs ONLY once this run's own mkdir has actually succeeded
#    (`lock_dir="$candidate_lock_dir"`), rather than relying on the lock
#    directory's own after-the-fact absence: that is true in BOTH the
#    fixed and the pre-fix version, because the EXIT trap removes the
#    lock before the process exits either way - the marker file is a
#    SEPARATE file the trap never touches, so its presence is a direct,
#    unambiguous record of whether the mkdir-success branch ever ran.
#    Checked both ways, for both installers: the marker must be ABSENT
#    after a dry run (F1's fix) and PRESENT after a real --yes run (a
#    sanity check that the injection itself is reachable at all - without
#    it, "absent on a dry run" could just mean the injection is broken).
# ==========================================================================
inject_lock_marker() {
  # inject_lock_marker <installer_copy_path> <marker_path>: inserts a
  # `touch <marker_path>` immediately after the FIRST line reading
  # exactly `lock_dir="$candidate_lock_dir"` in <installer_copy_path>.
  file=$1
  marker=$2
  # shellcheck disable=SC2016 # single-quoted deliberately: the literal
  # source text to grep for in the scratch install.sh copy, not an
  # expression to expand in THIS shell.
  line=$(grep -n -F 'lock_dir="$candidate_lock_dir"' "$file" | head -n 1 | cut -d: -f1)
  awk -v n="$line" -v m="$marker" 'NR == n { print; print "touch \"" m "\""; next } { print }' "$file" >"$file.new"
  mv "$file.new" "$file"
  chmod +x "$file"
}

installer_scratch_26c=$(make_codex_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_26c"
marker26c="$installer_scratch_26c/lock-mkdir-marker"
inject_lock_marker "$installer_scratch_26c/targets/codex/install.sh" "$marker26c"

home26c_dry=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home26c_dry"
mkdir -p "$home26c_dry/.codex"
HOME="$home26c_dry" "$installer_scratch_26c/targets/codex/install.sh" >/dev/null 2>&1
assert_file_absent "$marker26c" "F1 (codex): a dry run must never reach the lock's mkdir-success line at all"

home26c_real=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home26c_real"
mkdir -p "$home26c_real/.codex"
HOME="$home26c_real" "$installer_scratch_26c/targets/codex/install.sh" --yes >/dev/null 2>&1
assert_file_exists "$marker26c" "F1 sanity (codex): a REAL --yes run must still reach the lock's mkdir-success line - otherwise the dry-run absence above proves nothing"

installer_scratch_26u=$(make_cursor_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_26u"
marker26u="$installer_scratch_26u/lock-mkdir-marker"
inject_lock_marker "$installer_scratch_26u/targets/cursor/install.sh" "$marker26u"

home26u_dry=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home26u_dry"
mkdir -p "$home26u_dry/.cursor"
HOME="$home26u_dry" "$installer_scratch_26u/targets/cursor/install.sh" >/dev/null 2>&1
assert_file_absent "$marker26u" "F1 (cursor): a dry run must never reach the lock's mkdir-success line at all"

home26u_real=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home26u_real"
mkdir -p "$home26u_real/.cursor"
HOME="$home26u_real" "$installer_scratch_26u/targets/cursor/install.sh" --yes >/dev/null 2>&1
assert_file_exists "$marker26u" "F1 sanity (cursor): a REAL --yes run must still reach the lock's mkdir-success line - otherwise the dry-run absence above proves nothing"

# ==========================================================================
# 27 (F3). Under a permissive umask, a freshly CREATED destination must
#    not be group/world-writable - `chmod go-w` on write_destination's
#    create branch. AGENTS.md is the case that actually discriminates
#    the mutation (its staging content is generated fresh via shell
#    redirection, which follows the umask); the skill file and the
#    .mdc's content_file is the committed repo source, whose OWN mode -
#    not the runtime umask - is what `cp` propagates when creating a new
#    file, so those two hold with or without this fix and are included
#    here for class coverage/regression only, not as mutation proof.
# ==========================================================================
home27a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home27a"
mkdir -p "$home27a/.codex"
(umask 000 && HOME="$home27a" "$codex_install" --yes) >/dev/null 2>&1
mode27a=$(file_mode10 "$home27a/.codex/AGENTS.md")
assert_eq "-rw-r--r--" "$mode27a" "F3: under umask 000, a freshly CREATED ~/.codex/AGENTS.md must not be group/world-writable (was 666 before this fix)"

home27b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home27b"
mkdir -p "$home27b/.codex"
(umask 000 && HOME="$home27b" "$codex_install" --yes) >/dev/null 2>&1
mode27b=$(file_mode10 "$home27b/.agents/skills/digest/SKILL.md")
assert_eq "-rw-r--r--" "$mode27b" "F3 (class coverage, not mutation-discriminating): under umask 000, a freshly created skill file must not be group/world-writable either"

home27c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home27c"
mkdir -p "$home27c/.cursor"
(umask 000 && HOME="$home27c" "$cursor_install" --yes) >/dev/null 2>&1
mode27c=$(file_mode10 "$home27c/.cursor/rules/squirrel-mode.mdc")
assert_eq "-rw-r--r--" "$mode27c" "F3 (class coverage, not mutation-discriminating): under umask 000, a freshly created cursor .mdc must not be group/world-writable either"

# ==========================================================================
# 28 (F4). A symlinked destination must be REFUSED, not replaced - on
#    BOTH install and uninstall, on BOTH installers, for the shared
#    AGENTS.md destination, a per-command skill destination, and the
#    Cursor .mdc destination.
# ==========================================================================
assert_symlink_refused() {
  # assert_symlink_refused <home> <installer> <dest_path> <decoy_path>
  # <decoy_content> <label>: seeds <decoy_content> at <decoy_path>,
  # symlinks <dest_path> -> <decoy_path>, then asserts BOTH
  # `<installer> --yes` and `<installer> --uninstall --yes` refuse
  # (exit 1, message mentions "symlink"), leave the symlink AT <dest_path>
  # completely unreplaced (still `-L`, still pointing at <decoy_path>),
  # leave <decoy_path>'s own content completely untouched, and (G2, S7
  # review cycle 3) leave the REST of $HOME - every other file and
  # directory, snapshotted right after the decoy+symlink are seeded -
  # completely unchanged too, for both the install attempt and the
  # uninstall attempt.
  home=$1
  installer=$2
  dest=$3
  decoy=$4
  content=$5
  label=$6
  printf '%s' "$content" >"$decoy"
  ln -s "$decoy" "$dest"

  before_install=$(full_tree_listing "$home")
  if out_install=$(HOME="$home" "$installer" --yes 2>&1); then exit_install=0; else exit_install=$?; fi
  assert_eq "1" "$exit_install" "$label: install --yes must refuse (exit 1) a symlinked destination -- output: $out_install"
  assert_contains "$out_install" "symlink" "$label: install's refusal message must mention 'symlink'"
  if [ -L "$dest" ]; then is_symlink_after_install=yes; else is_symlink_after_install=no; fi
  assert_eq "yes" "$is_symlink_after_install" "$label: the symlink at the destination must survive install's refusal (never replaced by mv)"
  target_after_install=$(readlink "$dest" 2>/dev/null || true)
  assert_eq "$decoy" "$target_after_install" "$label: the symlink must still point at the original decoy after install's refusal"
  decoy_after_install=$(read_file "$decoy")
  assert_eq "$content" "$decoy_after_install" "$label: the decoy file's content must be untouched after install's refusal"
  after_install=$(full_tree_listing "$home")
  assert_eq "$before_install" "$after_install" "$label (G2): the entire \$HOME tree must be unchanged after install's symlink refusal, not just the symlink and decoy"

  before_uninstall=$(full_tree_listing "$home")
  if out_uninstall=$(HOME="$home" "$installer" --uninstall --yes 2>&1); then exit_uninstall=0; else exit_uninstall=$?; fi
  assert_eq "1" "$exit_uninstall" "$label: uninstall --yes must ALSO refuse (exit 1) a symlinked destination -- output: $out_uninstall"
  assert_contains "$out_uninstall" "symlink" "$label: uninstall's refusal message must mention 'symlink'"
  if [ -L "$dest" ]; then is_symlink_after_uninstall=yes; else is_symlink_after_uninstall=no; fi
  assert_eq "yes" "$is_symlink_after_uninstall" "$label: the symlink at the destination must survive uninstall's refusal too"
  decoy_after_uninstall=$(read_file "$decoy")
  assert_eq "$content" "$decoy_after_uninstall" "$label: the decoy file's content must be untouched after uninstall's refusal too"
  after_uninstall=$(full_tree_listing "$home")
  assert_eq "$before_uninstall" "$after_uninstall" "$label (G2): the entire \$HOME tree must be unchanged after uninstall's symlink refusal too"
}

home28a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home28a"
mkdir -p "$home28a/.codex"
assert_symlink_refused "$home28a" "$codex_install" "$home28a/.codex/AGENTS.md" "$home28a/real-agents-target.md" "Decoy AGENTS.md content that must survive untouched." "Codex ~/.codex/AGENTS.md symlink"

home28b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home28b"
mkdir -p "$home28b/.codex" "$home28b/.agents/skills/digest"
assert_symlink_refused "$home28b" "$codex_install" "$home28b/.agents/skills/digest/SKILL.md" "$home28b/real-skill-target.md" "Decoy skill content that must survive untouched." "Codex ~/.agents/skills/digest/SKILL.md symlink"
# "REFUSES, changing nothing" (this script's own header) must hold even
# when the SYMLINKED destination is a skill file, not AGENTS.md itself:
# AGENTS.md sits ABOVE the skills loop in install.sh's Execution
# section, so without a symlink pre-flight covering the skill paths
# too, install --yes would write/create AGENTS.md FIRST and only THEN
# reach the skills loop and refuse - "changing nothing" would already
# be false. AGENTS.md did not exist before this scenario ran, so its
# continued absence here is the direct proof.
assert_file_absent "$home28b/.codex/AGENTS.md" "the symlink refusal for a SKILL destination must change NOTHING - AGENTS.md must not have been created as a side effect before the refusal fired"

home28c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home28c"
mkdir -p "$home28c/.cursor/rules"
assert_symlink_refused "$home28c" "$cursor_install" "$home28c/.cursor/rules/squirrel-mode.mdc" "$home28c/real-mdc-target.md" "Decoy mdc content that must survive untouched." "Cursor ~/.cursor/rules/squirrel-mode.mdc symlink"

# ==========================================================================
# 29 (F5). A READ-ONLY PARENT directory for the lock (EACCES) must be
#    reported as "could not create .../may not be writable", never as
#    lock contention - and the lock directory itself must never actually
#    have been created. Contrasts with the pre-existing lock-already-
#    exists scenario at 21c/21d above, which correctly keeps the
#    contention message for that different failure mode.
# ==========================================================================
home29a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home29a"
mkdir -p "$home29a/.codex"
chmod 555 "$home29a/.codex"
before29a=$(full_tree_listing "$home29a")
if out29a=$(HOME="$home29a" "$codex_install" --yes 2>&1); then exit29a=0; else exit29a=$?; fi
after29a=$(full_tree_listing "$home29a")
chmod 755 "$home29a/.codex"
assert_eq "1" "$exit29a" "codex install.sh must exit non-zero when the lock's mkdir fails with EACCES (read-only \$HOME/.codex) -- output: $out29a"
assert_not_contains "$out29a" "appears to be running" "F5 (codex): an EACCES mkdir failure must NOT be reported as lock contention - nothing is running, nothing was created"
assert_contains "$out29a" "may not be writable" "F5 (codex): an EACCES mkdir failure must say the parent directory may not be writable"
if [ -d "$home29a/.codex/.squirrel-install.lock" ]; then lock_after_29a=yes; else lock_after_29a=no; fi
assert_eq "no" "$lock_after_29a" "F5 (codex): no lock directory must exist after an EACCES mkdir failure (mkdir itself never succeeded)"
assert_eq "$before29a" "$after29a" "29a (G2): \$HOME tree must be completely unchanged after the EACCES lock failure (captured while \$HOME/.codex was still 555, so the comparison is unaffected by the chmod 755 restore below)"

home29b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home29b"
mkdir -p "$home29b/.cursor"
chmod 555 "$home29b/.cursor"
before29b=$(full_tree_listing "$home29b")
if out29b=$(HOME="$home29b" "$cursor_install" --yes 2>&1); then exit29b=0; else exit29b=$?; fi
after29b=$(full_tree_listing "$home29b")
chmod 755 "$home29b/.cursor"
assert_eq "1" "$exit29b" "cursor install.sh must exit non-zero when the lock's mkdir fails with EACCES (read-only \$HOME/.cursor) -- output: $out29b"
assert_not_contains "$out29b" "appears to be running" "F5 (cursor): an EACCES mkdir failure must NOT be reported as lock contention"
assert_contains "$out29b" "may not be writable" "F5 (cursor): an EACCES mkdir failure must say the parent directory may not be writable"
if [ -d "$home29b/.cursor/.squirrel-install.lock" ]; then lock_after_29b=yes; else lock_after_29b=no; fi
assert_eq "no" "$lock_after_29b" "F5 (cursor): no lock directory must exist after an EACCES mkdir failure"
assert_eq "$before29b" "$after29b" "29b (G2): \$HOME tree must be completely unchanged after the EACCES lock failure"

# ==========================================================================
# 30 (F6). A read-only AGENTS.md must never crash with a raw shell error
#    naming an internal temp/work-dir path - on a DRY RUN
#    (render_agents_install's own fix: stream, don't `cp`, into the
#    staging file) and on a REAL --yes run (write_destination's
#    class-closure guard: a clean fail() naming the real path, before
#    ever touching a temp file at all).
# ==========================================================================
home30=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home30"
mkdir -p "$home30/.codex"
printf 'My own read-only instructions.\nSecond line.\n' >"$home30/.codex/AGENTS.md"
original_captured_30=$(cat "$home30/.codex/AGENTS.md")
chmod 444 "$home30/.codex/AGENTS.md"
before30=$(full_tree_listing "$home30")

if out30dry=$(HOME="$home30" "$codex_install" 2>&1); then exit30dry=0; else exit30dry=$?; fi
assert_eq "0" "$exit30dry" "F6: a DRY RUN against a read-only (444) AGENTS.md must exit 0, not crash -- output: $out30dry"
assert_not_contains "$out30dry" "Permission denied" "F6: a dry run must never surface a raw 'Permission denied' shell error"
assert_not_contains "$out30dry" "squirrel-codex-install" "F6: a dry run's output must never leak an internal \$TMPDIR work-dir path"

if out30yes=$(HOME="$home30" "$codex_install" --yes 2>&1); then exit30yes=0; else exit30yes=$?; fi
assert_eq "1" "$exit30yes" "F6: a REAL --yes run against a read-only (444) AGENTS.md must fail cleanly (it genuinely cannot be updated in place) -- output: $out30yes"
assert_contains "$out30yes" "$home30/.codex/AGENTS.md" "F6: the --yes failure must name the REAL AGENTS.md path"
assert_contains "$out30yes" "not writable" "F6: the --yes failure must say the file is not writable, via a clean fail() message"
assert_not_contains "$out30yes" "Permission denied" "F6: the --yes failure must never surface a raw shell 'Permission denied' error"
assert_not_contains "$out30yes" "squirrel-codex-install" "F6: the --yes failure must never leak an internal \$TMPDIR work-dir path"
assert_not_contains "$out30yes" ".tmp." "F6: the --yes failure must never leak an internal .tmp staging file name"

after30=$(cat "$home30/.codex/AGENTS.md")
assert_eq "$original_captured_30" "$after30" "F6: AGENTS.md must be byte-unchanged after the clean --yes failure (the mv never ran)"
leftover30=$(find "$home30" -name '.*.tmp.*' 2>/dev/null || true)
assert_eq "" "$leftover30" "F6: no leftover temp file must remain after the clean --yes failure"
after_tree30=$(full_tree_listing "$home30")
assert_eq "$before30" "$after_tree30" "30 (G2): \$HOME tree must be completely unchanged across both the dry run and the real --yes failure against a read-only AGENTS.md (no skill files created either)"

# ==========================================================================
# 31 (F7). Marker-shaped lines found only inside a fenced code block
#    (correctly ignored, per A1) must be called out explicitly in BOTH
#    install's "would append" message AND uninstall's "no block"
#    message for the identical file - uninstall used to say nothing
#    about it at all.
# ==========================================================================
home31=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home31"
mkdir -p "$home31/.codex"
cat >"$home31/.codex/AGENTS.md" <<'FENCE31_EOF'
My own instructions.

Example of what the squirrel-mode block looks like:
```
<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
some fake content
<!-- END SQUIRREL-MODE -->
```

More of my own content after the example.
FENCE31_EOF

if out31install=$(HOME="$home31" "$codex_install" 2>&1); then exit31install=0; else exit31install=$?; fi
assert_eq "0" "$exit31install" "F7 fixture: install dry run against a fenced-only example must exit 0 -- output: $out31install"
assert_contains "$out31install" "fenced code block" "F7: install's 'would append' message must call out the fence-internal marker-shaped lines it found and correctly ignored"

home31u=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home31u"
mkdir -p "$home31u/.codex"
cat >"$home31u/.codex/AGENTS.md" <<'FENCE31U_EOF'
My own instructions, never installed here.

Example of what the squirrel-mode block looks like:
```
<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
some fake content
<!-- END SQUIRREL-MODE -->
```
FENCE31U_EOF

if out31uninstall=$(HOME="$home31u" "$codex_install" --uninstall 2>&1); then exit31uninstall=0; else exit31uninstall=$?; fi
assert_eq "0" "$exit31uninstall" "F7 fixture: uninstall dry run against a fenced-only example (never installed) must exit 0 -- output: $out31uninstall"
assert_contains "$out31uninstall" "no squirrel-mode block" "F7 sanity: uninstall must still report 'no squirrel-mode block' for this file"
assert_contains "$out31uninstall" "fenced code block" "F7: uninstall's 'no squirrel-mode block' message must ALSO call out the fence-internal marker-shaped lines it found and ignored - this is the exact gap F7 closes"

# ==========================================================================
# 32 (F1/F5 documentation completeness). The lock must be absent after
#    EVERY exit path, not just the SIGTERM path already covered at
#    scenarios 21/21b: --help, a bad/unknown argument, and a normal
#    successful --yes run that never contended with anything.
# ==========================================================================
# Every invocation below has its exit status explicitly captured via
# if/then/else, per this file's own established idiom - NEVER a bare
# unguarded call, even one expected to exit 0: under this file's own
# `set -eu`, a bare call that turns out to exit non-zero would abort
# the WHOLE test file right there (no SUMMARY line at all, every later
# assertion silently never runs) - the exact anti-pattern
# tests/lib/assert.sh's own header comment warns against.
home32a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32a"
mkdir -p "$home32a/.codex"
before32a=$(full_tree_listing "$home32a")
if HOME="$home32a" "$codex_install" --help >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32a/.codex/.squirrel-install.lock" "the lock must be absent after --help (codex)"
after32a=$(full_tree_listing "$home32a")
assert_eq "$before32a" "$after32a" "32a (G2): \$HOME tree must be completely unchanged after --help (codex)"

home32b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32b"
mkdir -p "$home32b/.codex"
before32b=$(full_tree_listing "$home32b")
if HOME="$home32b" "$codex_install" --this-flag-does-not-exist >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32b/.codex/.squirrel-install.lock" "the lock must be absent after a bad/unknown argument (codex)"
after32b=$(full_tree_listing "$home32b")
assert_eq "$before32b" "$after32b" "32b (G2): \$HOME tree must be completely unchanged after a bad/unknown argument (codex) - argument parsing happens before any \$HOME access, but a refusal is a refusal"

home32c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32c"
mkdir -p "$home32c/.codex"
if HOME="$home32c" "$codex_install" --yes >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32c/.codex/.squirrel-install.lock" "the lock must be absent immediately after a normal, uncontended --yes run completes (codex)"

home32d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32d"
mkdir -p "$home32d/.cursor"
before32d=$(full_tree_listing "$home32d")
if HOME="$home32d" "$cursor_install" --help >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32d/.cursor/.squirrel-install.lock" "the lock must be absent after --help (cursor)"
after32d=$(full_tree_listing "$home32d")
assert_eq "$before32d" "$after32d" "32d (G2): \$HOME tree must be completely unchanged after --help (cursor)"

home32e=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32e"
mkdir -p "$home32e/.cursor"
before32e=$(full_tree_listing "$home32e")
if HOME="$home32e" "$cursor_install" --this-flag-does-not-exist >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32e/.cursor/.squirrel-install.lock" "the lock must be absent after a bad/unknown argument (cursor)"
after32e=$(full_tree_listing "$home32e")
assert_eq "$before32e" "$after32e" "32e (G2): \$HOME tree must be completely unchanged after a bad/unknown argument (cursor)"

home32f=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home32f"
mkdir -p "$home32f/.cursor"
if HOME="$home32f" "$cursor_install" --yes >/dev/null 2>&1; then :; else :; fi
assert_file_absent "$home32f/.cursor/.squirrel-install.lock" "the lock must be absent immediately after a normal, uncontended --yes run completes (cursor)"

assert_report
