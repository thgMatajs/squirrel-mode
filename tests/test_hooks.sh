#!/bin/sh
# Coverage for S4: hooks/hooks.json and the three POSIX sh hook scripts
# (load-profile.sh, check-off-flag.sh, allow-checkpoint.sh). Behavioural,
# not structural: every script is fed real JSON on stdin and asserted on
# its stdout, exit code, and filesystem side effects, under a temporary
# HOME so nothing here ever touches the real ~/.claude/squirrel/. This
# is also where .build-checkpoint.md's "Known gap, carried into S4" note
# gets closed: scenario 2 in particular is the missing-input case it
# flags.
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

hooks_json="$repo_root/hooks/hooks.json"
load_profile_script="$repo_root/scripts/load-profile.sh"
check_off_flag_script="$repo_root/scripts/check-off-flag.sh"
allow_checkpoint_script="$repo_root/scripts/allow-checkpoint.sh"

# --- Cleanup ----------------------------------------------------------
#
# All scratch HOME directories and mutant script copies accumulate in
# one space-joined list and are removed by a single EXIT trap - a
# second `trap ... EXIT` later in this file would silently REPLACE this
# one rather than add to it, so every scratch path created below is
# appended here, never given its own trap.
cleanup_paths=""
trap 'rm -rf $cleanup_paths' EXIT

new_home() {
  # new_home - creates a fresh, empty scratch directory to use as HOME
  # for one scenario. Nothing under it exists yet, matching a genuine
  # fresh install.
  h=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-hooks-home.XXXXXX")
  cleanup_paths="$cleanup_paths $h"
  printf '%s' "$h"
}

# --- Running a script under a scratch HOME with given stdin -----------
#
# Two separate helpers (rather than one that encodes both exit code and
# stdout into a single string) so each stays simple to read. Scripts
# under test are pure functions of stdin + HOME + the filesystem state
# a test sets up beforehand, so invoking twice per scenario costs
# nothing and never changes behaviour.
capture_exit() {
  # capture_exit <script> <home> <stdin_data>
  script=$1
  home=$2
  stdin_data=$3
  if printf '%s' "$stdin_data" | HOME="$home" "$script" >/dev/null 2>&1; then
    printf '0'
  else
    printf '%s' "$?"
  fi
}

capture_stdout() {
  # capture_stdout <script> <home> <stdin_data> - stderr discarded.
  # Never lets a non-zero exit from the script abort this helper: `||
  # true` is exempt from `set -e`, and $out already holds whatever the
  # script printed to stdout regardless of its exit status.
  script=$1
  home=$2
  stdin_data=$3
  out=$(printf '%s' "$stdin_data" | HOME="$home" "$script" 2>/dev/null) || true
  printf '%s' "$out"
}

# capture_exit_with_path / capture_stdout_with_path: same contracts as
# capture_exit / capture_stdout above, with PATH also overridden (see
# make_tool_path). Used wherever a scenario must prove behaviour holds
# with a specific external tool absent, not merely absent from this
# test process's own environment - the script under test always
# inherits the real, full PATH unless a test explicitly overrides it.
capture_exit_with_path() {
  script=$1
  home=$2
  toolpath=$3
  stdin_data=$4
  if printf '%s' "$stdin_data" | HOME="$home" PATH="$toolpath" "$script" >/dev/null 2>&1; then
    printf '0'
  else
    printf '%s' "$?"
  fi
}

capture_stdout_with_path() {
  script=$1
  home=$2
  toolpath=$3
  stdin_data=$4
  out=$(printf '%s' "$stdin_data" | HOME="$home" PATH="$toolpath" "$script" 2>/dev/null) || true
  printf '%s' "$out"
}

# extract_ctx <load-profile.sh stdout> - the additionalContext string,
# or "<jq error>" if the JSON could not be parsed (a distinctive
# sentinel that can never accidentally equal or contain real content,
# so a parse failure is never mistaken for a real, empty, or missing
# field downstream).
extract_ctx() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || printf '<jq error>'
}

extract_checkpoint_path_line() {
  # extract_checkpoint_path_line <additionalContext text> - the
  # resolved path load-profile.sh reported, per tech-lead Decision 1.
  # Read from the SCRIPT'S OWN reported output rather than recomputing
  # the slug algorithm a second time here - recomputing it would make
  # this test tautological (it would only ever check the algorithm
  # against itself) instead of checking what a real Claude session
  # actually does: read the injected line and use it verbatim.
  printf '%s\n' "$1" | sed -n 's/^Project checkpoint path: //p' | head -n 1
}

# --- Mutation-testing helpers (mirrors tests/test_build.sh's
# make_build_scratch / delete_line / replace_line style) -------------
#
# Used only by the failure-proof scenarios at the bottom of this file:
# each copies ONE real script into a throwaway scratch file, mutates
# that copy to reintroduce a specific, named bug, and asserts the
# mutant's behaviour genuinely differs from the real script's - proving
# the corresponding scenario's assertion is not vacuously passing. The
# real, shipped scripts are never touched.
make_script_scratch() {
  src=$1
  scratch=$(mktemp "${TMPDIR:-/tmp}/squirrel-hook-mutant.XXXXXX")
  cleanup_paths="$cleanup_paths $scratch"
  cp "$src" "$scratch"
  chmod +x "$scratch"
  printf '%s' "$scratch"
}

# --- Restricted-PATH helper --------------------------------------------
#
# make_tool_path <space-separated exclude list> - builds a fresh
# directory containing a symlink to every tool this suite might need
# from a fixed candidate list, resolved via THIS test process's own
# (real, full) PATH, except any name that appears in <exclude list>.
# Returns the directory's path; callers run a script under test with
# `PATH="$(make_tool_path 'realpath readlink')"` (etc.) to prove a
# behaviour genuinely holds with a given binary absent, rather than
# merely asserting a code path exists and hoping it is the one that
# ran. Silently skips any candidate not present on the real machine
# running the suite (e.g. a CI box without `cksum`), which is fine -
# absence-by-omission is indistinguishable from absence-by-exclusion to
# a script under test.
make_tool_path() {
  exclude=$1
  dir=$(mktemp -d "${TMPDIR:-/tmp}/squirrel-toolpath.XXXXXX")
  cleanup_paths="$cleanup_paths $dir"
  for tool in sh awk sed cat find dirname basename tr cksum od head tail wc cut printf grep jq realpath readlink mktemp rm mkdir ln touch; do
    case " $exclude " in
      *" $tool "*) continue ;;
    esac
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$tool_path" "$dir/$tool" 2>/dev/null || true
  done
  printf '%s' "$dir"
}

line_of() {
  # line_of <file> <literal_text> - first line number whose content is
  # EXACTLY <literal_text> (whole-line equality, not substring).
  #
  # <literal_text> is passed via ENVIRON, NOT `awk -v` (cycle-3 fix):
  # POSIX awk's `-v var=value` assignment runs the exact same
  # backslash-escape processing a string LITERAL in the awk program
  # itself gets, so `-v want='...\\u...'` - two literal backslashes,
  # precisely what a target line of shell source containing a JSON
  # \u-escape (see json_escape in load-profile.sh) looks like -
  # silently collapses to ONE backslash before the `$0 == want`
  # comparison ever runs, so it can never match the real line. This is
  # exactly the bug that made scenario 23's own failure proof
  # impossible to write correctly until this was fixed here.
  # `ENVIRON["WANT"]` reads the process environment directly, with no
  # string-literal reprocessing at all, so the exact bytes assigned
  # below survive untouched into the comparison.
  WANT="$2" awk '$0 == ENVIRON["WANT"] { print NR; exit }' "$1"
}

line_of_after() {
  # line_of_after <file> <start_line_no> <literal_text> - first line at
  # or after <start_line_no> whose content is exactly <literal_text>.
  # Needed wherever a closing "fi" or "}" is not unique in the whole
  # file (several functions in these scripts close the same way).
  # <start_line_no> is always a plain integer (never a backslash), so
  # it stays a normal `-v`; <literal_text> goes through ENVIRON for the
  # same reason line_of does, above.
  WANT="$3" awk -v start="$2" 'NR >= start && $0 == ENVIRON["WANT"] { print NR; exit }' "$1"
}

replace_line() {
  # replace_line <file> <line_no> <new_text>
  #
  # Rewriting via "awk ... >tmp && mv tmp file" replaces the file's
  # inode, so the new inode does NOT inherit the executable bit the
  # original had - it gets whatever the shell's umask gives a freshly
  # `>`-created file instead (tests/test_build.sh's own
  # inject_marker_and_sleep_after notes the identical gotcha for its
  # own awk+mv rewrite). Re-asserting +x after every mutation, here and
  # in replace_block below, is what lets a script mutated 1-3 times in
  # a row still be directly executable afterwards.
  #
  # <new_text> goes through ENVIRON, not `awk -v t=`, for the identical
  # backslash-collapsing reason line_of's own comment explains above -
  # a replacement line containing a JSON \u-escape or any other doubled
  # backslash would otherwise come out wrong on the way BACK in, not
  # just fail to match on the way in.
  file=$1
  n=$2
  t=$3
  NEWTEXT="$t" awk -v n="$n" 'NR == n { print ENVIRON["NEWTEXT"]; next } { print }' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
  chmod +x "$file"
}

replace_block() {
  # replace_block <file> <start_line_no> <end_line_no_inclusive> <replacement_text>
  # <replacement_text> may itself contain embedded real newlines (a
  # whole multi-line function body collapses into the given range).
  # Deliberately built from `head`/`printf`/`tail` rather than `awk -v`:
  # the BWK "one true awk" shipped as /usr/bin/awk on macOS rejects a
  # multi-line value in `-v name=value` outright ("newline in string"),
  # so passing a multi-line replacement through `-v` the way
  # tests/test_build.sh's own single-LINE helpers do is not portable
  # here - `head`/`tail` never pass the replacement through awk at all.
  # Re-asserts +x afterwards for the same reason replace_line does.
  file=$1
  s=$2
  e=$3
  t=$4
  tmp="$file.tmp.$$"
  head -n "$((s - 1))" "$file" >"$tmp"
  printf '%s\n' "$t" >>"$tmp"
  tail -n "+$((e + 1))" "$file" >>"$tmp"
  mv "$tmp" "$file"
  chmod +x "$file"
}

# ==========================================================================
# 1. hooks/hooks.json: valid JSON, all three events present, matchers
#    correct, every referenced script exists and is executable, every
#    command quotes ${CLAUDE_PLUGIN_ROOT}.
# ==========================================================================
assert_json_valid "$hooks_json" "hooks/hooks.json must be valid JSON"

session_start_matcher=$(jq -r '.hooks.SessionStart[0].matcher // "<missing>"' "$hooks_json" 2>/dev/null) || session_start_matcher="<jq error>"
assert_eq "startup|resume|clear|compact" "$session_start_matcher" "hooks.json SessionStart matcher must be 'startup|resume|clear|compact'"

pretooluse_matcher=$(jq -r '.hooks.PreToolUse[0].matcher // "<missing>"' "$hooks_json" 2>/dev/null) || pretooluse_matcher="<jq error>"
assert_eq "Write|Edit" "$pretooluse_matcher" "hooks.json PreToolUse matcher must be 'Write|Edit'"

userpromptsubmit_present=$(jq -r '(.hooks.UserPromptSubmit // []) | length > 0' "$hooks_json" 2>/dev/null) || userpromptsubmit_present="<jq error>"
assert_eq "true" "$userpromptsubmit_present" "hooks.json must define at least one UserPromptSubmit hook entry"

session_start_count=$(jq -r '(.hooks.SessionStart // []) | length' "$hooks_json" 2>/dev/null) || session_start_count="<jq error>"
assert_eq "1" "$session_start_count" "hooks.json must define exactly one SessionStart matcher entry"

pretooluse_count=$(jq -r '(.hooks.PreToolUse // []) | length' "$hooks_json" 2>/dev/null) || pretooluse_count="<jq error>"
assert_eq "1" "$pretooluse_count" "hooks.json must define exactly one PreToolUse matcher entry"

