#!/bin/sh
# Coverage for S7: the ported command artifacts
# (targets/codex/skills/*/SKILL.md, targets/cursor/commands/*.md),
# both targets/{codex,cursor}/install.sh, and docs/OTHER-TOOLS.md.
# Extended in S9 (scenarios 34 and 35, near the end of this file) to
# also check that neither installer writes inside a project directory,
# and to pin README.md's checkpoint auto-approval disclosure text.
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
readme_doc="$repo_root/README.md"
plan_doc="$repo_root/PLAN.md"

cleanup_dirs=""
trap 'rm -rf $cleanup_dirs' EXIT

read_file() {
  # read_file <path> - prints file content, or empty string if missing.
  #
  # DELIBERATELY NOT USED for a round-trip / "must be byte-unchanged"
  # comparison - see files_byte_status below for why.
  if [ -f "$1" ]; then
    cat "$1"
  else
    printf ''
  fi
}

files_byte_status() {
  # files_byte_status <expected_file> <actual_file>: prints "identical"
  # when the two files are byte-for-byte equal, "DIFFERS" otherwise
  # (including either file being missing entirely - cmp's own diagnostic
  # is discarded so a missing file reports as a clean assertion failure
  # rather than noise).
  #
  # This exists because `assert_eq "$(read_file "$orig")" "$(read_file
  # "$after")"` - the shape every round-trip comparison in this file
  # except scenario 10 used to have - is STRUCTURALLY BLIND to exactly
  # the corruption class those round trips exist to catch: command
  # substitution strips ALL trailing newlines from what it captures, on
  # both sides, so a file that came back one trailing newline short (or
  # long) compares EQUAL. Proven, not theorised: mutating
  # render_agents_uninstall's `printf '%s'` to `printf '%s\n'` - a
  # direct, deliberate byte-exactness break in the installer - went
  # UNCAUGHT across all ten test files and every assertion in them.
  # Every "must round-trip / must be byte-unchanged" assertion below now
  # goes through this function, against a real snapshot FILE (see
  # snapshot_file), never through a shell variable.
  if cmp -s "$1" "$2" 2>/dev/null; then
    printf 'identical\n'
  else
    printf 'DIFFERS\n'
  fi
}

snapshot_file() {
  # snapshot_file <path>: copies <path> to a fresh throwaway file
  # OUTSIDE any scenario's $HOME (so it can never be mistaken for
  # content under test, nor appear in a full_tree_listing snapshot) and
  # prints that copy's path. Registered for cleanup by the caller
  # (cleanup_dirs="$cleanup_dirs $result"), exactly like make_temp_home
  # above - a registration made INSIDE this function would be lost, the
  # function being run in a command substitution's subshell.
  snap=$(mktemp "${TMPDIR:-/tmp}/squirrel-snapshot.XXXXXX")
  cp "$1" "$snap"
  printf '%s\n' "$snap"
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
  # regenerates all fifteen artifacts, never touching the real repo.
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

# --- NO SCENARIO IN THIS FILE MAY INVOKE THE REAL REPO'S build.sh -------
#
# build.sh derives its own repo_root from its own location, so running
# "$build_script" (the repo's own copy) WRITES all fifteen generated
# artifacts into the working tree under test. Scenario 6's idempotence
# half used to do exactly that; see its own comment for what that cost.
# Every build.sh invocation in this file goes through make_full_scratch
# above and runs "$scratch/scripts/build.sh" instead. $build_script is
# read (and copied) but never executed.
#
# generated_target_rel_paths is every generated file under targets/ -
# the two derived from rules/base-rules.md AND the ten ported from
# skills/*/SKILL.md AND the Cursor hooks.json - and is used both by
# scenario 6's drift check and
# by the tripwire at the bottom of this file. The last four skill
# entries are
# the Cursor Agent Skills, which are generated exactly like every other
# entry here and must therefore be drift-checked exactly like them: a
# hand-edit to any one (say, deleting its disable-model-invocation
# line, which is the whole reason it behaves as a slash command rather
# than something Cursor fires on its own) has to fail this file.
generated_target_rel_paths="targets/codex/AGENTS.md targets/cursor/squirrel-mode.mdc targets/codex/skills/digest/SKILL.md targets/codex/skills/plan/SKILL.md targets/codex/skills/init/SKILL.md targets/codex/skills/tune/SKILL.md targets/cursor/commands/digest.md targets/cursor/commands/plan.md targets/cursor/skills/squirrel-digest/SKILL.md targets/cursor/skills/squirrel-plan/SKILL.md targets/cursor/skills/squirrel-init/SKILL.md targets/cursor/skills/squirrel-tune/SKILL.md targets/cursor/hooks/hooks.json"

# The four Cursor Agent Skills, as "<source command name>:<folder name>"
# pairs. Cursor requires a skill's frontmatter `name` to match its parent
# folder EXACTLY, and the folder carries a "squirrel-" prefix because
# Cursor has no command namespace - so every assertion below that touches
# a generated skill derives both halves from this single list rather than
# spelling the prefix out again per call site. Installer coverage keeps
# a separate digest/plan-only list: Task 8, not this one, stops copying
# skills into ~/.cursor/skills/, so install.sh's cursor_skill_names
# stays digest/plan until then.
cursor_skill_pairs="digest:squirrel-digest plan:squirrel-plan init:squirrel-init tune:squirrel-tune"
cursor_installed_skill_pairs="digest:squirrel-digest plan:squirrel-plan"

repo_generated_snapshot() {
  # Prints one "<rel> <cksum>" line per generated targets/ artifact,
  # with the volatile absolute path stripped (cksum reads stdin, so it
  # prints no filename), so two calls compare equal iff every one of
  # those files is byte-identical.
  for rel in $generated_target_rel_paths; do
    if [ -f "$repo_root/$rel" ]; then
      printf '%s %s\n' "$rel" "$(cksum <"$repo_root/$rel")"
    else
      printf '%s MISSING\n' "$rel"
    fi
  done
}
repo_generated_before=$(repo_generated_snapshot)

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
  if [ ! -f "$1" ]; then
    return 0
  fi
  awk -v key="$2" '
    /^---$/ { c++; if (c == 2) exit; next }
    c == 1 && $0 ~ ("^" key ":") { print; exit }
  ' "$1"
}

# ==========================================================================
# 1. build.sh generates exactly the four Codex skills, two Cursor
#    commands, and four Cursor Agent Skills. pickup/off/on are absent
#    from BOTH targets. init/tune port to Cursor as Agent Skills only -
#    never as project commands (plugin skills cover the machine).
# ==========================================================================
for cmd_name in digest plan init tune; do
  assert_file_exists "$repo_root/targets/codex/skills/$cmd_name/SKILL.md" "targets/codex/skills/$cmd_name/SKILL.md must exist"
done
for cmd_name in digest plan; do
  assert_file_exists "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must exist"
