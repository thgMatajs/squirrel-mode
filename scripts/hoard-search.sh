#!/bin/sh
# hoard-search.sh - the hoard's only reader.
#
# Enumerates every memory file in the global layer and (when --slug is
# given) one project layer, parses each file's frontmatter, and prints
# the ranked result as `<id> · <score> · <type> · <title>`.
#
# THERE IS NO INDEX, DELIBERATELY. Every read is a single awk pass over
# the frontmatter of every file - see docs/specs/2026-08-13-hoard-design.md
# §5.1 for the scale ceiling that buys and why it was chosen over a
# derived index (no rebuild, no staleness, no schema migration, no
# divergence between a file and its index).
#
# NEVER WRITES. Reinforcement (`uses`, `last_used`) is the caller's job,
# through the Write tool, so this script stays a pure function of $HOME,
# its arguments, and the filesystem - which is also what makes every
# test a plain stdout comparison.
#
# Never exits non-zero for an empty, missing, or malformed store: a
# reader that fails loudly on a first-ever run would put an error in
# front of a user who has done nothing wrong. Silence is the answer for
# "nothing to show".
#
# WHICH MAKES EVERY SILENT DROP A DEFECT, not a tolerance. If a store
# that holds memories can answer like a store that holds none, the user
# cannot tell the two apart, and this file is the only thing that could
# have told them. Four ways it did exactly that have been fixed rather
# than accepted - a regular file awk cannot open, a CRLF or BOM in the
# frontmatter, whitespace around a `status` value, and a query whose
# terms were all discarded - each one reproduced first and pinned by a
# scenario in tests/test_hoard.sh. What silence still covers is a file
# with no frontmatter delimiters at all and a file with no `title`:
# neither can be ranked or displayed, and both are states nothing in
# squirrel-mode writes.
set -eu
unset CDPATH

topk=5
slug=""
want_all=0
query=""

while [ $# -gt 0 ]; do
  case "$1" in
    -k)
      shift
      [ $# -gt 0 ] || break
      topk=$1
      ;;
    --slug)
      shift
      [ $# -gt 0 ] || break
      slug=$1
      ;;
    --all)
      want_all=1
      ;;
    --)
      shift
      break
      ;;
    -*)
      # An unknown flag is not fatal: this script is invoked by a model
      # following a skill, and refusing the whole search over one
      # unrecognised token would turn a typo into a dead end.
      ;;
    *)
      if [ -z "$query" ]; then
        query=$1
      else
        query="$query $1"
      fi
      ;;
  esac
  shift
done

while [ $# -gt 0 ]; do
  if [ -z "$query" ]; then
    query=$1
  else
    query="$query $1"
  fi
  shift
done

# -k IS BOUNDED, not merely required to be digits. `head -n 0` and
# `head -n <huge>` both fail - "head: illegal line count" on stderr,
# nothing on stdout, exit 0 - which is the one thing the header above
# promises this script never does: it complains at a user who has done
# nothing worse than typing a number. Measured on this machine with the
# digit-only test alone: `-k 0` and `-k 99999999999999999999` each
# printed that line and returned no results.
#
# OUT OF RANGE IS CLAMPED, NEVER FATAL, for the same reason an unknown
# flag is not fatal a few lines up. A caller asking for more than the
# store holds gets everything it holds, which is what they asked for;
# a caller asking for none gets the default rather than silence, because
# "show me nothing" is not a search anyone means.
#
# THE LENGTH TEST COMES FIRST, and it is not decoration: `[ "$topk" -gt
# 1000 ]` on a twenty-digit string is the shell's own integer overflow,
# not a comparison - dash reports "value too great for base" and `set -e`
# would end the search there. Anything longer than four digits is out of
# range by construction, so it never reaches an arithmetic test.
case "$topk" in
  '' | *[!0-9]*) topk=5 ;;
  *)
    if [ "${#topk}" -gt 4 ]; then
      topk=1000
    elif [ "$topk" -lt 1 ]; then
      topk=5
    elif [ "$topk" -gt 1000 ]; then
      topk=1000
    fi
    ;;
esac

home_dir="${HOME:-}"
[ -n "$home_dir" ] || exit 0

hoard_dir="$home_dir/.squirrel/hoard"
[ -d "$hoard_dir" ] || exit 0