all_commands=$(jq -r '.hooks[][] | .hooks[]?.command // empty' "$hooks_json" 2>/dev/null) || all_commands=""
command_count=$(printf '%s\n' "$all_commands" | grep -c '.' || true)
assert_eq "3" "$command_count" "hooks.json must define exactly 3 hook commands total (one per script)"

# Collect commands into positional parameters (never a piped while-read
# loop, which would fork a subshell and silently discard every
# assert_pass/assert_fail counter update made inside it - see
# tests/test_shell_dialect.sh for the same for-loop-over-IFS pattern).
old_ifs=$IFS
IFS='
'
set --
for cmd in $all_commands; do
  [ -n "$cmd" ] || continue
  set -- "$@" "$cmd"
done
IFS=$old_ifs

# shellcheck disable=SC2016 # single-quoted deliberately: this is the
# literal text every hook command must contain, not an expression to
# expand in THIS shell.
quoted_plugin_root='"${CLAUDE_PLUGIN_ROOT}"'
for cmd in "$@"; do
  assert_contains "$cmd" "$quoted_plugin_root" "hooks.json command '$cmd' must quote \${CLAUDE_PLUGIN_ROOT} exactly as \"\${CLAUDE_PLUGIN_ROOT}\""
  rel=${cmd#"$quoted_plugin_root"}
  if [ "$rel" != "$cmd" ]; then
    referenced_script="$repo_root$rel"
    assert_file_exists "$referenced_script" "hooks.json references '$referenced_script', which must exist"
    if [ -x "$referenced_script" ]; then
      referenced_script_exec=yes
    else
      referenced_script_exec=no
    fi
    assert_eq "yes" "$referenced_script_exec" "hooks.json-referenced script '$referenced_script' must be executable"
  fi
done

assert_file_exists "$load_profile_script" "scripts/load-profile.sh must exist"
assert_file_exists "$check_off_flag_script" "scripts/check-off-flag.sh must exist"
assert_file_exists "$allow_checkpoint_script" "scripts/allow-checkpoint.sh must exist"

# ==========================================================================
# 2. load-profile.sh - fresh install, nothing under ~/.claude/squirrel/
#    at all: exit 0, valid JSON, contains a single /squirrel:init
#    suggestion. This is the "Known gap" missing-input case.
# ==========================================================================
home2=$(new_home)
sessionstart_stdin=$(printf '{"session_id":"s1","cwd":"%s/project-a","hook_event_name":"SessionStart","source":"startup"}' "$home2")

exit2=$(capture_exit "$load_profile_script" "$home2" "$sessionstart_stdin")
assert_eq "0" "$exit2" "load-profile.sh must exit 0 on a completely fresh install (no ~/.claude/squirrel/ at all)"

out2=$(capture_stdout "$load_profile_script" "$home2" "$sessionstart_stdin")
out2_json_valid=$(printf '%s' "$out2" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out2_json_valid" "load-profile.sh stdout must be valid JSON on a fresh install"

ctx2=$(extract_ctx "$out2")
init_mentions2=$(printf '%s' "$ctx2" | grep -o '/squirrel:init' | grep -c '.' || true)
assert_eq "1" "$init_mentions2" "fresh-install additionalContext must mention /squirrel:init exactly once"

# ==========================================================================
# 3. load-profile.sh - profile exists, no checkpoint: exit 0, profile
#    contents present, checkpoint path present, NO 'Resume available'.
# ==========================================================================
home3=$(new_home)
mkdir -p "$home3/.claude/squirrel"
profile3_marker="LANGUAGE_MARKER_XYZ_pt-BR"
cat >"$home3/.claude/squirrel/profile.md" <<EOF
# squirrel-mode profile
language: $profile3_marker
EOF
stdin3=$(printf '{"session_id":"s1","cwd":"%s/project-a"}' "$home3")

exit3=$(capture_exit "$load_profile_script" "$home3" "$stdin3")
assert_eq "0" "$exit3" "load-profile.sh must exit 0 when a profile exists but no checkpoint does"

out3=$(capture_stdout "$load_profile_script" "$home3" "$stdin3")
ctx3=$(extract_ctx "$out3")
assert_contains "$ctx3" "$profile3_marker" "additionalContext must contain the profile file's own content"
assert_contains "$ctx3" "Project checkpoint path:" "additionalContext must contain the resolved checkpoint path line"
assert_not_contains "$ctx3" "Resume available" "additionalContext must NOT say 'Resume available' when no checkpoint exists yet"

# ==========================================================================
# 4. load-profile.sh - profile AND checkpoint exist: exit 0, contains
#    'Resume available', and does NOT contain the checkpoint's own body
#    text (PLAN.md: never dump checkpoint contents).
# ==========================================================================
home4=$(new_home)
mkdir -p "$home4/.claude/squirrel"
cat >"$home4/.claude/squirrel/profile.md" <<'EOF'
# squirrel-mode profile
language: en
EOF
stdin4=$(printf '{"cwd":"%s/project-b"}' "$home4")

# Learn the checkpoint path FROM THE SCRIPT ITSELF (Decision 1's own
# contract) rather than recomputing the slug here.
pre_out4=$(capture_stdout "$load_profile_script" "$home4" "$stdin4")
pre_ctx4=$(extract_ctx "$pre_out4")
checkpoint_path4=$(extract_checkpoint_path_line "$pre_ctx4")
if [ -n "$checkpoint_path4" ]; then
  checkpoint_path4_present=yes
else
  checkpoint_path4_present=no
fi
assert_eq "yes" "$checkpoint_path4_present" "load-profile.sh must report a non-empty checkpoint path before any checkpoint exists (Decision 1)"

mkdir -p "$(dirname "$checkpoint_path4")"
checkpoint4_body_marker="DISTINCTIVE_CHECKPOINT_BODY_DO_NOT_LEAK_998877"
cat >"$checkpoint_path4" <<EOF
# checkpoint: project-b
## Doing
$checkpoint4_body_marker
EOF

exit4=$(capture_exit "$load_profile_script" "$home4" "$stdin4")
assert_eq "0" "$exit4" "load-profile.sh must exit 0 when both profile and checkpoint exist"

out4=$(capture_stdout "$load_profile_script" "$home4" "$stdin4")
ctx4=$(extract_ctx "$out4")
assert_contains "$ctx4" "Resume available" "additionalContext must contain 'Resume available' once a checkpoint exists for this project"
assert_not_contains "$ctx4" "$checkpoint4_body_marker" "additionalContext must NOT leak the checkpoint file's own body text"

# ==========================================================================
# 5. load-profile.sh - slug collision resistance: two different cwd
#    values sharing a basename must produce different checkpoint paths.
# ==========================================================================
home5=$(new_home)
stdin5a=$(printf '{"cwd":"%s/alice/myapp"}' "$home5")
stdin5b=$(printf '{"cwd":"%s/bob/other/myapp"}' "$home5")

ctx5a=$(extract_ctx "$(capture_stdout "$load_profile_script" "$home5" "$stdin5a")")
ctx5b=$(extract_ctx "$(capture_stdout "$load_profile_script" "$home5" "$stdin5b")")
path5a=$(extract_checkpoint_path_line "$ctx5a")
path5b=$(extract_checkpoint_path_line "$ctx5b")

if [ -n "$path5a" ] && [ -n "$path5b" ] && [ "$path5a" != "$path5b" ]; then
  slugs5_differ=yes
else
  slugs5_differ=no
fi
assert_eq "yes" "$slugs5_differ" "two different cwd values sharing basename 'myapp' must produce different checkpoint paths (got a='$path5a' b='$path5b')"

# ==========================================================================
# 6. load-profile.sh - slug determinism: the same cwd twice produces the
#    identical checkpoint path.
# ==========================================================================
home6=$(new_home)
stdin6=$(printf '{"cwd":"%s/same/project"}' "$home6")
path6_first=$(extract_checkpoint_path_line "$(extract_ctx "$(capture_stdout "$load_profile_script" "$home6" "$stdin6")")")
path6_second=$(extract_checkpoint_path_line "$(extract_ctx "$(capture_stdout "$load_profile_script" "$home6" "$stdin6")")")
assert_eq "$path6_first" "$path6_second" "the same cwd must produce the identical checkpoint path on repeated invocations"

# ==========================================================================
# 7. load-profile.sh - output is valid JSON in every scenario above
#    (parsed via jq, not eyeballed).
# ==========================================================================
for pair in "2:$out2" "3:$out3" "4:$out4"; do
  label=${pair%%:*}
  content=${pair#*:}
  if printf '%s' "$content" | jq empty >/dev/null 2>&1; then
    scenario7_valid=yes
  else
    scenario7_valid=no
  fi
  assert_eq "yes" "$scenario7_valid" "load-profile.sh scenario $label output must be valid, parseable JSON"
done

# ==========================================================================
# 8. load-profile.sh - malformed stdin (empty, not JSON, JSON missing
#    cwd): exit 0, output is either empty or parseable JSON. Never a
#    non-zero exit.
# ==========================================================================
home8=$(new_home)
for malformed8 in "" "this is not json at all" '{"session_id":"only-this-no-cwd"}' '{"cwd":'; do
  exit8=$(capture_exit "$load_profile_script" "$home8" "$malformed8")
  assert_eq "0" "$exit8" "load-profile.sh must exit 0 on malformed stdin (input: '$malformed8')"
  out8=$(capture_stdout "$load_profile_script" "$home8" "$malformed8")
  if [ -z "$out8" ]; then
    out8_ok=yes
  elif printf '%s' "$out8" | jq empty >/dev/null 2>&1; then
    out8_ok=yes
  else
    out8_ok=no
  fi
  assert_eq "yes" "$out8_ok" "load-profile.sh output on malformed stdin ('$malformed8') must be empty or valid JSON, got: $out8"
done

# ==========================================================================
# 9. check-off-flag.sh - no flag file: empty stdout, exit 0.
# ==========================================================================
home9=$(new_home)
stdin9=$(printf '{"session_id":"sess-no-flag"}')
exit9=$(capture_exit "$check_off_flag_script" "$home9" "$stdin9")
assert_eq "0" "$exit9" "check-off-flag.sh must exit 0 when no flag file exists"
out9=$(capture_stdout "$check_off_flag_script" "$home9" "$stdin9")
assert_eq "" "$out9" "check-off-flag.sh must print nothing when no flag file exists"

# ==========================================================================
# 10. check-off-flag.sh - flag present: stdout contains the
#     counter-instruction, exit 0.
# ==========================================================================
home10=$(new_home)
mkdir -p "$home10/.claude/squirrel/off"
touch "$home10/.claude/squirrel/off/sess-flagged"
stdin10=$(printf '{"session_id":"sess-flagged"}')
exit10=$(capture_exit "$check_off_flag_script" "$home10" "$stdin10")
assert_eq "0" "$exit10" "check-off-flag.sh must exit 0 when the flag file exists"
out10=$(capture_stdout "$check_off_flag_script" "$home10" "$stdin10")
assert_contains "$out10" "squirrel-mode is OFF" "check-off-flag.sh must print the counter-instruction when the flag file exists"
assert_contains "$out10" "/squirrel:on" "the counter-instruction must reference /squirrel:on"

# ==========================================================================
# 11. check-off-flag.sh - flag for a DIFFERENT session id: empty stdout
#     (must not leak across sessions).
# ==========================================================================
home11=$home10
stdin11=$(printf '{"session_id":"sess-completely-different"}')
out11=$(capture_stdout "$check_off_flag_script" "$home11" "$stdin11")
assert_eq "" "$out11" "check-off-flag.sh must print nothing for a session id whose own flag file does not exist, even when another session's flag does"

# ==========================================================================
# 12. check-off-flag.sh - session_id traversal attempts: exit 0, no
#     injection, and no read outside the off/ directory. Proven by
#     placing a file OUTSIDE off/ (but inside squirrel/) that a
#     traversal could reach, and confirming it is never treated as "the
#     flag".
# ==========================================================================
home12=$(new_home)
mkdir -p "$home12/.claude/squirrel/off"
touch "$home12/.claude/squirrel/decoy-outside-off.txt"
for traversal12 in "../../../etc/passwd" "../decoy-outside-off.txt" "../off/../decoy-outside-off.txt" "/etc/passwd" "a/b" "sess with spaces"; do
  stdin12=$(printf '{"session_id":"%s"}' "$traversal12")
  exit12=$(capture_exit "$check_off_flag_script" "$home12" "$stdin12")
  assert_eq "0" "$exit12" "check-off-flag.sh must exit 0 for traversal-shaped session_id '$traversal12'"
  out12=$(capture_stdout "$check_off_flag_script" "$home12" "$stdin12")
  assert_eq "" "$out12" "check-off-flag.sh must print nothing for traversal-shaped session_id '$traversal12' (no read outside off/)"
done

# ==========================================================================
# 13. check-off-flag.sh - malformed/empty stdin: exit 0, empty stdout.
# ==========================================================================
home13=$(new_home)
for malformed13 in "" "not json" '{"no_session_id_here":true}'; do
  exit13=$(capture_exit "$check_off_flag_script" "$home13" "$malformed13")
  assert_eq "0" "$exit13" "check-off-flag.sh must exit 0 on malformed stdin ('$malformed13')"
  out13=$(capture_stdout "$check_off_flag_script" "$home13" "$malformed13")
  assert_eq "" "$out13" "check-off-flag.sh must print nothing on malformed stdin ('$malformed13')"
done

# ==========================================================================
# 14. allow-checkpoint.sh - file_path inside the checkpoints directory:
#     permissionDecision must be "allow".
# ==========================================================================
home14=$(new_home)
stdin14=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/myproj.md"}}' "$home14")
exit14=$(capture_exit "$allow_checkpoint_script" "$home14" "$stdin14")
assert_eq "0" "$exit14" "allow-checkpoint.sh must exit 0 for a legitimate checkpoint write"
out14=$(capture_stdout "$allow_checkpoint_script" "$home14" "$stdin14")
decision14=$(printf '%s' "$out14" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision14="<jq error>"
assert_eq "allow" "$decision14" "allow-checkpoint.sh must return 'allow' for a file_path inside the checkpoints directory"

# ==========================================================================
# 15. allow-checkpoint.sh - file_path elsewhere in $HOME: "defer".
# ==========================================================================
home15=$(new_home)
stdin15=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/Documents/notes.md"}}' "$home15")
out15=$(capture_stdout "$allow_checkpoint_script" "$home15" "$stdin15")
decision15=$(printf '%s' "$out15" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision15="<jq error>"
assert_eq "defer" "$decision15" "allow-checkpoint.sh must return 'defer' for a file_path elsewhere in \$HOME"

# ==========================================================================
# 16. allow-checkpoint.sh - traversal:
#     $HOME/.claude/squirrel/checkpoints/../../../.ssh/id_rsa -> "defer".
# ==========================================================================
home16=$(new_home)
stdin16=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$home16")
out16=$(capture_stdout "$allow_checkpoint_script" "$home16" "$stdin16")
decision16=$(printf '%s' "$out16" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision16="<jq error>"
assert_eq "defer" "$decision16" "allow-checkpoint.sh must return 'defer' for a traversal path escaping checkpoints/ via ../../../"

# ==========================================================================
# 17. allow-checkpoint.sh - prefix-escape:
#     $HOME/.claude/squirrel/checkpoints-evil/x -> "defer".
# ==========================================================================
home17=$(new_home)
stdin17=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints-evil/x"}}' "$home17")
out17=$(capture_stdout "$allow_checkpoint_script" "$home17" "$stdin17")
decision17=$(printf '%s' "$out17" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision17="<jq error>"
assert_eq "defer" "$decision17" "allow-checkpoint.sh must return 'defer' for a directory that merely starts with the string 'checkpoints' ('checkpoints-evil')"

# ==========================================================================
# 18. allow-checkpoint.sh - relative file_path, empty file_path, absent
#     file_path, tool_input absent entirely: all "defer", exit 0.
# ==========================================================================
home18=$(new_home)
scenario18_cases="relative_file_path:{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"relative/path.md\"}}
empty_file_path:{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"\"}}
absent_file_path:{\"tool_name\":\"Write\",\"tool_input\":{}}
absent_tool_input:{\"tool_name\":\"Write\"}"

old_ifs=$IFS
IFS='
'
for case18 in $scenario18_cases; do
  IFS=$old_ifs
  case18_name=${case18%%:*}
  case18_json=${case18#*:}
  exit18=$(capture_exit "$allow_checkpoint_script" "$home18" "$case18_json")
  assert_eq "0" "$exit18" "allow-checkpoint.sh must exit 0 for case '$case18_name'"
  out18=$(capture_stdout "$allow_checkpoint_script" "$home18" "$case18_json")
  decision18=$(printf '%s' "$out18" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision18="<jq error>"
  assert_eq "defer" "$decision18" "allow-checkpoint.sh must return 'defer' for case '$case18_name'"
  IFS='
'
done
IFS=$old_ifs

# ==========================================================================
# 19. allow-checkpoint.sh - a symlink inside the checkpoints directory
#     pointing outside it: "defer". Two sub-cases: the symlink is an
#     intermediate directory in the path, and the symlink IS the leaf
#     file_path itself.
# ==========================================================================
home19=$(new_home)
mkdir -p "$home19/.claude/squirrel/checkpoints" "$home19/outside-secret"
ln -s "$home19/outside-secret" "$home19/.claude/squirrel/checkpoints/escape-dir"
touch "$home19/outside-secret/secret.md"
ln -s "$home19/outside-secret/secret.md" "$home19/.claude/squirrel/checkpoints/escape-file"

stdin19a=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/escape-dir/evil.md"}}' "$home19")
out19a=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19a")
decision19a=$(printf '%s' "$out19a" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19a="<jq error>"
assert_eq "defer" "$decision19a" "allow-checkpoint.sh must return 'defer' when an intermediate directory inside checkpoints/ is a symlink pointing outside it"

stdin19b=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/escape-file"}}' "$home19")
out19b=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19b")
decision19b=$(printf '%s' "$out19b" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19b="<jq error>"
assert_eq "defer" "$decision19b" "allow-checkpoint.sh must return 'defer' when the file_path itself is a symlink pointing outside checkpoints/"

# Sanity: a genuine, non-symlinked nested file in the same directory is
# still allowed - the symlink defence above must not have become
# overbroad and started deferring everything under checkpoints/.
mkdir -p "$home19/.claude/squirrel/checkpoints/real-subdir"
stdin19c=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/real-subdir/a.md"}}' "$home19")
out19c=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19c")
decision19c=$(printf '%s' "$out19c" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19c="<jq error>"
assert_eq "allow" "$decision19c" "a genuine non-symlinked nested checkpoint path must still be allowed alongside the symlink fixtures in the same directory"

# ==========================================================================
# 20. allow-checkpoint.sh - tool_name other than Write/Edit: "defer".
# ==========================================================================
home20=$(new_home)
stdin20=$(printf '{"tool_name":"Bash","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/x.md"}}' "$home20")
out20=$(capture_stdout "$allow_checkpoint_script" "$home20" "$stdin20")
decision20=$(printf '%s' "$out20" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision20="<jq error>"
assert_eq "defer" "$decision20" "allow-checkpoint.sh must return 'defer' for tool_name 'Bash' even when file_path is a legitimate checkpoint path"

# ==========================================================================
# 21. allow-checkpoint.sh - output is valid JSON in every case above.
# ==========================================================================
for pair in "14:$out14" "15:$out15" "16:$out16" "17:$out17" "19a:$out19a" "19b:$out19b" "19c:$out19c" "20:$out20"; do
  label=${pair%%:*}
  content=${pair#*:}
  if printf '%s' "$content" | jq empty >/dev/null 2>&1; then
    scenario21_valid=yes
  else
    scenario21_valid=no
  fi
  assert_eq "yes" "$scenario21_valid" "allow-checkpoint.sh scenario $label output must be valid, parseable JSON"
done

# ==========================================================================
# 22. Cross-cutting: all three scripts exit 0 with HOME pointed at a
#     freshly created, completely empty directory (the fresh-install
#     path for each).
# ==========================================================================
home22=$(new_home)

exit22_load=$(capture_exit "$load_profile_script" "$home22" '{"session_id":"s","cwd":"/tmp/x"}')
assert_eq "0" "$exit22_load" "load-profile.sh must exit 0 with an empty HOME directory"

exit22_off=$(capture_exit "$check_off_flag_script" "$home22" '{"session_id":"s"}')
assert_eq "0" "$exit22_off" "check-off-flag.sh must exit 0 with an empty HOME directory"

exit22_allow=$(capture_exit "$allow_checkpoint_script" "$home22" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.md"}}')
assert_eq "0" "$exit22_allow" "allow-checkpoint.sh must exit 0 with an empty HOME directory"

# ==========================================================================
# 23. load-profile.sh - json_escape (no-jq fallback) must escape EVERY
#     C0 control byte, not just tab/newline/trailing-CR. Reproduces the
#     reviewer's exact repro for MAJOR #1: bell (0x07), ESC (0x1b), and
#     vertical tab (0x0b) in profile.md, with jq removed from PATH.
#     Before the fix, `jq empty` on this exact output failed with
#     "control characters ... must be escaped".
# ==========================================================================
home23=$(new_home)
mkdir -p "$home23/.claude/squirrel"
bell23=$(printf '\007')
esc23=$(printf '\033')
vtab23=$(printf '\013')
printf '# squirrel-mode profile\nBEFORE_BELL%sAFTER_BELL BEFORE_ESC%sAFTER_ESC BEFORE_VTAB%sAFTER_VTAB\n' \
  "$bell23" "$esc23" "$vtab23" >"$home23/.claude/squirrel/profile.md"
stdin23=$(printf '{"cwd":"%s/project-ctl"}' "$home23")
nojq_path23=$(make_tool_path "jq")

exit23=$(capture_exit_with_path "$load_profile_script" "$home23" "$nojq_path23" "$stdin23")
assert_eq "0" "$exit23" "MAJOR #1: load-profile.sh must exit 0 with control bytes in profile.md and jq absent from PATH"

out23=$(capture_stdout_with_path "$load_profile_script" "$home23" "$nojq_path23" "$stdin23")
out23_valid=$(printf '%s' "$out23" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out23_valid" "MAJOR #1: with control bytes in profile.md and jq absent, stdout must still be valid JSON ('jq empty' must accept it)"

# The raw (no-jq) JSON text must contain the actual \u00XX escapes -
# proof the escaping route (not silent dropping) was taken.
assert_contains "$out23" '\u0007' "MAJOR #1: raw JSON output must contain the \\u0007 escape for the BEL byte"
assert_contains "$out23" '\u001b' "MAJOR #1: raw JSON output must contain the \\u001b escape for the ESC byte"
assert_contains "$out23" '\u000b' "MAJOR #1: raw JSON output must contain the \\u000b escape for the vertical-tab byte"

# Decoding that JSON (via jq, the ultimate consumer) must round-trip
# back to the EXACT original bytes - proof the escape is correct, not
# merely present.
ctx23=$(extract_ctx "$out23")
needle_bell23="BEFORE_BELL${bell23}AFTER_BELL"
needle_esc23="BEFORE_ESC${esc23}AFTER_ESC"
needle_vtab23="BEFORE_VTAB${vtab23}AFTER_VTAB"
assert_contains "$ctx23" "$needle_bell23" "MAJOR #1: decoded additionalContext must round-trip the original BEL (0x07) byte exactly"
assert_contains "$ctx23" "$needle_esc23" "MAJOR #1: decoded additionalContext must round-trip the original ESC (0x1b) byte exactly"
assert_contains "$ctx23" "$needle_vtab23" "MAJOR #1: decoded additionalContext must round-trip the original vertical-tab (0x0b) byte exactly"

# ==========================================================================
# 24. load-profile.sh - invalid UTF-8 in profile.md must NOT be
#     silently truncated under a non-C locale, with jq absent. MAJOR #2:
#     under LANG=pt_BR.UTF-8 (the locale actually configured on this
#     machine) with jq absent, BSD sed used to abort mid-pipeline on
#     the invalid byte, and because POSIX sh has no `pipefail`, the
#     script still exited 0 and still emitted valid JSON while quietly
#     dropping everything after the bad byte. Content placed AFTER the
#     invalid bytes must survive intact, and the output must be
#     byte-identical regardless of which locale is active.
# ==========================================================================
home24=$(new_home)
mkdir -p "$home24/.claude/squirrel"
n24=1
: >"$home24/.claude/squirrel/profile.md"
while [ "$n24" -le 19 ]; do
  printf 'field%02d: value\n' "$n24" >>"$home24/.claude/squirrel/profile.md"
  n24=$((n24 + 1))
done
printf '\377\376\200\201 TAIL_MARKER_SURVIVES_998877\n' >>"$home24/.claude/squirrel/profile.md"
stdin24=$(printf '{"cwd":"%s/project-utf8"}' "$home24")
nojq_path24=$(make_tool_path "jq")

exit24_ptbr=$(printf '%s' "$stdin24" | LANG=pt_BR.UTF-8 LC_ALL='' HOME="$home24" PATH="$nojq_path24" "$load_profile_script" >/dev/null 2>&1; printf '%s' "$?")
assert_eq "0" "$exit24_ptbr" "MAJOR #2: load-profile.sh must exit 0 under LANG=pt_BR.UTF-8 with invalid UTF-8 in profile.md and jq absent"

out24_ptbr=$(printf '%s' "$stdin24" | LANG=pt_BR.UTF-8 LC_ALL='' HOME="$home24" PATH="$nojq_path24" "$load_profile_script" 2>/dev/null) || true
out24_ptbr_valid=$(printf '%s' "$out24_ptbr" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out24_ptbr_valid" "MAJOR #2: output under LANG=pt_BR.UTF-8 with invalid UTF-8 and jq absent must still be valid JSON"

# `grep` itself (not the script under test) must run under `LC_ALL=C`
# for this specific check: this test process's own ambient LANG is
# pt_BR.UTF-8 (per env), and BSD grep reading a PIPE (not a seekable
# file) containing these exact invalid UTF-8 bytes, under that locale,
# was observed to silently report zero matches for text on the same
# line immediately after the bad bytes - while grep on an identical
# FILE, or grep under `LC_ALL=C`, reports the match correctly every
# time. That is the same class of bug MAJOR #2 fixes in json_escape,
# here hitting this test's own verification tool instead of the script
# under test - so the fix is the same: force byte-oriented matching.
marker24_count=$(printf '%s' "$out24_ptbr" | LC_ALL=C grep -a -c 'TAIL_MARKER_SURVIVES_998877') || marker24_count=0
assert_eq "1" "$marker24_count" "MAJOR #2: content AFTER the invalid UTF-8 bytes must survive intact under LANG=pt_BR.UTF-8, not be silently truncated"

out24_c=$(printf '%s' "$stdin24" | LANG=C LC_ALL=C HOME="$home24" PATH="$nojq_path24" "$load_profile_script" 2>/dev/null) || true
assert_eq "$out24_c" "$out24_ptbr" "MAJOR #2: output must be byte-identical under LANG=C and LANG=pt_BR.UTF-8 - the locale must not change how bytes are interpreted"

# ==========================================================================
# 25. allow-checkpoint.sh - the SAME symlink fixtures as scenario 19,
#     re-run with `realpath` AND `readlink` stripped from PATH. MAJOR
#     #3: the header comment claimed Layer 2 "degrades to no additional
#     check, falling back to the Layer-1 answer" when neither tool
#     exists - it did not; it fell back to "allow". This is the
#     PERMANENT assertion the reviewer asked for: scenario 19 alone only
#     proves the boundary holds when realpath/readlink happen to exist.
# ==========================================================================
home25=$(new_home)
mkdir -p "$home25/.claude/squirrel/checkpoints" "$home25/outside-secret"
ln -s "$home25/outside-secret" "$home25/.claude/squirrel/checkpoints/escape-dir"
touch "$home25/outside-secret/secret.md"
ln -s "$home25/outside-secret/secret.md" "$home25/.claude/squirrel/checkpoints/escape-file"
mkdir -p "$home25/.claude/squirrel/checkpoints/real-subdir"
strip_path25=$(make_tool_path "realpath readlink")

stdin25a=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/escape-dir/evil.md"}}' "$home25")
out25a=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25a")
decision25a=$(printf '%s' "$out25a" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25a="<jq error>"
assert_eq "defer" "$decision25a" "MAJOR #3: with realpath AND readlink stripped from PATH, a symlinked intermediate directory inside checkpoints/ must still defer"

stdin25b=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/escape-file"}}' "$home25")
out25b=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25b")
decision25b=$(printf '%s' "$out25b" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25b="<jq error>"
assert_eq "defer" "$decision25b" "MAJOR #3: with realpath AND readlink stripped from PATH, a symlinked leaf file_path inside checkpoints/ must still defer"

stdin25c=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/real-subdir/a.md"}}' "$home25")
out25c=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25c")
decision25c=$(printf '%s' "$out25c" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25c="<jq error>"
assert_eq "allow" "$decision25c" "sanity (MAJOR #3): a genuine non-symlinked nested checkpoint path must still be allowed with realpath/readlink stripped - the fix must not become overbroad"

exit25=$(capture_exit_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25a")
assert_eq "0" "$exit25" "allow-checkpoint.sh must exit 0 even with realpath/readlink stripped from PATH"

# ==========================================================================
# 26. load-profile.sh - tech-lead ruling: an UNDER-cap profile (well
#     under 100 lines / 4 KB) must be injected in full, with no
#     truncation notice.
# ==========================================================================
home26=$(new_home)
mkdir -p "$home26/.claude/squirrel"
marker26="UNDER_CAP_MARKER_554433"
printf '# squirrel-mode profile\nlanguage: en\n%s\n' "$marker26" >"$home26/.claude/squirrel/profile.md"
stdin26=$(printf '{"cwd":"%s/project-cap-under"}' "$home26")

exit26=$(capture_exit "$load_profile_script" "$home26" "$stdin26")
assert_eq "0" "$exit26" "tech-lead cap: load-profile.sh must exit 0 for an under-cap profile"

out26=$(capture_stdout "$load_profile_script" "$home26" "$stdin26")
ctx26=$(extract_ctx "$out26")
assert_contains "$ctx26" "$marker26" "tech-lead cap: an under-cap profile's content must be injected in full"
assert_not_contains "$ctx26" "truncated" "tech-lead cap: an under-cap profile must NOT carry a truncation notice"

# ==========================================================================
# 27. load-profile.sh - tech-lead ruling: an OVER-cap profile by LINE
#     COUNT (150 lines, cap is 100) must be truncated at the line cap,
#     with a one-line notice, and the output must still parse as valid
#     JSON.
# ==========================================================================
home27=$(new_home)
mkdir -p "$home27/.claude/squirrel"
n27=1
: >"$home27/.claude/squirrel/profile.md"
while [ "$n27" -le 150 ]; do
  printf 'line%03d: marker\n' "$n27" >>"$home27/.claude/squirrel/profile.md"
  n27=$((n27 + 1))
done
stdin27=$(printf '{"cwd":"%s/project-cap-over-lines"}' "$home27")

exit27=$(capture_exit "$load_profile_script" "$home27" "$stdin27")
assert_eq "0" "$exit27" "tech-lead cap: load-profile.sh must exit 0 for an over-cap (150-line) profile"

out27=$(capture_stdout "$load_profile_script" "$home27" "$stdin27")
out27_valid=$(printf '%s' "$out27" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out27_valid" "tech-lead cap: output for an over-cap (150-line) profile must still be valid JSON"

ctx27=$(extract_ctx "$out27")
assert_contains "$ctx27" "line050: marker" "tech-lead cap: content within the 100-line cap must survive"
assert_not_contains "$ctx27" "line149: marker" "tech-lead cap: content past the 100-line cap must be dropped, not injected"
assert_contains "$ctx27" "truncated" "tech-lead cap: a one-line truncation notice must be present when the line cap is exceeded"

# ==========================================================================
# 28. load-profile.sh - tech-lead ruling: an OVER-cap profile by BYTE
#     COUNT (one line over 5 KB, well under 100 lines) must be truncated
#     at the byte cap, with a one-line notice, and the output must still
#     parse as valid JSON.
# ==========================================================================
home28=$(new_home)
mkdir -p "$home28/.claude/squirrel"
long28=$(awk 'BEGIN { s = ""; for (i = 0; i < 5000; i++) { s = s "X" }; print s }')
printf '%s TAIL_AFTER_BYTE_CAP_112233\n' "$long28" >"$home28/.claude/squirrel/profile.md"
stdin28=$(printf '{"cwd":"%s/project-cap-over-bytes"}' "$home28")

exit28=$(capture_exit "$load_profile_script" "$home28" "$stdin28")
assert_eq "0" "$exit28" "tech-lead cap: load-profile.sh must exit 0 for an over-cap (>4KB single line) profile"

out28=$(capture_stdout "$load_profile_script" "$home28" "$stdin28")
out28_valid=$(printf '%s' "$out28" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out28_valid" "tech-lead cap: output for a >4KB-single-line profile must still be valid JSON"

ctx28=$(extract_ctx "$out28")
assert_not_contains "$ctx28" "TAIL_AFTER_BYTE_CAP_112233" "tech-lead cap: content past the 4KB byte cap must be dropped, not injected"
assert_contains "$ctx28" "truncated" "tech-lead cap: a one-line truncation notice must be present when the byte cap is exceeded"

# ==========================================================================
# 29. allow-checkpoint.sh - cycle-3 BLOCKER fix: checkpoints_dir ITSELF
#     is a symlink pointing outside $HOME entirely - the tech lead's
#     exact repro (`ln -s $HOME/outside-secret
#     $HOME/.claude/squirrel/checkpoints`). Must defer, with
#     realpath/readlink present.
# ==========================================================================
home29=$(new_home)
mkdir -p "$home29/.claude/squirrel" "$home29/outside-secret-29"
ln -s "$home29/outside-secret-29" "$home29/.claude/squirrel/checkpoints"
stdin29=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/evil.md"}}' "$home29")

out29=$(capture_stdout "$allow_checkpoint_script" "$home29" "$stdin29")
decision29=$(printf '%s' "$out29" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision29="<jq error>"
assert_eq "defer" "$decision29" "BLOCKER fix: a symlink AT checkpoints_dir itself (not merely below it) must defer, not allow, with realpath/readlink present"

exit29=$(capture_exit "$allow_checkpoint_script" "$home29" "$stdin29")
assert_eq "0" "$exit29" "allow-checkpoint.sh must exit 0 even when checkpoints_dir itself is a symlink"

# ==========================================================================
# 30. allow-checkpoint.sh - same repro as scenario 29, with realpath AND
#     readlink stripped from PATH. THE permanent assertion: Layer 2
#     (the component walk, now testing checkpoints_dir itself) is what
#     must catch this unconditionally, not any realpath-based layer -
#     see the FAILURE PROOF at the bottom of this file that removes
#     exactly this check and confirms the mutant allows the escape.
# ==========================================================================
home30=$(new_home)
mkdir -p "$home30/.claude/squirrel" "$home30/outside-secret-30"
ln -s "$home30/outside-secret-30" "$home30/.claude/squirrel/checkpoints"
stdin30=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/evil.md"}}' "$home30")
strip_path30=$(make_tool_path "realpath readlink")

out30=$(capture_stdout_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30")
decision30=$(printf '%s' "$out30" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision30="<jq error>"
assert_eq "defer" "$decision30" "BLOCKER fix: a symlink AT checkpoints_dir itself must still defer with realpath AND readlink stripped from PATH"

exit30=$(capture_exit_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30")
assert_eq "0" "$exit30" "allow-checkpoint.sh must exit 0 for the symlinked-checkpoints_dir case even with realpath/readlink stripped"

# ==========================================================================
# 31. allow-checkpoint.sh - REGRESSION GUARD for the tech-lead's ruling:
#     $HOME/.claude ITSELF is a symlink (the chezmoi/stow/yadm
#     dotfile-manager pattern - ordinary user configuration, not an
#     attack, and explicitly OUT OF SCOPE for this hook's symlink
#     defence). A genuine checkpoint write beneath it must still be
#     "allow", with realpath/readlink present.
# ==========================================================================
home31=$(new_home)
real_claude31="$home31/real-dotfiles-claude-31"
mkdir -p "$real_claude31/squirrel/checkpoints"
ln -s "$real_claude31" "$home31/.claude"
stdin31=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/myproj.md"}}' "$home31")

out31=$(capture_stdout "$allow_checkpoint_script" "$home31" "$stdin31")
decision31=$(printf '%s' "$out31" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision31="<jq error>"
assert_eq "allow" "$decision31" "REGRESSION GUARD (tech-lead ruling): a legitimately symlinked \$HOME/.claude (dotfile-manager pattern) must still ALLOW a genuine checkpoint write beneath it, with realpath/readlink present"

exit31=$(capture_exit "$allow_checkpoint_script" "$home31" "$stdin31")
assert_eq "0" "$exit31" "allow-checkpoint.sh must exit 0 for a legitimately symlinked \$HOME/.claude"

# ==========================================================================
# 32. allow-checkpoint.sh - same regression guard as scenario 31, with
#     realpath AND readlink stripped from PATH: the ruling must hold
#     regardless of which tools happen to be installed, not as a
#     side-effect of a realpath-based layer that cycle 3 removed.
# ==========================================================================
home32=$(new_home)
real_claude32="$home32/real-dotfiles-claude-32"
mkdir -p "$real_claude32/squirrel/checkpoints"
ln -s "$real_claude32" "$home32/.claude"
stdin32=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/myproj.md"}}' "$home32")
strip_path32=$(make_tool_path "realpath readlink")

out32=$(capture_stdout_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32")
decision32=$(printf '%s' "$out32" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision32="<jq error>"
assert_eq "allow" "$decision32" "REGRESSION GUARD: a legitimately symlinked \$HOME/.claude must still ALLOW a genuine checkpoint write with realpath AND readlink stripped from PATH too"

exit32=$(capture_exit_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32")
assert_eq "0" "$exit32" "allow-checkpoint.sh must exit 0 for a legitimately symlinked \$HOME/.claude with realpath/readlink stripped"

# ==========================================================================
# 33. allow-checkpoint.sh - cycle-3 MAJOR fix: a file_path far past
#     MAX_FILE_PATH_LEN (4096 bytes) - 3000 "/a" segments, ~6004 bytes,
#     the exact size the tech lead asked to be measured and reported on
#     - must be rejected FAST (the length cap firing before any
#     per-segment work), not after paying the quadratic cost the
#     pre-fix script paid unconditionally (measured on this machine,
#     pre-fix: ~6.1s at this exact size). Uses whole-second `date +%s`
#     timestamps rather than `%N` sub-second ones, since `%N` is a GNU
#     date extension the reference BSD `date` on some contributors'
#     machines does not support - whole-second resolution is coarser
#     but adequate for a multi-second-vs-milliseconds distinction and
#     never depends on that extension being present.
# ==========================================================================
home33=$(new_home)
seg33=""
n33=0
while [ "$n33" -lt 3000 ]; do
  seg33="${seg33}/a"
  n33=$((n33 + 1))
done
long_path33="/tmp/unrelated-to-checkpoints$seg33"
stdin33=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$long_path33")

t0_33=$(date +%s)
out33=$(capture_stdout "$allow_checkpoint_script" "$home33" "$stdin33")
t1_33=$(date +%s)
delta33=$((t1_33 - t0_33))

decision33=$(printf '%s' "$out33" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision33="<jq error>"
assert_eq "defer" "$decision33" "MAJOR fix: an over-MAX_FILE_PATH_LEN file_path must defer (it is unrelated to checkpoints/ too, but must never even reach normalize_path to find that out)"

if [ "$delta33" -le 2 ]; then
  fast33=yes
else
  fast33=no
fi
assert_eq "yes" "$fast33" "MAJOR fix: a 3000-segment (~6KB) file_path must be rejected in a couple of seconds or less by the length cap (took ${delta33}s), not the multi-second quadratic blowup the pre-fix script paid unconditionally on every Write/Edit call"

exit33=$(capture_exit "$allow_checkpoint_script" "$home33" "$stdin33")
assert_eq "0" "$exit33" "allow-checkpoint.sh must exit 0 for an over-cap file_path"

# ==========================================================================
# 34. load-profile.sh - cycle-3 MINOR fix: the byte cap lands EXACTLY
#     inside a multi-byte UTF-8 character (a 3-byte euro sign, split so
#     `cut -b "1-4096"` keeps its first two bytes and drops the third).
#     Run through the no-jq (awk) emission path specifically - see
#     scenarios 23/24 for why: jq's own encoder can paper over an
#     invalid byte sequence on its way out, which would test jq's
#     leniency instead of THIS fix. Proof is byte-level, not merely
#     "still valid per jq empty" (the pre-fix version already passed
#     that, per the MINOR's own write-up): the euro sign's lead byte
#     (0xE2 / decimal 226) must not appear anywhere in raw output,
#     complete or dangling, once the incomplete tail is dropped.
# ==========================================================================
home34=$(new_home)
mkdir -p "$home34/.claude/squirrel"
head_marker34="HEAD_MARKER_BEFORE_CUT_778899"
filler_len34=$((4094 - ${#head_marker34}))
filler34=$(awk -v n="$filler_len34" 'BEGIN { s = ""; for (i = 0; i < n; i++) { s = s "X" }; print s }')
printf '%s%s\342\202\254TAIL_AFTER_UTF8_CUT_665544\n' "$head_marker34" "$filler34" >"$home34/.claude/squirrel/profile.md"
stdin34=$(printf '{"cwd":"%s/project-utf8-cut"}' "$home34")
nojq_path34=$(make_tool_path "jq")

exit34=$(capture_exit_with_path "$load_profile_script" "$home34" "$nojq_path34" "$stdin34")
assert_eq "0" "$exit34" "MINOR fix: load-profile.sh must exit 0 when the byte cap lands mid-character, with jq absent"

out34=$(capture_stdout_with_path "$load_profile_script" "$home34" "$nojq_path34" "$stdin34")
out34_valid=$(printf '%s' "$out34" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out34_valid" "MINOR fix: output must still be valid JSON when the byte cap lands mid-character, with jq absent"

ctx34=$(extract_ctx "$out34")
assert_contains "$ctx34" "$head_marker34" "MINOR fix: content before the byte-cap boundary must survive"
assert_not_contains "$ctx34" "TAIL_AFTER_UTF8_CUT_665544" "MINOR fix: content past the byte cap must still be dropped"
assert_contains "$ctx34" "truncated" "MINOR fix: the truncation notice must still be present"

e2_count34=$(printf '%s' "$out34" | LC_ALL=C od -An -v -tu1 | tr -s ' \n' ' ' | tr ' ' '\n' | awk '$1 == 226 { c++ } END { print c + 0 }')
assert_eq "0" "$e2_count34" "MINOR fix: cap_profile_body must not leave the euro sign's lead byte (0xE2) dangling, complete, or otherwise present in raw output once the byte cap lands mid-character"

# ==========================================================================
# 35. allow-checkpoint.sh - "Do not regress" list, closing a gap two
#     earlier review cycles left without dedicated coverage: shell
#     metacharacters, `$(...)`, backticks, a literal glob, a
#     percent-encoded traversal-looking segment, a raw control byte,
#     and a JSON-escaped embedded newline, all inside an otherwise
#     legitimate checkpoints/ path. None of these are directory-escape
#     attempts (no ".." anywhere) - the property under test is that
#     this hook treats file_path as OPAQUE TEXT throughout (no eval, no
#     command substitution, no glob expansion, no percent-decoding), so
#     each is benign and lexically contained, and must "allow".
#
#     The `$(...)` and backtick cases carry the sharpest proof
#     available: a marker file path embedded INSIDE the attempted
#     injection. If this script (or - as important to rule out - THIS
#     TEST FILE's own construction of the fixture below) ever executed
#     that text instead of treating it as an inert filename, the marker
#     would exist on disk afterward. It must not. The literal `$(` and
#     backtick sequences below are single-quoted at every point they
#     are built, specifically so THIS test file's own shell never
#     executes them either - see the inline comments at each
#     construction site.
# ==========================================================================
home35=$(new_home)
mkdir -p "$home35/.claude/squirrel/checkpoints"
marker35="$home35/PWNED_MARKER_35"
rm -f "$marker35"

# Built from single-quoted literal segments around the one
# double-quoted variable expansion, so the "$(" / ")" characters are
# never live shell syntax at any point - concatenation of separately-
# quoted segments does not re-scan the joined result for new syntax,
# per POSIX quote removal rules.
# shellcheck disable=SC2016 # deliberate: the single-quoted segments
# below must NOT expand - that is the entire point of this fixture.
fp_dollar35="$home35/.claude/squirrel/checkpoints/"'$(touch '"$marker35"')'".md"
stdin_dollar35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp_dollar35")
out_dollar35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_dollar35")
decision_dollar35=$(printf '%s' "$out_dollar35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_dollar35="<jq error>"
assert_eq "allow" "$decision_dollar35" "a literal \$(...) sequence inside an otherwise-legitimate checkpoint filename must be treated as inert text and allowed"
assert_file_absent "$marker35" "a literal \$(command) inside file_path must NEVER be executed - the marker file must not exist"

# Same technique, backtick form - same single-quoting discipline so
# the backticks are never live syntax either.
# shellcheck disable=SC2016
fp_backtick35="$home35/.claude/squirrel/checkpoints/"'`touch '"$marker35"'`'".md"
stdin_backtick35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp_backtick35")
out_backtick35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_backtick35")
decision_backtick35=$(printf '%s' "$out_backtick35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_backtick35="<jq error>"
assert_eq "allow" "$decision_backtick35" "a literal backtick-quoted command inside an otherwise-legitimate checkpoint filename must be treated as inert text and allowed"
assert_file_absent "$marker35" "a literal \`command\` inside file_path must NEVER be executed - the marker file must not exist"

# Literal glob: a bare "*" as a filename character, sitting alongside
# real decoy files it must NOT expand to match.
mkdir -p "$home35/.claude/squirrel/checkpoints/glob-dir-35"
touch "$home35/.claude/squirrel/checkpoints/glob-dir-35/decoy1.md" "$home35/.claude/squirrel/checkpoints/glob-dir-35/decoy2.md"
stdin_glob35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/glob-dir-35/*.md"}}' "$home35")
out_glob35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_glob35")
decision_glob35=$(printf '%s' "$out_glob35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_glob35="<jq error>"
assert_eq "allow" "$decision_glob35" "a literal '*' in file_path must be treated as an ordinary filename character (never glob-expanded) and allowed"

# Percent-encoded traversal-looking segment: nothing in this script (or
# the filesystem it eventually writes to) URL-decodes a path, so
# "%2e%2e" is just a literal, benign directory-name-shaped string, not
# a disguised "..".
stdin_pct35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/%%2e%%2e/%%2e%%2e/etc/passwd"}}' "$home35")
out_pct35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_pct35")
decision_pct35=$(printf '%s' "$out_pct35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_pct35="<jq error>"
assert_eq "allow" "$decision_pct35" "a percent-encoded '%2e%2e' segment must NOT be decoded into '..' anywhere in this pipeline, so it stays a literal, contained subdirectory name"

# Raw control byte (0x01) inside an otherwise-legitimate filename.
ctrl35=$(printf '\001')
stdin_ctrl35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/evil%sname.md"}}' "$home35" "$ctrl35")
out_ctrl35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_ctrl35")
decision_ctrl35=$(printf '%s' "$out_ctrl35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_ctrl35="<jq error>"
assert_eq "allow" "$decision_ctrl35" "a raw control byte (0x01) inside an otherwise-legitimate checkpoint filename must not crash normalize_path/component_walk_has_symlink and must still allow"

exit_ctrl35=$(capture_exit "$allow_checkpoint_script" "$home35" "$stdin_ctrl35")
assert_eq "0" "$exit_ctrl35" "allow-checkpoint.sh must exit 0 for a file_path containing a raw control byte"

# JSON-escaped embedded newline (the realistic form: valid JSON with a
# properly-escaped \n, not a raw unescaped newline byte, which is not
# even legal JSON) inside an otherwise-legitimate filename.
stdin_nl35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/evil\\nname.md"}}' "$home35")
out_nl35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_nl35")
decision_nl35=$(printf '%s' "$out_nl35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_nl35="<jq error>"
assert_eq "allow" "$decision_nl35" "a JSON-escaped embedded newline inside an otherwise-legitimate checkpoint filename must still allow"

exit_nl35=$(capture_exit "$allow_checkpoint_script" "$home35" "$stdin_nl35")
assert_eq "0" "$exit_nl35" "allow-checkpoint.sh must exit 0 for a file_path containing a JSON-escaped embedded newline"

# ==========================================================================
# 36. allow-checkpoint.sh - "Do not regress" list: $HOME unset, empty,
#     "/", and carrying a trailing slash. Unset/empty must defer (no
#     directory to be "inside" of); "/" and a trailing slash must still
#     allow a genuinely nested, legitimate checkpoint write - scenario
#     22 already covers HOME pointed at a freshly created EMPTY
#     DIRECTORY, which is a different condition from HOME being an
#     empty STRING, unset entirely, "/", or trailing-slash-bearing.
# ==========================================================================
stdin36=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/somewhere-unrelated-36/x.md"}}')

out36_unset=$(printf '%s' "$stdin36" | env -u HOME "$allow_checkpoint_script" 2>/dev/null) || true
decision36_unset=$(printf '%s' "$out36_unset" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_unset="<jq error>"
assert_eq "defer" "$decision36_unset" "\$HOME entirely unset must defer, never allow"

out36_empty=$(printf '%s' "$stdin36" | HOME="" "$allow_checkpoint_script" 2>/dev/null) || true
decision36_empty=$(printf '%s' "$out36_empty" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_empty="<jq error>"
assert_eq "defer" "$decision36_empty" "\$HOME set to an empty string must defer, never allow"

stdin36_root=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/.claude/squirrel/checkpoints/proj36.md"}}')
out36_root=$(printf '%s' "$stdin36_root" | HOME="/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36_root=$(printf '%s' "$out36_root" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_root="<jq error>"
assert_eq "allow" "$decision36_root" "\$HOME=/ (root) must still allow a genuine, nested checkpoint write under it"

home36_trail=$(new_home)
mkdir -p "$home36_trail/.claude/squirrel/checkpoints"
stdin36_trail=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/proj36.md"}}' "$home36_trail")
out36_trail=$(printf '%s' "$stdin36_trail" | HOME="$home36_trail/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36_trail=$(printf '%s' "$out36_trail" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_trail="<jq error>"
assert_eq "allow" "$decision36_trail" "\$HOME carrying a trailing slash must still allow a genuine, nested checkpoint write under it"

# ==========================================================================
# 37. load-profile.sh - "Do not regress" list, closing a second gap
#     with zero prior automated coverage: prune_stale_off_flags() must
#     stay CONFINED to off/ (never touch a sibling file merely because
#     it is also old) and must NEVER be able to fail the hook (a
#     permission-denied file inside off/ must not propagate a non-zero
#     exit). "Stale" is >7 days per ADR-0005; a file exactly at the
#     boundary is deliberately avoided here in favour of clearly-fresh
#     (today) and clearly-stale (well past 7 days) fixtures, since the
#     scenario is about CONFINEMENT and FAILURE-SAFETY, not the exact
#     7-day boundary itself.
# ==========================================================================
home37=$(new_home)
mkdir -p "$home37/.claude/squirrel/off" "$home37/.claude/squirrel/checkpoints"
touch "$home37/.claude/squirrel/off/fresh-session-37"
touch "$home37/.claude/squirrel/decoy-outside-off-37.txt"
touch "$home37/.claude/squirrel/checkpoints/decoy-in-checkpoints-37.md"
stale_flag37="$home37/.claude/squirrel/off/stale-session-37"
touch "$stale_flag37"
# Back-date the stale fixture past the 7-day cutoff. `touch -t` is
# POSIX; the two-digit-year form used here is deliberately far enough
# in the past (year 2020) that it stays stale for the lifetime of this
# repository without needing runtime date arithmetic in the test
# itself.
touch -t 202001010000 "$stale_flag37" 2>/dev/null || touch -d "30 days ago" "$stale_flag37" 2>/dev/null || true

stdin37=$(printf '{"cwd":"%s/project-prune"}' "$home37")
exit37=$(capture_exit "$load_profile_script" "$home37" "$stdin37")
assert_eq "0" "$exit37" "load-profile.sh must exit 0 while pruning stale off-flags"

# Actually run it (capture_exit already did, but re-run for a clean
# post-state check, since capture_exit/capture_stdout are pure
# functions of filesystem state and re-running changes nothing new).
capture_stdout "$load_profile_script" "$home37" "$stdin37" >/dev/null

assert_file_absent "$stale_flag37" "a stale (>7-day-old) off/ flag must actually be pruned"
assert_file_exists "$home37/.claude/squirrel/off/fresh-session-37" "a fresh off/ flag must survive pruning"
assert_file_exists "$home37/.claude/squirrel/decoy-outside-off-37.txt" "pruning must NEVER touch a file outside off/, however old-looking its neighbours are"
assert_file_exists "$home37/.claude/squirrel/checkpoints/decoy-in-checkpoints-37.md" "pruning must NEVER touch checkpoints/, even though it is a sibling of off/ under the same squirrel/ directory"

# Failure-safety: a permission-denied off/ directory must not fail the
# hook. Skipped (treated as a pass, not a false failure) on a machine
# where chmod cannot actually remove permissions for the invoking user
# (e.g. running as root, where every path is still readable/writable
# regardless of mode bits) - the assertion below only means something
# where chmod's effect is real.
home37b=$(new_home)
mkdir -p "$home37b/.claude/squirrel/off"
locked_flag37b="$home37b/.claude/squirrel/off/locked-37b"
touch -t 202001010000 "$locked_flag37b" 2>/dev/null || touch -d "30 days ago" "$locked_flag37b" 2>/dev/null || true
chmod 000 "$locked_flag37b" 2>/dev/null || true
chmod 500 "$home37b/.claude/squirrel/off" 2>/dev/null || true
stdin37b=$(printf '{"cwd":"%s/project-prune-locked"}' "$home37b")
exit37b=$(capture_exit "$load_profile_script" "$home37b" "$stdin37b")
chmod 755 "$home37b/.claude/squirrel/off" 2>/dev/null || true
chmod 700 "$locked_flag37b" 2>/dev/null || true
assert_eq "0" "$exit37b" "load-profile.sh must exit 0 even when pruning cannot remove a permission-denied flag file"

# ==========================================================================
# FAILURE PROOFS - scenarios 2, 4, 5, 12, 16, 17, 23, 24, 25, 26, 27, 28,
# 29/30, 33, 34.
#
# Each block below deliberately reintroduces ONE specific, named bug
# into a throwaway scratch COPY of the real script (the real, shipped
# script is never touched), then re-runs the exact same assertion the
# corresponding numbered scenario above uses, confirming the mutant's
# behaviour is genuinely different (i.e. the assertion would have
# FAILED had this bug shipped). This is the same mutation-testing
# technique tests/test_build.sh uses for its own malformed-input
# scenarios (see make_build_scratch there).
# ==========================================================================

# --- Failure proof for scenario 2: load-profile.sh must survive a
# missing profile file. Reintroduces exactly the bug
# .build-checkpoint.md's "Known gap" note describes: a version that (a)
# always attempts to read profile.md regardless of whether it exists,
# with no `|| fallback` on the read, and (b) has no outer safety net to
# catch that failure - i.e. a script that "exits non-zero on missing
# input files".
# ==========================================================================
fp2_script=$(make_script_scratch "$load_profile_script")

# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: every argument here is the LITERAL source text of a real line
# in load-profile.sh to search for or substitute, never an expression to
# expand in THIS shell.
fp2_cond_line=$(line_of "$fp2_script" '  if [ -n "$home_dir" ] && [ -f "$profile_file" ]; then')
[ -n "$fp2_cond_line" ] || fp2_cond_line=0
# shellcheck disable=SC2016
replace_line "$fp2_script" "$fp2_cond_line" '  if [ -n "$home_dir" ]; then'

# shellcheck disable=SC2016
fp2_cat_line=$(line_of "$fp2_script" '    profile_body=$(cat "$profile_file" 2>/dev/null) || profile_body=""')
[ -n "$fp2_cat_line" ] || fp2_cat_line=0
# shellcheck disable=SC2016
replace_line "$fp2_script" "$fp2_cat_line" '    profile_body=$(cat "$profile_file")'

# shellcheck disable=SC2016
fp2_ifnet_start=$(line_of "$fp2_script" 'if context=$(build_context 2>/dev/null); then')
[ -n "$fp2_ifnet_start" ] || fp2_ifnet_start=0
fp2_ifnet_end=$(line_of_after "$fp2_script" "$fp2_ifnet_start" "fi")
[ -n "$fp2_ifnet_end" ] || fp2_ifnet_end=0
# shellcheck disable=SC2016
replace_block "$fp2_script" "$fp2_ifnet_start" "$fp2_ifnet_end" 'context=$(build_context)'

fp2_home=$(new_home)
fp2_stdin=$(printf '{"cwd":"%s/project-a"}' "$fp2_home")
fp2_exit=$(capture_exit "$fp2_script" "$fp2_home" "$fp2_stdin")
assert_eq "1" "$fp2_exit" "FAILURE PROOF (scenario 2): a load-profile.sh mutant with the '-f profile.md' guard and its cat fallback removed, and the outer safety net disarmed, must exit non-zero on a fresh install - proving scenario 2's 'exit 0' assertion is not vacuous"

# --- Failure proof for scenario 4: load-profile.sh must NOT leak the
# checkpoint file's own body text. Reintroduces exactly the forbidden
# behaviour PLAN.md and ADR-0002 call out: dumping the checkpoint's
# contents into the injected context instead of just the one-line
# notice.
# ==========================================================================
fp4_script=$(make_script_scratch "$load_profile_script")

# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: literal source text/replacement for load-profile.sh, not an
# expression to expand here.
fp4_start=$(line_of "$fp4_script" '  if [ -n "$home_dir" ] && [ -f "$checkpoint_file" ]; then')
[ -n "$fp4_start" ] || fp4_start=0
fp4_end=$(line_of_after "$fp4_script" "$fp4_start" '  fi')
[ -n "$fp4_end" ] || fp4_end=0
# shellcheck disable=SC2016
fp4_leaking_block='  if [ -n "$home_dir" ] && [ -f "$checkpoint_file" ]; then
    context="$context
Resume available - run /squirrel:pickup
$(cat "$checkpoint_file" 2>/dev/null)"
  fi'
replace_block "$fp4_script" "$fp4_start" "$fp4_end" "$fp4_leaking_block"

fp4_home=$(new_home)
mkdir -p "$fp4_home/.claude/squirrel"
cat >"$fp4_home/.claude/squirrel/profile.md" <<'EOF'
language: en
EOF
fp4_stdin=$(printf '{"cwd":"%s/project-b"}' "$fp4_home")
fp4_pre_ctx=$(extract_ctx "$(capture_stdout "$fp4_script" "$fp4_home" "$fp4_stdin")")
fp4_checkpoint_path=$(extract_checkpoint_path_line "$fp4_pre_ctx")
mkdir -p "$(dirname "$fp4_checkpoint_path")"
fp4_marker="LEAK_PROOF_MARKER_445566"
printf '%s\n' "$fp4_marker" >"$fp4_checkpoint_path"

fp4_ctx=$(extract_ctx "$(capture_stdout "$fp4_script" "$fp4_home" "$fp4_stdin")")
if printf '%s' "$fp4_ctx" | grep -qF "$fp4_marker"; then
  fp4_leaks=yes
else
  fp4_leaks=no
fi
assert_eq "yes" "$fp4_leaks" "FAILURE PROOF (scenario 4): a load-profile.sh mutant that dumps the checkpoint file's own body must actually leak the marker text - proving scenario 4's assert_not_contains is not vacuous"

# --- Failure proof for scenario 5: collision resistance depends on the
# hash suffix. Reintroduces the literally-forbidden "bare basename"
# slug algorithm (PLAN.md / tech-lead Decision 1 explicitly reject it).
# ==========================================================================
fp5_script=$(make_script_scratch "$load_profile_script")
fp5_line=$(line_of "$fp5_script" "  printf '%s-%s' \"\$safe_base\" \"\$hash\"")
[ -n "$fp5_line" ] || fp5_line=0
replace_line "$fp5_script" "$fp5_line" "  printf '%s' \"\$safe_base\""

fp5_home=$(new_home)
fp5_stdin_a=$(printf '{"cwd":"%s/alice/myapp"}' "$fp5_home")
fp5_stdin_b=$(printf '{"cwd":"%s/bob/other/myapp"}' "$fp5_home")
fp5_path_a=$(extract_checkpoint_path_line "$(extract_ctx "$(capture_stdout "$fp5_script" "$fp5_home" "$fp5_stdin_a")")")
fp5_path_b=$(extract_checkpoint_path_line "$(extract_ctx "$(capture_stdout "$fp5_script" "$fp5_home" "$fp5_stdin_b")")")
assert_eq "$fp5_path_a" "$fp5_path_b" "FAILURE PROOF (scenario 5): a bare-basename slug mutant (no hash suffix) must COLLIDE for two different cwd values sharing a basename - proving scenario 5's inequality assertion is not vacuous"

# --- Failure proof for scenario 12: session_id traversal must actually
# be blocked BY the sanitiser. Reintroduces a sanitize_session_id that
# performs no validation at all.
# ==========================================================================
fp12_script=$(make_script_scratch "$check_off_flag_script")
# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: literal source text/replacement for check-off-flag.sh.
fp12_start=$(line_of "$fp12_script" 'sanitize_session_id() {')
[ -n "$fp12_start" ] || fp12_start=0
fp12_end=$(line_of_after "$fp12_script" "$fp12_start" '}')
[ -n "$fp12_end" ] || fp12_end=0
# shellcheck disable=SC2016
fp12_noop_body='sanitize_session_id() {
  raw=$1
  printf "%s" "$raw"
  return 0
}'
replace_block "$fp12_script" "$fp12_start" "$fp12_end" "$fp12_noop_body"

fp12_home=$(new_home)
mkdir -p "$fp12_home/.claude/squirrel/off"
touch "$fp12_home/.claude/squirrel/decoy-outside-off.txt"
fp12_stdin=$(printf '{"session_id":"../decoy-outside-off.txt"}')
fp12_out=$(capture_stdout "$fp12_script" "$fp12_home" "$fp12_stdin")
if [ -n "$fp12_out" ]; then
  fp12_leaks=yes
else
  fp12_leaks=no
fi
assert_eq "yes" "$fp12_leaks" "FAILURE PROOF (scenario 12): an unsanitized check-off-flag.sh mutant must incorrectly treat a traversal session_id pointing at a file outside off/ as 'flag present' - proving scenario 12's empty-output assertion is not vacuous"

# --- Failure proof for scenario 16: traversal must be blocked BY the
# lexical normalizer, not merely by luck. Reintroduces the literal
# "prefix string matching alone" bug the spec warns is a BLOCKER.
# ==========================================================================
fp16_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: literal source text/replacement for allow-checkpoint.sh.
fp16_start=$(line_of "$fp16_script" 'decide() {')
[ -n "$fp16_start" ] || fp16_start=0
fp16_end=$(line_of_after "$fp16_script" "$fp16_start" '}')
[ -n "$fp16_end" ] || fp16_end=0
# shellcheck disable=SC2016
fp16_naive_decide='decide() {
  input=$(cat)
  tool_name=$(extract_field "$input" "tool_name")
  file_path=$(extract_field "$input" "file_path")
  case "$tool_name" in
    Write | Edit) ;;
    *) printf "defer"; return 0 ;;
  esac
  home_dir="${HOME:-}"
  checkpoints_dir="$home_dir/.claude/squirrel/checkpoints"
  case "$file_path" in
    "$checkpoints_dir"/*) printf "allow" ;;
    *) printf "defer" ;;
  esac
  return 0
}'
replace_block "$fp16_script" "$fp16_start" "$fp16_end" "$fp16_naive_decide"

fp16_home=$(new_home)
fp16_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$fp16_home")
fp16_out=$(capture_stdout "$fp16_script" "$fp16_home" "$fp16_stdin")
fp16_decision=$(printf '%s' "$fp16_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp16_decision="<jq error>"
assert_eq "allow" "$fp16_decision" "FAILURE PROOF (scenario 16): a naive prefix-only mutant (no lexical '..' normalisation) must incorrectly ALLOW the traversal path - proving scenario 16's defer assertion is not vacuous"

# --- Failure proof for scenario 17: prefix-escape must be blocked BY
# the boundary-aware ("/" after the prefix) check, not by a bare
# substring/prefix match.
# ==========================================================================
fp17_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: literal source text/replacement for allow-checkpoint.sh.
fp17_start=$(line_of "$fp17_script" 'decide() {')
[ -n "$fp17_start" ] || fp17_start=0
fp17_end=$(line_of_after "$fp17_script" "$fp17_start" '}')
[ -n "$fp17_end" ] || fp17_end=0
# shellcheck disable=SC2016
fp17_naive_decide='decide() {
  input=$(cat)
  tool_name=$(extract_field "$input" "tool_name")
  file_path=$(extract_field "$input" "file_path")
  case "$tool_name" in
    Write | Edit) ;;
    *) printf "defer"; return 0 ;;
  esac
  home_dir="${HOME:-}"
  checkpoints_dir="$home_dir/.claude/squirrel/checkpoints"
  case "$file_path" in
    "$checkpoints_dir"*) printf "allow" ;;
    *) printf "defer" ;;
  esac
  return 0
}'
replace_block "$fp17_script" "$fp17_start" "$fp17_end" "$fp17_naive_decide"

fp17_home=$(new_home)
fp17_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints-evil/x"}}' "$fp17_home")
fp17_out=$(capture_stdout "$fp17_script" "$fp17_home" "$fp17_stdin")
fp17_decision=$(printf '%s' "$fp17_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp17_decision="<jq error>"
assert_eq "allow" "$fp17_decision" "FAILURE PROOF (scenario 17): a naive prefix mutant with no trailing-slash boundary check must incorrectly ALLOW 'checkpoints-evil' - proving scenario 17's defer assertion is not vacuous"

# --- Failure proof for scenario 25: the unconditional Layer 2
# component walk is what actually defeats the symlink once
# realpath/readlink are stripped from PATH, not merely Layer 3 which
# happened to still work in scenario 19 because those tools existed on
# THIS machine. Removing exactly Layer 2 (and leaving Layers 1 and 3
# intact) reproduces the pre-fix MAJOR #3 bug precisely.
# ==========================================================================
fp25_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal source
# text of allow-checkpoint.sh to search for, not an expression to expand
# in this shell.
fp25_start=$(line_of "$fp25_script" '  # Layer 2: unconditional POSIX component walk (see header) - the')
[ -n "$fp25_start" ] || fp25_start=0
fp25_end=$(line_of_after "$fp25_script" "$fp25_start" '  fi')
[ -n "$fp25_end" ] || fp25_end=0
replace_block "$fp25_script" "$fp25_start" "$fp25_end" ''

fp25_home=$(new_home)
mkdir -p "$fp25_home/.claude/squirrel/checkpoints" "$fp25_home/outside-secret"
ln -s "$fp25_home/outside-secret" "$fp25_home/.claude/squirrel/checkpoints/escape-dir"
fp25_strip_path=$(make_tool_path "realpath readlink")
fp25_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/escape-dir/evil.md"}}' "$fp25_home")
fp25_out=$(capture_stdout_with_path "$fp25_script" "$fp25_home" "$fp25_strip_path" "$fp25_stdin")
fp25_decision=$(printf '%s' "$fp25_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp25_decision="<jq error>"
assert_eq "allow" "$fp25_decision" "FAILURE PROOF (scenario 25): a mutant with the unconditional Layer-2 component walk removed must incorrectly ALLOW the symlink escape once realpath/readlink are also stripped from PATH - proving scenario 25's defer assertion is not vacuous, and reproducing the exact pre-fix MAJOR #3 bug"

# --- Failure proof for scenario 27: the profile size cap is what
# actually keeps an over-cap profile from being injected past the
# 100-line limit. Removing exactly the cap_profile_body call (leaving
# the function itself defined but unused) reproduces the pre-ruling
# behaviour: the full, uncapped profile injected verbatim.
# ==========================================================================
fp27_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp27_line=$(line_of "$fp27_script" '    profile_body=$(cap_profile_body "$profile_body")')
[ -n "$fp27_line" ] || fp27_line=0
replace_line "$fp27_script" "$fp27_line" ''

fp27_home=$(new_home)
mkdir -p "$fp27_home/.claude/squirrel"
n_fp27=1
: >"$fp27_home/.claude/squirrel/profile.md"
while [ "$n_fp27" -le 150 ]; do
  printf 'line%03d: marker\n' "$n_fp27" >>"$fp27_home/.claude/squirrel/profile.md"
  n_fp27=$((n_fp27 + 1))
done
fp27_stdin=$(printf '{"cwd":"%s/project-cap-fp"}' "$fp27_home")
fp27_out=$(capture_stdout "$fp27_script" "$fp27_home" "$fp27_stdin")
fp27_ctx=$(extract_ctx "$fp27_out")
if printf '%s' "$fp27_ctx" | grep -qF "line149: marker"; then
  fp27_uncapped=yes
else
  fp27_uncapped=no
fi
assert_eq "yes" "$fp27_uncapped" "FAILURE PROOF (scenario 27): a load-profile.sh mutant with the profile cap removed must inject content past line 100 (line149) in full - proving scenario 27's cap assertion is not vacuous"

# --- Failure proof for scenario 23: json_escape must escape EVERY C0
# control byte, not just tab/newline/CR. Removes exactly the generic
# `0 < b < 32` branch, reverting to the narrower special-cased set, so
# BEL (0x07) passes through raw and `jq empty` rejects the result.
# ==========================================================================
fp23_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal
# source text of load-profile.sh to search for, not an expression to
# expand in this shell.
fp23_line=$(line_of "$fp23_script" '        if (b > 0 && b < 32) { out = out sprintf("\\u%04x", b); continue }')
[ -n "$fp23_line" ] || fp23_line=0
replace_line "$fp23_script" "$fp23_line" ''

fp23_home=$(new_home)
mkdir -p "$fp23_home/.claude/squirrel"
fp23_bell=$(printf '\007')
printf '# squirrel-mode profile\nBEFORE_BELL%sAFTER_BELL\n' "$fp23_bell" >"$fp23_home/.claude/squirrel/profile.md"
fp23_stdin=$(printf '{"cwd":"%s/project-ctl-fp"}' "$fp23_home")
fp23_nojq_path=$(make_tool_path "jq")
fp23_out=$(capture_stdout_with_path "$fp23_script" "$fp23_home" "$fp23_nojq_path" "$fp23_stdin")
fp23_valid=$(printf '%s' "$fp23_out" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "no" "$fp23_valid" "FAILURE PROOF (scenario 23): a json_escape mutant with the generic C0-control-byte escape removed must produce output that 'jq empty' REJECTS for a raw BEL byte - proving scenario 23's 'must still be valid JSON' assertion is not vacuous"

# --- Failure proof for scenario 24: json_escape must run its byte scan
# under `LC_ALL=C`, not the ambient locale, specifically because the
# ORIGINAL bug (per this file's own header comment on json_escape) used
# `sed` under the ambient locale, which aborts mid-stream with "illegal
# byte sequence" on invalid UTF-8 under LANG=pt_BR.UTF-8 - and because
# POSIX sh has no pipefail, a pipeline ending in a command that still
# succeeds reports overall success while silently dropping everything
# from the bad byte onward. This mutant restores exactly that: a
# sed-based json_escape with no locale override at all.
# ==========================================================================
fp24_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp24_start=$(line_of "$fp24_script" 'json_escape() {')
[ -n "$fp24_start" ] || fp24_start=0
fp24_end=$(line_of_after "$fp24_script" "$fp24_start" '}')
[ -n "$fp24_end" ] || fp24_end=0
# Built via a QUOTED heredoc (not a single-quoted literal) specifically
# because the replacement body itself needs several embedded literal
# single quotes (around the sed/awk programs) - a quoted heredoc
# delimiter disables every form of shell expansion INSIDE it, so what
# comes out the other end is exactly these bytes, no escaping puzzle.
fp24_sed_body=$(cat <<'FP24_MUTANT_EOF'
json_escape() {
  str=$1
  printf '%s' "$str" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{ if (NR>1) printf "\\n"; printf "%s", $0 }'
}
FP24_MUTANT_EOF
)
replace_block "$fp24_script" "$fp24_start" "$fp24_end" "$fp24_sed_body"

fp24_home=$(new_home)
mkdir -p "$fp24_home/.claude/squirrel"
fp24_n=1
: >"$fp24_home/.claude/squirrel/profile.md"
while [ "$fp24_n" -le 2 ]; do
  printf 'field%02d: value\n' "$fp24_n" >>"$fp24_home/.claude/squirrel/profile.md"
  fp24_n=$((fp24_n + 1))
done
printf '\377\376\200\201 TAIL_MARKER_SURVIVES_998877\n' >>"$fp24_home/.claude/squirrel/profile.md"
fp24_stdin=$(printf '{"cwd":"%s/project-utf8-fp"}' "$fp24_home")
fp24_nojq_path=$(make_tool_path "jq")

fp24_out=$(printf '%s' "$fp24_stdin" | LANG=pt_BR.UTF-8 LC_ALL='' HOME="$fp24_home" PATH="$fp24_nojq_path" "$fp24_script" 2>/dev/null) || true
fp24_ctx=$(extract_ctx "$fp24_out")
fp24_marker_count=$(printf '%s' "$fp24_ctx" | LC_ALL=C grep -a -c 'TAIL_MARKER_SURVIVES_998877') || fp24_marker_count=0
if [ "$fp24_marker_count" -eq 0 ]; then
  fp24_dropped=yes
else
  fp24_dropped=no
fi
assert_eq "yes" "$fp24_dropped" "FAILURE PROOF (scenario 24): a sed-based, locale-unaware json_escape mutant must silently drop content after an invalid UTF-8 byte under LANG=pt_BR.UTF-8 - proving scenario 24's survival assertion is not vacuous"

# --- Failure proof for scenario 26: an under-cap profile must not be
# marked truncated. Forces `truncated=1` unconditionally regardless of
# whether either cap was actually exceeded.
# ==========================================================================
fp26_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp26_line=$(line_of "$fp26_script" '  truncated=0')
[ -n "$fp26_line" ] || fp26_line=0
replace_line "$fp26_script" "$fp26_line" '  truncated=1'

fp26_home=$(new_home)
mkdir -p "$fp26_home/.claude/squirrel"
fp26_marker="UNDER_CAP_MARKER_FP_112233"
printf '# squirrel-mode profile\nlanguage: en\n%s\n' "$fp26_marker" >"$fp26_home/.claude/squirrel/profile.md"
fp26_stdin=$(printf '{"cwd":"%s/project-cap-under-fp"}' "$fp26_home")
fp26_ctx=$(extract_ctx "$(capture_stdout "$fp26_script" "$fp26_home" "$fp26_stdin")")
if printf '%s' "$fp26_ctx" | grep -qF "truncated"; then
  fp26_falsely_truncated=yes
else
  fp26_falsely_truncated=no
fi
assert_eq "yes" "$fp26_falsely_truncated" "FAILURE PROOF (scenario 26): a cap_profile_body mutant that always sets truncated=1 must falsely report an under-cap profile as truncated - proving scenario 26's 'must NOT carry a truncation notice' assertion is not vacuous"

# --- Failure proof for scenario 28: the BYTE cap specifically (not
# just the line cap) is what truncates an over-cap-by-bytes profile.
# Removes exactly the byte-cap conditional's BODY (the `if` line has no
# single quotes in it, unlike the `byte_count=` assignment line right
# above it, so it anchors cleanly with no quoting gymnastics) - the
# `byte_count=` computation itself is left in place but unused, and the
# line cap is untouched, so a single line well over 4KB (and under 100
# lines) is never truncated at all.
# ==========================================================================
fp28_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp28_start=$(line_of "$fp28_script" '  if [ "$byte_count" -gt "$PROFILE_MAX_BYTES" ]; then')
[ -n "$fp28_start" ] || fp28_start=0
fp28_end=$(line_of_after "$fp28_script" "$fp28_start" '  fi')
[ -n "$fp28_end" ] || fp28_end=0
replace_block "$fp28_script" "$fp28_start" "$fp28_end" ''

fp28_home=$(new_home)
mkdir -p "$fp28_home/.claude/squirrel"
fp28_long=$(awk 'BEGIN { s = ""; for (i = 0; i < 5000; i++) { s = s "X" }; print s }')
printf '%s TAIL_AFTER_BYTE_CAP_FP_223344\n' "$fp28_long" >"$fp28_home/.claude/squirrel/profile.md"
fp28_stdin=$(printf '{"cwd":"%s/project-cap-over-bytes-fp"}' "$fp28_home")
fp28_ctx=$(extract_ctx "$(capture_stdout "$fp28_script" "$fp28_home" "$fp28_stdin")")
if printf '%s' "$fp28_ctx" | grep -qF "TAIL_AFTER_BYTE_CAP_FP_223344"; then
  fp28_leaks=yes
else
  fp28_leaks=no
fi
assert_eq "yes" "$fp28_leaks" "FAILURE PROOF (scenario 28): a cap_profile_body mutant with the byte-cap check removed must inject a >4KB single-line profile past the byte cap in full - proving scenario 28's byte-cap assertion is not vacuous"

# --- Failure proof for scenarios 29/30 (the cycle-3 BLOCKER): removes
# exactly the `[ -L "$base" ]` check added at the top of
# component_walk_has_symlink() - i.e. reverts to the pre-fix version
# that tests every component BELOW checkpoints_dir but never
# checkpoints_dir itself - and confirms the mutant incorrectly ALLOWS
# the write once checkpoints_dir itself is the symlink, with
# realpath/readlink stripped from PATH (so no other layer can mask the
# regression).
# ==========================================================================
fp2930_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016
fp2930_start=$(line_of "$fp2930_script" '  if [ -L "$base" ]; then')
[ -n "$fp2930_start" ] || fp2930_start=0
fp2930_end=$(line_of_after "$fp2930_script" "$fp2930_start" '  fi')
[ -n "$fp2930_end" ] || fp2930_end=0
replace_block "$fp2930_script" "$fp2930_start" "$fp2930_end" ''

fp2930_home=$(new_home)
mkdir -p "$fp2930_home/.claude/squirrel" "$fp2930_home/outside-secret-fp"
ln -s "$fp2930_home/outside-secret-fp" "$fp2930_home/.claude/squirrel/checkpoints"
fp2930_strip_path=$(make_tool_path "realpath readlink")
fp2930_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/squirrel/checkpoints/evil.md"}}' "$fp2930_home")
fp2930_out=$(capture_stdout_with_path "$fp2930_script" "$fp2930_home" "$fp2930_strip_path" "$fp2930_stdin")
fp2930_decision=$(printf '%s' "$fp2930_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp2930_decision="<jq error>"
assert_eq "allow" "$fp2930_decision" "FAILURE PROOF (scenarios 29/30): a component_walk_has_symlink mutant that never tests checkpoints_dir itself must incorrectly ALLOW a write when checkpoints_dir itself is the symlink - proving scenarios 29/30's defer assertions are not vacuous, and reproducing the exact pre-fix BLOCKER"

# --- Failure proof for scenario 33 (the cycle-3 MAJOR DoS fix): the
# length cap itself is what keeps an over-limit file_path fast, not
# some accidental early exit elsewhere. Removes exactly the
# MAX_FILE_PATH_LEN check, so normalize_path and
# component_walk_has_symlink run their full quadratic cost on the same
# 3000-segment file_path scenario 33 uses.
# ==========================================================================
fp33_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016
fp33_start=$(line_of "$fp33_script" '  if [ "${#file_path}" -gt "$MAX_FILE_PATH_LEN" ]; then')
[ -n "$fp33_start" ] || fp33_start=0
fp33_end=$(line_of_after "$fp33_script" "$fp33_start" '  fi')
[ -n "$fp33_end" ] || fp33_end=0
replace_block "$fp33_script" "$fp33_start" "$fp33_end" ''

fp33_home=$(new_home)
fp33_seg=""
fp33_n=0
while [ "$fp33_n" -lt 3000 ]; do
  fp33_seg="${fp33_seg}/a"
  fp33_n=$((fp33_n + 1))
done
fp33_path="/tmp/unrelated-to-checkpoints$fp33_seg"
fp33_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp33_path")

fp33_t0=$(date +%s)
fp33_out=$(capture_stdout "$fp33_script" "$fp33_home" "$fp33_stdin")
fp33_t1=$(date +%s)
fp33_delta=$((fp33_t1 - fp33_t0))
fp33_decision=$(printf '%s' "$fp33_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp33_decision="<jq error>"
assert_eq "defer" "$fp33_decision" "FAILURE PROOF (scenario 33) sanity: the cap-removed mutant must still eventually defer this unrelated path (only its SPEED is the regression under test)"

if [ "$fp33_delta" -gt 2 ]; then
  fp33_slow=yes
else
  fp33_slow=no
fi
assert_eq "yes" "$fp33_slow" "FAILURE PROOF (scenario 33): a mutant with the MAX_FILE_PATH_LEN cap removed must reproduce the multi-second quadratic blowup on the same 3000-segment file_path (took ${fp33_delta}s) - proving scenario 33's fast-rejection assertion is not vacuous"

# --- Failure proof for scenario 34 (the cycle-3 MINOR UTF-8 fix):
# removes exactly the strip_incomplete_utf8_tail call, so the byte cap
# alone (a raw `cut -b`) is what runs, and confirms the dangling euro
# lead byte (0xE2) reappears in raw output.
# ==========================================================================
fp34_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp34_line=$(line_of "$fp34_script" '    body=$(strip_incomplete_utf8_tail "$body")')
[ -n "$fp34_line" ] || fp34_line=0
replace_line "$fp34_script" "$fp34_line" ''

fp34_home=$(new_home)
mkdir -p "$fp34_home/.claude/squirrel"
fp34_head="HEAD_MARKER_BEFORE_CUT_778899"
fp34_filler_len=$((4094 - ${#fp34_head}))
fp34_filler=$(awk -v n="$fp34_filler_len" 'BEGIN { s = ""; for (i = 0; i < n; i++) { s = s "X" }; print s }')
printf '%s%s\342\202\254TAIL_AFTER_UTF8_CUT_665544\n' "$fp34_head" "$fp34_filler" >"$fp34_home/.claude/squirrel/profile.md"
fp34_stdin=$(printf '{"cwd":"%s/project-utf8-fp"}' "$fp34_home")
fp34_nojq_path=$(make_tool_path "jq")
fp34_out=$(capture_stdout_with_path "$fp34_script" "$fp34_home" "$fp34_nojq_path" "$fp34_stdin")
fp34_e2_count=$(printf '%s' "$fp34_out" | LC_ALL=C od -An -v -tu1 | tr -s ' \n' ' ' | tr ' ' '\n' | awk '$1 == 226 { c++ } END { print c + 0 }')
if [ "$fp34_e2_count" -gt 0 ]; then
  fp34_leaks=yes
else
  fp34_leaks=no
fi
assert_eq "yes" "$fp34_leaks" "FAILURE PROOF (scenario 34): a cap_profile_body mutant with strip_incomplete_utf8_tail removed must leave the dangling euro lead byte (0xE2) in raw output when the byte cap lands mid-character - proving scenario 34's zero-count assertion is not vacuous"

assert_report