done
for pair in $cursor_skill_pairs; do
  folder=${pair#*:}
  assert_file_exists "$repo_root/targets/cursor/skills/$folder/SKILL.md" "targets/cursor/skills/$folder/SKILL.md must exist (the user-level Cursor Agent Skill, installed once for every project)"
done
for cmd_name in pickup off on; do
  assert_file_absent "$repo_root/targets/codex/skills/$cmd_name/SKILL.md" "targets/codex/skills/$cmd_name/SKILL.md must NOT exist ($cmd_name is not ported to Codex - see PLAN.md's parity table)"
  assert_file_absent "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must NOT exist ($cmd_name is not ported to Cursor)"
  assert_file_absent "$repo_root/targets/cursor/skills/squirrel-$cmd_name/SKILL.md" "targets/cursor/skills/squirrel-$cmd_name/SKILL.md must NOT exist ($cmd_name needs a lifecycle hook Cursor does not have)"
done
for cmd_name in init tune; do
  assert_file_absent "$repo_root/targets/cursor/commands/$cmd_name.md" "targets/cursor/commands/$cmd_name.md must NOT exist ($cmd_name is a Cursor Agent Skill, not a project command)"
done

codex_skill_dir_count=$(find "$repo_root/targets/codex/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "4" "$codex_skill_dir_count" "targets/codex/skills/ must contain exactly 4 command directories"

cursor_command_count=$(find "$repo_root/targets/cursor/commands" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "2" "$cursor_command_count" "targets/cursor/commands/ must contain exactly 2 command files (digest and plan only; init/tune are skills, not commands)"

cursor_skill_dir_count=$(find "$repo_root/targets/cursor/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "4" "$cursor_skill_dir_count" "targets/cursor/skills/ must contain exactly 4 skill directories"

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
for pair in $cursor_skill_pairs; do
  cmd_name=${pair%%:*}
  folder=${pair#*:}
  content=$(read_file "$repo_root/targets/cursor/skills/$folder/SKILL.md")
  assert_contains "$content" "GENERATED FILE" "Cursor $folder skill must carry a GENERATED marker"
  assert_contains "$content" "skills/$cmd_name/SKILL.md" "Cursor $folder skill's marker must name skills/$cmd_name/SKILL.md as its source"
  assert_contains "$content" "scripts/build.sh" "Cursor $folder skill's marker must name scripts/build.sh as the generator"
done

# ==========================================================================
# 3. No generated Codex or Cursor artifact mentions a mechanism its
#    host lacks: injected-context lines, hooks, sentinels, PENDING,
#    CLEAR, or ~/.squirrel/off/. Case-SENSITIVE throughout -
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
off_flag_dir_needle='~/.squirrel/off/'
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
for pair in $cursor_skill_pairs; do
  folder=${pair#*:}
  content=$(read_file "$repo_root/targets/cursor/skills/$folder/SKILL.md")
  for term in $forbidden_terms; do
    assert_not_contains "$content" "$term" "Cursor $folder skill must not mention '$term' (a mechanism Cursor lacks)"
  done
  assert_not_contains "$content" "$off_flag_dir_needle" "Cursor $folder skill must not mention the off-flag directory"
  assert_not_contains "$content" "Session working directory" "Cursor $folder skill must not mention the injected 'Session working directory:' line"
  assert_not_contains "$content" "Project checkpoint path" "Cursor $folder skill must not mention the injected 'Project checkpoint path:' line"
done

# ==========================================================================
# 4. init and tune (Codex) reference the exact shared profile path.
# ==========================================================================
# shellcheck disable=SC2088 # same reasoning as off_flag_dir_needle above.
profile_path_needle='~/.squirrel/profile.md'
for cmd_name in init tune; do
  content=$(read_file "$repo_root/targets/codex/skills/$cmd_name/SKILL.md")
  assert_contains "$content" "$profile_path_needle" "Codex $cmd_name skill must reference the shared squirrel-mode profile path (the same file Claude Code and Cursor read)"
done

# ==========================================================================
# 4b. Cursor init/tune are Agent Skills only. After a successful Write
#     of ~/.squirrel/profile.md they tell the user to start a new chat;
#     they must not inherit Codex's "Cursor cannot read it" caveat, and
#     must not keep Claude's mid-session demonstration. Canonical Claude
#     sources and Codex artifacts stay put.
# ==========================================================================
cursor_profile_new_chat_sentence="Start a new chat for the profile to take effect; this chat will not pick it up."
claude_init_next_message_needle="immediately answer the user's very next message using the new profile"
for cmd_name in init tune; do
  content=$(read_file "$repo_root/targets/cursor/skills/squirrel-$cmd_name/SKILL.md")
  assert_contains "$content" "$profile_path_needle" "Cursor $cmd_name skill must reference the shared squirrel-mode profile path"
  assert_contains "$content" "$cursor_profile_new_chat_sentence" "Cursor $cmd_name skill must tell the user to start a new chat after writing the profile"
  assert_not_contains "$content" "Cursor cannot read it at all" "Cursor $cmd_name skill must not inherit Codex's 'Cursor cannot read it at all' paragraph"
  assert_not_contains "$content" "Cursor cannot read this file at all" "Cursor $cmd_name skill must not inherit Codex's 'Cursor cannot read this file at all' paragraph"
  assert_not_contains "$content" "$claude_init_next_message_needle" "Cursor $cmd_name skill must not keep Claude's mid-session 'immediately answer the next message' demonstration"
  assert_not_contains "$content" "/squirrel:" "Cursor $cmd_name skill must not contain /squirrel:"
  assert_not_contains "$content" "CLAUDE_PLUGIN_ROOT" "Cursor $cmd_name skill must not contain CLAUDE_PLUGIN_ROOT"
  assert_not_contains "$content" "SessionStart" "Cursor $cmd_name skill must not contain SessionStart"
  assert_not_contains "$content" "UserPromptSubmit" "Cursor $cmd_name skill must not contain UserPromptSubmit"
  assert_not_contains "$content" "PreToolUse" "Cursor $cmd_name skill must not contain PreToolUse"
  dmi_count=$(printf '%s\n' "$content" | grep -c -F "disable-model-invocation: true" || true)
  assert_eq "1" "$dmi_count" "Cursor squirrel-$cmd_name skill must contain disable-model-invocation: true exactly once"

  codex_content=$(read_file "$repo_root/targets/codex/skills/$cmd_name/SKILL.md")
  case "$cmd_name" in
    init) codex_caveat="Cursor cannot read it at all" ;;
    tune) codex_caveat="Cursor cannot read this file at all" ;;
  esac
  assert_contains "$codex_content" "$codex_caveat" "Codex $cmd_name skill must keep its existing Cursor-cannot-read paragraph"

  claude_content=$(read_file "$repo_root/skills/$cmd_name/SKILL.md")
  assert_contains "$claude_content" "/squirrel:$cmd_name" "canonical skills/$cmd_name/SKILL.md must stay the Claude source (still names /squirrel:$cmd_name)"
done
claude_init_content=$(read_file "$repo_root/skills/init/SKILL.md")
assert_contains "$claude_init_content" "$claude_init_next_message_needle" "canonical skills/init/SKILL.md must keep Claude's mid-session demonstration sentence"

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
# 5b. Cursor AGENT SKILL frontmatter, against Cursor's own documented
#     schema for ~/.cursor/skills/<folder>/SKILL.md:
#       - `name` is required, lowercase letters/numbers/hyphens only, and
#         MUST match the parent folder name exactly. A mismatch is not a
#         cosmetic problem: the folder is what Cursor discovers and the
#         field is what it registers, so the two disagreeing is how a
#         skill silently fails to load.
#       - `description` is required.
#       - `disable-model-invocation: true` is what makes these behave as
#         the explicit /squirrel-digest, /squirrel-plan, /squirrel-init
#         and /squirrel-tune slash commands
#         rather than something the model may fire on its own. Cursor
#         Agent Skills have NO alwaysApply equivalent, so this field is
#         the only control over when they run, and it is pinned exactly.
#     The "squirrel-" prefix itself is pinned too: Cursor has no command
#     namespace, so an unprefixed "digest" would sit in the user's global
#     skill namespace under a name their own skill could just as
#     plausibly want.
# ==========================================================================
for pair in $cursor_skill_pairs; do
  folder=${pair#*:}
  f="$repo_root/targets/cursor/skills/$folder/SKILL.md"
  if [ -f "$f" ]; then
    first_line=$(head -n 1 "$f")
  else
    first_line=""
  fi
  assert_eq "---" "$first_line" "Cursor $folder skill must OPEN with a YAML frontmatter delimiter (unlike a Cursor command, an Agent Skill requires frontmatter)"
  name_line=$(extract_frontmatter_line "$f" "name")
  assert_eq "name: $folder" "$name_line" "Cursor $folder skill's frontmatter name must match its own parent folder exactly (Cursor's documented requirement)"
  case "$folder" in
    squirrel-*) prefixed=yes ;;
    *) prefixed=no ;;
  esac
  assert_eq "yes" "$prefixed" "Cursor $folder skill's folder must carry the squirrel- prefix - Cursor has no command namespace, so an unprefixed name would collide with a user's own skill"
  case "$folder" in
    *[!a-z0-9-]*) name_charset=invalid ;;
    *) name_charset=valid ;;
  esac
  assert_eq "valid" "$name_charset" "Cursor $folder skill's name must be lowercase letters, numbers and hyphens only (Cursor's documented constraint)"
  desc_line=$(extract_frontmatter_line "$f" "description")
  if [ -n "$desc_line" ]; then desc_present=yes; else desc_present=no; fi
  assert_eq "yes" "$desc_present" "Cursor $folder skill's frontmatter must have a description field"
  dmi_line=$(extract_frontmatter_line "$f" "disable-model-invocation")
  assert_eq "disable-model-invocation: true" "$dmi_line" "Cursor $folder skill must set disable-model-invocation: true - Cursor Agent Skills have no alwaysApply, so this is the only thing making it an explicit /$folder invocation instead of something the model may fire on its own"
done

# ==========================================================================
# 5c. The Cursor "skill" -> "command" word swap must NOT be applied to a
#     Cursor AGENT SKILL. write_cursor_command runs that swap because in
#     THAT artifact the mechanism really is a Cursor command; these files
#     are skills, in a file Cursor itself requires to be named SKILL.md,
#     so the shared body's own wording is already right and rewriting it
#     would make it wrong. Pinned against the exact opening sentence each
#     body carries, and against the swapped form the command artifact
#     carries - so applying the swap here, or dropping it from the
#     command, fails immediately in one direction or the other.
# ==========================================================================
cursor_skill_opener_digest="This skill restructures messy inbound content into the fixed brief below."
cursor_skill_opener_plan="This skill turns a raw, disordered idea into a scoped, startable plan."
cursor_command_opener_digest="This command restructures messy inbound content into the fixed brief below."
cursor_command_opener_plan="This command turns a raw, disordered idea into a scoped, startable plan."

cursor_skill_digest_body=$(read_file "$repo_root/targets/cursor/skills/squirrel-digest/SKILL.md")
assert_contains "$cursor_skill_digest_body" "$cursor_skill_opener_digest" "the Cursor digest AGENT SKILL must keep the word 'skill' in its opening sentence - the command-only swap must not have run on it"
assert_not_contains "$cursor_skill_digest_body" "$cursor_command_opener_digest" "the Cursor digest AGENT SKILL must NOT carry the command artifact's swapped opening sentence"

cursor_skill_plan_body=$(read_file "$repo_root/targets/cursor/skills/squirrel-plan/SKILL.md")
assert_contains "$cursor_skill_plan_body" "$cursor_skill_opener_plan" "the Cursor plan AGENT SKILL must keep the word 'skill' in its opening sentence - the command-only swap must not have run on it"
assert_not_contains "$cursor_skill_plan_body" "$cursor_command_opener_plan" "the Cursor plan AGENT SKILL must NOT carry the command artifact's swapped opening sentence"

cursor_command_digest_body=$(read_file "$repo_root/targets/cursor/commands/digest.md")
assert_contains "$cursor_command_digest_body" "$cursor_command_opener_digest" "the Cursor digest COMMAND must still carry the swapped wording - the swap is not disabled globally, only skipped for the Agent Skills"
cursor_command_plan_body=$(read_file "$repo_root/targets/cursor/commands/plan.md")
assert_contains "$cursor_command_plan_body" "$cursor_command_opener_plan" "the Cursor plan COMMAND must still carry the swapped wording - the swap is not disabled globally, only skipped for the Agent Skills"

# ==========================================================================
# 6. Idempotence and drift for ALL ELEVEN generated artifacts under
#    targets/.
#
#    TWO defects were fixed here, and both are load-bearing:
#
#    a) COVERAGE. This scenario used to list only the six PORTED
#       artifacts (4 Codex SKILL.md + 2 Cursor commands) and omit the
#       two that targets/ also ships from rules/base-rules.md:
#       targets/codex/AGENTS.md and targets/cursor/squirrel-mode.mdc.
#       A hand-edit to either of those - e.g. flipping the .mdc's
#       `alwaysApply: true` to `false` - passed this whole file clean.
#       The list below is now every generated file under targets/,
#       whichever source it derives from - which as of Cursor init/tune
#       Agent Skills is thirteen files, not eleven.
#
#    b) THE TEST MUST NOT WRITE INTO THE TREE IT IS TESTING. The
#       idempotence half used to invoke "$build_script" - the REPO's own
#       copy - and build.sh derives its repo_root from its own location,
#       so that run regenerated all fifteen artifacts straight into the
#       working tree under test. A genuine drift was therefore
#       reportable exactly ONCE: the same run that reported it had
#       already rewritten the file back to canonical, `git status
#       --porcelain` came back empty afterwards, and every later run
#       passed. Idempotence is a property of build.sh, not of the
#       repository, so it is proven below by building TWICE inside one
#       make_full_scratch copy. The repository working tree is READ ONLY
#       for the whole of this file, and the tripwire at the bottom
#       asserts that outright.
#
#    generated_target_rel_paths is defined near the top of this file,
#    next to repo_generated_snapshot, because the tripwire needs the
#    same list before scenario 1 runs.
# ==========================================================================
idem_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $idem_scratch"
if idem_build_out=$("$idem_scratch/scripts/build.sh" 2>&1); then
  idem_build_exit=0
else
  idem_build_exit=$?
fi
assert_eq "0" "$idem_build_exit" "scripts/build.sh (first run, scratch) must exit 0 -- output: $idem_build_out"

snap_before=""
for rel in $generated_target_rel_paths; do
  assert_file_exists "$idem_scratch/$rel" "scratch build must produce $rel"
  if [ -f "$idem_scratch/$rel" ]; then
    snap_before="$snap_before
$rel $(cksum <"$idem_scratch/$rel")"
  else
    snap_before="$snap_before
$rel MISSING"
  fi
done

if idem_build2_out=$("$idem_scratch/scripts/build.sh" 2>&1); then
  idem_build2_exit=0
else
  idem_build2_exit=$?
fi
assert_eq "0" "$idem_build2_exit" "scripts/build.sh (second run, same scratch) must exit 0 -- output: $idem_build2_out"

snap_after=""
for rel in $generated_target_rel_paths; do
  if [ -f "$idem_scratch/$rel" ]; then
    snap_after="$snap_after
$rel $(cksum <"$idem_scratch/$rel")"
  else
    snap_after="$snap_after
$rel MISSING"
  fi
done
assert_eq "$snap_before" "$snap_after" "all thirteen generated targets/ artifacts must be byte-identical across two consecutive build.sh runs (idempotence)"

drift_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $drift_scratch"
if drift_build_out=$("$drift_scratch/scripts/build.sh" 2>&1); then
  drift_build_exit=0
else
  drift_build_exit=$?
fi
assert_eq "0" "$drift_build_exit" "regenerating the targets/ artifacts into a full scratch directory must succeed -- output: $drift_build_out"

for rel in $generated_target_rel_paths; do
  if [ ! -f "$repo_root/$rel" ] || [ ! -f "$drift_scratch/$rel" ]; then
    drift_status="DRIFT DETECTED: missing $rel in committed tree or scratch regeneration"
  elif drift_diff=$(diff -u "$repo_root/$rel" "$drift_scratch/$rel" 2>&1); then
    drift_status=identical
  else
    drift_status="DRIFT DETECTED: $drift_diff"
  fi
  assert_eq "identical" "$drift_status" "committed $rel must match a fresh regeneration from its own source (no drift)"
done

# ==========================================================================
# 6b. The Cursor "skill" -> "command" swap is guarded.
#
#     write_cursor_command's `literal_replace "$body" "skill" "command"`
#     is a blanket, literal, EVERY-occurrence substitution. It was
#     unguarded: any occurrence of the substring "skill" in a Cursor
#     body was rewritten, path segments and unrelated words included.
#     Appending one sentence naming skills/rules/SKILL.md to a source
#     skill shipped "commands/rules/SKILL.md" and "commandful" into
#     targets/cursor/commands/digest.md, with build.sh exiting 0.
#
#     This is unreachable by the drift check, for the same reason
#     build.sh's own backslash guard documents: the corruption is a
#     deterministic function of the source, so a fresh regeneration is
#     identically wrong and `git diff --exit-code` sees nothing. The
#     build must therefore refuse the input outright, which is what the
#     three sub-cases below check - each on its own throwaway scratch,
#     never against the real skills/ sources.
# ==========================================================================
# 6b-1: a non-standalone occurrence (a path segment AND a longer word)
# in a Cursor-ported source must fail the build loudly, and must not
# have written the corrupted artifact.
cursor_swap_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $cursor_swap_scratch"
printf '\nSee the skills/rules/SKILL.md file; skillful use of the skills directory helps.\n' >>"$cursor_swap_scratch/skills/digest/SKILL.md"
if cursor_swap_out=$("$cursor_swap_scratch/scripts/build.sh" 2>&1); then
  cursor_swap_exit=0
else
  cursor_swap_exit=$?
fi
assert_eq "1" "$cursor_swap_exit" "a source skill body containing 'skills/rules/SKILL.md' and 'skillful' must FAIL the build -- the Cursor skill-to-command swap would rewrite both -- output: $cursor_swap_out"
assert_contains "$cursor_swap_out" "targets/cursor/commands/digest.md" "the swap-guard failure must name the artifact it would have corrupted"
assert_contains "$cursor_swap_out" "standalone word" "the swap-guard failure must say the occurrence is not the standalone word, so the author knows what to reword"
if [ -f "$cursor_swap_scratch/targets/cursor/commands/digest.md" ]; then
  cursor_swap_body=$(cat "$cursor_swap_scratch/targets/cursor/commands/digest.md")
else
  cursor_swap_body=""
fi
assert_not_contains "$cursor_swap_body" "commandful" "the corrupted 'commandful' must never reach targets/cursor/commands/digest.md (the build must fail before any artifact is written)"
assert_not_contains "$cursor_swap_body" "commands/rules/" "the corrupted 'commands/rules/' path must never reach targets/cursor/commands/digest.md"
rm -rf "$cursor_swap_scratch"

# 6b-2: VACUOUS-PASS GUARD. The same sentence, with every "skill"
# occurrence reworded to something the swap cannot touch, must BUILD
# CLEAN - proving 6b-1 fails on the "skill" occurrences specifically and
# not merely on "any extra sentence appended to a source skill".
cursor_swap_ok_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $cursor_swap_ok_scratch"
printf '\nSee the rules file; careful use of that directory helps.\n' >>"$cursor_swap_ok_scratch/skills/digest/SKILL.md"
if cursor_swap_ok_out=$("$cursor_swap_ok_scratch/scripts/build.sh" 2>&1); then
  cursor_swap_ok_exit=0
else
  cursor_swap_ok_exit=$?
fi
assert_eq "0" "$cursor_swap_ok_exit" "vacuous-pass guard: the same appended sentence with no 'skill' occurrence in it must build clean -- output: $cursor_swap_ok_out"
rm -rf "$cursor_swap_ok_scratch"

# 6b-3: the standalone word must keep being swapped. An appended
# sentence using "skill" as an ordinary word is accepted by the guard
# AND arrives in the Cursor artifact as "command" - the transformation
# the guard exists to protect, not block.
cursor_swap_word_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $cursor_swap_word_scratch"
printf '\nThis skill is deliberate about that.\n' >>"$cursor_swap_word_scratch/skills/digest/SKILL.md"
if cursor_swap_word_out=$("$cursor_swap_word_scratch/scripts/build.sh" 2>&1); then
  cursor_swap_word_exit=0
else
  cursor_swap_word_exit=$?
fi
assert_eq "0" "$cursor_swap_word_exit" "a standalone-word 'skill' occurrence must be accepted by the swap guard -- output: $cursor_swap_word_out"
if [ -f "$cursor_swap_word_scratch/targets/cursor/commands/digest.md" ]; then
  cursor_swap_word_body=$(cat "$cursor_swap_word_scratch/targets/cursor/commands/digest.md")
else
  cursor_swap_word_body=""
fi
assert_contains "$cursor_swap_word_body" "This command is deliberate about that." "the standalone word 'skill' must still be swapped to 'command' in the Cursor artifact"

# 6b-4: 6b-3 also proves the Agent Skill artifact does NOT get the swap,
# from the same single mutation - the appended standalone-word sentence
# arrives in the Cursor COMMAND as "This command is deliberate about
# that." (asserted above) and in the Cursor AGENT SKILL unchanged. Read
# from the SAME scratch build, so the two artifacts are provably the
# output of one run over one source, not two runs that could have
# diverged.
if [ -f "$cursor_swap_word_scratch/targets/cursor/skills/squirrel-digest/SKILL.md" ]; then
  cursor_noswap_skill_body=$(cat "$cursor_swap_word_scratch/targets/cursor/skills/squirrel-digest/SKILL.md")
else
  cursor_noswap_skill_body=""
fi
assert_contains "$cursor_noswap_skill_body" "This skill is deliberate about that." "the Cursor AGENT SKILL must carry the standalone word 'skill' UNCHANGED from the same build that swapped it in the command - these files really are skills and the swap must not reach them"
assert_not_contains "$cursor_noswap_skill_body" "This command is deliberate about that." "the Cursor AGENT SKILL must NOT carry the swapped wording"
rm -rf "$cursor_swap_word_scratch"

# ==========================================================================
# 6c. The disable-model-invocation ALLOWANCE in build.sh's
#     check_no_claude_only_syntax is NARROW, not a blanket exemption.
#
#     That key is on the Claude-Code-only pattern list. Cursor's own
#     Agent Skill schema documents it too, so the two
#     targets/cursor/skills/squirrel-*/SKILL.md artifacts are permitted
#     EXACTLY ONE occurrence: the literal frontmatter line, inside their
#     own leading frontmatter block. Everything else must still fail.
#
#     Proving that needs the OTHER call sites out of the way: a
#     "disable-model-invocation" sentence appended to skills/digest/
#     SKILL.md reaches targets/codex/skills/digest/SKILL.md and
#     targets/cursor/commands/digest.md first, and either of those fails
#     the build before the Cursor Agent Skill is ever checked - so a
#     plain injection proves nothing about the allowance itself. The
#     scratch build.sh below therefore has exactly those earlier call
#     sites deleted (never the Agent Skill ones, and never the Cursor
#     hooks.json site which cannot see a skill-body injection), leaving
#     five check_no_claude_only_syntax call sites. The Cursor Agent Skill
#     check is then the one that can catch the injection. If the
#     allowance were a blanket exemption, that build would exit 0.
# ==========================================================================
dmi_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $dmi_scratch"
# shellcheck disable=SC2016 # single-quoted deliberately: these are the
# literal call-site texts to delete from the scratch build.sh copy, not
# expressions to expand in THIS shell.
grep -v -F 'check_no_claude_only_syntax "$(cat "$tmp_codex_skill_' "$dmi_scratch/scripts/build.sh" |
  grep -v -F 'check_no_claude_only_syntax "$(cat "$tmp_cursor_command_' >"$dmi_scratch/scripts/build.sh.stripped"
mv "$dmi_scratch/scripts/build.sh.stripped" "$dmi_scratch/scripts/build.sh"
chmod +x "$dmi_scratch/scripts/build.sh"
# shellcheck disable=SC2016 # same reasoning as the strip above: a
# literal needle for grep -F, never an expression to expand here.
dmi_remaining_calls=$(grep -c -F 'check_no_claude_only_syntax "$(cat ' "$dmi_scratch/scripts/build.sh" || true)
assert_eq "7" "$dmi_remaining_calls" "fixture sanity: stripping the six Codex-skill and Cursor-command call sites must leave exactly seven check_no_claude_only_syntax call sites (AGENTS.md, the .mdc, the four Cursor Agent Skills, and Cursor hooks.json)"

printf '\nA sentence mentioning disable-model-invocation in ordinary prose.\n' >>"$dmi_scratch/skills/digest/SKILL.md"
if dmi_out=$("$dmi_scratch/scripts/build.sh" 2>&1); then
  dmi_exit=0
else
  dmi_exit=$?
fi
assert_eq "1" "$dmi_exit" "a 'disable-model-invocation' mention in a source skill BODY must still fail the build at the Cursor Agent Skill artifact - the allowance covers one exact frontmatter line, not the key anywhere in the file -- output: $dmi_out"
assert_contains "$dmi_out" "targets/cursor/skills/squirrel-digest/SKILL.md" "the allowance failure must name the Cursor Agent Skill artifact it fired on"
assert_contains "$dmi_out" "leading YAML frontmatter block" "the allowance failure must say the permitted occurrence is the frontmatter line, so the author knows what is and is not allowed"
rm -rf "$dmi_scratch"

# 6c-2: VACUOUS-PASS GUARD for 6c. The identical stripped build.sh, with
# NO injection, must build clean - proving 6c fails on the injected
# mention specifically and not merely because the call sites were
# deleted or the fixture is broken.
dmi_ok_scratch=$(make_full_scratch)
cleanup_dirs="$cleanup_dirs $dmi_ok_scratch"
# shellcheck disable=SC2016 # same reasoning as the identical strip above.
grep -v -F 'check_no_claude_only_syntax "$(cat "$tmp_codex_skill_' "$dmi_ok_scratch/scripts/build.sh" |
  grep -v -F 'check_no_claude_only_syntax "$(cat "$tmp_cursor_command_' >"$dmi_ok_scratch/scripts/build.sh.stripped"
mv "$dmi_ok_scratch/scripts/build.sh.stripped" "$dmi_ok_scratch/scripts/build.sh"
chmod +x "$dmi_ok_scratch/scripts/build.sh"
if dmi_ok_out=$("$dmi_ok_scratch/scripts/build.sh" 2>&1); then
  dmi_ok_exit=0
else
  dmi_ok_exit=$?
fi
assert_eq "0" "$dmi_ok_exit" "vacuous-pass guard: the same stripped build.sh with no injected mention must build clean, so 6c's failure is caused by the injection -- output: $dmi_ok_out"
rm -rf "$dmi_ok_scratch"

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
# Seed real content at paths a dry run has to read but must not touch,
# so "unchanged" below is a claim about a non-empty tree rather than
# about two empty ones. The cksum in tree_snapshot is what would catch a
# dry run that rewrote one of these in place.
mkdir -p "$home7d/.cursor/skills/squirrel-digest"
printf 'A pre-existing file at one of the managed paths.\n' >"$home7d/.cursor/skills/squirrel-digest/SKILL.md"
printf 'Pre-existing user content.\n' >"$home7d/.codex/AGENTS.md"
before7d=$(full_tree_listing "$home7d")
before7d_contents=$(tree_snapshot "$home7d")
# MTIME PROOF, alongside the path/content proof: a marker file created
# immediately before the two dry runs, and `find -newer` afterwards.
# `-newer` is POSIX and compares modification times exactly, so it sees
# a rewrite that happened to reproduce identical bytes (which both
# listings above would call unchanged) and a directory whose mtime was
# bumped by a create-then-remove. The sleep is what makes the comparison
# meaningful on a filesystem with one-second mtime granularity: without
# it, a file written in the same second as the marker is not "newer"
# than it.
dry_run_marker=$(mktemp "${TMPDIR:-/tmp}/squirrel-dry-run-marker.XXXXXX")
cleanup_dirs="$cleanup_dirs $dry_run_marker"
sleep 1
HOME="$home7d" "$codex_install" >/dev/null 2>&1
HOME="$home7d" "$cursor_install" >/dev/null 2>&1
after7d=$(full_tree_listing "$home7d")
after7d_contents=$(tree_snapshot "$home7d")
assert_eq "$before7d" "$after7d" "a dry run (no --yes) on either installer must change nothing at all under \$HOME - not even a directory (F1: files-only find was blind to this)"
assert_eq "$before7d_contents" "$after7d_contents" "a dry run must leave every file under \$HOME byte-identical, including a pre-existing file sitting at one of the managed paths it had to read"
touched7d=$(find "$home7d" -newer "$dry_run_marker" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
assert_eq "" "$touched7d" "a dry run must not bump the MTIME of any file or directory under \$HOME - nothing may be newer than a marker created just before it ran (found: $touched7d)"

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
# 10c. Cursor's AGENT SKILLS: install puts both at the exact documented
#      user-level paths, and uninstall removes both AND the directories
#      install itself created - without ever removing ~/.cursor, which
#      Cursor creates and this installer only ever adds to.
# ==========================================================================
home10c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home10c"
mkdir -p "$home10c/.cursor"
if out10c=$(HOME="$home10c" "$cursor_install" --yes 2>&1); then exit10c=0; else exit10c=$?; fi
assert_eq "0" "$exit10c" "cursor install.sh --yes must exit 0 when installing the Agent Skills -- output: $out10c"
for pair in $cursor_installed_skill_pairs; do
  folder=${pair#*:}
  assert_file_exists "$home10c/.cursor/skills/$folder/SKILL.md" "cursor install must create \$HOME/.cursor/skills/$folder/SKILL.md - Cursor's documented user-level Agent Skill location"
  if cmp -s "$repo_root/targets/cursor/skills/$folder/SKILL.md" "$home10c/.cursor/skills/$folder/SKILL.md"; then
    installed_matches=identical
  else
    installed_matches=DIFFERS
  fi
  assert_eq "identical" "$installed_matches" "the installed \$HOME/.cursor/skills/$folder/SKILL.md must be byte-identical to the generated artifact it came from"
done

HOME="$home10c" "$cursor_install" --uninstall --yes >/dev/null 2>&1
for pair in $cursor_installed_skill_pairs; do
  folder=${pair#*:}
  assert_file_absent "$home10c/.cursor/skills/$folder/SKILL.md" "cursor uninstall must remove \$HOME/.cursor/skills/$folder/SKILL.md"
  assert_file_absent "$home10c/.cursor/skills/$folder" "cursor uninstall must remove the now-empty \$HOME/.cursor/skills/$folder directory it created"
done
assert_file_absent "$home10c/.cursor/skills" "cursor uninstall must remove the now-empty \$HOME/.cursor/skills directory it created"
if [ -d "$home10c/.cursor" ]; then cursor_home_survived=yes; else cursor_home_survived=no; fi
assert_eq "yes" "$cursor_home_survived" "cursor uninstall must NEVER remove \$HOME/.cursor itself - Cursor creates it, this installer only ever adds to it"

# 10d. The directory cleanup must be gated on having actually removed
#      one of OUR files. This is the exact bug targets/codex/install.sh
#      fixed for ~/.agents/skills: an ungated rmdir deletes a
#      ~/.cursor/skills the user made themselves and squirrel-mode never
#      installed into. Two shapes, because they fail differently: a
#      skills directory holding somebody else's skill (rmdir would fail
#      anyway, so only the SIBLING assertion below discriminates), and an
#      EMPTY user-made skills directory (rmdir would succeed - this is
#      the one the gate exists for).
home10d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home10d"
mkdir -p "$home10d/.cursor/skills/my-own-skill"
printf 'A skill of my own, nothing to do with squirrel-mode.\n' >"$home10d/.cursor/skills/my-own-skill/SKILL.md"
foreign_sibling_ref=$(snapshot_file "$home10d/.cursor/skills/my-own-skill/SKILL.md")
cleanup_dirs="$cleanup_dirs $foreign_sibling_ref"
HOME="$home10d" "$cursor_install" --uninstall --yes >/dev/null 2>&1
assert_eq "identical" "$(files_byte_status "$foreign_sibling_ref" "$home10d/.cursor/skills/my-own-skill/SKILL.md")" "an unrelated skill sitting beside ours in \$HOME/.cursor/skills must survive --uninstall --yes byte-for-byte"
if [ -d "$home10d/.cursor/skills" ]; then skills_dir_survived_10d=yes; else skills_dir_survived_10d=no; fi
assert_eq "yes" "$skills_dir_survived_10d" "\$HOME/.cursor/skills must survive uninstall while it still holds somebody else's skill"

home10e=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home10e"
mkdir -p "$home10e/.cursor/skills"
HOME="$home10e" "$cursor_install" --uninstall --yes >/dev/null 2>&1
if [ -d "$home10e/.cursor/skills" ]; then skills_dir_survived_10e=yes; else skills_dir_survived_10e=no; fi
assert_eq "yes" "$skills_dir_survived_10e" "an EMPTY \$HOME/.cursor/skills the user made themselves, that squirrel-mode never installed into, must survive --uninstall --yes - the cleanup rmdir is gated on this run having actually removed one of OUR files"

# ==========================================================================
# 11. Each installer reports, rather than fails, when its host
#     directory is absent, and exits 0.
# ==========================================================================
home11=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home11"
if out11c=$(HOME="$home11" "$codex_install" --yes 2>&1); then exit11c=0; else exit11c=$?; fi
assert_eq "0" "$exit11c" "codex install.sh must exit 0 when ~/.codex does not exist -- output: $out11c"
# RE-PINNED: this used to require the substring "not appear to be
# installed". That wording was deliberately removed from both installers
# because it was WRONG for the case it actually fires on - a user who HAS
# installed Codex but has never launched it has no ~/.codex yet, and
# telling them the app "does not appear to be installed" sends them to
# reinstall something that is already there. Both messages now say the
# app "has not been run on this machine yet", which is the condition the
# missing directory genuinely proves. Pinned to the phrase the two new
# messages SHARE, so this stays a real assertion about what the user is
# told rather than a copy of one installer's exact sentence.
assert_contains "$out11c" "has not been run on this machine yet" "codex install.sh must report that Codex has not been run on this machine, not merely exit silently"
assert_file_absent "$home11/.agents" "codex install.sh must not create ~/.agents when ~/.codex is absent"

if out11u=$(HOME="$home11" "$cursor_install" --yes 2>&1); then exit11u=0; else exit11u=$?; fi
assert_eq "0" "$exit11u" "cursor install.sh must exit 0 when ~/.cursor does not exist -- output: $out11u"
assert_contains "$out11u" "has not been run on this machine yet" "cursor install.sh must report that Cursor has not been run on this machine, not merely exit silently (same re-pinning as the codex assertion above)"
assert_file_absent "$home11/.cursor" "cursor install.sh must not create ~/.cursor when it does not already exist"
assert_file_absent "$home11/.cursor/skills" "cursor install.sh must not create ~/.cursor/skills when ~/.cursor is absent - the Agent Skills live INSIDE ~/.cursor, so the host gate covers them too"

# The same gate covers uninstall, and for Cursor - unlike Codex, whose
# skills live at the sibling path ~/.agents/skills and must still be
# cleaned when ~/.codex is gone - nothing is stranded by it: every path
# this installer manages is under ~/.cursor, so its absence really does
# mean there is nothing left anywhere to remove.
if out11u_un=$(HOME="$home11" "$cursor_install" --uninstall --yes 2>&1); then exit11u_un=0; else exit11u_un=$?; fi
assert_eq "0" "$exit11u_un" "cursor install.sh --uninstall --yes must exit 0 when ~/.cursor does not exist -- output: $out11u_un"
assert_file_absent "$home11/.cursor" "cursor install.sh --uninstall must not create ~/.cursor either"

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

# Invariant 6e, digest's narrowed auto-trigger. The Cursor bullet in this
# doc contrasts Cursor's explicit-invocation-only Agent Skills against
# Claude Code's model-invocable digest, and to do that it describes what
# that model invocation actually fires on. That trigger was NARROWED
# (skills/digest/SKILL.md's description: the ordinary-language question
# fires it only when the pasted content is recognisably a ticket, email
# or note, never code/trace/log/diff/config/command output), so the same
# fact now lives in two files. tests/test_skills.sh scenario 28 pins the
# skill's end; these four pin BOTH ends against the same two needles, so
# narrowing one file without the other fails here rather than leaving
# this doc describing a trigger that no longer ships.
digest_narrowing_needle="recognisably a ticket, an email, or a written note"
digest_exclusion_needle="code, a stack trace, a log, a diff, a config, or command output"
digest_skill_content=$(read_file "$repo_root/skills/digest/SKILL.md")
assert_contains "$other_tools_content" "$digest_narrowing_needle" "docs/OTHER-TOOLS.md's Cursor contrast must describe Claude Code's digest trigger as NARROWED - it fires on the ordinary-language question only when what was pasted is recognisably a ticket, email or note"
assert_contains "$other_tools_content" "$digest_exclusion_needle" "docs/OTHER-TOOLS.md's Cursor contrast must also name the content classes that never fire digest - without that half the narrowing is not stated, only hinted"
assert_contains "$digest_skill_content" "$digest_narrowing_needle" "skills/digest/SKILL.md must carry the same narrowing wording docs/OTHER-TOOLS.md describes (cross-file agreement, invariant 6e)"
assert_contains "$digest_skill_content" "$digest_exclusion_needle" "skills/digest/SKILL.md must carry the same exclusion list docs/OTHER-TOOLS.md describes (cross-file agreement, invariant 6e)"

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
# The `cd` gets its own explicit failure path, and that is a real fix,
# not a style change. Folded into one `cd "$repo_root" && git ls-files
# ... || true` chain, a `cd` that FAILED was indistinguishable from "the
# sweep ran and matched nothing": `|| true` swallowed the failure, the
# variable came back empty, and this assertion passed - green, with the
# repo-wide sweep never having run at all. That is exactly the
# vacuous-pass this file's other guards exist to prevent, and it is the
# reason `A && B || C` is worth spelling out here rather than silencing.
# `|| true` still covers the one status that legitimately means success:
# `grep -l` exits 1 when the retired phrase is nowhere to be found, which
# is the outcome this assertion WANTS. The subshell keeps the `cd`
# contained, so the rest of this file still runs from its own directory.
retired_lock_wording_hits=$(
  cd "$repo_root" || { printf '%s' "<sweep did not run: could not cd to $repo_root>"; exit 0; }
  git ls-files -z | xargs -0 grep -l "$retired_lock_phrase" 2>/dev/null || true
)
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
  # files_byte_status (not a bare `cat`, and not a $(...) capture) is
  # used throughout, deliberately, for two independent reasons. (1) If
  # the mutation this scenario exists to catch is present, an
  # "uninstall" can actually DELETE the seeded foreign file - a bare
  # `cat` on a now-missing file would exit non-zero and, under
  # `set -eu`, abort this whole test FILE right there (no SUMMARY line,
  # every later scenario silently never runs); cmp inside an `if` is
  # exempt from `set -e` and reports "DIFFERS" instead. (2) "byte-for-
  # byte" must actually mean byte-for-byte: a $(...) capture of both
  # sides silently discards trailing newlines on both, so a foreign file
  # that came back with its trailing newline added or removed would
  # compare equal - see files_byte_status's own comment.
  home=$1
  installer=$2
  dest=$3
  content=$4
  label=$5
  printf '%s' "$content" >"$dest"
  seed_ref=$(snapshot_file "$dest")
  cleanup_dirs="$cleanup_dirs $seed_ref"
  HOME="$home" "$installer" --yes >/dev/null 2>&1
  assert_eq "identical" "$(files_byte_status "$seed_ref" "$dest")" "$label: must survive install byte-for-byte at the exact install path (ownership must be an exact banner-line match, not a substring search)"
  HOME="$home" "$installer" --uninstall --yes >/dev/null 2>&1
  assert_eq "identical" "$(files_byte_status "$seed_ref" "$dest")" "$label: must survive --uninstall --yes byte-for-byte at the exact install path"
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

# --- 15e: Cursor AGENT SKILL, no-marker foreign file at the exact path -
home15e=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15e"
mkdir -p "$home15e/.cursor/skills/squirrel-digest"
assert_foreign_survives_install_and_uninstall "$home15e" "$cursor_install" "$home15e/.cursor/skills/squirrel-digest/SKILL.md" "This is a foreign file with no squirrel-mode marker at all, sitting at squirrel-mode's exact Cursor digest skill path." "Cursor ~/.cursor/skills/squirrel-digest/SKILL.md, no marker"

# --- 15f: Cursor AGENT SKILL, substring-but-not-exact-banner foreign ---
home15f=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home15f"
mkdir -p "$home15f/.cursor/skills/squirrel-plan"
substring_content_15f="This foreign skill quotes squirrel-mode's own docs, including the substring: <!-- GENERATED FILE. Source: something-else-entirely.md. Generator: scripts/build.sh. -- but it is not actually squirrel-mode's plan skill."
assert_foreign_survives_install_and_uninstall "$home15f" "$cursor_install" "$home15f/.cursor/skills/squirrel-plan/SKILL.md" "$substring_content_15f" "Cursor ~/.cursor/skills/squirrel-plan/SKILL.md, substring-only (not exact banner line)"

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
fence_snapshot_16=$(snapshot_file "$home16/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $fence_snapshot_16"
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
fence_roundtrip_16=$(files_byte_status "$fence_snapshot_16" "$home16/.codex/AGENTS.md")
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
seed_snapshot_21=$(snapshot_file "$home21/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $seed_snapshot_21"

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
seed_after_21=$(files_byte_status "$seed_snapshot_21" "$home21/.codex/AGENTS.md")
assert_eq "identical" "$seed_after_21" "AGENTS.md must be unmodified after a SIGTERM mid-write (A8) - the mv never ran"
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
original_24=$(snapshot_file "$home24/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $original_24"
before24=$(full_tree_listing "$home24")
if out24=$(HOME="$home24" "$codex_install" --yes 2>&1); then exit24=0; else exit24=$?; fi
assert_eq "1" "$exit24" "install must exit non-zero against an AGENTS.md ending inside an unterminated fence, rather than append the block where it can never be found again -- output: $out24"
assert_contains "$out24" "unterminated" "the failure message must name the unterminated fence as the cause"
after24=$(files_byte_status "$original_24" "$home24/.codex/AGENTS.md")
assert_eq "identical" "$after24" "AGENTS.md must be byte-unchanged after install refuses an unterminated-fence file"
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
tilde_snapshot_25=$(snapshot_file "$home25/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $tilde_snapshot_25"
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
tilde_roundtrip_25=$(files_byte_status "$tilde_snapshot_25" "$home25/.codex/AGENTS.md")
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

# --- 28d: the same, for a Cursor AGENT SKILL destination ---------------
#
# This is 28b's argument transplanted to the Cursor installer, and it is
# the assertion that actually proves the symlink pre-flight covers the
# NEW paths rather than only the .mdc: the .mdc sits ABOVE the skills
# loop in this installer's Execution section too, so a symlink check
# that lived only inside the loop would let install --yes create the
# .mdc first and refuse only afterwards - "refuses, changing nothing"
# would already be false. The .mdc did not exist before this scenario
# ran, so its continued absence is the direct proof.
home28d=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home28d"
mkdir -p "$home28d/.cursor/skills/squirrel-digest"
assert_symlink_refused "$home28d" "$cursor_install" "$home28d/.cursor/skills/squirrel-digest/SKILL.md" "$home28d/real-cursor-skill-target.md" "Decoy Cursor skill content that must survive untouched." "Cursor ~/.cursor/skills/squirrel-digest/SKILL.md symlink"
assert_file_absent "$home28d/.cursor/rules/squirrel-mode.mdc" "the symlink refusal for a Cursor AGENT SKILL destination must change NOTHING - the .mdc must not have been created as a side effect before the refusal fired"

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
original_captured_30=$(snapshot_file "$home30/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $original_captured_30"
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

after30=$(files_byte_status "$original_captured_30" "$home30/.codex/AGENTS.md")
assert_eq "identical" "$after30" "F6: AGENTS.md must be byte-unchanged after the clean --yes failure (the mv never ran)"
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

# ==========================================================================
# 33 (S8, invariant 6e). README.md's "Parity across targets" table must
#    match docs/OTHER-TOOLS.md's "Parity at a glance" table EXACTLY - the
#    task brief's own requirement, and exactly the multi-file drift class
#    invariant 6e exists to catch mechanically instead of trusting a
#    reviewer's memory (S6 was rejected twice for the unenforced version
#    of this same failure). This same table also appears, near-verbatim,
#    in PLAN.md Section 3 ("Codex and Cursor (ADR-0004)") - pinned here
#    too, as a third copy of the identical table. It is NOT extended to
#    docs/adr/0004-tiered-parity-across-targets.md's own copy: that one
#    is a deliberately different rendering (unbolded "10 namespaced
#    skills", no Hoard column,
#    "skills in `~/.agents/skills/`" instead of the specific
#    per-file path, "instructed file read only" without ", best-effort",
#    no `**N**` counts) written when the ADR was drafted, before the
#    paths were finalized - a design-history record, not a
#    live copy meant to track later edits, so forcing it to match would
#    misrepresent what that document is. Its command COUNT is kept in
#    step by hand, unlike the rest of that rendering: a count that
#    disagrees with the three pinned tables is a factual error about how
#    many commands ship, not a stale draft rendering. Checked against the real files
#    (expect identical, line for line, for README.md/OTHER-TOOLS.md/
#    PLAN.md), then against a scratch copy of README.md with one cell of
#    its table edited (expect the tables to differ).
# ==========================================================================
assert_file_exists "$readme_doc" "README.md must exist"
assert_file_exists "$plan_doc" "PLAN.md must exist"

extract_parity_table() {
  # extract_parity_table <file> - prints the 5-line "| Target | Always-on
  # rules | Commands | Auto profile injection | Auto checkpoints | Hoard |"
  # table (header, separator, and the three target rows) verbatim, or
  # nothing if no such table exists in <file>.
  #
  # THE HEADER GAINED A SIXTH COLUMN in phase 1 of the hoard, and this
  # exact-match pattern moved with it, in all three files at once. That is
  # the point of the pattern being exact: adding a column to one copy makes
  # the extractor return NOTHING for that file, and the equality assertions
  # below then fail loudly rather than comparing two tables that happen to
  # share five columns. What this guard exists to catch is one copy drifting
  # from the other two, not the column set being frozen forever - the same
  # distinction tests/test_research.sh's docs/ listing assertion draws for
  # itself.
  file=$1
  awk '
    BEGIN { capture = 0 }
    /^\| Target \| Always-on rules \| Commands \| Auto profile injection \| Auto checkpoints \| Hoard \|$/ { capture = 1; print; next }
    capture == 1 && /^\|/ { print; next }
    capture == 1 { capture = 0 }
  ' "$file" 2>/dev/null
}

other_tools_parity_table=$(extract_parity_table "$other_tools_doc")
readme_parity_table=$(extract_parity_table "$readme_doc")
plan_parity_table=$(extract_parity_table "$plan_doc")

# Vacuous-pass guard: docs/OTHER-TOOLS.md's own table must yield exactly
# 5 lines (header + separator + 3 target rows), or "identical" below
# could be true for the wrong reason (nothing parsed on either side).
other_tools_parity_line_count=$(printf '%s\n' "$other_tools_parity_table" | sed '/^$/d' | wc -l | awk '{print $1}')
assert_eq "5" "$other_tools_parity_line_count" "parsing docs/OTHER-TOOLS.md's parity table must yield exactly 5 lines: header + separator + 3 targets (vacuous-pass guard for scenario 33)"

assert_eq "$other_tools_parity_table" "$readme_parity_table" "README.md's parity table must match docs/OTHER-TOOLS.md's parity table exactly, line for line"
assert_eq "$other_tools_parity_table" "$plan_parity_table" "PLAN.md Section 3's parity table must match docs/OTHER-TOOLS.md's parity table exactly, line for line (the third copy of the same table)"

# --- Failure proof: a scratch copy of README.md with one cell of its ---
#     parity table edited must no longer match docs/OTHER-TOOLS.md's.
parity_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-readme-parity-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $parity_mutant_dir"
parity_mutant="$parity_mutant_dir/README.md"
# shellcheck disable=SC2016 # single-quoted deliberately: the backtick-quoted
# text below is a literal sed pattern to match in README.md's own markdown,
# not command substitution to evaluate.
sed 's/| Codex | `~\/.codex\/AGENTS.md` global layer |/| Codex | some other description entirely |/' "$readme_doc" >"$parity_mutant"
mutant_parity_table=$(extract_parity_table "$parity_mutant")
if [ "$mutant_parity_table" = "$other_tools_parity_table" ]; then
  parity_mutant_matches=yes
else
  parity_mutant_matches=no
fi
assert_eq "no" "$parity_mutant_matches" "FAILURE PROOF (scenario 33): editing one cell of README.md's parity table in a scratch copy must make the line-for-line equality check fail"

# --- Failure proof: a scratch copy of PLAN.md's header word reverted to
#     the pre-fix wording ("Auto profile" instead of "Auto profile
#     injection") must no longer be found by the same exact-header match
#     the extractor requires - proving the PLAN.md pin is not vacuous.
plan_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-plan-parity-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $plan_mutant_dir"
plan_mutant="$plan_mutant_dir/PLAN.md"
sed 's/| Target | Always-on rules | Commands | Auto profile injection | Auto checkpoints | Hoard |/| Target | Always-on rules | Commands | Auto profile | Auto checkpoints | Hoard |/' "$plan_doc" >"$plan_mutant"
plan_mutant_table=$(extract_parity_table "$plan_mutant")
plan_mutant_line_count=$(printf '%s\n' "$plan_mutant_table" | sed '/^$/d' | wc -l | awk '{print $1}')
assert_eq "0" "$plan_mutant_line_count" "FAILURE PROOF (scenario 33, PLAN.md): reverting PLAN.md's table header to the old 'Auto profile' wording in a scratch copy must make the exact-header extractor find no table at all"

# ==========================================================================
# 33b. The OTHER cross-file table, which scenario 33 never covered.
#
#      WHY THIS EXISTS. docs/OTHER-TOOLS.md and PLAN.md Section 3 each
#      carry a "Which commands port" table, and the two drifted apart in
#      exactly the way scenario 33 was written to catch for the parity
#      table - and nothing caught it, because scenario 33 pins only the
#      table whose header starts "| Target |". docs/OTHER-TOOLS.md gained
#      a `stash` row and a `dig` row and moved its heading from "the other
#      four" to "the other six"; PLAN.md kept seven rows and the word
#      "four". Both copies were wrong about something a reader would act
#      on, and the suite was green throughout. One unpinned copy of a
#      pinned kind of table is the whole defect.
#
#      WHAT IS PAIRED, AND WHAT DELIBERATELY IS NOT. The first four
#      columns - the command name and its ✅/❌ for the three targets -
#      are pinned line for line. The fifth column, "Reason", is NOT: the
#      two documents legitimately explain the same fact at different
#      length and for different readers (PLAN.md is the build plan,
#      docs/OTHER-TOOLS.md is the page a user reads before installing),
#      and forcing those paragraphs to match byte for byte would be
#      pinning a writing style rather than a fact. What a reader acts on
#      is which commands exist and which targets have them; that is what
#      is pinned. Truncation is by `|` count, which is safe here because
#      no cell in the first four columns contains a `|` - they hold a
#      command name in backticks and single characters.
#
#      NAMING WHAT THAT EXEMPTION LETS THROUGH, because "prose varies"
#      was too kind a description of it. The Reason column is free text,
#      but it is not free of FACTS: it is where both files explain what a
#      command costs, and a cost is a number a reader acts on exactly as
#      much as a ✅ is. A review mutated ONLY that column, in PLAN.md
#      alone, to "A stash costs ZERO permission prompts on Claude Code" -
#      false, and contradicted by docs/OTHER-TOOLS.md's own stash row and
#      by README.md - and the whole suite closed green. Nothing in this
#      scenario looked at the cell, and nothing anywhere else pinned that
#      claim, so the exemption was covering a factual assertion and not a
#      difference of length or audience.
#
#      The class is therefore: a PROMPT-COST claim about a command,
#      written in the one column no cross-file check reads. Proof (d)
#      below closes the shape the review actually produced - the two
#      files may not say a stash costs zero or no permission prompts,
#      which is the assertion the mutant fails - without pinning the
#      wording around it. The residual is stated rather than implied: a
#      cost claim spelled some other way ("free", "silently", a different
#      command) still escapes, exactly as MARKER_REGEX cannot catch a
#      marker spelled some new way. The pairing that would close the
#      class outright is a cost claim carried in ONE place both files
#      cite, and neither file is written that way today.
#
#      THE HEADING'S NUMBER IS PINNED TWICE, on purpose. Once across the
#      two files (they must agree), and once against the table itself
#      (the word must be the number of COMMANDS marked ❌ for both Codex
#      and Cursor). Cross-file equality alone would pass if both copies
#      went stale together, which is the more likely next failure now
#      that one of them is being kept in step by hand. Deriving it from
#      the table is what makes the heading a claim about the rows rather
#      than a sentence nobody re-counts.
#
#      COMMANDS, NOT ROWS: `off` / `on` is one row naming two commands,
#      which is why nine rows and six unported commands are both correct
#      at once. The first cell is split on " / " and each name counted.
# ==========================================================================
extract_port_table() {
  # extract_port_table <file> - prints the "| Command | Claude Code |
  # Codex | Cursor | Reason |" table with everything from the fifth `|`
  # onward removed, or nothing if no such table exists in <file>. Same
  # exact-header discipline as extract_parity_table above, and for the
  # same reason: a column added to one copy makes this return NOTHING for
  # that file, and the equality assertion below fails loudly rather than
  # comparing two tables that happen to share four columns.
  awk '
    BEGIN { capture = 0 }
    /^\| Command \| Claude Code \| Codex \| Cursor \| Reason \|$/ { capture = 1; print; next }
    capture == 1 && /^\|/ { print; next }
    capture == 1 { capture = 0 }
  ' "$1" 2>/dev/null | sed 's/^\(\([^|]*|\)\{5\}\).*$/\1/'
}

port_heading_word() {
  # port_heading_word <file> - the number word in that file's "Which
  # commands port, and why the other <word> cannot" heading. Matched
  # without anchoring to the surrounding markup, because the two files
  # render the same sentence differently on purpose: a `##` heading in
  # docs/OTHER-TOOLS.md, a bolded line ending in a full stop in PLAN.md.
  grep -o 'Which commands port, and why the other [a-z][a-z]* cannot' "$1" 2>/dev/null \
    | sed 's/^.*why the other //; s/ cannot$//' | head -n 1
}

port_unported_command_count() {
  # port_unported_command_count <file> - how many COMMANDS the table
  # marks ❌ for both Codex and Cursor. `index()` against the literal
  # character, not a regex and not a \x escape: the first keeps any awk's
  # regex engine from having an opinion about a multi-byte character
  # under any locale, and the second is a non-POSIX awk extension this
  # file has no reason to depend on when the character itself is already
  # written literally in the sed patterns below.
  # Fields: $1 is empty (before the leading `|`), $2 Command, $3 Claude
  # Code, $4 Codex, $5 Cursor.
  extract_port_table "$1" | awk -F'|' '
    NF >= 5 && index($4, "❌") > 0 && index($5, "❌") > 0 {
      total += split($2, port_cmds, " / ")
    }
    END { print total + 0 }
  '
}

port_number_word() {
  case "$1" in
    1) printf 'one' ;;
    2) printf 'two' ;;
    3) printf 'three' ;;
    4) printf 'four' ;;
    5) printf 'five' ;;
    6) printf 'six' ;;
    7) printf 'seven' ;;
    8) printf 'eight' ;;
    9) printf 'nine' ;;
    10) printf 'ten' ;;
    *) printf '<%s-has-no-word-here>' "$1" ;;
  esac
}