# Build the file list: ONE `set --` per LAYER, never one per file.
#
# THE PER-FILE FORM IS QUADRATIC. Appending one file at a time - the
# loop this replaced - rebuilds the entire positional list on every
# call, and macOS's /bin/sh (bash 3.2) rebuilds it by copying, so
# appending n files costs O(n^2). (The forbidden form is deliberately
# not spelled here: tests/test_hoard.sh scenario 14 greps this file for
# it, and a guard that its own subject's comment satisfies is a guard
# that cannot fail.)
# Measured on the author's machine at 2000 memories: 12.05 s in that loop
# against 110 ms for the whole awk pass it was feeding. Assigning each
# layer's expansion in a single `set --` makes that one copy per layer
# instead of one per file. tests/test_hoard.sh scenario 14 pins the
# shape so the per-file form cannot come back unnoticed.
#
# An unmatched glob stays literal in POSIX sh, and the literal names no
# file, so it is dropped by testing "$1" and shifting it off. The test
# is exact rather than a sample: an unmatched glob expands to exactly
# one word - the pattern itself - and that word is the FIRST of the
# layer just assigned. Keeping each test immediately after its own
# `set --` is what makes "$1" both the right word to test and a defined
# one under `set -u`.
#
# THOSE TWO SHIFTS ALSO GUARD A PERFORMANCE CLIFF, not just correctness.
# The prescan below treats any non-regular entry as a reason to rebuild,
# and an unmatched glob's literal is non-regular. A fresh project with a
# populated global layer - the commonest state there is - would therefore
# rebuild on every single search if the literal were still in the list.
# Dropping it here, in O(1), is what keeps the rebuild for genuinely
# irregular entries.
#
# inbox/ is never enumerated: a candidate is not a memory.
set -- "$hoard_dir"/global/*.md
[ -f "$1" ] || shift
if [ -n "$slug" ]; then
  # A slug carrying a "/" or a ".." COMPONENT would reach outside the
  # project layer. Nothing legitimate produces one: project_slug() in
  # load-profile.sh emits `basename-hash`, where basename has been run
  # through `tr -c 'A-Za-z0-9._-'`.
  #
  # It is the COMPONENT that is rejected, never the two characters - the
  # same distinction allow-checkpoint.sh's Layer 0 draws, and for the
  # same reason. `tr` keeps dots, so a repository named `my..repo`
  # produces the perfectly legitimate slug `my..repo-abc123`; a bare
  # `*..*` test would silently drop that project's whole layer and
  # return only global memories, with nothing reported. Wrapping both
  # ends in "/" is what makes one pattern cover a bare "..", a leading
  # "../x", a trailing "x/.." and an interior "/../" without touching a
  # name that merely contains two dots.
  #
  # WHAT THIS GUARD BOUNDS, AND WHAT IT DOES NOT. It bounds the STRING:
  # no slug can name a path outside `projects/`. It does not bound the
  # FILESYSTEM. If `projects/<slug>` is a symbolic link to a directory
  # elsewhere, this script follows it and returns what is over there -
  # measured, not supposed: a link planted at `projects/evil-abc123`
  # pointing at a directory outside the hoard returned that directory's
  # memories beside the global layer.
  #
  # LEFT OPEN DELIBERATELY, and said out loud rather than implied. A
  # single `.md` file inside `global/` may be a symbolic link too, and
  # that one is followed as well, so a check on this directory alone
  # would close one route while claiming a boundary the store does not
  # have. Closing both would mean resolving every path in the hoard
  # against the hoard's own real path on every search - a per-file cost
  # this file exists to avoid, for a threat that already requires write
  # access to the hoard, where planting a memory outright is easier than
  # planting a link to one. The hoard is the user's own directory and a
  # link in it is the user's own decision; what this guard promises is
  # that no slug HANDED to this script can leave `projects/`.
  case "$slug" in
    */*) slug="" ;;
  esac
  case "/$slug/" in
    */../*) slug="" ;;
  esac
fi
if [ -n "$slug" ]; then
  # PREPENDED, not appended, so the layer under test is once again the
  # front of the list and the same one-word check applies unchanged.
  # Appending would put the candidate literal LAST, where reaching it
  # costs either an `eval` on ${$#} or a walk of the whole list - the
  # per-file cost this rewrite exists to remove. Which layer comes first
  # never reaches the caller: the pipeline below sorts by score and then
  # by id, so awk's argument order decides nothing.
  set -- "$hoard_dir/projects/$slug"/*.md "$@"
  [ -f "$1" ] || shift
fi

# HAND awk NOTHING IT CANNOT SAFELY OPEN. A `*.md` entry awk cannot open
# is not a memory, and awk does not merely ignore one:
#
#   - a FIFO makes awk BLOCK FOREVER on open, waiting for a writer that
#     never comes. The search never returns and prints nothing, which is
#     the one failure a user cannot diagnose - there is nothing to read.
#   - a broken symlink, or a directory under mawk, makes awk exit fatally
#     mid-list. Because emit() defers each record until the NEXT file's
#     FNR == 1, the memory parsed just before the fatal is DROPPED - a
#     complete-looking answer, silently missing an entry, exit status 0.
#     Measured: 3 memories in, 2 out, on all three awks this project
#     meets. Silent loss from the store's only reader is the worst
#     outcome in this file, worse than being slow and worse than failing.
#   - A REGULAR FILE WITH NO READ PERMISSION does exactly the same, and
#     it is the case a test for regularity alone CANNOT SEE. `[ -f ]` is
#     true for it, so it passed straight through the prescan this test
#     replaced. Measured on this machine, four memories in a global layer
#     with the third at mode 000: ONE came back, exit status 0. The
#     memory before the unreadable one was lost to the deferred emit()
#     and every memory after it was never read at all. That is why the
#     test below is `-f` AND `-r`, and why scenario 16 in
#     tests/test_hoard.sh now fabricates this victim as well as the three
#     that `[ -f ]` already caught.
#
# `-r` IS THE FILESYSTEM'S ANSWER, NOT A GUARANTEE. It asks whether a
# read would be permitted for this user now; a file whose mode changes
# between this walk and awk's open, or one on a filesystem that fails
# the open for a reason permissions cannot express, still reaches awk.
# That residue costs the record before it and everything after it, in
# silence, exactly as before - it is narrower than the class this test
# closes, not different in kind.
#
# So the list is prescanned, and rebuilt only if the prescan finds
# something. The prescan is O(n) with NO `set --` at all, so the common
# case - every entry a regular, readable file - pays one stat per file
# and nothing else.
#
# WHAT THAT COSTS, MEASURED, AND WHY THE RATIO IS THE ONLY PART WORTH
# QUOTING. One controlled run on the author's machine, 2000 memories, the
# same fixture for all three, /bin/sh (bash 3.2):
#
#     prescan, no irregular entry            0.11 s
#     per-file rebuild (this branch)        14.67 s
#     the pre-one-shot per-file loop        14.42 s
#
# So the rebuild costs what this script cost before the one-shot
# construction landed - within 2% of it - and no state is slower than it
# used to be. That RATIO is the claim; the seconds are not a property of
# the construction. Appending one word at a time copies the whole list
# each time, so the cost scales with the LENGTH of the paths as well as
# their number: the same 2000 files, same loop, under a directory making
# each path 292 bytes instead of 176, took 24.08 s. The 12.05 s quoted
# higher up this file and in README.md is CONSISTENT with that same loop
# on a shorter fixture rather than with a different construction - the
# fixture behind that figure was not re-run here, so this reconciles the
# two numbers without claiming to have reproduced either. An earlier
# draft of this paragraph read 8.1 s, and is retired for the same reason. A number that moves with the
# length of a user's home directory belongs in a sentence that says so.
#
# The rebuild reassigns "$@" while iterating it, which is safe because a
# `for` loop expands its word list ONCE, before the body runs - verified
# on bash 3.2, dash and zsh, not assumed from the wording. Those three
# are what was actually run; no bash 5 was available to run it on, and
# naming one that was never used would make this comment the kind of
# claim the rest of this repository exists to stop shipping.
irregular=0
for f in "$@"; do
  if [ -f "$f" ] && [ -r "$f" ]; then continue; fi
  irregular=1; break
done
if [ "$irregular" = 1 ]; then
  kept=0
  for f in "$@"; do
    if [ "$kept" = 0 ]; then set --; kept=1; fi
    if [ -f "$f" ] && [ -r "$f" ]; then set -- "$@" "$f"; fi
  done
fi

[ $# -gt 0 ] || exit 0

now_ymd=$(date -u +%Y%m%d 2>/dev/null) || now_ymd="19700101"
tab=$(printf '\t')

# LC_ALL=C: `printf "%.4f"` below writes the locale's decimal separator,
# not always ".": under pt_BR.UTF-8 it writes "0,0000". That breaks both
# the `sort -k1,1nr` numeric comparison downstream and the "exactly four
# decimal places after a '.'" contract callers rely on to parse the
# score. Same discipline as the `LC_ALL=C sort` a few lines down, and as
# load-profile.sh's json_escape - see its "WHY THE BODY RUNS UNDER
# LC_ALL=C" comment.
#
# THE QUERY GOES THROUGH THE ENVIRONMENT, NEVER `-v`. POSIX awk
# re-processes backslash escapes in a `-v` assignment, so the user's own
# text was being read as awk source escapes before it was ever tokenised
# - the same trap load-profile.sh's neutralise_forged_lines documents for
# its own prefix list. Measured against the committed script, all three
# defects real:
#
#   - a search for `a\nb` became a search for two tokens split by a real
#     newline; both were one character long, both were dropped, the query
#     counted as EMPTY and every memory came back as if no terms had been
#     given at all.
#   - a search for `C:\temp` searched for `emp`, because `\t` became a
#     tab.
#   - a term carrying a literal newline aborted the awk program itself
#     ("newline in string"), which returns nothing, says nothing, and
#     exits 0.
#
# want_all and now_ymd stay on `-v`: both are this script's own values,
# a digit and a date, with no path from the caller to their contents.
SQUIRREL_HS_QUERY="$query" \
  LC_ALL=C awk -v want_all="$want_all" -v now_ymd="$now_ymd" '
# days_from_civil: Howard Hinnant days-from-civil, the standard
# proleptic-Gregorian day count. Chosen over `date` arithmetic because
# no portable `date` computes a difference: GNU `date -d` and BSD
# `date -v` disagree in syntax, and this project ships to both. Bucketed
# tiers ("used in the last 30 days") were rejected in the spec: not less
# code, and two memories a day apart would rank identically for a month.
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y = y - 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function stamp_days(s,   y, m, d) {
  # s is a compact UTC stamp: YYYYMMDDTHHMMSSZ. Only the date half is
  # read; a malformed or empty stamp yields day 0, which makes the
  # memory maximally stale rather than crashing the whole search.
  if (length(s) < 8) return 0
  y = substr(s, 1, 4) + 0
  m = substr(s, 5, 2) + 0
  d = substr(s, 7, 2) + 0
  if (y == 0 || m == 0 || d == 0) return 0
  return days_from_civil(y, m, d)
}
function relevance(   hay, i, hits) {
  # TWO DIFFERENT THINGS BOTH LEAVE q_n AT ZERO, and answering them the
  # same way is a lie to one of them.
  #
  # No terms at all means "show me the top of the store", and every
  # memory is fully relevant. Terms that were all DISCARDED mean the user
  # asked for something this tokeniser cannot look for, and handing back
  # the top of the store dresses it up as an answer to their question.
  # Two ways a query arrives here with nothing left of it: a stopword on
  # its own, and a short accented word - the tokeniser above replaces
  # every byte that is not an ASCII letter or digit with a space, so
  # "n" plus "o" is all it can make of the Portuguese for "no", and both
  # pieces are then dropped for being one character long.
  #
  # Measured on the committed script, against a two-memory hoard: `nao`
  # spelled with its tilde, and `que`, each returned EVERY memory with
  # the scores of a search that had no terms in it at all. The same holds
  # for the Portuguese for "action", "are" and "only", and for any single
  # accented letter.
  if (q_n == 0) {
    if (q_dropped) return 0
    return 1
  }
  hay = tolower(m_title " " m_tags)
  gsub(/[^a-z0-9]+/, " ", hay)
  hay = " " hay " "
  hits = 0
  for (i = 1; i <= q_n; i++) {
    if (index(hay, " " q_tok[i] " ") > 0) hits++
  }
  return hits / q_n
}
function untab(s) {
  # A tab in a value would manufacture a field. Every value printed below
  # is a frontmatter value or a filename, either of which may hold one,
  # and the sort and the formatter downstream both address these fields
  # by number. Replacing it with a space keeps the record five fields
  # wide by construction rather than by hoping.
  gsub(/\t/, " ", s)
  return s
}
function emit(   imp, lambda, days, score, rel, uses, sortkey) {
  if (m_title == "") return
  if (want_all != 1 && m_status != "active") return

  rel = relevance()
  if (rel == 0) return

  imp = m_importance + 0
  if (imp < 1) imp = 1
  if (imp > 5) imp = 5

  # `uses` gets the FLOOR importance has had all along. Without it
  # `uses: -1` printed `-inf` and `uses: -5` printed `nan`: log(0) and
  # log(a negative), straight into a field this script promises is a
  # number with four decimal places - and `-inf` sorts ABOVE a legitimate
  # 0.0000, so a hand-edited counter could put a memory at the top by
  # being wrong. Measured, both of them, on the committed script.
  uses = m_uses + 0
  if (uses < 0) uses = 0

  # Important memories decay more slowly. These weights are a design
  # decision, not a finding: they are specified in
  # docs/specs/2026-08-13-hoard-design.md §5, and are registered in
  # docs/RESEARCH.md as a design decision with no finding behind it by
  # Task 8 of this phase.
  lambda = 0.16 * (1 - imp * 0.8 / 5)
  days = now_days - stamp_days(m_last_used)
  if (days < 0) days = 0

  score = rel * (imp / 5) * exp(-lambda * days) * (1 + 0.2 * log(1 + uses))

  # THE ORDER IS DECIDED ON `sortkey`, NOT ON THE PRINTED SCORE. The score is
  # published with four decimal places, and four decimal places is not a
  # ranking: after a couple of months of decay every memory in a hoard
  # prints 0.0000, `sort` then compares equal strings, and the id
  # tie-break puts the OLDEST id on top. Reproduced: an importance-1
  # memory last used in 2020 outranked an importance-5 memory used nine
  # times, also from 2020, because "0.0000" is not less than "0.0000".
  #
  # `sortkey` is the LOGARITHM of that same score, term by term, and log
  # is strictly increasing, so ordering by it is ordering by the score
  # exactly. It carries that name so that nothing else in this program is
  # called `key`: the frontmatter parser below already is, and a mutation
  # test aimed at one of them must not be able to hit the other.
  #
  # COMPUTED TERM BY TERM rather than taken as log(score), for a reason
  # the pair above shows: their true scores are 1.5e-142 and 3.6e-34, and
  # exp(-lambda * days) underflows to a hard zero within a few decades,
  # which log() could not recover. The sum never underflows at all - that
  # pair comes out at -326.59 against -77.00 (computed for 2026-08-15;
  # both drift with the calendar, the ORDER does not), on a scale that
  # stays readable for centuries of staleness. Every term is finite by
  # construction here: rel is non-zero (returned above), imp is clamped
  # into 1..5, and uses is floored at 0.
  #
  # It is printed as an EXTRA FIRST FIELD and dropped by the formatter at
  # the end of the pipeline, so nothing about the published contract -
  # four fields, four decimal places, `id . score . type . title` - moves
  # a byte. %.6f, not %g: `sort -n` does not read exponent notation, and
  # `-g` is a GNU extension this project cannot use.
  sortkey = log(rel) + log(imp / 5) - lambda * days + log(1 + 0.2 * log(1 + uses))
  printf "%.6f\t%.4f\t%s\t%s\t%s\n", sortkey, score, untab(m_id), untab(m_type), untab(m_title)
}
function reset() {
  in_fm = 0; fm_done = 0
  m_type = ""; m_title = ""; m_status = "active"; m_id = ""
  m_importance = 3; m_uses = 0; m_last_used = ""; m_tags = ""
}
BEGIN {
  now_days = days_from_civil(substr(now_ymd, 1, 4) + 0, substr(now_ymd, 5, 2) + 0, substr(now_ymd, 7, 2) + 0)

  # Built from character codes rather than written as escapes: a BOM is
  # not typeable and an escape for it would have to survive three awks
  # and this file being edited. sprintf("%c", n) under LC_ALL=C emits the
  # single BYTE n - checked on all three awks this project meets, not
  # assumed.
  cr = sprintf("%c", 13)
  bom = sprintf("%c%c%c", 239, 187, 191)

  query = ENVIRON["SQUIRREL_HS_QUERY"]

  # Query tokens: lowercased, split on anything that is not a letter or
  # digit, with one-character tokens and a small stopword set dropped.
  # The stopword list is deliberately tiny - it exists to stop "the" and
  # "a" from making every memory look half-relevant, not to be a
  # linguistics project.
  q_n = 0
  q_dropped = 0
  if (query != "") {
    tmp = tolower(query)
    gsub(/[^a-z0-9]+/, " ", tmp)
    c = split(tmp, qparts, " ")
    for (i = 1; i <= c; i++) {
      t = qparts[i]
      if (length(t) < 2) continue
      if (t == "the" || t == "and" || t == "for" || t == "que" || t == "com" || t == "para") continue
      q_n++
      q_tok[q_n] = t
    }
    # The user gave terms and nothing usable survived. relevance() reads
    # this to tell that apart from a search with no terms at all.
    if (q_n == 0) q_dropped = 1
  }
}
{
  # CRLF, STRIPPED BEFORE ANY RULE BELOW LOOKS AT THE LINE. A memory
  # written on Windows, or pasted through a tool that converts line
  # endings, carries "\r" at the end of every line: the delimiter test
  # below sees "---\r" and never opens the frontmatter, so the whole
  # memory is never returned by any search, with `--all` and without,
  # and the store cannot be told from an empty one. Reproduced end to end.
  # substr rather than a regex escape, for the reason BEGIN gives.
  if (length($0) > 0 && substr($0, length($0), 1) == cr) {
    $0 = substr($0, 1, length($0) - 1)
  }
}
FNR == 1 {
  # A UTF-8 BOM sits in front of the first "---" and makes the same line
  # fail the same test, and the memory is lost to every search the same
  # way. Editors write one without being asked; a user cannot see it.
  if (substr($0, 1, 3) == bom) { $0 = substr($0, 4) }
  emit()
  reset()
  n = split(FILENAME, parts, "/")
  base = parts[n]
  sub(/\.md$/, "", base)
  m_id = base
}
fm_done { next }
/^---[ \t]*$/ {
  if (in_fm == 0) { in_fm = 1; next }
  fm_done = 1
  next
}
in_fm == 1 {
  # BOTH SIDES ARE TRIMMED, and both trims are load-bearing:
  #
  #   - the KEY keeps whatever sits before its colon, so `status : active`
  #     parses as the key "status " and matches nothing. The memory keeps
  #     every default instead: no title, and so no result at all.
  #   - the VALUE kept whatever sat after it. `status: active ` - one
  #     trailing space, which no editor shows - is not "active", so
  #     the memory was excluded from every default search and returned
  #     only by `--all`. That is a memory deleted by a keystroke nobody
  #     can see, and skills/stash/SKILL.md tells the model to WRITE this
  #     field and skills/dig/SKILL.md to EDIT it on every read.
  #
  # Leading whitespace on the key is deliberately NOT trimmed: a line
  # that starts with a space is an indented key, which in YAML belongs to
  # a nested mapping and is not the `status` of this memory at all.
  key = $0
  sub(/:.*$/, "", key)
  sub(/[ \t]+$/, "", key)
  val = $0
  sub(/^[^:]*:[ \t]*/, "", val)
  sub(/[ \t]+$/, "", val)
  if (key == "type")       m_type = val
  if (key == "title")      m_title = val
  if (key == "importance") m_importance = val
  if (key == "uses")       m_uses = val
  if (key == "last_used")  m_last_used = val
  if (key == "tags")       m_tags = val
  if (key == "status" && val != "") m_status = val
  next
}
END { emit() }
' "$@" |
  # Deterministic order: ordering key desc, then id asc. Field 1 is the
  # full-precision key emit() prints for exactly this comparison and
  # field 3 is the id; the published score is field 2 and is never sorted
  # on, because four decimal places cannot order anything two months
  # stale. The id tie-break is what makes two equally-ranked memories
  # come back in the same order on every machine and every run - which is
  # only true with LC_ALL=C. Without it, `sort` collates by the caller's
  # locale, and this project already ships tests that run under pt_BR
  # precisely because a locale-dependent answer is one that is right on
  # the author's machine and wrong somewhere else.
  LC_ALL=C sort -t"$tab" -k1,1nr -k3,3 |
  head -n "$topk" |
  # THE FORMATTER IS awk, NOT `while IFS=<tab> read`. A tab is IFS
  # WHITESPACE, so `read` merges consecutive tabs into one delimiter and
  # every empty field shifts the ones after it left: a memory with no
  # `type` came out as `<id> . <score> . <title> . ` - the title standing
  # in the type's column, the contract skills/dig/SKILL.md reads by
  # POSITION quietly broken by an absent field. awk's FS is a real
  # delimiter and does not merge, so an empty field stays empty and in
  # its place. It also drops field 1, which is how the ordering key
  # leaves the pipeline without ever reaching the caller.
  LC_ALL=C awk -F'\t' '{ printf "%s · %s · %s · %s\n", $3, $2, $4, $5 }'

exit 0
