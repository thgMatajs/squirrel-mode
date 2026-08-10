#!/bin/sh
# Coverage for S4: hooks/hooks.json and the three POSIX sh hook scripts
# (load-profile.sh, check-off-flag.sh, allow-checkpoint.sh). Behavioural,
# not structural: every script is fed real JSON on stdin and asserted on
# its stdout, exit code, and filesystem side effects, under a temporary
# HOME so nothing here ever touches the real ~/.squirrel/. This
# is also where .build-checkpoint.md's "Known gap, carried into S4" note
# gets closed: scenario 2 in particular is the missing-input case it
# flags.
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
assert_eq "Write|Edit|Read" "$pretooluse_matcher" "hooks.json PreToolUse matcher must be 'Write|Edit|Read' (S10-1: Read must reach allow-checkpoint.sh too, not just Write/Edit)"

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
# 2. load-profile.sh - fresh install, nothing under ~/.squirrel/
#    at all: exit 0, valid JSON, contains a single /squirrel:init
#    suggestion. This is the "Known gap" missing-input case.
# ==========================================================================
home2=$(new_home)
sessionstart_stdin=$(printf '{"session_id":"s1","cwd":"%s/project-a","hook_event_name":"SessionStart","source":"startup"}' "$home2")

exit2=$(capture_exit "$load_profile_script" "$home2" "$sessionstart_stdin")
assert_eq "0" "$exit2" "load-profile.sh must exit 0 on a completely fresh install (no ~/.squirrel/ at all)"

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
mkdir -p "$home3/.squirrel"
profile3_marker="LANGUAGE_MARKER_XYZ_pt-BR"
cat >"$home3/.squirrel/profile.md" <<EOF
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
mkdir -p "$home4/.squirrel"
cat >"$home4/.squirrel/profile.md" <<'EOF'
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
mkdir -p "$home10/.squirrel/off"
touch "$home10/.squirrel/off/sess-flagged"
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
mkdir -p "$home12/.squirrel/off"
touch "$home12/.squirrel/decoy-outside-off.txt"
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
stdin14=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home14")
exit14=$(capture_exit "$allow_checkpoint_script" "$home14" "$stdin14")
assert_eq "0" "$exit14" "allow-checkpoint.sh must exit 0 for a legitimate checkpoint write"
out14=$(capture_stdout "$allow_checkpoint_script" "$home14" "$stdin14")
decision14=$(printf '%s' "$out14" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision14="<jq error>"
assert_eq "allow" "$decision14" "allow-checkpoint.sh must return 'allow' for a file_path inside the checkpoints directory"

# --- S10-1 Read mirror of scenario 14: the same legitimate checkpoint
# path, with tool_name "Read" instead of "Write". This is the exact
# defect a live probe found - /squirrel:pickup and rule 14's own
# update path both START with a Read of the checkpoint file, and before
# this fix that Read fell through to the normal permission prompt even
# though the hook already returned "allow" for a Write to the identical
# path. Same scratch HOME/fixture as scenario 14, reused (inert
# directory state, safe to share).
#
# WRAPPER FAIL-SAFE CONTRACT, RELABELLED (S10 review, AB4): the "exit 0"
# assertion immediately below this comment, and every other "must exit 0
# for tool_name Read ..." assertion added across this file for S10-1, was
# being counted as Read-widening coverage. It is not, and cannot be: the
# outer wrapper (`if decision=$(decide 2>/dev/null); then :; else
# decision="defer"; fi`, then an unconditional `case`/`exit 0` at the
# bottom of allow-checkpoint.sh) turns ANY internal failure of decide()
# into a hardcoded "defer" and always exits 0, regardless of whether
# decide()'s Read-vs-Write logic is right or wrong. Proven: scenario 58
# below breaks decide() entirely for Read (reverts the case statement to
# the pre-fix "Write | Edit) ;;") and every "exit 0" assertion in this
# file stays green while the DECISION assertions (checking "allow" vs
# "defer") correctly go red. These "exit 0" assertions still verify
# something real and worth checking - invariant 5, that a hook never
# exits non-zero even on a code path this specific - they are just not,
# and were never, evidence that the Read decision itself is correct. The
# "allow"/"defer" assertions immediately following each one are that
# evidence.
# ==========================================================================
stdin14r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home14")
exit14r=$(capture_exit "$allow_checkpoint_script" "$home14" "$stdin14r")
assert_eq "0" "$exit14r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see the comment above and scenario 58's mutation proof): allow-checkpoint.sh must exit 0 for a legitimate checkpoint Read"
out14r=$(capture_stdout "$allow_checkpoint_script" "$home14" "$stdin14r")
decision14r=$(printf '%s' "$out14r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision14r="<jq error>"
assert_eq "allow" "$decision14r" "S10-1 BLOCKER fix: allow-checkpoint.sh must return 'allow' for tool_name Read on a file_path inside the checkpoints directory, identically to Write/Edit"

# ==========================================================================
# 15. allow-checkpoint.sh - file_path elsewhere in $HOME: "defer".
# ==========================================================================
home15=$(new_home)
stdin15=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/Documents/notes.md"}}' "$home15")
out15=$(capture_stdout "$allow_checkpoint_script" "$home15" "$stdin15")
decision15=$(printf '%s' "$out15" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision15="<jq error>"
assert_eq "defer" "$decision15" "allow-checkpoint.sh must return 'defer' for a file_path elsewhere in \$HOME"

# --- S10-1 Read mirror of scenario 15.
stdin15r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/Documents/notes.md"}}' "$home15")
out15r=$(capture_stdout "$allow_checkpoint_script" "$home15" "$stdin15r")
decision15r=$(printf '%s' "$out15r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision15r="<jq error>"
assert_eq "defer" "$decision15r" "S10-1: allow-checkpoint.sh must return 'defer' for tool_name Read on a file_path elsewhere in \$HOME"

# ==========================================================================
# 16. allow-checkpoint.sh - traversal:
#     $HOME/.squirrel/checkpoints/../../../.ssh/id_rsa -> "defer".
# ==========================================================================
home16=$(new_home)
stdin16=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$home16")
out16=$(capture_stdout "$allow_checkpoint_script" "$home16" "$stdin16")
decision16=$(printf '%s' "$out16" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision16="<jq error>"
assert_eq "defer" "$decision16" "allow-checkpoint.sh must return 'defer' for a traversal path escaping checkpoints/ via ../../../"

# --- S10-1 Read mirror of scenario 16 (attack matrix: traversal).
stdin16r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$home16")
out16r=$(capture_stdout "$allow_checkpoint_script" "$home16" "$stdin16r")
decision16r=$(printf '%s' "$out16r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision16r="<jq error>"
assert_eq "defer" "$decision16r" "S10-1: allow-checkpoint.sh must return 'defer' for tool_name Read on a traversal path escaping checkpoints/ via ../../../ - the boundary must not loosen for a read"

# ==========================================================================
# 17. allow-checkpoint.sh - prefix-escape:
#     $HOME/.squirrel/checkpoints-evil/x -> "defer".
# ==========================================================================
home17=$(new_home)
stdin17=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints-evil/x"}}' "$home17")
out17=$(capture_stdout "$allow_checkpoint_script" "$home17" "$stdin17")
decision17=$(printf '%s' "$out17" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision17="<jq error>"
assert_eq "defer" "$decision17" "allow-checkpoint.sh must return 'defer' for a directory that merely starts with the string 'checkpoints' ('checkpoints-evil')"

# --- S10-1 Read mirror of scenario 17 (attack matrix: prefix-escape).
stdin17r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints-evil/x"}}' "$home17")
out17r=$(capture_stdout "$allow_checkpoint_script" "$home17" "$stdin17r")
decision17r=$(printf '%s' "$out17r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision17r="<jq error>"
assert_eq "defer" "$decision17r" "S10-1: allow-checkpoint.sh must return 'defer' for tool_name Read on 'checkpoints-evil' (prefix-escape)"

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

# --- S10-1 Read mirror of scenario 18: the identical relative/empty/
# absent file_path and absent-tool_input cases, with tool_name "Read".
# ==========================================================================
scenario18r_cases="relative_file_path:{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"relative/path.md\"}}
empty_file_path:{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"\"}}
absent_file_path:{\"tool_name\":\"Read\",\"tool_input\":{}}
absent_tool_input:{\"tool_name\":\"Read\"}"

old_ifs=$IFS
IFS='
'
for case18r in $scenario18r_cases; do
  IFS=$old_ifs
  case18r_name=${case18r%%:*}
  case18r_json=${case18r#*:}
  exit18r=$(capture_exit "$allow_checkpoint_script" "$home18" "$case18r_json")
  assert_eq "0" "$exit18r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for Read case '$case18r_name'"
  out18r=$(capture_stdout "$allow_checkpoint_script" "$home18" "$case18r_json")
  decision18r=$(printf '%s' "$out18r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision18r="<jq error>"
  assert_eq "defer" "$decision18r" "S10-1: allow-checkpoint.sh must return 'defer' for Read case '$case18r_name'"
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
mkdir -p "$home19/.squirrel/checkpoints" "$home19/outside-secret"
ln -s "$home19/outside-secret" "$home19/.squirrel/checkpoints/escape-dir"
touch "$home19/outside-secret/secret.md"
ln -s "$home19/outside-secret/secret.md" "$home19/.squirrel/checkpoints/escape-file"

stdin19a=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$home19")
out19a=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19a")
decision19a=$(printf '%s' "$out19a" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19a="<jq error>"
assert_eq "defer" "$decision19a" "allow-checkpoint.sh must return 'defer' when an intermediate directory inside checkpoints/ is a symlink pointing outside it"

stdin19b=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-file"}}' "$home19")
out19b=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19b")
decision19b=$(printf '%s' "$out19b" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19b="<jq error>"
assert_eq "defer" "$decision19b" "allow-checkpoint.sh must return 'defer' when the file_path itself is a symlink pointing outside checkpoints/"

# Sanity: a genuine, non-symlinked nested file in the same directory is
# still allowed - the symlink defence above must not have become
# overbroad and started deferring everything under checkpoints/.
mkdir -p "$home19/.squirrel/checkpoints/real-subdir"
stdin19c=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/real-subdir/a.md"}}' "$home19")
out19c=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19c")
decision19c=$(printf '%s' "$out19c" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19c="<jq error>"
assert_eq "allow" "$decision19c" "a genuine non-symlinked nested checkpoint path must still be allowed alongside the symlink fixtures in the same directory"

# --- S10-1 Read mirror of scenario 19: the identical symlinked-
# intermediate-directory, symlinked-leaf, and sanity-nested-real-file
# cases, with tool_name "Read". Same home19 fixtures, reused.
# ==========================================================================
stdin19ar=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$home19")
out19ar=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19ar")
decision19ar=$(printf '%s' "$out19ar" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19ar="<jq error>"
assert_eq "defer" "$decision19ar" "S10-1: allow-checkpoint.sh must return 'defer' for tool_name Read when an intermediate directory inside checkpoints/ is a symlink pointing outside it"

stdin19br=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-file"}}' "$home19")
out19br=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19br")
decision19br=$(printf '%s' "$out19br" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19br="<jq error>"
assert_eq "defer" "$decision19br" "S10-1: allow-checkpoint.sh must return 'defer' for tool_name Read when the file_path itself is a symlink pointing outside checkpoints/"

stdin19cr=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/real-subdir/a.md"}}' "$home19")
out19cr=$(capture_stdout "$allow_checkpoint_script" "$home19" "$stdin19cr")
decision19cr=$(printf '%s' "$out19cr" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision19cr="<jq error>"
assert_eq "allow" "$decision19cr" "S10-1: a genuine non-symlinked nested checkpoint path must still be allowed for tool_name Read too, alongside the symlink fixtures in the same directory"

# ==========================================================================
# 20. allow-checkpoint.sh - tool_name other than Write/Edit/Read: "defer".
# ==========================================================================
home20=$(new_home)
stdin20=$(printf '{"tool_name":"Bash","tool_input":{"file_path":"%s/.squirrel/checkpoints/x.md"}}' "$home20")
out20=$(capture_stdout "$allow_checkpoint_script" "$home20" "$stdin20")
decision20=$(printf '%s' "$out20" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision20="<jq error>"
assert_eq "defer" "$decision20" "allow-checkpoint.sh must return 'defer' for tool_name 'Bash' even when file_path is a legitimate checkpoint path - the matcher must not widen beyond Write/Edit/Read"

# ==========================================================================
# 21. allow-checkpoint.sh - output is valid JSON in every case above.
#
# WRAPPER FAIL-SAFE CONTRACT, RELABELLED (S10 review, AB4): this single
# loop covers BOTH the pre-existing Write/Edit cases (14, 15, 16, 17, 19a,
# 19b, 19c, 20) AND the S10-1 Read mirrors added alongside them (14r, 15r,
# 16r, 17r, 19ar, 19br, 19cr) with one shared assertion template, so the
# "r"-suffixed iterations were counted as Read-widening coverage alongside
# the real decision assertions above. They are not: the script's final
# `case` always emits exactly one well-formed JSON blob before `exit 0`
# (see scenario 14r's comment, above, for the full mechanism and the
# scenario-58 mutation proof), so every iteration of this loop - old
# pairs and new "r" pairs alike - is structurally unable to fail
# regardless of whether the underlying decision is right or wrong. This
# verifies invariant 5's "always valid JSON" half, a real and separate
# property worth checking; it is just not, and was never, Read-decision
# coverage.
# ==========================================================================
for pair in "14:$out14" "14r:$out14r" "15:$out15" "15r:$out15r" "16:$out16" "16r:$out16r" "17:$out17" "17r:$out17r" "19a:$out19a" "19ar:$out19ar" "19b:$out19b" "19br:$out19br" "19c:$out19c" "19cr:$out19cr" "20:$out20"; do
  label=${pair%%:*}
  content=${pair#*:}
  if printf '%s' "$content" | jq empty >/dev/null 2>&1; then
    scenario21_valid=yes
  else
    scenario21_valid=no
  fi
  assert_eq "yes" "$scenario21_valid" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage: allow-checkpoint.sh scenario $label output must be valid, parseable JSON"
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

exit22_allow_read=$(capture_exit "$allow_checkpoint_script" "$home22" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x.md"}}')
assert_eq "0" "$exit22_allow_read" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for tool_name Read with an empty HOME directory"

# ==========================================================================
# 23. load-profile.sh - json_escape (no-jq fallback) must escape EVERY
#     C0 control byte, not just tab/newline/trailing-CR. Reproduces the
#     reviewer's exact repro for MAJOR #1: bell (0x07), ESC (0x1b), and
#     vertical tab (0x0b) in profile.md, with jq removed from PATH.
#     Before the fix, `jq empty` on this exact output failed with
#     "control characters ... must be escaped".
# ==========================================================================
home23=$(new_home)
mkdir -p "$home23/.squirrel"
bell23=$(printf '\007')
esc23=$(printf '\033')
vtab23=$(printf '\013')
printf '# squirrel-mode profile\nBEFORE_BELL%sAFTER_BELL BEFORE_ESC%sAFTER_ESC BEFORE_VTAB%sAFTER_VTAB\n' \
  "$bell23" "$esc23" "$vtab23" >"$home23/.squirrel/profile.md"
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
mkdir -p "$home24/.squirrel"
n24=1
: >"$home24/.squirrel/profile.md"
while [ "$n24" -le 19 ]; do
  printf 'field%02d: value\n' "$n24" >>"$home24/.squirrel/profile.md"
  n24=$((n24 + 1))
done
printf '\377\376\200\201 TAIL_MARKER_SURVIVES_998877\n' >>"$home24/.squirrel/profile.md"
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
mkdir -p "$home25/.squirrel/checkpoints" "$home25/outside-secret"
ln -s "$home25/outside-secret" "$home25/.squirrel/checkpoints/escape-dir"
touch "$home25/outside-secret/secret.md"
ln -s "$home25/outside-secret/secret.md" "$home25/.squirrel/checkpoints/escape-file"
mkdir -p "$home25/.squirrel/checkpoints/real-subdir"
strip_path25=$(make_tool_path "realpath readlink")

stdin25a=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$home25")
out25a=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25a")
decision25a=$(printf '%s' "$out25a" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25a="<jq error>"
assert_eq "defer" "$decision25a" "MAJOR #3: with realpath AND readlink stripped from PATH, a symlinked intermediate directory inside checkpoints/ must still defer"

stdin25b=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-file"}}' "$home25")
out25b=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25b")
decision25b=$(printf '%s' "$out25b" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25b="<jq error>"
assert_eq "defer" "$decision25b" "MAJOR #3: with realpath AND readlink stripped from PATH, a symlinked leaf file_path inside checkpoints/ must still defer"

stdin25c=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/real-subdir/a.md"}}' "$home25")
out25c=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25c")
decision25c=$(printf '%s' "$out25c" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25c="<jq error>"
assert_eq "allow" "$decision25c" "sanity (MAJOR #3): a genuine non-symlinked nested checkpoint path must still be allowed with realpath/readlink stripped - the fix must not become overbroad"

exit25=$(capture_exit_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25a")
assert_eq "0" "$exit25" "allow-checkpoint.sh must exit 0 even with realpath/readlink stripped from PATH"

# --- S10-1 Read mirror of scenario 25: the same symlink fixtures, same
# realpath/readlink-stripped PATH, with tool_name "Read".
# ==========================================================================
stdin25ar=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$home25")
out25ar=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25ar")
decision25ar=$(printf '%s' "$out25ar" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25ar="<jq error>"
assert_eq "defer" "$decision25ar" "S10-1: with realpath AND readlink stripped from PATH, tool_name Read on a symlinked intermediate directory inside checkpoints/ must still defer"

stdin25br=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-file"}}' "$home25")
out25br=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25br")
decision25br=$(printf '%s' "$out25br" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25br="<jq error>"
assert_eq "defer" "$decision25br" "S10-1: with realpath AND readlink stripped from PATH, tool_name Read on a symlinked leaf file_path inside checkpoints/ must still defer"

stdin25cr=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/real-subdir/a.md"}}' "$home25")
out25cr=$(capture_stdout_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25cr")
decision25cr=$(printf '%s' "$out25cr" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision25cr="<jq error>"
assert_eq "allow" "$decision25cr" "S10-1 sanity: a genuine non-symlinked nested checkpoint path must still be allowed for tool_name Read with realpath/readlink stripped"

exit25r=$(capture_exit_with_path "$allow_checkpoint_script" "$home25" "$strip_path25" "$stdin25ar")
assert_eq "0" "$exit25r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for tool_name Read even with realpath/readlink stripped from PATH"

# ==========================================================================
# 26. load-profile.sh - tech-lead ruling: an UNDER-cap profile (well
#     under 100 lines / 4 KB) must be injected in full, with no
#     truncation notice.
# ==========================================================================
home26=$(new_home)
mkdir -p "$home26/.squirrel"
marker26="UNDER_CAP_MARKER_554433"
printf '# squirrel-mode profile\nlanguage: en\n%s\n' "$marker26" >"$home26/.squirrel/profile.md"
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
mkdir -p "$home27/.squirrel"
n27=1
: >"$home27/.squirrel/profile.md"
while [ "$n27" -le 150 ]; do
  printf 'line%03d: marker\n' "$n27" >>"$home27/.squirrel/profile.md"
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
mkdir -p "$home28/.squirrel"
long28=$(awk 'BEGIN { s = ""; for (i = 0; i < 5000; i++) { s = s "X" }; print s }')
printf '%s TAIL_AFTER_BYTE_CAP_112233\n' "$long28" >"$home28/.squirrel/profile.md"
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
#     $HOME/.squirrel/checkpoints`). Must defer, with
#     realpath/readlink present.
# ==========================================================================
home29=$(new_home)
mkdir -p "$home29/.squirrel" "$home29/outside-secret-29"
ln -s "$home29/outside-secret-29" "$home29/.squirrel/checkpoints"
stdin29=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$home29")

out29=$(capture_stdout "$allow_checkpoint_script" "$home29" "$stdin29")
decision29=$(printf '%s' "$out29" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision29="<jq error>"
assert_eq "defer" "$decision29" "BLOCKER fix: a symlink AT checkpoints_dir itself (not merely below it) must defer, not allow, with realpath/readlink present"

exit29=$(capture_exit "$allow_checkpoint_script" "$home29" "$stdin29")
assert_eq "0" "$exit29" "allow-checkpoint.sh must exit 0 even when checkpoints_dir itself is a symlink"

# --- S10-1 Read mirror of scenario 29: checkpoints_dir itself is a
# symlink, tool_name "Read", realpath/readlink present.
stdin29r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$home29")
out29r=$(capture_stdout "$allow_checkpoint_script" "$home29" "$stdin29r")
decision29r=$(printf '%s' "$out29r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision29r="<jq error>"
assert_eq "defer" "$decision29r" "S10-1: a symlink AT checkpoints_dir itself must defer for tool_name Read too, with realpath/readlink present"

exit29r=$(capture_exit "$allow_checkpoint_script" "$home29" "$stdin29r")
assert_eq "0" "$exit29r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for tool_name Read even when checkpoints_dir itself is a symlink"

# ==========================================================================
# 30. allow-checkpoint.sh - same repro as scenario 29, with realpath AND
#     readlink stripped from PATH. THE permanent assertion: Layer 2
#     (the component walk, now testing checkpoints_dir itself) is what
#     must catch this unconditionally, not any realpath-based layer -
#     see the FAILURE PROOF at the bottom of this file that removes
#     exactly this check and confirms the mutant allows the escape.
# ==========================================================================
home30=$(new_home)
mkdir -p "$home30/.squirrel" "$home30/outside-secret-30"
ln -s "$home30/outside-secret-30" "$home30/.squirrel/checkpoints"
stdin30=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$home30")
strip_path30=$(make_tool_path "realpath readlink")

out30=$(capture_stdout_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30")
decision30=$(printf '%s' "$out30" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision30="<jq error>"
assert_eq "defer" "$decision30" "BLOCKER fix: a symlink AT checkpoints_dir itself must still defer with realpath AND readlink stripped from PATH"

exit30=$(capture_exit_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30")
assert_eq "0" "$exit30" "allow-checkpoint.sh must exit 0 for the symlinked-checkpoints_dir case even with realpath/readlink stripped"

# --- S10-1 Read mirror of scenario 30: same repro, realpath AND
# readlink stripped from PATH, tool_name "Read".
stdin30r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$home30")
out30r=$(capture_stdout_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30r")
decision30r=$(printf '%s' "$out30r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision30r="<jq error>"
assert_eq "defer" "$decision30r" "S10-1: a symlink AT checkpoints_dir itself must still defer for tool_name Read with realpath AND readlink stripped from PATH"

exit30r=$(capture_exit_with_path "$allow_checkpoint_script" "$home30" "$strip_path30" "$stdin30r")
assert_eq "0" "$exit30r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for the symlinked-checkpoints_dir case with tool_name Read, even with realpath/readlink stripped"

# ==========================================================================
# 31. allow-checkpoint.sh - REGRESSION GUARD for the tech-lead's ruling,
#     RE-DERIVED AT THE S11 LOCATION (docs/adr/0003's Amendment (S11)):
#     $HOME/.squirrel ITSELF is a symlink (the chezmoi/stow/yadm
#     dotfile-manager pattern - ordinary user configuration, not an
#     attack, and explicitly OUT OF SCOPE for this hook's symlink
#     defence). Before S11 this was $HOME/.claude (two ancestor levels
#     above checkpoints_dir: .claude, then .squirrel); moving the
#     data directory out from under .claude collapses those two trusted
#     ancestors into the one now being tested here - the same rule, one
#     level shallower, not a new one. A genuine checkpoint write beneath
#     it must still be "allow", with realpath/readlink present.
# ==========================================================================
home31=$(new_home)
real_squirrel31="$home31/real-dotfiles-squirrel-31"
mkdir -p "$real_squirrel31/checkpoints"
ln -s "$real_squirrel31" "$home31/.squirrel"
stdin31=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home31")

out31=$(capture_stdout "$allow_checkpoint_script" "$home31" "$stdin31")
decision31=$(printf '%s' "$out31" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision31="<jq error>"
assert_eq "allow" "$decision31" "REGRESSION GUARD (tech-lead ruling, re-derived at the S11 location): a legitimately symlinked \$HOME/.squirrel (dotfile-manager pattern) must still ALLOW a genuine checkpoint write beneath it, with realpath/readlink present"

exit31=$(capture_exit "$allow_checkpoint_script" "$home31" "$stdin31")
assert_eq "0" "$exit31" "allow-checkpoint.sh must exit 0 for a legitimately symlinked \$HOME/.squirrel"

# --- S10-1 Read mirror of scenario 31: legitimately symlinked
# $HOME/.squirrel, tool_name "Read", realpath/readlink present. This is
# the dotfile-manager regression guard the S10-1 fix must also satisfy
# for reads, per the task's own requirement.
stdin31r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home31")
out31r=$(capture_stdout "$allow_checkpoint_script" "$home31" "$stdin31r")
decision31r=$(printf '%s' "$out31r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision31r="<jq error>"
assert_eq "allow" "$decision31r" "S10-1 REGRESSION GUARD: a legitimately symlinked \$HOME/.squirrel (dotfile-manager pattern) must still ALLOW a genuine checkpoint Read beneath it, with realpath/readlink present"

exit31r=$(capture_exit "$allow_checkpoint_script" "$home31" "$stdin31r")
assert_eq "0" "$exit31r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for tool_name Read on a legitimately symlinked \$HOME/.squirrel"

# ==========================================================================
# 32. allow-checkpoint.sh - same regression guard as scenario 31, with
#     realpath AND readlink stripped from PATH: the ruling must hold
#     regardless of which tools happen to be installed, not as a
#     side-effect of a realpath-based layer that cycle 3 removed.
# ==========================================================================
home32=$(new_home)
real_squirrel32="$home32/real-dotfiles-squirrel-32"
mkdir -p "$real_squirrel32/checkpoints"
ln -s "$real_squirrel32" "$home32/.squirrel"
stdin32=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home32")
strip_path32=$(make_tool_path "realpath readlink")

out32=$(capture_stdout_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32")
decision32=$(printf '%s' "$out32" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision32="<jq error>"
assert_eq "allow" "$decision32" "REGRESSION GUARD: a legitimately symlinked \$HOME/.squirrel must still ALLOW a genuine checkpoint write with realpath AND readlink stripped from PATH too"

exit32=$(capture_exit_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32")
assert_eq "0" "$exit32" "allow-checkpoint.sh must exit 0 for a legitimately symlinked \$HOME/.squirrel with realpath/readlink stripped"

# --- S10-1 Read mirror of scenario 32: same regression guard, realpath
# AND readlink stripped from PATH, tool_name "Read".
stdin32r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$home32")
out32r=$(capture_stdout_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32r")
decision32r=$(printf '%s' "$out32r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision32r="<jq error>"
assert_eq "allow" "$decision32r" "S10-1 REGRESSION GUARD: a legitimately symlinked \$HOME/.squirrel must still ALLOW a genuine checkpoint Read with realpath AND readlink stripped from PATH too"

exit32r=$(capture_exit_with_path "$allow_checkpoint_script" "$home32" "$strip_path32" "$stdin32r")
assert_eq "0" "$exit32r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for tool_name Read on a legitimately symlinked \$HOME/.squirrel with realpath/readlink stripped"

# --- Failure proof for scenario 31 (S11 trust-boundary rewrite): proves
# scenario 31's "allow" is not vacuous by mutating a scratch copy to ALSO
# reject a symlinked $HOME/.squirrel itself - the over-strict design the
# tech lead explicitly rejected (see scripts/allow-checkpoint.sh's own
# "WHERE THE TRUST BOUNDARY SITS" comment and docs/adr/0003's Amendment
# (S11)). If this mutant did not flip scenario 31's exact payload from
# "allow" to "defer", scenario 31 would not actually be exercising the
# ~/.squirrel trust decision at all.
# ==========================================================================
fp31_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal source text to locate, not shell expansion
fp31_call_line=$(line_of "$fp31_script" '  if component_walk_has_symlink "$checkpoints_dir" "$after"; then')
[ -n "$fp31_call_line" ] || fp31_call_line=0
# shellcheck disable=SC2016 # single-quoted deliberately: literal replacement source text, not shell expansion
replace_block "$fp31_script" "$fp31_call_line" "$fp31_call_line" '  if [ -L "$home_dir/.squirrel" ] || component_walk_has_symlink "$checkpoints_dir" "$after"; then'

fp31_out=$(capture_stdout "$fp31_script" "$home31" "$stdin31")
fp31_decision=$(printf '%s' "$fp31_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp31_decision="<jq error>"
assert_eq "defer" "$fp31_decision" "FAILURE PROOF (invariant S11, scenario 31): a mutant that also rejects a symlinked \$HOME/.squirrel itself must flip scenario 31's exact payload to defer - proving scenario 31's allow assertion genuinely depends on the trust-boundary decision, not on an accident"

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

# --- S10-1 Read mirror of scenario 33: the identical over-cap file_path,
# tool_name "Read" - the length cap must fire before normalize_path or
# component_walk_has_symlink for a Read too, not only for Write/Edit.
stdin33r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$long_path33")

t0_33r=$(date +%s)
out33r=$(capture_stdout "$allow_checkpoint_script" "$home33" "$stdin33r")
t1_33r=$(date +%s)
delta33r=$((t1_33r - t0_33r))

decision33r=$(printf '%s' "$out33r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision33r="<jq error>"
assert_eq "defer" "$decision33r" "S10-1: an over-MAX_FILE_PATH_LEN file_path must defer for tool_name Read too"

if [ "$delta33r" -le 2 ]; then
  fast33r=yes
else
  fast33r=no
fi
assert_eq "yes" "$fast33r" "S10-1: a 3000-segment (~6KB) file_path with tool_name Read must be rejected in a couple of seconds or less by the length cap (took ${delta33r}s)"

exit33r=$(capture_exit "$allow_checkpoint_script" "$home33" "$stdin33r")
assert_eq "0" "$exit33r" "WRAPPER FAIL-SAFE CONTRACT, not Read-decision coverage (see scenario 14r's comment): allow-checkpoint.sh must exit 0 for an over-cap file_path with tool_name Read"

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
mkdir -p "$home34/.squirrel"
head_marker34="HEAD_MARKER_BEFORE_CUT_778899"
filler_len34=$((4094 - ${#head_marker34}))
filler34=$(awk -v n="$filler_len34" 'BEGIN { s = ""; for (i = 0; i < n; i++) { s = s "X" }; print s }')
printf '%s%s\342\202\254TAIL_AFTER_UTF8_CUT_665544\n' "$head_marker34" "$filler34" >"$home34/.squirrel/profile.md"
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
mkdir -p "$home35/.squirrel/checkpoints"
marker35="$home35/PWNED_MARKER_35"
rm -f "$marker35"

# Built from single-quoted literal segments around the one
# double-quoted variable expansion, so the "$(" / ")" characters are
# never live shell syntax at any point - concatenation of separately-
# quoted segments does not re-scan the joined result for new syntax,
# per POSIX quote removal rules.
# shellcheck disable=SC2016 # deliberate: the single-quoted segments
# below must NOT expand - that is the entire point of this fixture.
fp_dollar35="$home35/.squirrel/checkpoints/"'$(touch '"$marker35"')'".md"
stdin_dollar35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp_dollar35")
out_dollar35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_dollar35")
decision_dollar35=$(printf '%s' "$out_dollar35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_dollar35="<jq error>"
assert_eq "allow" "$decision_dollar35" "a literal \$(...) sequence inside an otherwise-legitimate checkpoint filename must be treated as inert text and allowed"
assert_file_absent "$marker35" "a literal \$(command) inside file_path must NEVER be executed - the marker file must not exist"

# Same technique, backtick form - same single-quoting discipline so
# the backticks are never live syntax either.
# shellcheck disable=SC2016
fp_backtick35="$home35/.squirrel/checkpoints/"'`touch '"$marker35"'`'".md"
stdin_backtick35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$fp_backtick35")
out_backtick35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_backtick35")
decision_backtick35=$(printf '%s' "$out_backtick35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_backtick35="<jq error>"
assert_eq "allow" "$decision_backtick35" "a literal backtick-quoted command inside an otherwise-legitimate checkpoint filename must be treated as inert text and allowed"
assert_file_absent "$marker35" "a literal \`command\` inside file_path must NEVER be executed - the marker file must not exist"

# Literal glob: a bare "*" as a filename character, sitting alongside
# real decoy files it must NOT expand to match.
mkdir -p "$home35/.squirrel/checkpoints/glob-dir-35"
touch "$home35/.squirrel/checkpoints/glob-dir-35/decoy1.md" "$home35/.squirrel/checkpoints/glob-dir-35/decoy2.md"
stdin_glob35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/glob-dir-35/*.md"}}' "$home35")
out_glob35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_glob35")
decision_glob35=$(printf '%s' "$out_glob35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_glob35="<jq error>"
assert_eq "allow" "$decision_glob35" "a literal '*' in file_path must be treated as an ordinary filename character (never glob-expanded) and allowed"

# Percent-encoded traversal-looking segment: nothing in this script (or
# the filesystem it eventually writes to) URL-decodes a path, so
# "%2e%2e" is just a literal, benign directory-name-shaped string, not
# a disguised "..".
stdin_pct35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/%%2e%%2e/%%2e%%2e/etc/passwd"}}' "$home35")
out_pct35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_pct35")
decision_pct35=$(printf '%s' "$out_pct35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_pct35="<jq error>"
assert_eq "allow" "$decision_pct35" "a percent-encoded '%2e%2e' segment must NOT be decoded into '..' anywhere in this pipeline, so it stays a literal, contained subdirectory name"

# Raw control byte (0x01) inside an otherwise-legitimate filename. A raw,
# unescaped control byte inside a JSON string is not legal JSON at all
# (RFC 8259 requires control characters to be escaped) - jq correctly
# rejects the whole document as unparseable. UPDATED (S10 review cycle
# 2, AC1): this used to still "allow", because extract_tool_input_field's
# now-removed sed fallback did not care whether the surrounding document
# was valid JSON and extracted the path anyway. Requiring a real parser
# for file_path means a payload the parser cannot parse at all no longer
# gets a best-effort answer from a regex that does not know better - it
# defers, the same safe outcome jq-absent already produces, for the same
# reason. `tool_name` still resolves to "Write" via extract_field's own
# (unaffected, out of AC1's scope) sed fallback, so this exercises
# decide() actually reaching the file_path check and deferring there
# specifically, not short-circuiting earlier on an unrecognised tool_name.
ctrl35=$(printf '\001')
stdin_ctrl35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil%sname.md"}}' "$home35" "$ctrl35")
out_ctrl35=$(capture_stdout "$allow_checkpoint_script" "$home35" "$stdin_ctrl35")
decision_ctrl35=$(printf '%s' "$out_ctrl35" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision_ctrl35="<jq error>"
assert_eq "defer" "$decision_ctrl35" "AC1: a raw control byte (0x01) makes the whole payload invalid JSON (RFC 8259) - jq correctly refuses to parse it, and without a real parser to consult, extract_tool_input_field must not guess via a regex; the safe, deliberate outcome is defer, not a best-effort allow"

exit_ctrl35=$(capture_exit "$allow_checkpoint_script" "$home35" "$stdin_ctrl35")
assert_eq "0" "$exit_ctrl35" "allow-checkpoint.sh must exit 0 for a file_path containing a raw control byte (never a crash, even on unparseable input)"

# JSON-escaped embedded newline (the realistic form: valid JSON with a
# properly-escaped \n, not a raw unescaped newline byte, which is not
# even legal JSON) inside an otherwise-legitimate filename.
stdin_nl35=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil\\nname.md"}}' "$home35")
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

stdin36_root=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/.squirrel/checkpoints/proj36.md"}}')
out36_root=$(printf '%s' "$stdin36_root" | HOME="/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36_root=$(printf '%s' "$out36_root" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_root="<jq error>"
assert_eq "allow" "$decision36_root" "\$HOME=/ (root) must still allow a genuine, nested checkpoint write under it"

home36_trail=$(new_home)
mkdir -p "$home36_trail/.squirrel/checkpoints"
stdin36_trail=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/proj36.md"}}' "$home36_trail")
out36_trail=$(printf '%s' "$stdin36_trail" | HOME="$home36_trail/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36_trail=$(printf '%s' "$out36_trail" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36_trail="<jq error>"
assert_eq "allow" "$decision36_trail" "\$HOME carrying a trailing slash must still allow a genuine, nested checkpoint write under it"

# --- S10-1 Read mirror of scenario 36: the identical $HOME
# unset/empty/root/trailing-slash matrix, with tool_name "Read".
# ==========================================================================
stdin36r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/somewhere-unrelated-36/x.md"}}')

out36r_unset=$(printf '%s' "$stdin36r" | env -u HOME "$allow_checkpoint_script" 2>/dev/null) || true
decision36r_unset=$(printf '%s' "$out36r_unset" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36r_unset="<jq error>"
assert_eq "defer" "$decision36r_unset" "S10-1: \$HOME entirely unset must defer for tool_name Read too, never allow"

out36r_empty=$(printf '%s' "$stdin36r" | HOME="" "$allow_checkpoint_script" 2>/dev/null) || true
decision36r_empty=$(printf '%s' "$out36r_empty" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36r_empty="<jq error>"
assert_eq "defer" "$decision36r_empty" "S10-1: \$HOME set to an empty string must defer for tool_name Read too, never allow"

stdin36r_root=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/.squirrel/checkpoints/proj36.md"}}')
out36r_root=$(printf '%s' "$stdin36r_root" | HOME="/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36r_root=$(printf '%s' "$out36r_root" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36r_root="<jq error>"
assert_eq "allow" "$decision36r_root" "S10-1: \$HOME=/ (root) must still allow a genuine, nested checkpoint Read under it"

home36r_trail=$(new_home)
mkdir -p "$home36r_trail/.squirrel/checkpoints"
stdin36r_trail=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/proj36.md"}}' "$home36r_trail")
out36r_trail=$(printf '%s' "$stdin36r_trail" | HOME="$home36r_trail/" "$allow_checkpoint_script" 2>/dev/null) || true
decision36r_trail=$(printf '%s' "$out36r_trail" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision36r_trail="<jq error>"
assert_eq "allow" "$decision36r_trail" "S10-1: \$HOME carrying a trailing slash must still allow a genuine, nested checkpoint Read under it"

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
mkdir -p "$home37/.squirrel/off" "$home37/.squirrel/checkpoints"
touch "$home37/.squirrel/off/fresh-session-37"
touch "$home37/.squirrel/decoy-outside-off-37.txt"
touch "$home37/.squirrel/checkpoints/decoy-in-checkpoints-37.md"
stale_flag37="$home37/.squirrel/off/stale-session-37"
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
assert_file_exists "$home37/.squirrel/off/fresh-session-37" "a fresh off/ flag must survive pruning"
assert_file_exists "$home37/.squirrel/decoy-outside-off-37.txt" "pruning must NEVER touch a file outside off/, however old-looking its neighbours are"
assert_file_exists "$home37/.squirrel/checkpoints/decoy-in-checkpoints-37.md" "pruning must NEVER touch checkpoints/, even though it is a sibling of off/ under the same squirrel/ directory"

# Failure-safety: a permission-denied off/ directory must not fail the
# hook. Skipped (treated as a pass, not a false failure) on a machine
# where chmod cannot actually remove permissions for the invoking user
# (e.g. running as root, where every path is still readable/writable
# regardless of mode bits) - the assertion below only means something
# where chmod's effect is real.
home37b=$(new_home)
mkdir -p "$home37b/.squirrel/off"
locked_flag37b="$home37b/.squirrel/off/locked-37b"
touch -t 202001010000 "$locked_flag37b" 2>/dev/null || touch -d "30 days ago" "$locked_flag37b" 2>/dev/null || true
chmod 000 "$locked_flag37b" 2>/dev/null || true
chmod 500 "$home37b/.squirrel/off" 2>/dev/null || true
stdin37b=$(printf '{"cwd":"%s/project-prune-locked"}' "$home37b")
exit37b=$(capture_exit "$load_profile_script" "$home37b" "$stdin37b")
chmod 755 "$home37b/.squirrel/off" 2>/dev/null || true
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
mkdir -p "$fp4_home/.squirrel"
cat >"$fp4_home/.squirrel/profile.md" <<'EOF'
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
mkdir -p "$fp12_home/.squirrel/off"
touch "$fp12_home/.squirrel/decoy-outside-off.txt"
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
    Write | Edit | Read) ;;
    *) printf "defer"; return 0 ;;
  esac
  home_dir="${HOME:-}"
  checkpoints_dir="$home_dir/.squirrel/checkpoints"
  case "$file_path" in
    "$checkpoints_dir"/*) printf "allow" ;;
    *) printf "defer" ;;
  esac
  return 0
}'
replace_block "$fp16_script" "$fp16_start" "$fp16_end" "$fp16_naive_decide"

fp16_home=$(new_home)
fp16_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$fp16_home")
fp16_out=$(capture_stdout "$fp16_script" "$fp16_home" "$fp16_stdin")
fp16_decision=$(printf '%s' "$fp16_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp16_decision="<jq error>"
assert_eq "allow" "$fp16_decision" "FAILURE PROOF (scenario 16): a naive prefix-only mutant (no lexical '..' normalisation) must incorrectly ALLOW the traversal path - proving scenario 16's defer assertion is not vacuous"

# S10-1 Read mirror: the naive mutant's case statement now includes
# Read (so this isolates the SAME lexical-normalisation gap the mutant
# reintroduces, not merely "Read never reached the case statement").
fp16_stdin_r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../.ssh/id_rsa"}}' "$fp16_home")
fp16_out_r=$(capture_stdout "$fp16_script" "$fp16_home" "$fp16_stdin_r")
fp16_decision_r=$(printf '%s' "$fp16_out_r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp16_decision_r="<jq error>"
assert_eq "allow" "$fp16_decision_r" "S10-1 FAILURE PROOF (scenario 16 Read mirror): the same naive prefix-only mutant must incorrectly ALLOW the traversal path for tool_name Read too - proving the Read mirror's defer assertion is not vacuous"

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
    Write | Edit | Read) ;;
    *) printf "defer"; return 0 ;;
  esac
  home_dir="${HOME:-}"
  checkpoints_dir="$home_dir/.squirrel/checkpoints"
  case "$file_path" in
    "$checkpoints_dir"*) printf "allow" ;;
    *) printf "defer" ;;
  esac
  return 0
}'
replace_block "$fp17_script" "$fp17_start" "$fp17_end" "$fp17_naive_decide"

fp17_home=$(new_home)
fp17_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints-evil/x"}}' "$fp17_home")
fp17_out=$(capture_stdout "$fp17_script" "$fp17_home" "$fp17_stdin")
fp17_decision=$(printf '%s' "$fp17_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp17_decision="<jq error>"
assert_eq "allow" "$fp17_decision" "FAILURE PROOF (scenario 17): a naive prefix mutant with no trailing-slash boundary check must incorrectly ALLOW 'checkpoints-evil' - proving scenario 17's defer assertion is not vacuous"

# S10-1 Read mirror: same naive mutant, tool_name Read.
fp17_stdin_r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints-evil/x"}}' "$fp17_home")
fp17_out_r=$(capture_stdout "$fp17_script" "$fp17_home" "$fp17_stdin_r")
fp17_decision_r=$(printf '%s' "$fp17_out_r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp17_decision_r="<jq error>"
assert_eq "allow" "$fp17_decision_r" "S10-1 FAILURE PROOF (scenario 17 Read mirror): the same naive prefix mutant must incorrectly ALLOW 'checkpoints-evil' for tool_name Read too - proving the Read mirror's defer assertion is not vacuous"

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
mkdir -p "$fp25_home/.squirrel/checkpoints" "$fp25_home/outside-secret"
ln -s "$fp25_home/outside-secret" "$fp25_home/.squirrel/checkpoints/escape-dir"
fp25_strip_path=$(make_tool_path "realpath readlink")
fp25_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$fp25_home")
fp25_out=$(capture_stdout_with_path "$fp25_script" "$fp25_home" "$fp25_strip_path" "$fp25_stdin")
fp25_decision=$(printf '%s' "$fp25_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp25_decision="<jq error>"
assert_eq "allow" "$fp25_decision" "FAILURE PROOF (scenario 25): a mutant with the unconditional Layer-2 component walk removed must incorrectly ALLOW the symlink escape once realpath/readlink are also stripped from PATH - proving scenario 25's defer assertion is not vacuous, and reproducing the exact pre-fix MAJOR #3 bug"

# S10-1 Read mirror: fp25_script is a scratch copy of the REAL (fixed)
# allow-checkpoint.sh with the Layer-2 block deleted, so its case
# statement already includes Read - this isolates the Layer-2 removal
# itself as the cause, for a Read too, not merely "Read reaches the
# case statement".
fp25_stdin_r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/escape-dir/evil.md"}}' "$fp25_home")
fp25_out_r=$(capture_stdout_with_path "$fp25_script" "$fp25_home" "$fp25_strip_path" "$fp25_stdin_r")
fp25_decision_r=$(printf '%s' "$fp25_out_r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp25_decision_r="<jq error>"
assert_eq "allow" "$fp25_decision_r" "S10-1 FAILURE PROOF (scenario 25 Read mirror): a mutant with the unconditional Layer-2 component walk removed must incorrectly ALLOW the symlink escape for tool_name Read too, once realpath/readlink are also stripped from PATH"

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
mkdir -p "$fp27_home/.squirrel"
n_fp27=1
: >"$fp27_home/.squirrel/profile.md"
while [ "$n_fp27" -le 150 ]; do
  printf 'line%03d: marker\n' "$n_fp27" >>"$fp27_home/.squirrel/profile.md"
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
mkdir -p "$fp23_home/.squirrel"
fp23_bell=$(printf '\007')
printf '# squirrel-mode profile\nBEFORE_BELL%sAFTER_BELL\n' "$fp23_bell" >"$fp23_home/.squirrel/profile.md"
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
mkdir -p "$fp24_home/.squirrel"
fp24_n=1
: >"$fp24_home/.squirrel/profile.md"
while [ "$fp24_n" -le 2 ]; do
  printf 'field%02d: value\n' "$fp24_n" >>"$fp24_home/.squirrel/profile.md"
  fp24_n=$((fp24_n + 1))
done
printf '\377\376\200\201 TAIL_MARKER_SURVIVES_998877\n' >>"$fp24_home/.squirrel/profile.md"
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
mkdir -p "$fp26_home/.squirrel"
fp26_marker="UNDER_CAP_MARKER_FP_112233"
printf '# squirrel-mode profile\nlanguage: en\n%s\n' "$fp26_marker" >"$fp26_home/.squirrel/profile.md"
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
mkdir -p "$fp28_home/.squirrel"
fp28_long=$(awk 'BEGIN { s = ""; for (i = 0; i < 5000; i++) { s = s "X" }; print s }')
printf '%s TAIL_AFTER_BYTE_CAP_FP_223344\n' "$fp28_long" >"$fp28_home/.squirrel/profile.md"
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
mkdir -p "$fp2930_home/.squirrel" "$fp2930_home/outside-secret-fp"
ln -s "$fp2930_home/outside-secret-fp" "$fp2930_home/.squirrel/checkpoints"
fp2930_strip_path=$(make_tool_path "realpath readlink")
fp2930_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$fp2930_home")
fp2930_out=$(capture_stdout_with_path "$fp2930_script" "$fp2930_home" "$fp2930_strip_path" "$fp2930_stdin")
fp2930_decision=$(printf '%s' "$fp2930_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp2930_decision="<jq error>"
assert_eq "allow" "$fp2930_decision" "FAILURE PROOF (scenarios 29/30): a component_walk_has_symlink mutant that never tests checkpoints_dir itself must incorrectly ALLOW a write when checkpoints_dir itself is the symlink - proving scenarios 29/30's defer assertions are not vacuous, and reproducing the exact pre-fix BLOCKER"

# S10-1 Read mirror: fp2930_script is a scratch copy of the REAL
# (fixed) allow-checkpoint.sh with only the `[ -L "$base" ]` check
# removed, so its case statement already includes Read - isolating the
# checkpoints_dir-itself-symlink regression for tool_name Read too.
fp2930_stdin_r=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/evil.md"}}' "$fp2930_home")
fp2930_out_r=$(capture_stdout_with_path "$fp2930_script" "$fp2930_home" "$fp2930_strip_path" "$fp2930_stdin_r")
fp2930_decision_r=$(printf '%s' "$fp2930_out_r" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp2930_decision_r="<jq error>"
assert_eq "allow" "$fp2930_decision_r" "S10-1 FAILURE PROOF (scenarios 29/30 Read mirror): the same component_walk_has_symlink mutant must incorrectly ALLOW a Read when checkpoints_dir itself is the symlink"

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
mkdir -p "$fp34_home/.squirrel"
fp34_head="HEAD_MARKER_BEFORE_CUT_778899"
fp34_filler_len=$((4094 - ${#fp34_head}))
fp34_filler=$(awk -v n="$fp34_filler_len" 'BEGIN { s = ""; for (i = 0; i < n; i++) { s = s "X" }; print s }')
printf '%s%s\342\202\254TAIL_AFTER_UTF8_CUT_665544\n' "$fp34_head" "$fp34_filler" >"$fp34_home/.squirrel/profile.md"
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

# ==========================================================================
# 38. check-off-flag.sh - ADR-0005 (amended): a PENDING.<random> sentinel
#     whose contents match THIS invocation's cwd is claimed (renamed to
#     off/<session_id>), and the counter-instruction fires on the SAME
#     invocation that does the claiming - not merely on some later
#     prompt. A single call captures both stdout and the exit code, so
#     the claim and the injection are proven to come from one call, not
#     two calls that would let the first one's side effect quietly
#     satisfy the second.
# ==========================================================================
home38=$(new_home)
mkdir -p "$home38/.squirrel/off"
cwd38="$home38/project-pending-match-38"
pending38="$home38/.squirrel/off/PENDING.matchtoken38"
printf '%s\n' "$cwd38" >"$pending38"
stdin38=$(printf '{"session_id":"sess-pending-38","cwd":"%s"}' "$cwd38")

if out38=$(printf '%s' "$stdin38" | HOME="$home38" "$check_off_flag_script" 2>/dev/null); then
  exit38=0
else
  exit38=$?
fi
assert_eq "0" "$exit38" "check-off-flag.sh must exit 0 for the single invocation that claims a matching PENDING sentinel"
assert_contains "$out38" "squirrel-mode is OFF" "ADR-0005: the counter-instruction must fire on the SAME invocation that claims a matching PENDING sentinel, not merely on some later prompt"
assert_file_exists "$home38/.squirrel/off/sess-pending-38" "ADR-0005: a matching PENDING sentinel must be renamed to off/<session_id>"
assert_file_absent "$pending38" "ADR-0005: the original PENDING sentinel must no longer exist after being claimed"

# ==========================================================================
# 39. check-off-flag.sh - ADR-0005: a PENDING sentinel whose recorded cwd
#     does NOT match this invocation's cwd must NOT be claimed - no
#     rename, no off/<session_id> flag, no counter-instruction.
# ==========================================================================
home39=$(new_home)
mkdir -p "$home39/.squirrel/off"
cwd39_actual="$home39/project-real-39"
cwd39_pending="$home39/project-different-39"
pending39="$home39/.squirrel/off/PENDING.mismatch39"
printf '%s\n' "$cwd39_pending" >"$pending39"
stdin39=$(printf '{"session_id":"sess-mismatch-39","cwd":"%s"}' "$cwd39_actual")

exit39=$(capture_exit "$check_off_flag_script" "$home39" "$stdin39")
assert_eq "0" "$exit39" "check-off-flag.sh must exit 0 when a PENDING sentinel's cwd does not match this invocation's cwd"

out39=$(capture_stdout "$check_off_flag_script" "$home39" "$stdin39")
assert_eq "" "$out39" "ADR-0005: a cwd-mismatched PENDING sentinel must not be claimed, so no counter-instruction fires"
assert_file_exists "$pending39" "ADR-0005: a cwd-mismatched PENDING sentinel must survive untouched (not renamed)"
assert_file_absent "$home39/.squirrel/off/sess-mismatch-39" "ADR-0005: no off/<session_id> flag must be created from a cwd-mismatched PENDING sentinel"

# ==========================================================================
# 40. check-off-flag.sh - ADR-0005: two PENDING sentinels for different
#     directories present at once - only the one matching THIS
#     invocation's cwd is claimed; the other is left exactly as it was.
# ==========================================================================
home40=$(new_home)
mkdir -p "$home40/.squirrel/off"
cwd40_a="$home40/project-a-40"
cwd40_b="$home40/project-b-40"
pending40_a="$home40/.squirrel/off/PENDING.dirA40"
pending40_b="$home40/.squirrel/off/PENDING.dirB40"
printf '%s\n' "$cwd40_a" >"$pending40_a"
printf '%s\n' "$cwd40_b" >"$pending40_b"
stdin40=$(printf '{"session_id":"sess-two-pending-40","cwd":"%s"}' "$cwd40_b")

exit40=$(capture_exit "$check_off_flag_script" "$home40" "$stdin40")
assert_eq "0" "$exit40" "check-off-flag.sh must exit 0 with two competing PENDING sentinels present"

assert_file_absent "$pending40_b" "ADR-0005: the PENDING sentinel matching THIS invocation's cwd must be claimed (removed by rename)"
assert_file_exists "$pending40_a" "ADR-0005: a PENDING sentinel for a DIFFERENT directory must be left untouched when another one matches"
assert_file_exists "$home40/.squirrel/off/sess-two-pending-40" "ADR-0005: the matching PENDING sentinel must be renamed to off/<session_id>"

# ==========================================================================
# 41. check-off-flag.sh - ADR-0005: a matching CLEAR sentinel removes an
#     existing off/<session_id> flag, and the deletion happens before the
#     existence check in the SAME invocation (no counter-instruction from
#     that same call either).
# ==========================================================================
home41=$(new_home)
mkdir -p "$home41/.squirrel/off"
touch "$home41/.squirrel/off/sess-clear-41"
cwd41="$home41/project-clear-41"
clear41="$home41/.squirrel/off/CLEAR.token41"
printf '%s\n' "$cwd41" >"$clear41"
stdin41=$(printf '{"session_id":"sess-clear-41","cwd":"%s"}' "$cwd41")

if out41=$(printf '%s' "$stdin41" | HOME="$home41" "$check_off_flag_script" 2>/dev/null); then
  exit41=0
else
  exit41=$?
fi
assert_eq "0" "$exit41" "check-off-flag.sh must exit 0 for the single invocation that claims a matching CLEAR sentinel"
assert_eq "" "$out41" "ADR-0005: once a matching CLEAR sentinel removes the off flag, no counter-instruction must fire, even on the claiming invocation itself"
assert_file_absent "$home41/.squirrel/off/sess-clear-41" "ADR-0005: a matching CLEAR sentinel must delete the existing off/<session_id> flag"
assert_file_absent "$clear41" "ADR-0005: the CLEAR sentinel itself must be deleted once claimed"

# ==========================================================================
# 42. check-off-flag.sh - ADR-0005: a symlinked sentinel must be ignored
#     outright (same posture as allow-checkpoint.sh's own `[ -L ]`
#     defence), regardless of what it points at. Two sub-cases: a
#     symlinked PENDING and a symlinked CLEAR, both pointing at a file
#     whose contents WOULD otherwise match this invocation's cwd exactly
#     - proving the rejection is the symlink check itself, not a content
#     mismatch.
# ==========================================================================
home42=$(new_home)
mkdir -p "$home42/.squirrel/off"
cwd42="$home42/project-symlink-42"
real_pending42="$home42/.squirrel/real-pending-content-42"
printf '%s\n' "$cwd42" >"$real_pending42"
ln -s "$real_pending42" "$home42/.squirrel/off/PENDING.symlinked42"
stdin42a=$(printf '{"session_id":"sess-symlink-pending-42","cwd":"%s"}' "$cwd42")

exit42a=$(capture_exit "$check_off_flag_script" "$home42" "$stdin42a")
assert_eq "0" "$exit42a" "check-off-flag.sh must exit 0 with a symlinked PENDING sentinel present"
out42a=$(capture_stdout "$check_off_flag_script" "$home42" "$stdin42a")
assert_eq "" "$out42a" "ADR-0005: a symlinked PENDING sentinel must be ignored even when its target's content matches this invocation's cwd exactly"
assert_file_exists "$home42/.squirrel/off/PENDING.symlinked42" "ADR-0005: a symlinked PENDING sentinel must survive untouched, never renamed"
assert_file_absent "$home42/.squirrel/off/sess-symlink-pending-42" "ADR-0005: a symlinked PENDING sentinel must never result in a claimed off/<session_id> flag"

touch "$home42/.squirrel/off/sess-symlink-clear-42"
real_clear42="$home42/.squirrel/real-clear-content-42"
printf '%s\n' "$cwd42" >"$real_clear42"
ln -s "$real_clear42" "$home42/.squirrel/off/CLEAR.symlinked42"
stdin42b=$(printf '{"session_id":"sess-symlink-clear-42","cwd":"%s"}' "$cwd42")

exit42b=$(capture_exit "$check_off_flag_script" "$home42" "$stdin42b")
assert_eq "0" "$exit42b" "check-off-flag.sh must exit 0 with a symlinked CLEAR sentinel present"
out42b=$(capture_stdout "$check_off_flag_script" "$home42" "$stdin42b")
assert_contains "$out42b" "squirrel-mode is OFF" "ADR-0005: a symlinked CLEAR sentinel must be ignored, leaving the existing off/<session_id> flag (and its counter-instruction) in place"
assert_file_exists "$home42/.squirrel/off/sess-symlink-clear-42" "ADR-0005: a symlinked CLEAR sentinel must never delete an existing off/<session_id> flag"
assert_file_exists "$home42/.squirrel/off/CLEAR.symlinked42" "ADR-0005: a symlinked CLEAR sentinel must survive untouched, never deleted"

# ==========================================================================
# 43. check-off-flag.sh - ADR-0005: when session_id sanitisation fails,
#     every sentinel under off/ - PENDING, CLEAR, and an existing
#     off/<session_id> flag belonging to some other session - must be
#     left completely untouched, for a later, valid invocation.
# ==========================================================================
home43=$(new_home)
mkdir -p "$home43/.squirrel/off"
cwd43="$home43/project-sanitize-fail-43"
pending43="$home43/.squirrel/off/PENDING.sanitizefail43"
printf '%s\n' "$cwd43" >"$pending43"
clear43="$home43/.squirrel/off/CLEAR.sanitizefail43b"
printf '%s\n' "$cwd43" >"$clear43"
touch "$home43/.squirrel/off/existing-flag-43"
stdin43=$(printf '{"session_id":"../traversal-attempt-43","cwd":"%s"}' "$cwd43")

exit43=$(capture_exit "$check_off_flag_script" "$home43" "$stdin43")
assert_eq "0" "$exit43" "check-off-flag.sh must exit 0 when session_id sanitisation fails"
out43=$(capture_stdout "$check_off_flag_script" "$home43" "$stdin43")
assert_eq "" "$out43" "check-off-flag.sh must print nothing when session_id sanitisation fails"
assert_file_exists "$pending43" "ADR-0005: a sanitisation failure must leave a pending PENDING sentinel untouched for a later, valid invocation"
assert_file_exists "$clear43" "ADR-0005: a sanitisation failure must leave a pending CLEAR sentinel untouched for a later, valid invocation"
assert_file_exists "$home43/.squirrel/off/existing-flag-43" "ADR-0005: a sanitisation failure must not disturb an existing off/<session_id> flag belonging to some other session"

# ==========================================================================
# FAILURE PROOFS for scenarios 39 and 41 (Definition-of-done proofs:
# "PENDING cwd-mismatch not claimed" and "CLEAR removing a flag").
# ==========================================================================

# --- Failure proof for scenario 39: the cwd comparison in claim_pending
# is what actually keeps a mismatched PENDING sentinel from being
# claimed. Reintroduces a claim_pending that claims UNCONDITIONALLY,
# ignoring cwd entirely, and confirms the mismatched sentinel from
# scenario 39's own fixture gets claimed anyway.
# ==========================================================================
fp39_script=$(make_script_scratch "$check_off_flag_script")
# shellcheck disable=SC2016 # single-quoted deliberately throughout this
# block: literal source text/replacement for check-off-flag.sh.
fp39_start=$(line_of "$fp39_script" 'claim_pending() {')
[ -n "$fp39_start" ] || fp39_start=0
fp39_end=$(line_of_after "$fp39_script" "$fp39_start" '}')
[ -n "$fp39_end" ] || fp39_end=0
# shellcheck disable=SC2016
fp39_unconditional_claim='claim_pending() {
  off_dir=$1
  session_id=$2
  cwd=$3
  for f in "$off_dir"/PENDING.*; do
    [ -e "$f" ] || continue
    mv -- "$f" "$off_dir/$session_id" 2>/dev/null || true
  done
  return 0
}'
replace_block "$fp39_script" "$fp39_start" "$fp39_end" "$fp39_unconditional_claim"

fp39_home=$(new_home)
mkdir -p "$fp39_home/.squirrel/off"
fp39_cwd_actual="$fp39_home/project-real-fp39"
fp39_cwd_pending="$fp39_home/project-different-fp39"
fp39_pending="$fp39_home/.squirrel/off/PENDING.mismatchfp39"
printf '%s\n' "$fp39_cwd_pending" >"$fp39_pending"
fp39_stdin=$(printf '{"session_id":"sess-mismatch-fp39","cwd":"%s"}' "$fp39_cwd_actual")
capture_stdout "$fp39_script" "$fp39_home" "$fp39_stdin" >/dev/null

if [ -f "$fp39_home/.squirrel/off/sess-mismatch-fp39" ]; then
  fp39_wrongly_claimed=yes
else
  fp39_wrongly_claimed=no
fi
assert_eq "yes" "$fp39_wrongly_claimed" "FAILURE PROOF (scenario 39): a claim_pending mutant with the cwd comparison removed must claim a cwd-MISMATCHED PENDING sentinel anyway - proving scenario 39's 'must not be claimed' assertion is not vacuous"

# --- Failure proof for scenario 41: claim_clear is what actually removes
# an existing off/<session_id> flag on a matching CLEAR sentinel.
# Reintroduces a decide() with the claim_clear call removed entirely (the
# function stays defined but unused), so a matching CLEAR sentinel is
# left inert and the flag survives.
# ==========================================================================
fp41_script=$(make_script_scratch "$check_off_flag_script")
# shellcheck disable=SC2016
fp41_line=$(line_of "$fp41_script" '  claim_clear "$off_dir" "$session_id" "$cwd"')
[ -n "$fp41_line" ] || fp41_line=0
replace_line "$fp41_script" "$fp41_line" ''

fp41_home=$(new_home)
mkdir -p "$fp41_home/.squirrel/off"
touch "$fp41_home/.squirrel/off/sess-clear-fp41"
fp41_cwd="$fp41_home/project-clear-fp41"
fp41_clear="$fp41_home/.squirrel/off/CLEAR.tokenfp41"
printf '%s\n' "$fp41_cwd" >"$fp41_clear"
fp41_stdin=$(printf '{"session_id":"sess-clear-fp41","cwd":"%s"}' "$fp41_cwd")
capture_stdout "$fp41_script" "$fp41_home" "$fp41_stdin" >/dev/null

if [ -f "$fp41_home/.squirrel/off/sess-clear-fp41" ]; then
  fp41_flag_survived=yes
else
  fp41_flag_survived=no
fi
assert_eq "yes" "$fp41_flag_survived" "FAILURE PROOF (scenario 41): a decide() mutant with the claim_clear call removed must leave an existing off/<session_id> flag in place despite a matching CLEAR sentinel - proving scenario 41's 'must delete the existing flag' assertion is not vacuous"

# ==========================================================================
# 44. load-profile.sh - cycle-3 BLOCKER fix: additionalContext must
#     contain the literal `cwd` this hook was invoked with, as a
#     "Session working directory: <cwd>" line - the exact value
#     /squirrel:off and /squirrel:on now write into their sentinels
#     verbatim, so a model-computed value (e.g. by running a shell
#     command itself) can never disagree with what check-off-flag.sh
#     compares against. Parallel to scenarios 3/4's own checkpoint-path
#     checks.
# ==========================================================================
home44=$(new_home)
cwd44="$home44/project-cwd-line-44"
stdin44=$(printf '{"cwd":"%s"}' "$cwd44")

out44=$(capture_stdout "$load_profile_script" "$home44" "$stdin44")
ctx44=$(extract_ctx "$out44")
assert_contains "$ctx44" "Session working directory: $cwd44" "BLOCKER fix: additionalContext must contain the literal 'Session working directory: <cwd>' line, matching the cwd this invocation was given verbatim"

exit44=$(capture_exit "$load_profile_script" "$home44" "$stdin44")
assert_eq "0" "$exit44" "load-profile.sh must exit 0 while emitting the Session working directory line"

# ==========================================================================
# 45. load-profile.sh - cycle-3 BLOCKER fix: the "Session working
#     directory:" line is emitted deterministically even when `cwd` is
#     empty or absent from stdin entirely, so the skill has a definite,
#     ALWAYS-PRESENT line to branch a "missing or empty" case on -
#     mirroring how /squirrel:pickup handles an absent checkpoint-path
#     line - rather than a line that sometimes does not exist at all.
# ==========================================================================
home45=$(new_home)

out45_empty=$(capture_stdout "$load_profile_script" "$home45" '{"cwd":""}')
ctx45_empty=$(extract_ctx "$out45_empty")
assert_contains "$ctx45_empty" "Session working directory:" "BLOCKER fix: the Session working directory line must still be emitted when cwd is an empty string"

out45_absent=$(capture_stdout "$load_profile_script" "$home45" '{"session_id":"s"}')
ctx45_absent=$(extract_ctx "$out45_absent")
assert_contains "$ctx45_absent" "Session working directory:" "BLOCKER fix: the Session working directory line must still be emitted when cwd is absent from stdin entirely"

# --- Failure proof for scenario 44: confirms the assertion is actually
# bound to the real emission site, not some other coincidental text.
# ==========================================================================
fp44_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016
fp44_line=$(line_of "$fp44_script" 'Session working directory: $cwd')
[ -n "$fp44_line" ] || fp44_line=0
replace_line "$fp44_script" "$fp44_line" ''

fp44_home=$(new_home)
fp44_cwd="$fp44_home/project-cwd-line-fp44"
fp44_stdin=$(printf '{"cwd":"%s"}' "$fp44_cwd")
fp44_ctx=$(extract_ctx "$(capture_stdout "$fp44_script" "$fp44_home" "$fp44_stdin")")
assert_not_contains "$fp44_ctx" "Session working directory:" "FAILURE PROOF (scenario 44): removing the 'Session working directory: \$cwd' line from a scratch copy must make it disappear from additionalContext - proving scenario 44 is not vacuous"

# ==========================================================================
# 46. check-off-flag.sh - cycle-3 MAJOR fix: a PENDING sentinel with TWO
#     trailing newline bytes must NOT be claimed. Reproduces the
#     reviewer's exact repro: `printf '%s\n\n' "$CWD" > off/PENDING.x`.
#     Before the fix, both read_sentinel_exact's protective "X" trick
#     and trim_one_trailing_newline's "at most one" logic were defeated
#     by the SECOND command substitution at the call site, which
#     stripped every trailing newline unconditionally.
# ==========================================================================
home46=$(new_home)
mkdir -p "$home46/.squirrel/off"
cwd46="$home46/project-two-trailing-nl-46"
pending46="$home46/.squirrel/off/PENDING.twonl46"
printf '%s\n\n' "$cwd46" >"$pending46"
stdin46=$(printf '{"session_id":"sess-twonl-46","cwd":"%s"}' "$cwd46")

exit46=$(capture_exit "$check_off_flag_script" "$home46" "$stdin46")
assert_eq "0" "$exit46" "check-off-flag.sh must exit 0 for a PENDING sentinel with two trailing newlines"
out46=$(capture_stdout "$check_off_flag_script" "$home46" "$stdin46")
assert_eq "" "$out46" "MAJOR fix: a PENDING sentinel with TWO trailing newlines must NOT be claimed - its trimmed contents (after removing only one) still end in a newline byte the cwd itself never has"
assert_file_exists "$pending46" "MAJOR fix: a PENDING sentinel with two trailing newlines must survive untouched, not be renamed"
assert_file_absent "$home46/.squirrel/off/sess-twonl-46" "MAJOR fix: no off/<session_id> flag must be created from a PENDING sentinel with two trailing newlines"

# ==========================================================================
# 47. check-off-flag.sh - cycle-3 MAJOR fix: the same repro as scenario
#     46, with THREE trailing newlines - "at most one trimmed" must hold
#     for any number greater than one, not merely for exactly two.
# ==========================================================================
home47=$(new_home)
mkdir -p "$home47/.squirrel/off"
cwd47="$home47/project-three-trailing-nl-47"
pending47="$home47/.squirrel/off/PENDING.threenl47"
printf '%s\n\n\n' "$cwd47" >"$pending47"
stdin47=$(printf '{"session_id":"sess-threenl-47","cwd":"%s"}' "$cwd47")

exit47=$(capture_exit "$check_off_flag_script" "$home47" "$stdin47")
assert_eq "0" "$exit47" "check-off-flag.sh must exit 0 for a PENDING sentinel with three trailing newlines"
out47=$(capture_stdout "$check_off_flag_script" "$home47" "$stdin47")
assert_eq "" "$out47" "MAJOR fix: a PENDING sentinel with THREE trailing newlines must NOT be claimed"
assert_file_exists "$pending47" "MAJOR fix: a PENDING sentinel with three trailing newlines must survive untouched"

# ==========================================================================
# 48. check-off-flag.sh - cycle-3 MAJOR fix sanity: exactly ONE trailing
#     newline (the normal, expected case /squirrel:off itself writes)
#     must still be claimed - the fix must not become overzealous and
#     start rejecting the ordinary case along with the malformed one.
# ==========================================================================
home48=$(new_home)
mkdir -p "$home48/.squirrel/off"
cwd48="$home48/project-one-trailing-nl-48"
pending48="$home48/.squirrel/off/PENDING.onenl48"
printf '%s\n' "$cwd48" >"$pending48"
stdin48=$(printf '{"session_id":"sess-onenl-48","cwd":"%s"}' "$cwd48")

out48=$(capture_stdout "$check_off_flag_script" "$home48" "$stdin48")
assert_contains "$out48" "squirrel-mode is OFF" "MAJOR fix sanity: a PENDING sentinel with EXACTLY one trailing newline must still be claimed"
assert_file_exists "$home48/.squirrel/off/sess-onenl-48" "MAJOR fix sanity: exactly one trailing newline must still result in a claimed off/<session_id> flag"
assert_file_absent "$pending48" "MAJOR fix sanity: the claimed PENDING sentinel with exactly one trailing newline must no longer exist as PENDING.*"

# --- Failure proof for scenario 46: reproduces the HISTORICAL BUG'S
# VISIBLE EFFECT - a single unconditional command substitution collapsing
# ALL trailing newlines, exactly what happened when the old caller wrapped
# an already-safe read in a second `$(...)` - and confirms it wrongly
# claims the two-trailing-newline sentinel scenario 46 uses. Patches only
# claim_pending's own call to read_sentinel_trimmed (the first occurrence
# in the file), leaving the champion-precompute logic untouched and
# correct, to isolate the proof to the exact call site the bug lived in.
# ==========================================================================
fp46_script=$(make_script_scratch "$check_off_flag_script")
# shellcheck disable=SC2016
fp46_line=$(line_of "$fp46_script" '    read_sentinel_trimmed "$f"')
[ -n "$fp46_line" ] || fp46_line=0
# shellcheck disable=SC2016
replace_line "$fp46_script" "$fp46_line" '    SENTINEL_CONTENTS=$(cat "$f" 2>/dev/null)'

fp46_home=$(new_home)
mkdir -p "$fp46_home/.squirrel/off"
fp46_cwd="$fp46_home/project-two-trailing-nl-fp46"
fp46_pending="$fp46_home/.squirrel/off/PENDING.twonlfp46"
printf '%s\n\n' "$fp46_cwd" >"$fp46_pending"
fp46_stdin=$(printf '{"session_id":"sess-twonl-fp46","cwd":"%s"}' "$fp46_cwd")
capture_stdout "$fp46_script" "$fp46_home" "$fp46_stdin" >/dev/null

if [ -f "$fp46_home/.squirrel/off/sess-twonl-fp46" ]; then
  fp46_wrongly_claimed=yes
else
  fp46_wrongly_claimed=no
fi
assert_eq "yes" "$fp46_wrongly_claimed" "FAILURE PROOF (scenario 46): a claim_pending mutant using a single unconditional command substitution (the historical bug's visible effect) must wrongly claim a two-trailing-newline PENDING sentinel - proving scenario 46's 'must not be claimed' assertion is not vacuous"

# ==========================================================================
# 49. check-off-flag.sh - ADR-0005 (amended) MAJOR fix: when a matching
#     PENDING sentinel is NEWER than a matching CLEAR sentinel for the
#     same cwd, PENDING wins - the session ends up OFF. This is the
#     reviewer's exact repro (already off, /squirrel:on then
#     /squirrel:off before any prompt) landing correctly this time: a
#     fixed claim-order used to always let CLEAR win regardless of which
#     one the user actually issued last.
# ==========================================================================
home49=$(new_home)
mkdir -p "$home49/.squirrel/off"
cwd49="$home49/project-newer-wins-49"
clear49="$home49/.squirrel/off/CLEAR.older49"
pending49="$home49/.squirrel/off/PENDING.newer49"
printf '%s\n' "$cwd49" >"$clear49"
touch -t 202001010000 "$clear49" 2>/dev/null || touch -d "30 days ago" "$clear49" 2>/dev/null || true
printf '%s\n' "$cwd49" >"$pending49"
stdin49=$(printf '{"session_id":"sess-newerwins-49","cwd":"%s"}' "$cwd49")

exit49=$(capture_exit "$check_off_flag_script" "$home49" "$stdin49")
assert_eq "0" "$exit49" "check-off-flag.sh must exit 0 when both a PENDING and a CLEAR sentinel match the same cwd"
out49=$(capture_stdout "$check_off_flag_script" "$home49" "$stdin49")
assert_contains "$out49" "squirrel-mode is OFF" "MAJOR fix: ADR-0005 - when the PENDING sentinel is newer than the CLEAR sentinel, PENDING must win: the session ends up OFF"
assert_file_exists "$home49/.squirrel/off/sess-newerwins-49" "MAJOR fix: the newer PENDING sentinel must be claimed (renamed to off/<session_id>) when it outdates a competing CLEAR sentinel"
assert_file_absent "$pending49" "MAJOR fix: the winning PENDING sentinel must no longer exist as PENDING.* after being claimed"
assert_file_absent "$clear49" "MAJOR fix: the losing (older) CLEAR sentinel must be discarded, not left in place to re-fire on a later prompt"

# ==========================================================================
# 50. check-off-flag.sh - ADR-0005 (amended) MAJOR fix: the mirror of
#     scenario 49 - when a matching CLEAR sentinel is NEWER than a
#     matching PENDING sentinel for the same cwd, CLEAR wins - the
#     session ends up ON, even though it was off going into this
#     invocation.
# ==========================================================================
home50=$(new_home)
mkdir -p "$home50/.squirrel/off"
touch "$home50/.squirrel/off/sess-newerwins-50"
cwd50="$home50/project-newer-wins-50"
pending50="$home50/.squirrel/off/PENDING.older50"
clear50="$home50/.squirrel/off/CLEAR.newer50"
printf '%s\n' "$cwd50" >"$pending50"
touch -t 202001010000 "$pending50" 2>/dev/null || touch -d "30 days ago" "$pending50" 2>/dev/null || true
printf '%s\n' "$cwd50" >"$clear50"
stdin50=$(printf '{"session_id":"sess-newerwins-50","cwd":"%s"}' "$cwd50")

exit50=$(capture_exit "$check_off_flag_script" "$home50" "$stdin50")
assert_eq "0" "$exit50" "check-off-flag.sh must exit 0 when both a PENDING and a CLEAR sentinel match the same cwd"
out50=$(capture_stdout "$check_off_flag_script" "$home50" "$stdin50")
assert_eq "" "$out50" "MAJOR fix: ADR-0005 - when the CLEAR sentinel is newer than the PENDING sentinel, CLEAR must win: the session ends up ON, even though it was off going into this invocation"
assert_file_absent "$home50/.squirrel/off/sess-newerwins-50" "MAJOR fix: the pre-existing off flag must be removed once the newer CLEAR sentinel wins"
assert_file_absent "$clear50" "MAJOR fix: the winning CLEAR sentinel must be consumed (deleted) after claiming"
assert_file_absent "$pending50" "MAJOR fix: the losing (older) PENDING sentinel must be discarded, not left in place to re-fire on a later prompt"

# ==========================================================================
# 51. check-off-flag.sh - ADR-0005 (amended) MAJOR fix: on an EXACT
#     mtime tie between a matching PENDING and a matching CLEAR
#     sentinel, PENDING wins - a user asking to turn squirrel-mode off
#     is reporting the formatting is actively in their way, and that
#     reading takes priority. `touch -r` forces the tie deterministically
#     (no reliance on filesystem mtime resolution or timing races).
# ==========================================================================
home51=$(new_home)
mkdir -p "$home51/.squirrel/off"
cwd51="$home51/project-newer-wins-tie-51"
pending51="$home51/.squirrel/off/PENDING.tie51"
clear51="$home51/.squirrel/off/CLEAR.tie51"
printf '%s\n' "$cwd51" >"$pending51"
printf '%s\n' "$cwd51" >"$clear51"
touch -r "$pending51" "$clear51"
stdin51=$(printf '{"session_id":"sess-tie-51","cwd":"%s"}' "$cwd51")

exit51=$(capture_exit "$check_off_flag_script" "$home51" "$stdin51")
assert_eq "0" "$exit51" "check-off-flag.sh must exit 0 when a PENDING and a CLEAR sentinel match the same cwd with an exact mtime tie"
out51=$(capture_stdout "$check_off_flag_script" "$home51" "$stdin51")
assert_contains "$out51" "squirrel-mode is OFF" "MAJOR fix: ADR-0005 - on an EXACT mtime tie between a matching PENDING and CLEAR sentinel, PENDING must win: the session ends up OFF"
assert_file_exists "$home51/.squirrel/off/sess-tie-51" "MAJOR fix: on a tie, the PENDING sentinel must be claimed"
assert_file_absent "$clear51" "MAJOR fix: on a tie, the CLEAR sentinel must be discarded, not left in place"

# ==========================================================================
# 52. check-off-flag.sh - MINOR (missing coverage): a directory that
#     happens to match the PENDING.* glob must be ignored outright, the
#     same posture is_unclaimable_sentinel already takes for a symlink.
# ==========================================================================
home52=$(new_home)
mkdir -p "$home52/.squirrel/off"
cwd52="$home52/project-dirsentinel-52"
mkdir -p "$home52/.squirrel/off/PENDING.dirshaped52"
stdin52=$(printf '{"session_id":"sess-dirshaped-52","cwd":"%s"}' "$cwd52")

exit52=$(capture_exit "$check_off_flag_script" "$home52" "$stdin52")
assert_eq "0" "$exit52" "check-off-flag.sh must exit 0 when a directory happens to match the PENDING.* glob"
out52=$(capture_stdout "$check_off_flag_script" "$home52" "$stdin52")
assert_eq "" "$out52" "MINOR: a directory-shaped entry matching PENDING.* must be ignored, not treated as a sentinel"
if [ -d "$home52/.squirrel/off/PENDING.dirshaped52" ]; then
  dirshaped52_survived=yes
else
  dirshaped52_survived=no
fi
assert_eq "yes" "$dirshaped52_survived" "MINOR: a directory-shaped PENDING.* entry must survive untouched (assert_file_exists uses '-f', which a directory fails, so this checks '-d' directly)"

# ==========================================================================
# 53. check-off-flag.sh - MINOR (missing coverage): an empty or entirely
#     absent cwd must claim nothing, even against a sentinel whose own
#     (malformed) content is also empty.
# ==========================================================================
home53=$(new_home)
mkdir -p "$home53/.squirrel/off"
pending53="$home53/.squirrel/off/PENDING.emptycwd53"
printf '\n' >"$pending53"
stdin53_empty=$(printf '{"session_id":"sess-emptycwd-53","cwd":""}')
exit53_empty=$(capture_exit "$check_off_flag_script" "$home53" "$stdin53_empty")
assert_eq "0" "$exit53_empty" "check-off-flag.sh must exit 0 when cwd is an empty string"
out53_empty=$(capture_stdout "$check_off_flag_script" "$home53" "$stdin53_empty")
assert_eq "" "$out53_empty" "MINOR: an empty cwd must claim nothing, even against a sentinel whose own trimmed content is also empty"
assert_file_exists "$pending53" "MINOR: a sentinel must survive when the invocation's own cwd is empty"

stdin53_absent=$(printf '{"session_id":"sess-emptycwd-53b"}')
exit53_absent=$(capture_exit "$check_off_flag_script" "$home53" "$stdin53_absent")
assert_eq "0" "$exit53_absent" "check-off-flag.sh must exit 0 when cwd is absent from stdin entirely"
out53_absent=$(capture_stdout "$check_off_flag_script" "$home53" "$stdin53_absent")
assert_eq "" "$out53_absent" "MINOR: an absent cwd must claim nothing"

# ==========================================================================
# 54. check-off-flag.sh - MINOR (missing coverage): a matching CLEAR
#     sentinel with NO existing off/<session_id> flag to remove must
#     still exit 0, print nothing, and still consume the sentinel.
# ==========================================================================
home54=$(new_home)
mkdir -p "$home54/.squirrel/off"
cwd54="$home54/project-clear-noexisting-54"
clear54="$home54/.squirrel/off/CLEAR.noexisting54"
printf '%s\n' "$cwd54" >"$clear54"
stdin54=$(printf '{"session_id":"sess-clearnoexisting-54","cwd":"%s"}' "$cwd54")

exit54=$(capture_exit "$check_off_flag_script" "$home54" "$stdin54")
assert_eq "0" "$exit54" "MINOR: check-off-flag.sh must exit 0 for a matching CLEAR sentinel when no off/<session_id> flag exists to remove"
out54=$(capture_stdout "$check_off_flag_script" "$home54" "$stdin54")
assert_eq "" "$out54" "MINOR: no counter-instruction fires when a CLEAR sentinel is claimed and there was no flag to begin with"
assert_file_absent "$clear54" "MINOR: the CLEAR sentinel itself must still be consumed even when there was no flag to remove"

# ==========================================================================
# 55. check-off-flag.sh - MINOR (missing coverage): a sentinel FILENAME
#     containing a space and a shell metacharacter must still be
#     processed correctly - file_path/filenames are opaque text here,
#     the same posture allow-checkpoint.sh's own scenario 35 exercises.
# ==========================================================================
home55=$(new_home)
mkdir -p "$home55/.squirrel/off"
cwd55="$home55/project-metachar-55"
# Built from separately-quoted segments, exactly like allow-checkpoint.sh's
# own scenario 35 fixtures, so the literal '$(' text is never live shell
# syntax at any point in THIS test file either.
# shellcheck disable=SC2016
pending55="$home55/.squirrel/off/PENDING.odd name"'$(x)'"55"
printf '%s\n' "$cwd55" >"$pending55"
stdin55=$(printf '{"session_id":"sess-metachar-55","cwd":"%s"}' "$cwd55")

exit55=$(capture_exit "$check_off_flag_script" "$home55" "$stdin55")
assert_eq "0" "$exit55" "MINOR: check-off-flag.sh must exit 0 for a sentinel filename containing a space and a shell metacharacter"
out55=$(capture_stdout "$check_off_flag_script" "$home55" "$stdin55")
assert_contains "$out55" "squirrel-mode is OFF" "MINOR: a PENDING sentinel whose FILENAME contains a space and a shell metacharacter must still be claimed normally when its content matches cwd"
assert_file_exists "$home55/.squirrel/off/sess-metachar-55" "MINOR: the odd-named PENDING sentinel must still be claimed (renamed) correctly"
assert_file_absent "$pending55" "MINOR: the odd-named PENDING sentinel must no longer exist after being claimed"

# ==========================================================================
# 56. check-off-flag.sh - MINOR (missing coverage): off/<session_id>
#     ITSELF is a symlink pointing outside off/ entirely. A matching
#     CLEAR sentinel must unlink the symlink (never follow it), and the
#     file it points at must survive completely untouched.
# ==========================================================================
home56=$(new_home)
mkdir -p "$home56/.squirrel/off" "$home56/outside-target-56"
target56="$home56/outside-target-56/real-flag-56"
touch "$target56"
ln -s "$target56" "$home56/.squirrel/off/sess-symlinkflag-56"
cwd56="$home56/project-symlinkflag-56"
clear56="$home56/.squirrel/off/CLEAR.symlinkflag56"
printf '%s\n' "$cwd56" >"$clear56"
stdin56=$(printf '{"session_id":"sess-symlinkflag-56","cwd":"%s"}' "$cwd56")

exit56=$(capture_exit "$check_off_flag_script" "$home56" "$stdin56")
assert_eq "0" "$exit56" "MINOR: check-off-flag.sh must exit 0 when off/<session_id> itself is a symlink pointing outside off/"
out56=$(capture_stdout "$check_off_flag_script" "$home56" "$stdin56")
assert_eq "" "$out56" "MINOR: once the matching CLEAR sentinel removes a symlinked off/<session_id>, no counter-instruction must fire"
assert_file_absent "$home56/.squirrel/off/sess-symlinkflag-56" "MINOR: a symlinked off/<session_id> must itself be unlinked when a matching CLEAR sentinel claims it"
assert_file_exists "$target56" "MINOR: unlinking a symlinked off/<session_id> must NEVER remove the file it points at"

# ==========================================================================
# 57. check-off-flag.sh - MINOR: no timing bound existed on this
#     per-prompt hook. Measured (pre-existing, on the reviewer's
#     machine): empty off/ 0.025s; 100 stale sentinels 0.39s; 200
#     sentinels 0.73s - and pruning only happens at the 7-day threshold,
#     so a growing off/ is the normal long-run state, not an edge case.
#     100 PENDING/CLEAR-shaped sentinels (50/50, none matching this
#     invocation's own cwd) exercise the full cost of this hook's
#     per-prompt scan, including the newer-wins champion precompute
#     added by the MAJOR fix above. Whole-second `date +%s` timestamps
#     only (no GNU-only `%N`), matching scenario 33's own technique.
# ==========================================================================
home57=$(new_home)
mkdir -p "$home57/.squirrel/off"
n57=1
while [ "$n57" -le 50 ]; do
  printf '/tmp/unrelated-dir-a-%s\n' "$n57" >"$home57/.squirrel/off/PENDING.stale$n57"
  printf '/tmp/unrelated-dir-b-%s\n' "$n57" >"$home57/.squirrel/off/CLEAR.stale$n57"
  n57=$((n57 + 1))
done
cwd57="$home57/project-timing-57"
stdin57=$(printf '{"session_id":"sess-timing-57","cwd":"%s"}' "$cwd57")

t0_57=$(date +%s)
out57=$(capture_stdout "$check_off_flag_script" "$home57" "$stdin57")
t1_57=$(date +%s)
delta57=$((t1_57 - t0_57))

exit57=$(capture_exit "$check_off_flag_script" "$home57" "$stdin57")
assert_eq "0" "$exit57" "check-off-flag.sh must exit 0 with 100 stale PENDING/CLEAR-shaped sentinels under off/"
assert_eq "" "$out57" "check-off-flag.sh must print nothing for a session with no matching sentinel, even with 100 unrelated stale sentinels present"

if [ "$delta57" -le 3 ]; then
  fast57=yes
else
  fast57=no
fi
assert_eq "yes" "$fast57" "MINOR timing bound: check-off-flag.sh must process 100 stale PENDING/CLEAR sentinels in a stated bound (3s or less; took ${delta57}s) on the hot path of every prompt, so a future change that makes this materially worse is caught"

# ==========================================================================
# 58. allow-checkpoint.sh - S10-1 CLASS-LEVEL FAILURE PROOF: reverting
#     decide()'s case statement from "Write | Edit | Read) ;;" back to
#     the original "Write | Edit) ;;" must reproduce the S10-1 BLOCKER
#     exactly - a legitimate checkpoint Read incorrectly falls through
#     to "defer" - while a legitimate checkpoint Write is completely
#     unaffected. This single mutant is what proves every "allow"-side
#     Read assertion added above (scenarios 14r, 19cr, 25cr, 29r/30r's
#     sibling allow case at 31r/32r, 36r's root/trailing-slash cases) is
#     not vacuous: none of them could pass against the pre-fix matcher
#     logic. It deliberately does NOT prove the Read DEFER-side mirrors
#     (16r, 17r, 19ar/19br, etc.) - those pass trivially under a
#     mutant that defers more, not less - which is exactly why the
#     Read-specific failure proofs above (16, 17, 25, 29/30 mirrors) use
#     the ORIGINAL naive/removed-layer mutants with Read ADDED to their
#     own case statements instead.
# ==========================================================================
fp58_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal source
# text of allow-checkpoint.sh to search for/replace, not an expression to
# expand in this shell.
fp58_line=$(line_of "$fp58_script" '    Write | Edit | Read) ;;')
[ -n "$fp58_line" ] || fp58_line=0
# shellcheck disable=SC2016
replace_line "$fp58_script" "$fp58_line" '    Write | Edit) ;;'

fp58_home=$(new_home)
fp58_stdin_read=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$fp58_home")
fp58_out_read=$(capture_stdout "$fp58_script" "$fp58_home" "$fp58_stdin_read")
fp58_decision_read=$(printf '%s' "$fp58_out_read" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp58_decision_read="<jq error>"
assert_eq "defer" "$fp58_decision_read" "S10-1 CLASS-LEVEL FAILURE PROOF: reverting the case statement to 'Write | Edit) ;;' (the pre-fix matcher) must reproduce the exact BLOCKER - a legitimate checkpoint Read incorrectly deferring - proving every allow-side Read assertion added above is not vacuous"

fp58_stdin_write=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.squirrel/checkpoints/myproj.md"}}' "$fp58_home")
fp58_out_write=$(capture_stdout "$fp58_script" "$fp58_home" "$fp58_stdin_write")
fp58_decision_write=$(printf '%s' "$fp58_out_write" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp58_decision_write="<jq error>"
assert_eq "allow" "$fp58_decision_write" "S10-1 CLASS-LEVEL FAILURE PROOF sanity: reverting the case statement to pre-fix must leave a legitimate checkpoint Write completely unaffected, isolating the mutant's effect to Read specifically"

# ==========================================================================
# 59. allow-checkpoint.sh - AB1 (S10 review cycle 1, MAJOR security): the
#     extract_field top-level-vs-tool_input SHADOWING bypass. Before this
#     fix, a payload carrying a benign top-level `file_path` alongside a
#     malicious `tool_input.file_path` returned "allow" for Read, Write,
#     and Edit alike - the hook validated the field the tool never reads
#     (top-level) instead of the one it does (tool_input.file_path), in
#     BOTH the jq path (its filter preferred top-level over tool_input)
#     and the sed fallback (an unscoped, key-order-dependent scan of the
#     whole payload - reproduced independently of the jq bug by
#     reordering the same payload's keys). Fixed: file_path is read ONLY
#     from tool_input, in both paths - see scripts/allow-checkpoint.sh's
#     extract_tool_input_field.
#
#     SUPERSEDED IN PART (S10 review cycle 2, AC1): the "sed fallback" this
#     comment and the 59b/59d/59e scenarios below describe no longer
#     exists - it could not parse a NESTED object inside tool_input (see
#     scenario 60's nested-decoy payload and scripts/allow-checkpoint.sh's
#     own comment), so it was removed outright rather than narrowed again.
#     59a/59b/59c's "jq present" and "jq absent" assertions are UNCHANGED
#     and still both pass: with jq absent, tool_name and file_path both
#     now resolve empty (no sed scan is ever attempted), which already
#     defers via decide()'s existing empty-value handling - the SAME
#     observable outcome as before, reached by a simpler, sed-free path.
#     Only 59e (a mutation proof of the now-deleted sed scoping step) is
#     retired; see scenario 60 for its replacement.
# ==========================================================================
home59=$(new_home)
mkdir -p "$home59/.squirrel/checkpoints"
nojq_path59=$(make_tool_path "jq")

# 59a. THE TASK'S EXACT SPOOF SHAPE: top-level file_path is a genuine,
# legitimate checkpoint path; tool_input.file_path is a traversal
# escaping the checkpoints directory. Must defer - for Read, Write, and
# Edit, with jq present AND with jq stripped from PATH.
for tool59a in Read Write Edit; do
  stdin59a=$(printf '{"tool_name":"%s","file_path":"%s/.squirrel/checkpoints/legit.md","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../../etc/passwd"}}' "$tool59a" "$home59" "$home59")

  out59a=$(capture_stdout "$allow_checkpoint_script" "$home59" "$stdin59a")
  decision59a=$(printf '%s' "$out59a" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision59a="<jq error>"
  assert_eq "defer" "$decision59a" "AB1 (jq present): tool_name $tool59a with a benign top-level file_path AND a malicious tool_input.file_path (traversal) must defer, not allow via the shadowed top-level field"

  out59ar=$(capture_stdout_with_path "$allow_checkpoint_script" "$home59" "$nojq_path59" "$stdin59a")
  decision59ar=$(printf '%s' "$out59ar" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision59ar="<jq error>"
  assert_eq "defer" "$decision59ar" "AB1 (jq absent): tool_name $tool59a with a benign top-level file_path AND a malicious tool_input.file_path (traversal) must defer, not allow via the shadowed top-level field, with jq stripped from PATH"

  exit59a=$(capture_exit "$allow_checkpoint_script" "$home59" "$stdin59a")
  assert_eq "0" "$exit59a" "AB1: allow-checkpoint.sh must exit 0 for the spoof payload (tool_name $tool59a)"
done

# 59b. The DISCRIMINATING variant a fix that only closes the jq filter
# still misses: tool_input is present but has NO file_path key at all;
# the (legitimate, in-checkpoints) file_path lives only at top level.
# The tool call Claude Code actually issues has no file_path in its own
# parameters in this shape, so there is nothing legitimate to allow -
# must defer, Read/Write/Edit, jq present and absent.
for tool59b in Read Write Edit; do
  stdin59b=$(printf '{"tool_name":"%s","file_path":"%s/.squirrel/checkpoints/legit.md","tool_input":{"other":"x"}}' "$tool59b" "$home59")

  out59b=$(capture_stdout "$allow_checkpoint_script" "$home59" "$stdin59b")
  decision59b=$(printf '%s' "$out59b" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision59b="<jq error>"
  assert_eq "defer" "$decision59b" "AB1 (jq present): tool_name $tool59b with tool_input present but lacking file_path, and a legitimate top-level file_path, must defer - tool_input's own parameters have no file_path to allow"

  out59br=$(capture_stdout_with_path "$allow_checkpoint_script" "$home59" "$nojq_path59" "$stdin59b")
  decision59br=$(printf '%s' "$out59br" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision59br="<jq error>"
  assert_eq "defer" "$decision59br" "AB1 (jq absent): tool_name $tool59b with tool_input present but lacking file_path, and a legitimate top-level file_path, must defer, with jq stripped from PATH"
done

# 59c. Regression sanity: a genuine tool_input.file_path inside
# checkpoints, with NO top-level file_path field at all, must still
# allow - for Edit specifically (Read/Write's equivalent shape is
# already covered by scenarios 14/14r and the symlink/traversal
# matrix) - proving the fix did not become overbroad and start
# deferring legitimate tool_input-only payloads.
stdin59c=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.squirrel/checkpoints/legit.md"}}' "$home59")
out59c=$(capture_stdout "$allow_checkpoint_script" "$home59" "$stdin59c")
decision59c=$(printf '%s' "$out59c" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision59c="<jq error>"
assert_eq "allow" "$decision59c" "AB1 sanity: tool_name Edit with a genuine tool_input.file_path inside checkpoints/ and no top-level field at all must still allow"
exit59c=$(capture_exit "$allow_checkpoint_script" "$home59" "$stdin59c")
assert_eq "0" "$exit59c" "AB1 sanity: allow-checkpoint.sh must exit 0 for the tool_input-only Edit payload"

# 59d. FAILURE PROOF, jq path: reverting extract_tool_input_field's jq
# filter to the OLD, vulnerable form - '(.[$k] // .tool_input[$k] //
# empty)', preferring a top-level field over tool_input - must
# reproduce scenario 59a's exact spoof-allow bug (Read case, jq
# present). Isolated via a single, unique substring substitution (the
# fixed filter's exact text, single-quoted, appears nowhere else in the
# file outside this one line - the header's own prose comment uses
# backtick-quoting, not single-quoting, for the same text, so it cannot
# collide).
fp59d_script=$(make_script_scratch "$allow_checkpoint_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal source
# text to search for/replace (real $ characters), not shell expansion.
fp59d_want="    if val=\$(printf '%s' \"\$json\" | jq -r --arg k \"\$key\" '(.tool_input[\$k] // empty)' 2>/dev/null); then"
fp59d_replacement="    if val=\$(printf '%s' \"\$json\" | jq -r --arg k \"\$key\" '(.[\$k] // .tool_input[\$k] // empty)' 2>/dev/null); then"
fp59d_line=$(line_of "$fp59d_script" "$fp59d_want")
[ -n "$fp59d_line" ] || fp59d_line=0
replace_line "$fp59d_script" "$fp59d_line" "$fp59d_replacement"

fp59d_home=$(new_home)
mkdir -p "$fp59d_home/.squirrel/checkpoints"
fp59d_stdin=$(printf '{"tool_name":"Read","file_path":"%s/.squirrel/checkpoints/legit.md","tool_input":{"file_path":"%s/.squirrel/checkpoints/../../../../etc/passwd"}}' "$fp59d_home" "$fp59d_home")
fp59d_out=$(capture_stdout "$fp59d_script" "$fp59d_home" "$fp59d_stdin")
fp59d_decision=$(printf '%s' "$fp59d_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp59d_decision="<jq error>"
assert_eq "allow" "$fp59d_decision" "AB1 FAILURE PROOF (jq path): reverting extract_tool_input_field's jq filter to the old top-level-preferring form must reproduce the exact spoof-allow bug scenario 59a proves fixed, confirming 59a's jq-present assertions are not vacuous"

fp59d_exit=$(capture_exit "$fp59d_script" "$fp59d_home" "$fp59d_stdin")
assert_eq "0" "$fp59d_exit" "AB1 FAILURE PROOF sanity (jq path): the reverted-filter mutant must still exit 0 (the outer wrapper's fail-safe contract is unaffected by this mutation)"

# 59e. RETIRED (S10 review cycle 2, AC1). This used to neutralize
# extract_tool_input_field's sed SCOPING step (making tool_input_text
# equal the whole raw json) to prove the sed fallback's shadowing bug
# reproduced without jq. AC1 removed the sed fallback itself, not just
# its scoping, so there is no longer a scoping step to neutralize - the
# mutation this scenario performed no longer applies to the current
# source. Superseded by scenario 60's failure proof below, which targets
# the class this scenario existed to guard (a sed decision path in
# extract_tool_input_field) rather than one specific line of one that no
# longer exists.

# ==========================================================================
# 60. allow-checkpoint.sh - AC1 (S10 review cycle 2, BLOCKER security): a
#     NESTED object inside tool_input defeats extract_tool_input_field's
#     old sed isolation regex, which stopped at the first literal "}" -
#     the nested decoy's own closing brace, not tool_input's. The tech
#     lead's exact reproduction:
#       {"tool_name":"Write","tool_input":{"file_path":"/etc/passwd",
#        "decoy":{"file_path":"$HOME/.squirrel/checkpoints/legit.md"}}}
#     jq present -> defer (correct: jq parses the real nested structure
#     and finds /etc/passwd, outside checkpoints/). jq stripped -> used to
#     return "allow" (WRONG: the sed fallback's isolation regex captured
#     up to the decoy's own "}", and the greedy key search inside that
#     capture found the decoy's legit-looking checkpoints/ path instead
#     of the real, dangerous tool_input.file_path). FIX (removal, not a
#     narrower regex): the sed decision path is gone. Without jq,
#     extract_tool_input_field now returns nothing unconditionally, so
#     jq-absent defers on EVERY payload, this one included - see
#     scripts/allow-checkpoint.sh's own comment for the full mechanism.
#
#     The fixture below sends that same JSON content on ONE physical
#     line, not wrapped across two the way it is shown above for
#     readability: `sed -n` reads its input line by line, so a payload
#     with a REAL embedded newline splitting "tool_input":{ from its own
#     "}" already defers under the OLD sed fallback too (for an
#     unrelated reason - a line-break defeating a per-line scan, AC3's
#     territory, not this one) and would not isolate the nested-object
#     bug this scenario exists to prove. Keeping the payload on one line
#     is what makes this a clean reproduction of the BRACE-COUNTING
#     blindness specifically, uncomplicated by a second, different
#     evasion.
# ==========================================================================
home60=$(new_home)
mkdir -p "$home60/.squirrel/checkpoints"
nojq_path60=$(make_tool_path "jq")

for tool60 in Read Write Edit; do
  stdin60=$(printf '{"tool_name":"%s","tool_input":{"file_path":"/etc/passwd", "decoy":{"file_path":"%s/.squirrel/checkpoints/legit.md"}}}' "$tool60" "$home60")

  out60=$(capture_stdout "$allow_checkpoint_script" "$home60" "$stdin60")
  decision60=$(printf '%s' "$out60" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision60="<jq error>"
  assert_eq "defer" "$decision60" "AC1 (jq present): tool_name $tool60 with the nested-decoy payload (real tool_input.file_path=/etc/passwd, decoy tool_input.decoy.file_path=legit checkpoints/ path) must defer - jq parses the real nesting and finds /etc/passwd"
  exit60=$(capture_exit "$allow_checkpoint_script" "$home60" "$stdin60")
  assert_eq "0" "$exit60" "AC1: allow-checkpoint.sh must exit 0 for the nested-decoy payload (tool_name $tool60, jq present)"
  out60_valid=$(printf '%s' "$out60" | jq empty >/dev/null 2>&1 && echo yes || echo no)
  assert_eq "yes" "$out60_valid" "AC1: allow-checkpoint.sh output for the nested-decoy payload (tool_name $tool60, jq present) must be valid JSON"

  out60n=$(capture_stdout_with_path "$allow_checkpoint_script" "$home60" "$nojq_path60" "$stdin60")
  decision60n=$(printf '%s' "$out60n" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision60n="<jq error>"
  assert_eq "defer" "$decision60n" "AC1 BLOCKER FIX (jq absent): tool_name $tool60 with the nested-decoy payload must defer, not allow via the decoy's legit-looking path - this is the exact BLOCKER the tech lead reproduced, jq stripped from PATH"
  exit60n=$(capture_exit_with_path "$allow_checkpoint_script" "$home60" "$nojq_path60" "$stdin60")
  assert_eq "0" "$exit60n" "AC1: allow-checkpoint.sh must exit 0 for the nested-decoy payload (tool_name $tool60, jq absent)"
  out60n_valid=$(printf '%s' "$out60n" | jq empty >/dev/null 2>&1 && echo yes || echo no)
  assert_eq "yes" "$out60n_valid" "AC1: allow-checkpoint.sh output for the nested-decoy payload (tool_name $tool60, jq absent) must be valid JSON"
done

# 60b. AC1 cost, made explicit: a payload that WOULD have been a
# legitimate "allow" (no nesting, no decoy, tool_input.file_path
# genuinely inside checkpoints/) now defers when jq is absent, for
# Read, Write, and Edit alike - the graceful-degradation half of AC1's
# fix. This is the "existing jq-absent test, flipped" the task asked
# for: before this cycle no such test existed for allow-checkpoint.sh
# (only the AB1 spoof/discriminating shapes were exercised jq-absent,
# and those already deferred before and after this fix) - this is the
# first assertion of this exact shape, and it asserts the NEW, correct
# behaviour directly rather than a stale "allow" expectation.
for tool60b in Read Write Edit; do
  stdin60b=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s/.squirrel/checkpoints/legit-60b.md"}}' "$tool60b" "$home60")

  out60b_jq=$(capture_stdout "$allow_checkpoint_script" "$home60" "$stdin60b")
  decision60b_jq=$(printf '%s' "$out60b_jq" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision60b_jq="<jq error>"
  assert_eq "allow" "$decision60b_jq" "AC1 sanity: tool_name $tool60b on a genuinely legitimate, non-nested checkpoint path must still allow with jq present"

  out60b_nojq=$(capture_stdout_with_path "$allow_checkpoint_script" "$home60" "$nojq_path60" "$stdin60b")
  decision60b_nojq=$(printf '%s' "$out60b_nojq" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || decision60b_nojq="<jq error>"
  assert_eq "defer" "$decision60b_nojq" "AC1 cost, stated as a permanent assertion: tool_name $tool60b on a payload that would otherwise be a legitimate allow must defer when jq is absent - checkpoint auto-approval requires a real parser, and this is the graceful fallback, not a crash or a wrong allow"
  exit60b_nojq=$(capture_exit_with_path "$allow_checkpoint_script" "$home60" "$nojq_path60" "$stdin60b")
  assert_eq "0" "$exit60b_nojq" "AC1: allow-checkpoint.sh must still exit 0 for an otherwise-legitimate payload with jq absent (graceful fallback, never a crash)"
done

# 60c. FAILURE PROOF: reintroduce a sed decision path into
# extract_tool_input_field (the exact code AC1 removed) in a scratch copy
# of the REAL, CURRENT (already-fixed) script, and confirm the
# nested-decoy payload reproduces the BLOCKER - "allow" - with jq
# stripped from PATH. This proves scenario 60's jq-absent "defer"
# assertions are not vacuous: they can and do fail against code that
# still asks a regex to isolate tool_input's own text.
fp60c_script=$(make_script_scratch "$allow_checkpoint_script")
fp60c_func_line=$(line_of "$fp60c_script" 'extract_tool_input_field() {')
[ -n "$fp60c_func_line" ] || fp60c_func_line=0
fp60c_return_line=$(line_of_after "$fp60c_script" "$fp60c_func_line" '  return 0')
[ -n "$fp60c_return_line" ] || fp60c_return_line=0
fp60c_old_sed_block=$(cat <<'BLOCK'
  tool_input_text=$(printf '%s\n' "$json" | sed -n 's/^.*"tool_input"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p')
  [ -n "$tool_input_text" ] || return 0
  printf '%s\n' "$tool_input_text" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
BLOCK
)
replace_block "$fp60c_script" "$fp60c_return_line" "$fp60c_return_line" "$fp60c_old_sed_block"

fp60c_home=$(new_home)
mkdir -p "$fp60c_home/.squirrel/checkpoints"
fp60c_stdin=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd", "decoy":{"file_path":"%s/.squirrel/checkpoints/legit.md"}}}' "$fp60c_home")

fp60c_out=$(capture_stdout_with_path "$fp60c_script" "$fp60c_home" "$nojq_path60" "$fp60c_stdin")
fp60c_decision=$(printf '%s' "$fp60c_out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp60c_decision="<jq error>"
assert_eq "allow" "$fp60c_decision" "AC1 FAILURE PROOF: reintroducing a sed decision path into extract_tool_input_field, jq stripped from PATH, must reproduce the exact nested-decoy BLOCKER (allow, via the decoy's legit-looking path) scenario 60 proves fixed - confirming its jq-absent 'defer' assertions are not vacuous"

fp60c_exit=$(capture_exit_with_path "$fp60c_script" "$fp60c_home" "$nojq_path60" "$fp60c_stdin")
assert_eq "0" "$fp60c_exit" "AC1 FAILURE PROOF sanity: the reintroduced-sed-fallback mutant must still exit 0 (the outer wrapper's fail-safe contract is unaffected by this mutation)"

# Sanity: the SAME mutant, with jq PRESENT, must be unaffected - the jq
# path returns before the appended sed code is ever reached, isolating
# the mutation's effect to the jq-absent path specifically (same
# isolation discipline as scenario 58's Write-unaffected check).
fp60c_out_jq=$(capture_stdout "$fp60c_script" "$fp60c_home" "$fp60c_stdin")
fp60c_decision_jq=$(printf '%s' "$fp60c_out_jq" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null) || fp60c_decision_jq="<jq error>"
assert_eq "defer" "$fp60c_decision_jq" "AC1 FAILURE PROOF sanity: the reintroduced-sed-fallback mutant, run WITH jq present, must still defer correctly on the nested-decoy payload - the mutation's effect is isolated to the jq-absent path, matching the real bug's own reproduction"

# ==========================================================================
# 61. load-profile.sh - S11 migration notice: a completely fresh install
#     (no ~/.claude/squirrel/ from before, no ~/.squirrel/ yet) must NOT
#     mention any migration at all - the notice is conditional on the OLD
#     directory's presence, not unconditional boilerplate.
# ==========================================================================
home61=$(new_home)
stdin61=$(printf '{"session_id":"s1","cwd":"%s/project-a"}' "$home61")
out61=$(capture_stdout "$load_profile_script" "$home61" "$stdin61")
ctx61=$(extract_ctx "$out61")
assert_not_contains "$ctx61" "older install" "fresh-install additionalContext (no old directory at all) must not mention a migration from an older install"
assert_not_contains "$ctx61" ".claude/squirrel" "fresh-install additionalContext must not name the old data directory at all when it never existed"

# ==========================================================================
# 62. load-profile.sh - S11 migration notice: ~/.claude/squirrel/ (the
#     pre-S11 location) exists on disk - additionalContext must contain a
#     one-line notice naming BOTH the old path and the new ~/.squirrel/
#     path, addressed to the model the same way the "no profile found"
#     line is (instructing it to relay the notice, briefly).
# ==========================================================================
home62=$(new_home)
mkdir -p "$home62/.claude/squirrel"
cat >"$home62/.claude/squirrel/profile.md" <<'EOF'
# squirrel-mode profile
language: en
EOF
stdin62=$(printf '{"session_id":"s1","cwd":"%s/project-a"}' "$home62")

exit62=$(capture_exit "$load_profile_script" "$home62" "$stdin62")
assert_eq "0" "$exit62" "load-profile.sh must exit 0 when the pre-S11 directory exists"

out62=$(capture_stdout "$load_profile_script" "$home62" "$stdin62")
out62_json_valid=$(printf '%s' "$out62" | jq empty >/dev/null 2>&1 && echo yes || echo no)
assert_eq "yes" "$out62_json_valid" "load-profile.sh stdout must be valid JSON when the pre-S11 directory exists"

ctx62=$(extract_ctx "$out62")
assert_contains "$ctx62" "$home62/.claude/squirrel" "additionalContext must name the exact old data directory path when it exists"
assert_contains "$ctx62" "$home62/.squirrel" "additionalContext must also name the new data directory path in the same notice"
migration_mentions62=$(printf '%s' "$ctx62" | grep -io 'older install' | grep -c '.' || true)
assert_eq "1" "$migration_mentions62" "the migration notice must appear exactly once, not repeated or duplicated"

# ==========================================================================
# 63. load-profile.sh - S11 migration notice coexists with a real, current
#     profile: if the user already has BOTH an old directory (not yet
#     removed) and a fresh ~/.squirrel/profile.md, both the profile content
#     and the migration notice must appear - this is a deliberate,
#     accepted combination (see docs/adr/0003's Amendment (S11) migration
#     paragraph), not a bug to be resolved by silently preferring one.
# ==========================================================================
home63=$(new_home)
mkdir -p "$home63/.claude/squirrel"
touch "$home63/.claude/squirrel/profile.md"
mkdir -p "$home63/.squirrel"
profile63_marker="LANGUAGE_MARKER_S11_MIGRATION_COEXIST"
cat >"$home63/.squirrel/profile.md" <<EOF
# squirrel-mode profile
language: $profile63_marker
EOF
stdin63=$(printf '{"session_id":"s1","cwd":"%s/project-a"}' "$home63")

out63=$(capture_stdout "$load_profile_script" "$home63" "$stdin63")
ctx63=$(extract_ctx "$out63")
assert_contains "$ctx63" "$profile63_marker" "additionalContext must still contain the CURRENT profile's own content when an old directory also lingers"
assert_contains "$ctx63" "older install" "additionalContext must still carry the migration notice even when a current profile already exists"

# --- Failure proof for scenario 61: mutate detect_old_data_dir to fire
# unconditionally (drop its own [ -d "$old_dir" ] guard) - scenario 61's
# fresh install must then WRONGLY show the migration notice, proving
# scenario 61's absence assertion is not vacuous.
fp61_script=$(make_script_scratch "$load_profile_script")
# shellcheck disable=SC2016 # single-quoted deliberately: literal source text to locate, not shell expansion
fp61_guard_line=$(line_of "$fp61_script" '  [ -d "$old_dir" ] || return 0')
[ -n "$fp61_guard_line" ] || fp61_guard_line=0
replace_block "$fp61_script" "$fp61_guard_line" "$fp61_guard_line" '  :'
fp61_out=$(capture_stdout "$fp61_script" "$home61" "$stdin61")
fp61_ctx=$(extract_ctx "$fp61_out")
if printf '%s' "$fp61_ctx" | grep -qi 'older install'; then
  fp61_wrongly_fires=yes
else
  fp61_wrongly_fires=no
fi
assert_eq "yes" "$fp61_wrongly_fires" "FAILURE PROOF (invariant S11, scenario 61): removing detect_old_data_dir's own [ -d ] guard must make a fresh install wrongly show the migration notice - proving scenario 61's absence assertion is not vacuous"

# --- Failure proof for scenario 62: mutate detect_old_data_dir to always
# return nothing (stub it out) - scenario 62's real old-directory case must
# then WRONGLY show no notice, proving scenario 62's presence assertion is
# not vacuous.
fp62_script=$(make_script_scratch "$load_profile_script")
fp62_func_line=$(line_of "$fp62_script" 'detect_old_data_dir() {')
[ -n "$fp62_func_line" ] || fp62_func_line=0
fp62_func_end=$(line_of_after "$fp62_script" "$fp62_func_line" '}')
[ -n "$fp62_func_end" ] || fp62_func_end=0
replace_block "$fp62_script" "$fp62_func_line" "$fp62_func_end" 'detect_old_data_dir() { return 0; }'
fp62_out=$(capture_stdout "$fp62_script" "$home62" "$stdin62")
fp62_ctx=$(extract_ctx "$fp62_out")
if printf '%s' "$fp62_ctx" | grep -qi 'older install'; then
  fp62_still_fires=yes
else
  fp62_still_fires=no
fi
assert_eq "no" "$fp62_still_fires" "FAILURE PROOF (invariant S11, scenario 62): stubbing out detect_old_data_dir entirely must make a genuine pre-S11 directory WRONGLY show no migration notice - proving scenario 62's presence assertion is not vacuous"

assert_report