other_tools_port_table=$(extract_port_table "$other_tools_doc")
plan_port_table=$(extract_port_table "$plan_doc")

# Vacuous-pass guard, the same shape scenario 33 uses: docs/OTHER-TOOLS.md's
# own port table must yield exactly 11 lines (header + separator + 9 command
# rows), or "identical" below could be true because nothing parsed on either
# side.
other_tools_port_line_count=$(printf '%s\n' "$other_tools_port_table" | sed '/^$/d' | wc -l | awk '{print $1}')
assert_eq "11" "$other_tools_port_line_count" "parsing docs/OTHER-TOOLS.md's port table must yield exactly 11 lines: header + separator + 9 command rows (vacuous-pass guard for scenario 33b)"

assert_eq "$other_tools_port_table" "$plan_port_table" "PLAN.md Section 3's port table must match docs/OTHER-TOOLS.md's, command for command and ✅/❌ for ✅/❌ (the Reason column is deliberately not compared)"

other_tools_port_word=$(port_heading_word "$other_tools_doc")
plan_port_word=$(port_heading_word "$plan_doc")
assert_eq "six" "$other_tools_port_word" "docs/OTHER-TOOLS.md's port heading must name a number word this scenario can read - a heading that stopped matching would make the two comparisons below vacuous"
assert_eq "$other_tools_port_word" "$plan_port_word" "PLAN.md's 'why the other <N> cannot' heading must name the same number as docs/OTHER-TOOLS.md's"

