#!/bin/sh
# Coverage for the Cursor-native plugin packaging: .cursor-plugin/plugin.json
# and the generated targets/cursor/hooks/hooks.json. Claude packaging stays
# in tests/test_manifests.sh and tests/test_hooks.sh; this file does not
# replace those asserts.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion: every assert_* helper always returns 0, and
# only assert_report (called once, at the end) turns a failure into a
# non-zero exit code.
set -eu

# A CDPATH entry containing "." makes the `cd` on the next line ECHO its
# resolved path to stdout in addition to changing directory, corrupting
# the command substitution below with an extra line. Unset
# unconditionally, before that `cd` runs.
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# shellcheck source=lib/assert.sh
# shellcheck disable=SC1091
. "$script_dir/lib/assert.sh"

plugin_json="$repo_root/.cursor-plugin/plugin.json"
cursor_hooks_json="$repo_root/targets/cursor/hooks/hooks.json"

# ==========================================================================
# 1. .cursor-plugin/plugin.json: valid JSON, identity, version, paths.
# ==========================================================================
assert_json_valid "$plugin_json" ".cursor-plugin/plugin.json must be valid JSON"

cursor_name=$(jq -r '.name // ""' "$plugin_json" 2>/dev/null) || cursor_name=""
assert_eq "squirrel-mode" "$cursor_name" ".cursor-plugin/plugin.json .name must be exactly 'squirrel-mode'"

case "$cursor_name" in
  '' | *[!a-z0-9-]* | -* | *-)
    cursor_name_kebab=no
    ;;
  *)
    cursor_name_kebab=yes
    ;;
esac
assert_eq "yes" "$cursor_name_kebab" ".cursor-plugin/plugin.json .name must be lowercase kebab-case"

cursor_display_name=$(jq -r '.displayName // ""' "$plugin_json" 2>/dev/null) || cursor_display_name=""
if [ -n "$cursor_display_name" ]; then
  cursor_display_name_present=yes
else
  cursor_display_name_present=no
fi
assert_eq "yes" "$cursor_display_name_present" ".cursor-plugin/plugin.json must include displayName"

assert_json_eq "$plugin_json" '.displayName' "squirrel-mode" ".cursor-plugin/plugin.json .displayName must be 'squirrel-mode'"
assert_json_eq "$plugin_json" '.version' "0.6.0" ".cursor-plugin/plugin.json .version must be 0.6.0"

cursor_description=$(jq -r '.description // ""' "$plugin_json" 2>/dev/null) || cursor_description=""
assert_contains "$cursor_description" "ADHD" ".cursor-plugin/plugin.json .description must contain 'ADHD'"

assert_json_eq "$plugin_json" '.rules' "targets/cursor/squirrel-mode.mdc" ".cursor-plugin/plugin.json .rules must point at targets/cursor/squirrel-mode.mdc"
assert_json_eq "$plugin_json" '.skills' "targets/cursor/skills/" ".cursor-plugin/plugin.json .skills must point at targets/cursor/skills/"
assert_json_eq "$plugin_json" '.commands' "targets/cursor/commands/" ".cursor-plugin/plugin.json .commands must point at targets/cursor/commands/"
assert_json_eq "$plugin_json" '.hooks' "targets/cursor/hooks/hooks.json" ".cursor-plugin/plugin.json .hooks must point at targets/cursor/hooks/hooks.json"

cursor_rules=$(jq -r '.rules // ""' "$plugin_json" 2>/dev/null) || cursor_rules=""
cursor_skills=$(jq -r '.skills // ""' "$plugin_json" 2>/dev/null) || cursor_skills=""
cursor_commands=$(jq -r '.commands // ""' "$plugin_json" 2>/dev/null) || cursor_commands=""
cursor_hooks=$(jq -r '.hooks // ""' "$plugin_json" 2>/dev/null) || cursor_hooks=""

assert_file_exists "$repo_root/$cursor_rules" "plugin.json .rules path must exist relative to the repo root"

if [ -d "$repo_root/$cursor_skills" ]; then
  cursor_skills_dir_ok=yes
else
  cursor_skills_dir_ok=no
fi
assert_eq "yes" "$cursor_skills_dir_ok" "plugin.json .skills path must exist as a directory relative to the repo root"

if [ -d "$repo_root/$cursor_commands" ]; then
  cursor_commands_dir_ok=yes
else
  cursor_commands_dir_ok=no
fi
assert_eq "yes" "$cursor_commands_dir_ok" "plugin.json .commands path must exist as a directory relative to the repo root"

