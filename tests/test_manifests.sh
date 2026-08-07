#!/bin/sh
# Coverage for S1's manifests: .claude-plugin/plugin.json,
# .claude-plugin/marketplace.json, LICENSE, and the rule that no
# component directory lives inside .claude-plugin/.
#
# See tests/lib/assert.sh for why `set -eu` here does not abort on the
# first failed assertion: every assert_* helper always returns 0, and
# only assert_report (called once, at the end) turns a failure into a
# non-zero exit code.
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# shellcheck source=lib/assert.sh
. "$script_dir/lib/assert.sh"

plugin_json="$repo_root/.claude-plugin/plugin.json"
marketplace_json="$repo_root/.claude-plugin/marketplace.json"
license_file="$repo_root/LICENSE"

# 1. plugin.json is valid JSON.
assert_json_valid "$plugin_json" "plugin.json must be valid JSON"

# 2. plugin.json .name is exactly the string "squirrel".
assert_json_eq "$plugin_json" '.name' "squirrel" "plugin.json .name must be exactly 'squirrel'"

# 3. plugin.json .description contains ADHD.
plugin_description=$(jq -r '.description // ""' "$plugin_json" 2>/dev/null) || plugin_description=""
assert_contains "$plugin_description" "ADHD" "plugin.json .description must contain 'ADHD'"

# 4. plugin.json .version is present and matches a semver pattern (X.Y.Z),
# with at least one digit required in EACH of the three dot-separated
# positions. A plain shell-glob `[0-9]*.[0-9]*.[0-9]*` looks like it
# enforces that but does not: `[0-9]` there anchors only the character
# immediately at that spot, while the `*` after it is an independent
# "any characters" wildcard, not a repeat-quantifier on the class before
# it — so a trailing `*` after the third `[0-9]` happily absorbs
# non-digit trailing garbage (e.g. "1.2.3.4" and "1.2.3-beta" both satisfy
# that pattern), and an extra dot can carve out a digit-free segment
# elsewhere in the string (e.g. "1..2.3" also satisfies it — the first
# `[0-9]` anchors "1", one dot and one digit satisfy the middle
# `[0-9]`/dot pair using the STRING's second and third characters, and the
# remaining ".3" is absorbed by the final `*`). POSIX `case` globbing has
# no repeat-quantifier for a class (no `+`), so "one or more digits" is
# validated here by splitting on the first two dots with parameter
# expansion instead of leaning on the glob to enforce it: `%%.*` (longest
# suffix starting with a dot removed) isolates the segment before the
# FIRST dot, and `#*.` (shortest prefix ending in a dot removed) isolates
# everything after it, applied twice to peel off major/minor/patch in
# turn. Each resulting segment is then checked for being non-empty AND
# entirely digits — `''` catches the empty case (also what an omitted
# segment reduces to, e.g. the middle segment of "1..2"), `*[!0-9]*`
# catches any non-digit character anywhere in the segment (also what
# rejects a segment containing a literal leftover dot, which is how a
# 4th dot-separated part gets caught too).
plugin_version=$(jq -r '.version // ""' "$plugin_json" 2>/dev/null) || plugin_version=""
case "$plugin_version" in
  *.*.*)
    semver_major=${plugin_version%%.*}
    semver_rest=${plugin_version#*.}
    semver_minor=${semver_rest%%.*}
    semver_patch=${semver_rest#*.}
    ;;
  *)
    semver_major=""
    semver_minor=""
    semver_patch=""
    ;;
esac
case "$semver_major" in
  '' | *[!0-9]*) semver_major_ok=no ;;
  *) semver_major_ok=yes ;;
esac
case "$semver_minor" in
  '' | *[!0-9]*) semver_minor_ok=no ;;
  *) semver_minor_ok=yes ;;
esac
case "$semver_patch" in
  '' | *[!0-9]*) semver_patch_ok=no ;;
  *) semver_patch_ok=yes ;;
esac
if [ "$semver_major_ok" = yes ] && [ "$semver_minor_ok" = yes ] && [ "$semver_patch_ok" = yes ]; then
  semver_ok=yes
else
  semver_ok=no
fi
assert_eq "yes" "$semver_ok" "plugin.json .version ('$plugin_version') must match a semver pattern X.Y.Z with a non-empty, all-digit segment in each of the three positions"

# 5. plugin.json .license is MIT.
assert_json_eq "$plugin_json" '.license' "MIT" "plugin.json .license must be 'MIT'"

# 6. plugin.json contains none of the path-override keys — we rely on
# default locations, and a stray override would silently disable a
# component (see rule 14 in rules/base-rules.md for why we avoid that
# word in prose; here it just names the risk this check guards).
for key in commands skills hooks agents outputStyles mcpServers lspServers; do
  has_key=$(jq -r --arg k "$key" 'has($k)' "$plugin_json" 2>/dev/null) || has_key="<jq error>"
  assert_eq "false" "$has_key" "plugin.json must not override '$key' (defaults only)"
done

# 7. marketplace.json is valid JSON.
assert_json_valid "$marketplace_json" "marketplace.json must be valid JSON"

# 8. marketplace.json .owner.name is present and non-empty.
owner_name=$(jq -r '.owner.name // ""' "$marketplace_json" 2>/dev/null) || owner_name=""
if [ -n "$owner_name" ]; then
  owner_name_present=yes
else
  owner_name_present=no
fi
assert_eq "yes" "$owner_name_present" "marketplace.json .owner.name must be present and non-empty"