other_tools_unported=$(port_unported_command_count "$other_tools_doc")
assert_eq "$(port_number_word "$other_tools_unported")" "$other_tools_port_word" "docs/OTHER-TOOLS.md's heading number must equal the commands its own table marks ❌ for both Codex and Cursor ($other_tools_unported), so the sentence is a claim about the rows rather than one nobody re-counts"

# --- Failure proof (a): a scratch copy of PLAN.md with one ✅/❌ cell of ---
#     its port table flipped must stop matching docs/OTHER-TOOLS.md's. The
#     mutant is diffed BEFORE it is trusted: a sed that matched nothing
#     leaves a byte-identical copy, which the assertion correctly passes,
#     and this proof would then report clean while proving the opposite.
port_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-port-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $port_mutant_dir"
port_cell_mutant="$port_mutant_dir/PLAN-cell.md"
# shellcheck disable=SC2016 # single-quoted deliberately: the backticks below are
# literal characters in PLAN.md's own markdown table cell, not command substitution.
sed 's/^| `stash` | ✅ | ❌ | ❌ |/| `stash` | ✅ | ✅ | ❌ |/' "$plan_doc" >"$port_cell_mutant"
if cmp -s "$plan_doc" "$port_cell_mutant"; then port_cell_differs=no; else port_cell_differs=yes; fi
assert_eq "yes" "$port_cell_differs" "FAILURE PROOF (scenario 33b), control: the cell mutation must genuinely change PLAN.md - if it does not, PLAN.md no longer carries the row this proof mutates and the proof below is passing for a reason nobody chose"
if [ "$(extract_port_table "$port_cell_mutant")" = "$other_tools_port_table" ]; then
  port_cell_mutant_matches=yes