assert_file_exists "$repo_root/$cursor_hooks" "plugin.json .hooks path must exist relative to the repo root"

assert_file_absent "$repo_root/.cursor-plugin/marketplace.json" ".cursor-plugin/ must not contain marketplace.json"

# ==========================================================================
# 2. generated targets/cursor/hooks/hooks.json: Cursor event names,
#    matcher, CURSOR_PLUGIN_ROOT.
# ==========================================================================
assert_json_valid "$cursor_hooks_json" "targets/cursor/hooks/hooks.json must be valid JSON"
assert_json_eq "$cursor_hooks_json" '.version' "1" "targets/cursor/hooks/hooks.json .version must be 1"

for event in sessionStart beforeSubmitPrompt preToolUse; do
  event_present=$(jq -r --arg e "$event" '(.hooks[$e] // []) | length > 0' "$cursor_hooks_json" 2>/dev/null) || event_present="<jq error>"
  assert_eq "true" "$event_present" "targets/cursor/hooks/hooks.json must define at least one '$event' hook entry"
done

for claude_event in SessionStart UserPromptSubmit PreToolUse; do
  claude_event_present=$(jq -r --arg e "$claude_event" '(.hooks | has($e))' "$cursor_hooks_json" 2>/dev/null) || claude_event_present="<jq error>"
  assert_eq "false" "$claude_event_present" "targets/cursor/hooks/hooks.json must not have a Claude PascalCase '$claude_event' key"
done

pretooluse_matcher=$(jq -r '.hooks.preToolUse[0].matcher // "<missing>"' "$cursor_hooks_json" 2>/dev/null) || pretooluse_matcher="<jq error>"
assert_eq "Write|Read" "$pretooluse_matcher" "targets/cursor/hooks/hooks.json preToolUse matcher must be 'Write|Read' (Cursor has no Edit matcher sibling of Claude's Write|Edit|Read)"

cursor_hook_commands=$(jq -r '.hooks[][] | .command // empty' "$cursor_hooks_json" 2>/dev/null) || cursor_hook_commands=""

# shellcheck disable=SC2016 # single-quoted deliberately: this is the
# literal text every Cursor hook command must contain, not an expression
# to expand in THIS shell.
quoted_cursor_root='"${CURSOR_PLUGIN_ROOT}"'
old_ifs=$IFS
IFS='
'
set --
for cmd in $cursor_hook_commands; do
  [ -n "$cmd" ] || continue
  set -- "$@" "$cmd"
done
IFS=$old_ifs

assert_eq "4" "$#" "targets/cursor/hooks/hooks.json must define exactly 4 hook commands (sessionStart load-profile, beforeSubmitPrompt check-off-flag + load-profile, preToolUse allow-checkpoint)"

for cmd in "$@"; do
  assert_contains "$cmd" "$quoted_cursor_root" "Cursor hooks.json command '$cmd' must quote \${CURSOR_PLUGIN_ROOT} exactly as \"\${CURSOR_PLUGIN_ROOT}\""
  assert_not_contains "$cmd" "CLAUDE_PLUGIN_ROOT" "Cursor hooks.json command '$cmd' must not use CLAUDE_PLUGIN_ROOT"
  rel=${cmd#"$quoted_cursor_root"}
  if [ "$rel" != "$cmd" ]; then
    referenced_script="$repo_root$rel"
    assert_file_exists "$referenced_script" "Cursor hooks.json references '$referenced_script', which must exist"
    if [ -x "$referenced_script" ]; then
      referenced_script_exec=yes
    else
      referenced_script_exec=no
    fi
    assert_eq "yes" "$referenced_script_exec" "Cursor hooks.json-referenced script '$referenced_script' must be executable"
  fi
done

# ==========================================================================
# 3. Cursor skills dir currently ships exactly digest and plan.
# ==========================================================================
cursor_skills_dir="$repo_root/targets/cursor/skills"
cursor_skill_count=0
cursor_skill_names=""
for d in "$cursor_skills_dir"/*; do
  [ -d "$d" ] || continue
  cursor_skill_count=$((cursor_skill_count + 1))
  cursor_skill_names="$cursor_skill_names $(basename "$d")"
done
assert_eq "2" "$cursor_skill_count" "targets/cursor/skills/ must currently contain exactly 2 skills (squirrel-digest, squirrel-plan); do not assert 10 skills yet"
assert_contains "$cursor_skill_names" "squirrel-digest" "targets/cursor/skills/ must include squirrel-digest"
assert_contains "$cursor_skill_names" "squirrel-plan" "targets/cursor/skills/ must include squirrel-plan"

assert_report