# 9. marketplace.json .plugins is an array of length 1.
plugins_length=$(jq -r '.plugins | length' "$marketplace_json" 2>/dev/null) || plugins_length="<jq error>"
assert_eq "1" "$plugins_length" "marketplace.json .plugins must be an array of length 1"

# 10. The marketplace entry .plugins[0].name equals plugin.json's .name.
# Read both files and compare — never hardcode the string twice, so a
# rename of one without the other is caught.
plugin_json_name=$(jq -r '.name // ""' "$plugin_json" 2>/dev/null) || plugin_json_name=""
marketplace_entry_name=$(jq -r '.plugins[0].name // ""' "$marketplace_json" 2>/dev/null) || marketplace_entry_name=""
assert_eq "$plugin_json_name" "$marketplace_entry_name" "marketplace .plugins[0].name must equal plugin.json .name"

# 11. .plugins[0].source is "./".
assert_json_eq "$marketplace_json" '.plugins[0].source' "./" "marketplace .plugins[0].source must be './'"

# 12. .plugins[0].tags contains adhd.
plugins_tags=$(jq -r '.plugins[0].tags | join(",")' "$marketplace_json" 2>/dev/null) || plugins_tags=""
assert_contains "$plugins_tags" "adhd" "marketplace .plugins[0].tags must contain 'adhd'"

# 13. .claude-plugin/ contains EXACTLY plugin.json and marketplace.json
# and nothing else — not an enumerated subset of forbidden names (a
# stray file, or a differently-named component directory, must fail
# this too, not just the three specific names skills/hooks/commands).
claude_plugin_dir="$repo_root/.claude-plugin"
if [ -d "$claude_plugin_dir" ]; then
  # Shell-glob listing (not `ls`, which shellcheck SC2012 flags as
  # unsafe for non-alphanumeric names in a pipeline): the three
  # patterns together match every entry except `.` and `..`, dotfiles
  # included, so a stray `.DS_Store` fails this just as loudly as a
  # stray directory would.
  claude_plugin_entries=""
  for entry in "$claude_plugin_dir"/* "$claude_plugin_dir"/.[!.]* "$claude_plugin_dir"/..?*; do
    if [ -e "$entry" ]; then
      claude_plugin_entries="$claude_plugin_entries $(basename "$entry")"
    fi
  done
  claude_plugin_listing=$(printf '%s\n' "$claude_plugin_entries" | tr -s ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ *$//')
else
  claude_plugin_listing="<directory missing>"
fi
assert_eq "marketplace.json plugin.json" "$claude_plugin_listing" ".claude-plugin/ must contain exactly plugin.json and marketplace.json, nothing else"

# 14. LICENSE exists and contains MIT License and Thiago Matajs.
assert_file_exists "$license_file" "LICENSE must exist"
if [ -f "$license_file" ]; then
  license_body=$(cat "$license_file")
else
  license_body=""
fi
assert_contains "$license_body" "MIT License" "LICENSE must contain 'MIT License'"
assert_contains "$license_body" "Thiago Matajs" "LICENSE must contain 'Thiago Matajs'"
# The MIT template's unfilled placeholders ("Copyright (c) [year]
# [fullname]") must not survive a copy-paste — a genuine, real-world
# failure mode, and one assert_not_contains is actually suited to.
assert_not_contains "$license_body" "[fullname]" "LICENSE must not contain the unfilled MIT template placeholder '[fullname]'"
assert_not_contains "$license_body" "[year]" "LICENSE must not contain the unfilled MIT template placeholder '[year]'"

# 15. marketplace.json's plugin entry must NOT carry its own 'version'
# key. Claude Code always reads version from plugin.json and silently
# ignores marketplace.json's copy (per the live docs — see finding 8),
# so a duplicated version key here can only go stale unnoticed.
marketplace_entry_has_version=$(jq -r '.plugins[0] | has("version")' "$marketplace_json" 2>/dev/null) || marketplace_entry_has_version="<jq error>"
assert_eq "false" "$marketplace_entry_has_version" "marketplace .plugins[0] must not carry a 'version' key (plugin.json is the only source of truth)"

# 16. marketplace.json must not duplicate plugin.json's version at ANY
# other level either — not a top-level '.version', and not a
# '.metadata.version'. Cycle 2 already removed .plugins[0].version for
# exactly this reason (assertion 15 above); a duplicate one level up (or
# at the root) is the same staleness risk in a different spot, and
# PLAN.md never calls for a 'metadata' field on marketplace.json at all.
# `(.metadata // {})` makes this assertion correct whether or not
# 'metadata' exists as a key at all: `has("version")` on `{}` is `false`,
# so a wholesale-removed 'metadata' object passes exactly like a
# 'metadata' object that simply never carried 'version' would.
marketplace_has_top_version=$(jq -r 'has("version")' "$marketplace_json" 2>/dev/null) || marketplace_has_top_version="<jq error>"
assert_eq "false" "$marketplace_has_top_version" "marketplace.json must not carry a top-level 'version' key (plugin.json is the only source of truth)"

marketplace_has_metadata_version=$(jq -r '(.metadata // {}) | has("version")' "$marketplace_json" 2>/dev/null) || marketplace_has_metadata_version="<jq error>"
assert_eq "false" "$marketplace_has_metadata_version" "marketplace.json must not carry a '.metadata.version' key (plugin.json is the only source of truth)"

assert_report