else
  port_cell_mutant_matches=no
fi
assert_eq "no" "$port_cell_mutant_matches" "FAILURE PROOF (scenario 33b): flipping one target cell of PLAN.md's port table in a scratch copy must make the line-for-line equality check fail"

# --- Failure proof (b): the exact regression this scenario was written ---
#     against - PLAN.md's heading left at "four" while the table carries
#     nine rows - must be caught, both against docs/OTHER-TOOLS.md and
#     against the table's own ❌/❌ count.
port_word_mutant="$port_mutant_dir/PLAN-four.md"
sed 's/why the other six cannot/why the other four cannot/' "$plan_doc" >"$port_word_mutant"
if cmp -s "$plan_doc" "$port_word_mutant"; then port_word_differs=no; else port_word_differs=yes; fi
assert_eq "yes" "$port_word_differs" "FAILURE PROOF (scenario 33b), control: the heading mutation must genuinely change PLAN.md"
assert_eq "four" "$(port_heading_word "$port_word_mutant")" "FAILURE PROOF (scenario 33b): the stale 'why the other four cannot' heading must be readable as such in the mutant"
if [ "$(port_heading_word "$port_word_mutant")" = "$other_tools_port_word" ]; then
  port_word_mutant_matches=yes
else
  port_word_mutant_matches=no
fi
assert_eq "no" "$port_word_mutant_matches" "FAILURE PROOF (scenario 33b): PLAN.md's pre-fix 'four' heading must no longer agree with docs/OTHER-TOOLS.md's"

# --- Failure proof (c): deleting the `dig` row from a scratch copy of ---
#     docs/OTHER-TOOLS.md must break the derived count, proving the
#     heading is pinned to the rows and not merely to the other file.
port_row_mutant="$port_mutant_dir/OTHER-TOOLS-norow.md"
# shellcheck disable=SC2016 # literal markdown, see above.
sed '/^| `dig` | ✅ | ❌ | ❌ |/d' "$other_tools_doc" >"$port_row_mutant"
if cmp -s "$other_tools_doc" "$port_row_mutant"; then port_row_differs=no; else port_row_differs=yes; fi
assert_eq "yes" "$port_row_differs" "FAILURE PROOF (scenario 33b), control: the row deletion must genuinely change docs/OTHER-TOOLS.md"
assert_eq "5" "$(port_unported_command_count "$port_row_mutant")" "FAILURE PROOF (scenario 33b): with the \`dig\` row deleted the derived count must fall to 5, so the 'six' in the heading no longer matches the table it describes"

# --- The one factual class the free-form Reason column let through. See ---
#     "NAMING WHAT THAT EXEMPTION LETS THROUGH" in this scenario's header
#     for what this does and does not cover.
port_reason_false_cost_hits() {
  # port_reason_false_cost_hits <file> - prints the Reason cell of every
  # port-table row of <file> that claims zero or no permission prompts
  # without also stating what the command does cost.
  #
  # THE UNIT IS THE CELL, AND IT USED TO BE THE SENTENCE. The sentence
  # version flattened the file to one line, split it on `.`, and required
  # the word `stash` and the cost claim inside one chunk. `tr` knows
  # nothing about table cells, so what actually bounded that scan was the
  # FULL STOP, and it was wrong in both directions - measured, both:
  #
  #   - FALSE POSITIVE on true prose. docs/OTHER-TOOLS.md's stash row says
  #     the memory *write* costs no permission prompt and that the command
  #     still costs one, in two sentences. Join those two sentences with a
  #     dash instead of a stop - an ordinary edit, changing no fact - and
  #     the row name lands in the same chunk as the cost claim and this
  #     guard goes red on a document that is telling the truth.
  #   - FALSE NEGATIVE on the lie it exists for. Write the false claim as
  #     two sentences - `A stash is instant on Claude Code. It costs zero
  #     permission prompts.` - and neither chunk holds both anchors, so it
  #     passes untouched.
  #
  # A guard that fails on true prose and passes the false claim is worse
  # than no guard, so the boundary is now the thing the claim actually
  # lives in: the Reason cell of one table row, whole, however many
  # sentences it is written in and wherever the stops fall. The first five
  # `|`-separated fields are stripped off and everything after them is the
  # cell; the cell is NOT split on `|` because it legitimately contains
  # one (`Write|Edit|Read`), which is the same truncation the four-column
  # comparison above performs and the reason that comparison cannot see
  # this column at all.
  #
  # WHAT EXCULPATES A CELL is saying what the command costs: `costs one`.
  # That is what makes the true sentence true, and a cell claiming a zero
  # cost without it is claiming it unqualified.
  #
  # RESIDUE, NAMED, because this is a grep and not a reader:
  #   - a false claim written OUTSIDE the port table is not scanned here.
  #     This column is scanned because it is free text no other check
  #     reads; ordinary prose elsewhere in these files is subject to the
  #     scans in tests/test_repo_invariants.sh.
  #   - a cell that lies AND happens to contain the words `costs one`
  #     passes. No pattern can tell which clause those two words belong
  #     to; the exculpation is a marker, not a proof.
  awk -F '|' '
    /^\| `[^`]*` \| / {
      cell = $0
      n = 0
      while (n < 5) { sub(/^[^|]*\|/, "", cell); n++ }
      low = tolower(cell)
      if (low ~ /(zero|no) permission prompts?/ && low !~ /costs one/) print cell
    }
  ' "$1" 2>/dev/null
}

port_reason_retired_sentence_hits() {
  # The scan this replaced, kept for the two failure proofs below and used
  # nowhere else. Both of its directions are asserted against the same
  # inputs the new one is, so the repair is measured rather than asserted.
  tr '\n' ' ' <"$1" 2>/dev/null | tr '.' '\n' \
    | grep -i 'stash' | grep -iE '(zero|no) permission prompts?'
}

assert_eq "" "$(port_reason_false_cost_hits "$plan_doc")" "PLAN.md must not claim a stash costs zero or no permission prompts - it costs one (README.md's command table, and docs/specs/2026-08-13-hoard-design.md section 12), and the Reason column of the table above is free text no other check reads"
assert_eq "" "$(port_reason_false_cost_hits "$other_tools_doc")" "docs/OTHER-TOOLS.md must not claim it either - the same scan on the other side of the same table, so the guard cannot be satisfied by whichever file happens to stay honest"

# --- Failure proof (d): the review's ACTUAL mutant. Only the Reason cell ---
#     of PLAN.md's stash row is replaced, exactly as the review did it. Two
#     things are asserted about it, and the second is the point: the new
#     scan catches it, AND the four-column equality check above still
#     PASSES on the same mutant - which is what proves this assertion is
#     closing a real gap rather than duplicating a check that already fired.
port_reason_mutant="$port_mutant_dir/PLAN-zero-cost.md"
awk 'BEGIN { FS = "|"; OFS = "|" }
  /^\| `stash` \| / {
    print "| `stash` | ✅ | ❌ | ❌ | A stash costs ZERO permission prompts on Claude Code. |"
    next
  }
  { print }
' "$plan_doc" >"$port_reason_mutant"
if cmp -s "$plan_doc" "$port_reason_mutant"; then port_reason_differs=no; else port_reason_differs=yes; fi
assert_eq "yes" "$port_reason_differs" "FAILURE PROOF (scenario 33b, prompt cost), control: the Reason-cell mutation must genuinely change PLAN.md - if PLAN.md no longer carries a stash row in that shape, everything below passes for a reason nobody chose"
if [ -n "$(port_reason_false_cost_hits "$port_reason_mutant")" ]; then port_reason_caught=yes; else port_reason_caught=no; fi
assert_eq "yes" "$port_reason_caught" "FAILURE PROOF (scenario 33b, prompt cost): the review's own mutant - 'A stash costs ZERO permission prompts on Claude Code', in the Reason column and nowhere else - must be caught"
if [ "$(extract_port_table "$port_reason_mutant")" = "$other_tools_port_table" ]; then
  port_reason_table_still_matches=yes
else
  port_reason_table_still_matches=no
fi
assert_eq "yes" "$port_reason_table_still_matches" "FAILURE PROOF (scenario 33b, prompt cost), the gap itself: the four-column equality check must STILL PASS on that mutant. This is why the assertion above had to be added - the Reason column is truncated before comparison, so every other check in this scenario is green while the file publishes a false cost"
assert_eq "$other_tools_port_word" "$(port_heading_word "$port_reason_mutant")" "FAILURE PROOF (scenario 33b, prompt cost), the gap itself: and the heading checks stay green on it too - the mutant touches nothing they read"

# --- Failure proof (e): the FALSE POSITIVE the retired scan produced on ---
#     TRUE prose. One edit, no fact changed: docs/OTHER-TOOLS.md's stash
#     row says the same two things in one sentence instead of two.
port_reason_joined="$port_mutant_dir/OTHER-TOOLS-joined.md"
sed 's/porting it is a rewrite rather than a copy\. It writes a memory/porting it is a rewrite rather than a copy - it writes a memory/' \
  "$other_tools_doc" >"$port_reason_joined"
if cmp -s "$other_tools_doc" "$port_reason_joined"; then port_joined_differs=no; else port_joined_differs=yes; fi
assert_eq "yes" "$port_joined_differs" "FAILURE PROOF (scenario 33b, false positive), control: joining the stash row's first two sentences must genuinely change docs/OTHER-TOOLS.md, or the two assertions below pass against the file that was already there"
if [ -n "$(port_reason_retired_sentence_hits "$port_reason_joined")" ]; then port_joined_old=yes; else port_joined_old=no; fi
assert_eq "yes" "$port_joined_old" "FAILURE PROOF (scenario 33b, false positive): the RETIRED sentence scan goes red on that file - a document stating the cost correctly, failed by a guard because of where a full stop sits. That is the defect this repair is about, reproduced"
assert_eq "" "$(port_reason_false_cost_hits "$port_reason_joined")" "FAILURE PROOF (scenario 33b, false positive), the repair: the cell-scoped scan is silent on the same file. The claim never changed, so neither may the verdict - a guard that reprimands correct prose is a guard that gets edited out"

# --- Failure proof (f): the FALSE NEGATIVE. The same lie as (d), split ---
#     across two sentences inside the one cell.
port_reason_split="$port_mutant_dir/PLAN-zero-cost-split.md"
awk 'BEGIN { FS = "|"; OFS = "|" }
  /^\| `stash` \| / {
    print "| `stash` | ✅ | ❌ | ❌ | A stash is instant on Claude Code. It costs zero permission prompts. |"
    next
  }
  { print }
' "$plan_doc" >"$port_reason_split"
if cmp -s "$plan_doc" "$port_reason_split"; then port_split_differs=no; else port_split_differs=yes; fi
assert_eq "yes" "$port_split_differs" "FAILURE PROOF (scenario 33b, two sentences), control: the split-sentence mutation must genuinely change PLAN.md"
if [ -n "$(port_reason_retired_sentence_hits "$port_reason_split")" ]; then port_split_old=yes; else port_split_old=no; fi
assert_eq "no" "$port_split_old" "FAILURE PROOF (scenario 33b, two sentences): the RETIRED sentence scan does NOT catch it - the row name and the cost claim land in different chunks, so the exact claim the guard was written for walks straight through by being punctuated differently"
if [ -n "$(port_reason_false_cost_hits "$port_reason_split")" ]; then port_split_new=yes; else port_split_new=no; fi
assert_eq "yes" "$port_split_new" "FAILURE PROOF (scenario 33b, two sentences), the repair: the cell-scoped scan catches it, because the cell is the boundary and both sentences are inside it"

# --- And the residue, asserted rather than only written down: a cell ---
#     that lies and also carries the exculpating words is not caught.
port_reason_hedged="$port_mutant_dir/PLAN-zero-cost-hedged.md"
awk 'BEGIN { FS = "|"; OFS = "|" }
  /^\| `stash` \| / {
    print "| `stash` | ✅ | ❌ | ❌ | A stash costs zero permission prompts. Reading one back costs one. |"
    next
  }
  { print }
' "$plan_doc" >"$port_reason_hedged"
if cmp -s "$plan_doc" "$port_reason_hedged"; then port_hedged_differs=no; else port_hedged_differs=yes; fi
assert_eq "yes" "$port_hedged_differs" "DECLARED LIMIT (scenario 33b), control: the hedged mutation must genuinely change PLAN.md"
assert_eq "" "$(port_reason_false_cost_hits "$port_reason_hedged")" "DECLARED LIMIT (scenario 33b): a cell that makes the false claim AND contains the words \`costs one\` about something else is NOT caught. The exculpation is a marker and cannot be a proof - no pattern can tell which clause two words belong to. This assertion exists so the limit is a measured boundary rather than a sentence in a comment, and it is the reason the four-column equality check and the two heading checks are not the only things standing behind this table"

# ==========================================================================
# 34. [S9, PLAN.md Section 5: "Installs user-scoped; zero files written
#     inside any project repository"] Running either installer from
#     INSIDE a project directory -- the realistic case: a developer runs
#     `targets/codex/install.sh --yes` from their own repo's checkout --
#     must never write anything into that project directory. Every
#     earlier scenario in this file proves the installers write
#     correctly under a scratch $HOME; none of them prove the OTHER half
#     of this criterion -- that a directory standing in for "the user's
#     project repo", deliberately SEPARATE from $HOME (so a bug that
#     resolved a path against cwd instead of $HOME would be caught here
#     and nowhere else), stays byte-and-path-identical. Both installers
#     take no cwd-dependent argument at all (verified by reading both
#     scripts start to finish: every managed path is built from
#     `$HOME`, never from `.` or a relative path), so this is expected
#     to pass by construction -- but "the code looks right" is exactly
#     the standard this project's own review process has rejected
#     before without a mechanical check behind it. Covers --yes install
#     AND --uninstall --yes, both installers, with cwd set INSIDE the
#     project directory for the whole invocation.
# ==========================================================================
project34=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-project-repo.XXXXXX")
cleanup_dirs="$cleanup_dirs $project34"
mkdir -p "$project34/.git" "$project34/src"
printf 'seed\n' >"$project34/README.md"
printf 'seed\n' >"$project34/src/main.py"
before34=$(full_tree_listing "$project34")

home34c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home34c"
mkdir -p "$home34c/.codex"
if run34c1_out=$(cd "$project34" && HOME="$home34c" "$codex_install" --yes 2>&1); then run34c1_exit=0; else run34c1_exit=$?; fi
assert_eq "0" "$run34c1_exit" "codex install.sh --yes, run from inside the scratch project directory, must exit 0 -- output: $run34c1_out"
if run34c2_out=$(cd "$project34" && HOME="$home34c" "$codex_install" --uninstall --yes 2>&1); then run34c2_exit=0; else run34c2_exit=$?; fi
assert_eq "0" "$run34c2_exit" "codex install.sh --uninstall --yes, run from inside the scratch project directory, must exit 0 -- output: $run34c2_out"
after34c=$(full_tree_listing "$project34")
assert_eq "$before34" "$after34c" "codex install.sh --yes (install then uninstall), run from INSIDE a scratch project directory, must leave that project directory completely untouched"

home34u=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home34u"
mkdir -p "$home34u/.cursor"
if run34u1_out=$(cd "$project34" && HOME="$home34u" "$cursor_install" --yes 2>&1); then run34u1_exit=0; else run34u1_exit=$?; fi
assert_eq "0" "$run34u1_exit" "cursor install.sh --yes, run from inside the scratch project directory, must exit 0 -- output: $run34u1_out"
if run34u2_out=$(cd "$project34" && HOME="$home34u" "$cursor_install" --uninstall --yes 2>&1); then run34u2_exit=0; else run34u2_exit=$?; fi
assert_eq "0" "$run34u2_exit" "cursor install.sh --uninstall --yes, run from inside the scratch project directory, must exit 0 -- output: $run34u2_out"
after34u=$(full_tree_listing "$project34")
assert_eq "$before34" "$after34u" "cursor install.sh --yes (install then uninstall), run from INSIDE a scratch project directory, must leave that project directory completely untouched"

# ==========================================================================
# 35. [S9, S8-5 regression pin] README.md's checkpoint auto-approval
#     disclosure must keep naming BOTH the ADR-0002 symlink trust
#     boundary and the one-write-per-turn cap. S8 review cycle 1 (S8-5)
#     found the disclosure omitted both facts entirely; the prose fix
#     landed in README.md, but nothing pinned it there afterward -- a
#     later edit to the Privacy section could silently drop either
#     sentence again with no test noticing, the exact "fix landed, no
#     test enforces it" gap invariant 6e in .build-checkpoint.md warns
#     about. Checked against the real file (expect both present), then
#     against a scratch copy with each sentence removed independently
#     (expect that one specifically absent, the other still present).
# ==========================================================================
readme_content_35=$(read_file "$readme_doc")
# The symlink needle is the WHOLE clause, not the bare "never auto-approved"
# it used to be. Since the hard-link refusal below became its own paragraph,
# "never auto-approved" appears twice in README.md, and a mutant that deleted
# the symlink paragraph would still contain the phrase - the proof at the
# bottom of this scenario would then report clean while proving nothing.
# shellcheck disable=SC2016 # single-quoted deliberately: the backtick is a literal Markdown character in README.md's text.
symlink_pin_needle='checkpoints/` itself, or anywhere below it, is never auto-approved'
# The two needles scenario 35a below pins, defined here because the symlink
# proof further down asserts the hard-link paragraph SURVIVES its mutation.
# shellcheck disable=SC2016 # single-quoted deliberately: literal Markdown backticks, not command substitution.
hardlink_pin_needle='that some other name also points at is never auto-approved either'
# shellcheck disable=SC2016 # ditto.
hardlink_find_needle='the test needs `find` on `PATH`'
assert_contains "$readme_content_35" "a symlink at" "README.md's checkpoint auto-approval disclosure must still name the ADR-0002 symlink trust boundary (S8-5)"
assert_contains "$readme_content_35" "$symlink_pin_needle" "README.md's checkpoint auto-approval disclosure must still state that a symlink at or below checkpoints/ is never auto-approved (S8-5)"
assert_contains "$readme_content_35" "cap them at one checkpoint write per turn" "README.md's checkpoint auto-approval disclosure must still state the one-write-per-turn cap (S8-5)"

symlink_pin_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-readme-symlink-pin-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $symlink_pin_mutant_dir"
symlink_pin_mutant="$symlink_pin_mutant_dir/README.md"
# shellcheck disable=SC2016 # single-quoted deliberately: literal sed pattern, not substitution.
sed '/^The auto-approval decides about the path as a \*\*name\*\*/,/^normal permission prompt instead of being silently redirected through the symlink\.$/d' "$readme_doc" >"$symlink_pin_mutant"
symlink_pin_mutant_content=$(read_file "$symlink_pin_mutant")
if printf '%s' "$symlink_pin_mutant_content" | grep -qF "$symlink_pin_needle"; then symlink_pin_removed=no; else symlink_pin_removed=yes; fi
assert_eq "yes" "$symlink_pin_removed" "FAILURE PROOF (scenario 35, symlink boundary): deleting that paragraph from a scratch copy of README.md must remove the pinned text"
assert_contains "$symlink_pin_mutant_content" "$hardlink_pin_needle" "FAILURE PROOF (scenario 35, symlink boundary): deleting the SYMLINK paragraph alone must leave the hard-link paragraph standing - the two refusals are separate facts and one must not cover for the other"
assert_contains "$symlink_pin_mutant_content" "cap them at one checkpoint write per turn" "FAILURE PROOF (scenario 35, symlink boundary): deleting the symlink-boundary paragraph alone must leave the SEPARATE one-write-per-turn sentence untouched (proving the two pins are independent, not one accidentally covering for the other)"

perturn_pin_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-readme-perturn-pin-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $perturn_pin_mutant_dir"
perturn_pin_mutant="$perturn_pin_mutant_dir/README.md"
sed '/^The base rules that trigger these writes also cap them at one checkpoint write per turn\./d' "$readme_doc" >"$perturn_pin_mutant"
perturn_pin_mutant_content=$(read_file "$perturn_pin_mutant")
if printf '%s' "$perturn_pin_mutant_content" | grep -qF "cap them at one checkpoint write per turn"; then perturn_pin_removed=no; else perturn_pin_removed=yes; fi
assert_eq "yes" "$perturn_pin_removed" "FAILURE PROOF (scenario 35, per-turn cap): deleting that sentence from a scratch copy of README.md must remove the pinned text"
assert_contains "$perturn_pin_mutant_content" "$symlink_pin_needle" "FAILURE PROOF (scenario 35, per-turn cap): deleting the one-write-per-turn sentence alone must leave the SEPARATE symlink-boundary paragraph untouched (proving the two pins are independent)"

# ==========================================================================
# 35a. [hard-link fix] The SECOND exception, which this disclosure claimed
#      did not exist.
#
#      README.md used to open this paragraph with "The auto-approval only
#      covers paths that genuinely resolve inside that directory" and then
#      name the symlink as the single exception. The hard-link refusal
#      (scripts/allow-checkpoint.sh Layer 2b, shipped in this same branch)
#      falsified both halves at once: a hard link inside checkpoints/ IS a
#      path that genuinely resolves inside the directory, and it is not
#      auto-approved. One sentence enumerating one exception where there
#      are two is exactly the shape scenario 35 above exists to stop, so
#      the second exception gets the same treatment as the first.
#
#      Three pins, each proved by deleting what it pins:
#        1. README states there IS a hard-link refusal.
#        2. README states its LIMIT - the check needs `find` on PATH, and
#           without it the hard link is auto-approved again. A refusal
#           published without the condition it depends on is the
#           overstated guarantee this repo keeps having to retract.
#        3. It is pinned against the hook that has to actually implement
#           it, so README cannot go on claiming a refusal that
#           scripts/allow-checkpoint.sh stopped making (invariant 6e,
#           the same cross-file shape as scenario 35b's pin 2).
# ==========================================================================
assert_contains "$readme_content_35" "$hardlink_pin_needle" "README.md's checkpoint auto-approval disclosure must name the hard-link refusal: a hard link resolves inside the directory and is still not auto-approved, so a disclosure naming only the symlink enumerates one exception where there are two"
assert_contains "$readme_content_35" "$hardlink_find_needle" "README.md must also state the hard-link refusal's LIMIT - it needs \`find\` on PATH and does not run without it (docs/adr/0008-hoard-auto-allow.md:65-72, tests/test_hooks.sh HOARD-14e) - because a refusal published without its precondition is a guarantee wider than the code makes"
assert_contains "$(read_file "$repo_root/scripts/allow-checkpoint.sh")" "-links +1" "scripts/allow-checkpoint.sh must actually carry the link-count test, or README.md's hard-link disclosure is claiming a refusal that no longer exists (cross-file agreement, invariant 6e)"

hardlink_pin_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-readme-hardlink-pin-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $hardlink_pin_mutant_dir"

hardlink_pin_mutant="$hardlink_pin_mutant_dir/README-hardlink.md"
sed '/^The second is a hard link, and it is the reason the sentence above says/,/records that limit)\.$/d' "$readme_doc" >"$hardlink_pin_mutant"
if cmp -s "$readme_doc" "$hardlink_pin_mutant"; then hardlink_pin_differs=no; else hardlink_pin_differs=yes; fi
assert_eq "yes" "$hardlink_pin_differs" "FAILURE PROOF (scenario 35a), control: deleting the hard-link paragraph must genuinely change README.md - a sed that matched nothing would leave a byte-identical copy and turn the proof below into a second copy of the passing test"
hardlink_pin_mutant_content=$(read_file "$hardlink_pin_mutant")
if printf '%s' "$hardlink_pin_mutant_content" | grep -qF "$hardlink_pin_needle"; then hardlink_pin_removed=no; else hardlink_pin_removed=yes; fi
assert_eq "yes" "$hardlink_pin_removed" "FAILURE PROOF (scenario 35a): deleting that paragraph from a scratch copy of README.md must remove the pinned text"
assert_contains "$hardlink_pin_mutant_content" "$symlink_pin_needle" "FAILURE PROOF (scenario 35a): deleting the HARD-LINK paragraph alone must leave the symlink-boundary paragraph standing (proving the two pins are independent, not one accidentally covering for the other)"

hardlink_find_mutant="$hardlink_pin_mutant_dir/README-hardlink-find.md"
grep -vF "$hardlink_find_needle" "$readme_doc" >"$hardlink_find_mutant"
if cmp -s "$readme_doc" "$hardlink_find_mutant"; then hardlink_find_differs=no; else hardlink_find_differs=yes; fi
assert_eq "yes" "$hardlink_find_differs" "FAILURE PROOF (scenario 35a, find limit), control: the deletion must genuinely change README.md"
hardlink_find_mutant_content=$(read_file "$hardlink_find_mutant")
if printf '%s' "$hardlink_find_mutant_content" | grep -qF "$hardlink_find_needle"; then hardlink_find_removed=no; else hardlink_find_removed=yes; fi
assert_eq "yes" "$hardlink_find_removed" "FAILURE PROOF (scenario 35a, find limit): dropping the line that states the \`find\` dependency must remove the pinned text - README would then publish the refusal without the one condition that switches it off"
assert_contains "$hardlink_find_mutant_content" "$hardlink_pin_needle" "FAILURE PROOF (scenario 35a, find limit): dropping the limit alone must leave the refusal claim itself standing (proving the two pins are independent)"

# ==========================================================================
# 35b. Same disclosure, the half about which TOOL writes a checkpoint.
#
#      README used to disclose a live gap here: the auto-approval covers
#      Write|Edit|Read, and the base rule that keeps a checkpoint current
#      named no tool at all, so the model could reach for a Bash heredoc
#      this plugin registers no hook for. Commit cecbd7c closed it - rule 14 now
#      names the `Read` and `Write` tools (pinned at the rule's own end by
#      tests/test_base_rules.sh scenario 36, which also pins PLAN.md's
#      copy). README now says so, which makes it the THIRD file carrying
#      that one fact, and invariant 6e wants the third end pinned like the
#      other two: pin 1 below fails if README drops the claim, pin 2 fails
#      if rules/base-rules.md drops what README is claiming ABOUT it, so
#      removing the tool naming from the rule cannot leave README quietly
#      asserting it.
#
#      Pin 3 is the honesty half and matters just as much. Rule 14
#      INSTRUCTS the model to use those tools; the harness does not
#      ENFORCE the choice, and docs/ACCEPTANCE.md's live evidence is on
#      init/tune/off/on, not on the checkpoint rule. Without this pin the
#      claim above could drift into "impossible" - a bigger guarantee than
#      anything here delivers - with the two pins above still green.
# ==========================================================================
# shellcheck disable=SC2016 # single-quoted deliberately: the backticks
# below are literal Markdown characters this needle searches README.md's
# and rules/base-rules.md's own TEXT for, not command substitution.
readme_tools_needle='`Read` and `Write` tools'
readme_unenforced_needle="instruction, not enforcement"
base_rules_content_35b=$(read_file "$repo_root/rules/base-rules.md")

assert_contains "$readme_content_35" "$readme_tools_needle" "README.md's checkpoint auto-approval disclosure must state that the base rule names the Read and Write tools - that is what closed the Bash-heredoc gap this paragraph used to disclose as open"
assert_contains "$base_rules_content_35b" "$readme_tools_needle" "rules/base-rules.md must actually name those two tools, or README.md's disclosure is claiming a closure that no longer exists (cross-file agreement, invariant 6e)"
assert_contains "$readme_content_35" "$readme_unenforced_needle" "README.md must keep saying the tool naming is an INSTRUCTION and not enforcement - a model can still reach for a Bash heredoc, and this plugin registers no hook that would run on one, so 'names the tools' must never be read as 'cannot happen'"

readme_35b_mutant_dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-readme-tools-pin-mutant.XXXXXX")
cleanup_dirs="$cleanup_dirs $readme_35b_mutant_dir"

readme_tools_mutant="$readme_35b_mutant_dir/README-tools.md"
grep -vF "$readme_tools_needle" "$readme_doc" >"$readme_tools_mutant"
readme_tools_mutant_content=$(read_file "$readme_tools_mutant")
if printf '%s' "$readme_tools_mutant_content" | grep -qF "$readme_tools_needle"; then readme_tools_pin_removed=no; else readme_tools_pin_removed=yes; fi
assert_eq "yes" "$readme_tools_pin_removed" "FAILURE PROOF (scenario 35b, tools claim): deleting that line from a scratch copy of README.md must remove the pinned text"
assert_contains "$readme_tools_mutant_content" "$readme_unenforced_needle" "FAILURE PROOF (scenario 35b, tools claim): deleting the tools-naming line alone must leave the SEPARATE instruction-not-enforcement sentence standing (proving the two pins are independent)"

readme_unenforced_mutant="$readme_35b_mutant_dir/README-unenforced.md"
grep -vF "$readme_unenforced_needle" "$readme_doc" >"$readme_unenforced_mutant"
readme_unenforced_mutant_content=$(read_file "$readme_unenforced_mutant")
if printf '%s' "$readme_unenforced_mutant_content" | grep -qF "$readme_unenforced_needle"; then readme_unenforced_pin_removed=no; else readme_unenforced_pin_removed=yes; fi
assert_eq "yes" "$readme_unenforced_pin_removed" "FAILURE PROOF (scenario 35b, unenforced caveat): deleting that line from a scratch copy of README.md must remove the pinned text"
assert_contains "$readme_unenforced_mutant_content" "$readme_tools_needle" "FAILURE PROOF (scenario 35b, unenforced caveat): deleting the instruction-not-enforcement line alone must leave the SEPARATE tools claim standing (proving the two pins are independent)"

# ==========================================================================
# 36. The AGENTS.md round trip must be byte-exact across ALL FOUR
#     combinations of {the user's original file ends with a newline /
#     does not} x {the user writes their own content BELOW the installed
#     block / does not}. Scenario 10 is the only other byte-exact check
#     of this round trip, and its fixture covers exactly one of the four
#     (ends with a newline, nothing below the block) - so
#     render_agents_uninstall's OTHER branch, the one taken whenever the
#     line before BEGIN is not blank, had no test at all.
#
#     Combination D is a real, reproduced data-corruption bug, not a
#     hypothetical: an AGENTS.md seeded WITHOUT a trailing newline, then
#     added to below the block, came back from --uninstall --yes with
#     the user's last own line and their first line below the block
#     MERGED INTO ONE ("Always answer in English.And never use emoji.")
#     - while the script printed "leaving the rest of the file
#     byte-identical to before it was ever installed".
#
#     Combination C is the one that discriminates the byte-exactness
#     mutation described in files_byte_status above (`printf '%s'` ->
#     `printf '%s\n'`): it is the only combination whose correct result
#     ends WITHOUT a trailing newline. Scenario 10 cannot see that
#     mutation (its fixture ends with one) and neither can D (which
#     routes through the head branch), so C must exist as its own
#     byte-exact scenario or the mutation stays invisible.
# ==========================================================================
od_dump() {
  # od_dump <file>: a compact one-line byte dump for failure messages.
  # "expected: identical / actual: DIFFERS" does not say WHICH bytes
  # moved, and for a trailing-newline defect that is the entire content
  # of the finding. Truncated to the first 300 characters: these
  # messages are built eagerly, pass or fail, and a whole installed
  # AGENTS.md dumped in full would bury every other line of output.
  od -An -c "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | cut -c1-300
}

assert_agents_roundtrip() {
  # assert_agents_roundtrip <label> <seed_file> <trailer_file>
  # <expected_file>: seeds a fresh throwaway $HOME's ~/.codex/AGENTS.md
  # with <seed_file>'s exact bytes, installs, appends <trailer_file>'s
  # bytes BELOW the installed block (skipped when <trailer_file> is
  # empty), uninstalls, and asserts the result is byte-identical to
  # <expected_file>.
  rt_label=$1
  rt_seed=$2
  rt_trailer=$3
  rt_expected=$4
  rt_home=$(make_temp_home)
  cleanup_dirs="$cleanup_dirs $rt_home"
  mkdir -p "$rt_home/.codex"
  cp "$rt_seed" "$rt_home/.codex/AGENTS.md"

  if rt_install_out=$(HOME="$rt_home" "$codex_install" --yes 2>&1); then rt_install_exit=0; else rt_install_exit=$?; fi
  assert_eq "0" "$rt_install_exit" "$rt_label: install --yes must exit 0 -- output: $rt_install_out"
  # Vacuous-pass guard: for the two combinations whose expected result
  # IS the seed file unchanged, an install that silently did nothing at
  # all would make the uninstall assertion below pass for entirely the
  # wrong reason.
  rt_begin_count=$(grep -c 'BEGIN SQUIRREL-MODE' "$rt_home/.codex/AGENTS.md" || true)
  assert_eq "1" "$rt_begin_count" "$rt_label: sanity - install must actually have written exactly one squirrel-mode block into AGENTS.md"

  if [ -s "$rt_trailer" ]; then
    cat "$rt_trailer" >>"$rt_home/.codex/AGENTS.md"
  fi

  if rt_uninstall_out=$(HOME="$rt_home" "$codex_install" --uninstall --yes 2>&1); then rt_uninstall_exit=0; else rt_uninstall_exit=$?; fi
  assert_eq "0" "$rt_uninstall_exit" "$rt_label: uninstall --yes must exit 0 -- output: $rt_uninstall_out"
  assert_eq "identical" "$(files_byte_status "$rt_expected" "$rt_home/.codex/AGENTS.md")" "$rt_label: uninstall must leave AGENTS.md byte-exact -- expected: $(od_dump "$rt_expected") / actual: $(od_dump "$rt_home/.codex/AGENTS.md")"
}

fixtures36=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-roundtrip-fixtures.XXXXXX")
cleanup_dirs="$cleanup_dirs $fixtures36"
printf 'Always answer in English.\nBe concise.\n' >"$fixtures36/seed-with-newline"
printf 'Always answer in English.' >"$fixtures36/seed-no-newline"
printf 'And never use emoji.\n' >"$fixtures36/trailer"
: >"$fixtures36/no-trailer"

# A: ends with a newline, nothing below the block -> the seed, unchanged.
cp "$fixtures36/seed-with-newline" "$fixtures36/expect-a"
# B: ends with a newline, user content below the block -> the seed, then
#    that content. The blank separator line install added is the only
#    thing removed.
cat "$fixtures36/seed-with-newline" "$fixtures36/trailer" >"$fixtures36/expect-b"
# C: no trailing newline, nothing below the block -> the seed, unchanged,
#    STILL with no trailing newline: the single newline install added to
#    terminate the dangling last line was squirrel-mode's own, and
#    nothing else needs it now.
cp "$fixtures36/seed-no-newline" "$fixtures36/expect-c"
# D: no trailing newline, user content below the block -> the seed, that
#    same newline, then the content. Here the newline install added is
#    the ONLY thing separating the user's last own line from their first
#    line below the block; removing it merges two of their instructions
#    into one.
{ cat "$fixtures36/seed-no-newline"; printf '\n'; cat "$fixtures36/trailer"; } >"$fixtures36/expect-d"

assert_agents_roundtrip "36A (trailing newline, nothing below the block)" "$fixtures36/seed-with-newline" "$fixtures36/no-trailer" "$fixtures36/expect-a"
assert_agents_roundtrip "36B (trailing newline, user content below the block)" "$fixtures36/seed-with-newline" "$fixtures36/trailer" "$fixtures36/expect-b"
assert_agents_roundtrip "36C (no trailing newline, nothing below the block)" "$fixtures36/seed-no-newline" "$fixtures36/no-trailer" "$fixtures36/expect-c"
assert_agents_roundtrip "36D (no trailing newline, user content below the block)" "$fixtures36/seed-no-newline" "$fixtures36/trailer" "$fixtures36/expect-d"

# ==========================================================================
# 37. A pair of squirrel-mode marker lines the INSTALLER never wrote -
#     placed by hand around the user's own notes, e.g. copied out of
#     docs/OTHER-TOOLS.md and pasted into their own AGENTS.md - must not
#     hand this script ownership of whatever sits between them.
#
#     Everywhere else the installer decides ownership by an exact,
#     full-line match against the artifact's own GENERATED banner, read
#     fresh from the bundled source, and is "biased toward foreign
#     whenever there is any doubt" (classify_dedicated_file's own
#     comment). The AGENTS.md block was the one path with no such check
#     at all: matching BEGIN and END lines outside a fence were taken as
#     proof of ownership, so install REPLACED and uninstall DELETED
#     whatever was between them, whoever wrote it. Reproduced: a file of
#     "top / <BEGIN> / MY OWN NOTES / <END> / bottom" came back from
#     --uninstall --yes as "top / bottom", exit 0, reported as "leaving
#     the rest of the file byte-identical to before it was ever
#     installed".
#
#     Both directions are pinned - install must not overwrite it,
#     uninstall must not delete it - each with the whole $HOME tree
#     asserted unchanged, because "refuses, changing nothing" has to
#     mean the skill files were not written either.
# ==========================================================================
home37=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home37"
mkdir -p "$home37/.codex"
cat >"$home37/.codex/AGENTS.md" <<'HAND_MARKERS_EOF'
My own instructions, above the markers.
<!-- BEGIN SQUIRREL-MODE (generated - do not edit by hand; re-run targets/codex/install.sh instead) -->
MY OWN NOTES, between markers I placed here by hand. This installer never wrote them.
<!-- END SQUIRREL-MODE -->
My own instructions, below the markers.
HAND_MARKERS_EOF
snapshot37=$(snapshot_file "$home37/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $snapshot37"

before37install=$(full_tree_listing "$home37")
if out37install=$(HOME="$home37" "$codex_install" --yes 2>&1); then exit37install=0; else exit37install=$?; fi
assert_eq "1" "$exit37install" "install --yes must REFUSE a marker pair whose content is not squirrel-mode's own generated block, never silently overwrite it -- output: $out37install"
assert_contains "$out37install" "not squirrel-mode's own generated block" "install's refusal must say plainly that what is between the markers is not squirrel-mode's own block"
assert_eq "identical" "$(files_byte_status "$snapshot37" "$home37/.codex/AGENTS.md")" "AGENTS.md must be byte-unchanged after install refuses a foreign marker pair -- expected: $(od_dump "$snapshot37") / actual: $(od_dump "$home37/.codex/AGENTS.md")"
after37install=$(full_tree_listing "$home37")
assert_eq "$before37install" "$after37install" "37: the whole \$HOME tree must be unchanged after install refuses a foreign marker pair (no skill files written either)"

before37uninstall=$(full_tree_listing "$home37")
if out37uninstall=$(HOME="$home37" "$codex_install" --uninstall --yes 2>&1); then exit37uninstall=0; else exit37uninstall=$?; fi
assert_eq "1" "$exit37uninstall" "--uninstall --yes must REFUSE to delete the content between a marker pair squirrel-mode never wrote -- output: $out37uninstall"
assert_contains "$out37uninstall" "not squirrel-mode's own generated block" "uninstall's refusal must say plainly that what is between the markers is not squirrel-mode's own block"
assert_eq "identical" "$(files_byte_status "$snapshot37" "$home37/.codex/AGENTS.md")" "AGENTS.md must be byte-unchanged after uninstall refuses a foreign marker pair -- expected: $(od_dump "$snapshot37") / actual: $(od_dump "$home37/.codex/AGENTS.md")"
after37uninstall=$(full_tree_listing "$home37")
assert_eq "$before37uninstall" "$after37uninstall" "37: the whole \$HOME tree must be unchanged after uninstall refuses a foreign marker pair"

# Positive control: the identical code path must still recognise a block
# this installer really did write - otherwise the refusals above could be
# passing simply because the ownership check rejects everything.
home37ok=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home37ok"
mkdir -p "$home37ok/.codex"
printf 'My own instructions.\n' >"$home37ok/.codex/AGENTS.md"
snapshot37ok=$(snapshot_file "$home37ok/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $snapshot37ok"
if out37ok1=$(HOME="$home37ok" "$codex_install" --yes 2>&1); then exit37ok1=0; else exit37ok1=$?; fi
assert_eq "0" "$exit37ok1" "positive control: a real install must still exit 0 with the ownership check in place -- output: $out37ok1"
if out37ok2=$(HOME="$home37ok" "$codex_install" --yes 2>&1); then exit37ok2=0; else exit37ok2=$?; fi
assert_eq "0" "$exit37ok2" "positive control: RE-installing over squirrel-mode's own block must still be recognised as ours and exit 0 -- output: $out37ok2"
if out37ok3=$(HOME="$home37ok" "$codex_install" --uninstall --yes 2>&1); then exit37ok3=0; else exit37ok3=$?; fi
assert_eq "0" "$exit37ok3" "positive control: uninstalling squirrel-mode's own block must still exit 0 -- output: $out37ok3"
assert_eq "identical" "$(files_byte_status "$snapshot37ok" "$home37ok/.codex/AGENTS.md")" "positive control: the ownership check must not disturb the byte-exact round trip of a genuine block"

# ==========================================================================
# 38. The BUNDLED block must be validated BEFORE it is inserted, so a
#     future edit to rules/base-rules.md cannot permanently wedge a
#     user's AGENTS.md.
#
#     render_agents_install validates the user's file thoroughly -
#     marker shape, fence awareness, an unterminated fence at EOF - and
#     validated the content it INSERTS not at all. targets/codex/AGENTS.md
#     is generated from rules/base-rules.md, which is exactly the kind of
#     file someone later quotes the markers in, or adds a fenced example
#     to. Two shapes wedge the user's file permanently: a line equal to
#     one of squirrel-mode's own marker lines (the installed file then has
#     two ENDs, so markers_state reports "corrupt" forever) and a bundled
#     file with no trailing newline (END is glued onto the last line, so
#     the installed file has a BEGIN and no END). In both cases the first
#     --yes succeeds, and from then on the user's own AGENTS.md can
#     never be updated OR uninstalled by this script again.
#
#     Both are run against a SCRATCH copy of targets/codex/ - the real
#     generated artifact is never modified, not even transiently.
# ==========================================================================
assert_bad_bundle_refused() {
  # assert_bad_bundle_refused <label> <installer_scratch>: runs the
  # scratch installer (whose bundled targets/codex/AGENTS.md the caller
  # has already broken) against a fresh throwaway $HOME and asserts it
  # refuses before writing anything, names the BUNDLED file as the
  # problem, and leaves the user with a file that is still perfectly
  # uninstallable - i.e. never wedged.
  bb_label=$1
  bb_scratch=$2
  bb_home=$(make_temp_home)
  cleanup_dirs="$cleanup_dirs $bb_home"
  mkdir -p "$bb_home/.codex"
  printf 'My own instructions.\n' >"$bb_home/.codex/AGENTS.md"
  bb_snapshot=$(snapshot_file "$bb_home/.codex/AGENTS.md")
  cleanup_dirs="$cleanup_dirs $bb_snapshot"
  bb_before=$(full_tree_listing "$bb_home")

  if bb_out=$(HOME="$bb_home" "$bb_scratch/targets/codex/install.sh" --yes 2>&1); then bb_exit=0; else bb_exit=$?; fi
  assert_eq "1" "$bb_exit" "$bb_label: install --yes must refuse an unusable bundled block instead of writing it -- output: $bb_out"
  # The installer resolves its own repo_root through `cd ... && pwd`,
  # which expands symlinks - on macOS a mktemp -d under /var comes back
  # as /private/var - so the expected path is resolved the same way
  # rather than compared against the raw mktemp string.
  bb_resolved=$(cd "$bb_scratch" && pwd)
  assert_contains "$bb_out" "$bb_resolved/targets/codex/AGENTS.md" "$bb_label: the refusal must name the BUNDLED file that is wrong, not blame the user's own AGENTS.md"
  assert_not_contains "$bb_out" "Installed:" "$bb_label: nothing may be reported as installed"
  assert_eq "identical" "$(files_byte_status "$bb_snapshot" "$bb_home/.codex/AGENTS.md")" "$bb_label: the user's AGENTS.md must be byte-unchanged -- expected: $(od_dump "$bb_snapshot") / actual: $(od_dump "$bb_home/.codex/AGENTS.md")"
  bb_after=$(full_tree_listing "$bb_home")
  assert_eq "$bb_before" "$bb_after" "$bb_label: the whole \$HOME tree must be unchanged (no skill files written either)"

  # The wedge itself: before this validation existed, the first install
  # succeeded and every later install AND uninstall failed forever. A
  # clean uninstall here is the direct proof that never happened.
  if bb_un_out=$(HOME="$bb_home" "$bb_scratch/targets/codex/install.sh" --uninstall --yes 2>&1); then bb_un_exit=0; else bb_un_exit=$?; fi
  assert_eq "0" "$bb_un_exit" "$bb_label: the user's AGENTS.md must not be wedged - --uninstall --yes must still exit 0 afterwards -- output: $bb_un_out"
}

# --- 38a: the bundled block quotes one of squirrel-mode's own markers ---
installer_scratch_38a=$(make_codex_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_38a"
{
  printf 'A quoted example of the closing marker:\n'
  printf '%s\n' '<!-- END SQUIRREL-MODE -->'
} >>"$installer_scratch_38a/targets/codex/AGENTS.md"
assert_bad_bundle_refused "38a (bundled block quotes an END marker)" "$installer_scratch_38a"

# --- 38b: the bundled block has no trailing newline --------------------
installer_scratch_38b=$(make_codex_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_38b"
bundle38b=$(cat "$installer_scratch_38b/targets/codex/AGENTS.md")
printf '%s' "$bundle38b" >"$installer_scratch_38b/targets/codex/AGENTS.md"
assert_bad_bundle_refused "38b (bundled block has no trailing newline)" "$installer_scratch_38b"

# --- 38c: positive control - an UNMODIFIED scratch bundle must still ----
#     install and uninstall cleanly, or 38a/38b could be passing because
#     the new validation rejects every bundle.
installer_scratch_38c=$(make_codex_installer_scratch)
cleanup_dirs="$cleanup_dirs $installer_scratch_38c"
home38c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home38c"
mkdir -p "$home38c/.codex"
printf 'My own instructions.\n' >"$home38c/.codex/AGENTS.md"
snapshot38c=$(snapshot_file "$home38c/.codex/AGENTS.md")
cleanup_dirs="$cleanup_dirs $snapshot38c"
if out38c1=$(HOME="$home38c" "$installer_scratch_38c/targets/codex/install.sh" --yes 2>&1); then exit38c1=0; else exit38c1=$?; fi
assert_eq "0" "$exit38c1" "38c (positive control): the real, unmodified bundled block must still pass validation and install -- output: $out38c1"
assert_contains "$out38c1" "Installed:" "38c (positive control): the unmodified bundle must actually be installed, not merely accepted"
if out38c2=$(HOME="$home38c" "$installer_scratch_38c/targets/codex/install.sh" --uninstall --yes 2>&1); then exit38c2=0; else exit38c2=$?; fi
assert_eq "0" "$exit38c2" "38c (positive control): uninstall must still exit 0 -- output: $out38c2"
assert_eq "identical" "$(files_byte_status "$snapshot38c" "$home38c/.codex/AGENTS.md")" "38c (positive control): the round trip through a scratch installer copy must still be byte-exact"

# ==========================================================================
# 39. Directory cleanup on uninstall must be symmetric with what install
#     created - and must stop there.
#
#     Install creates ~/.agents/skills/<name> with `mkdir -p`, which
#     also creates ~/.agents. Uninstall rmdir'd <name> and skills but
#     never ~/.agents, so every uninstall left an empty ~/.agents behind
#     forever, while docs/OTHER-TOOLS.md says the skill files "and their
#     now-empty directories" are removed.
#
#     The mirror-image defect: that final rmdir ran unconditionally on
#     any --uninstall --yes, so a user who had their own empty
#     ~/.agents/skills and had never installed squirrel-mode's skills at
#     all lost that directory to a squirrel-mode uninstall. Removal is
#     now gated on this run having actually removed one of our own files.
# ==========================================================================
home39a=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home39a"
mkdir -p "$home39a/.codex"
HOME="$home39a" "$codex_install" --yes >/dev/null 2>&1
assert_file_exists "$home39a/.agents/skills/digest/SKILL.md" "39a fixture: install must have created the skill files it is about to remove"
if out39a=$(HOME="$home39a" "$codex_install" --uninstall --yes 2>&1); then exit39a=0; else exit39a=$?; fi
assert_eq "0" "$exit39a" "39a: --uninstall --yes must exit 0 -- output: $out39a"
assert_file_absent "$home39a/.agents" "39a: uninstall must remove ~/.agents itself once it is empty, not just the directories below it - install created it, so a complete uninstall owes its removal (docs/OTHER-TOOLS.md says so in as many words)"

home39b=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home39b"
mkdir -p "$home39b/.codex" "$home39b/.agents/skills"
if out39b=$(HOME="$home39b" "$codex_install" --uninstall --yes 2>&1); then exit39b=0; else exit39b=$?; fi
assert_eq "0" "$exit39b" "39b: --uninstall --yes must exit 0 when there is nothing of ours to remove -- output: $out39b"
if [ -d "$home39b/.agents/skills" ]; then skills_dir_39b=present; else skills_dir_39b=absent; fi
assert_eq "present" "$skills_dir_39b" "39b: a pre-existing, EMPTY ~/.agents/skills that squirrel-mode never put anything into must survive an uninstall - this installer may only remove a directory its own files were just removed from"
if [ -d "$home39b/.agents" ]; then agents_dir_39b=present; else agents_dir_39b=absent; fi
assert_eq "present" "$agents_dir_39b" "39b: the same holds one level up - a ~/.agents this run never installed into must survive it"

home39c=$(make_temp_home)
cleanup_dirs="$cleanup_dirs $home39c"
mkdir -p "$home39c/.codex" "$home39c/.agents"
printf 'my own agents-level notes, nothing to do with squirrel-mode\n' >"$home39c/.agents/notes.md"
snapshot39c=$(snapshot_file "$home39c/.agents/notes.md")
cleanup_dirs="$cleanup_dirs $snapshot39c"
HOME="$home39c" "$codex_install" --yes >/dev/null 2>&1
if out39c=$(HOME="$home39c" "$codex_install" --uninstall --yes 2>&1); then exit39c=0; else exit39c=$?; fi
assert_eq "0" "$exit39c" "39c: --uninstall --yes must exit 0 with unrelated content under ~/.agents -- output: $out39c"
assert_file_absent "$home39c/.agents/skills" "39c: ~/.agents/skills must still be removed once our four files are gone from it"
assert_file_exists "$home39c/.agents/notes.md" "39c: an unrelated file directly under ~/.agents must survive - the rmdir of a non-empty ~/.agents must fail harmlessly, never escalate to a recursive removal"
assert_eq "identical" "$(files_byte_status "$snapshot39c" "$home39c/.agents/notes.md")" "39c: that unrelated file must be byte-unchanged"

# ==========================================================================
# 40. Tripwire: running this test file must not have written a single
#     byte into the repository working tree.
#
#     The counted, always-on form of the "NO SCENARIO IN THIS FILE MAY
#     INVOKE THE REAL REPO'S build.sh" note at the top. Against an
#     already-clean tree it can only pass (build.sh is idempotent, so
#     even the old repo-targeted run left the bytes unchanged); against
#     a DRIFTED tree it is the assertion that turns "the test run
#     silently repaired the drift" - which is how a real hand-edit
#     stayed reportable exactly once and never again - into a loud,
#     permanent failure.
# ==========================================================================
repo_generated_after=$(repo_generated_snapshot)
assert_eq "$repo_generated_before" "$repo_generated_after" "running tests/test_targets.sh must leave every generated targets/ artifact in the repository working tree byte-identical (no scenario may build into the real repo)"

assert_report
