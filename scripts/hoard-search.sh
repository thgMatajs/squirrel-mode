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
# have told them. The ways it did exactly that have been fixed rather
# than accepted, not tolerated - a regular file awk cannot open, a CRLF or a BOM
# anywhere in the frontmatter, whitespace on either side of a key or a
# value, a one-character search term thrown away for being one character
# long, and a query whose terms really were all discarded - each one
# reproduced first and pinned by a scenario in tests/test_hoard.sh.
#
# THE LAST OF THOSE IS ANSWERED WITH A SENTENCE, NOT WITH SILENCE. A
# query nothing survives is the one case where an empty stdout is
# correct and still misleading, because the user asked a real question: a
# single accented letter on its own leaves this tokeniser nothing to look
# for. So stdout stays empty and the exit stays 0, and ONE line goes to
# stderr saying the terms were unusable. skills/dig/SKILL.md relays that
# line instead of telling the user there is nothing in the hoard about it.
#
# What silence still covers is a file with no frontmatter delimiters at
# all and a file with no `title`: neither can be ranked or displayed,
# and both are states nothing in squirrel-mode writes.
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
# would end the search there. Any VALUE of more than four digits is out
# of range by construction, so it never reaches an arithmetic test.
#
# WHICH IS WHY THE LEADING ZEROS COME OFF FIRST. `${#topk}` counts
# CHARACTERS, and `00005` is five characters carrying one digit of
# value, so the length test read it as out of range and clamped it to
# 1000. Measured on the committed script against a twelve-memory store:
# `-k 5` and `-k 0005` each returned 5 results, `-k 00005` and
# `-k 000000000000000005` each returned all 12 - the whole store, from a
# request for five. The boundary was exactly five characters, and the
# sentence above used to say no such value could exist. Stripping the
# zeros makes the length test measure the value, which is what it was
# always meant to measure; `0`, and any run of zeros, still reduces to
# `0` and falls through to the `-lt 1` arm below.
case "$topk" in
  '' | *[!0-9]*) topk=5 ;;
  *)
    while :; do
      case "$topk" in
        0?*) topk=${topk#0} ;;
        *) break ;;
      esac
    done
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
# against about 84 ms for the whole awk pass it was feeding. That second
# figure used to read 110 ms here, and 110 ms was published wrong:
# docs/specs/2026-08-13-hoard-design.md §5.1 and README.md both now say
# so in as many words, having re-measured the phases inside one run at
# about 41 ms expanding the globs, 29 ms in the prescan, 84 ms in awk and
# 2 ms in the trailing pipeline. Only the awk figure moved; the ratio
# this paragraph is about did not, because 12.05 s against either number
# is the same two orders of magnitude. Assigning each layer's expansion
# in a single `set --` makes that one copy per layer instead of one per
# file. tests/test_hoard.sh scenario 14 pins the shape so the per-file
# form cannot come back unnoticed.
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
# That residue costs the record before it and everything after it,
# exactly as before - it is narrower than the class this test closes,
# not different in kind.
#
# IT IS NOT SILENT, THOUGH, AND THAT DIFFERENCE IS THE ONLY WAY TO TELL
# THE TWO APART. The class this test CLOSES is filtered before awk ever
# sees it: stdout is complete and stderr is empty, which is what
# scenario 16d asserts. The residue is awk failing on an open it was
# handed, and awk says so - measured here, one unreadable file among
# three: exit 2, stdout short, and 409 bytes of `awk: can't open file
# ...` on stderr, its length following the length of the path. So a
# short answer with an empty stderr is this script dropping something,
# and a short answer with an awk diagnostic on stderr is the race. The
# word "silence" was in this paragraph and was wrong about the case it
# describes.
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
  # "n" plus "o" is all it can make of the Portuguese for "no", and those
  # two pieces are dropped as fragments of a word this tokeniser cannot
  # spell rather than as terms that were merely short. A one-character
  # term the user actually typed is kept - see the comment on the
  # tokeniser itself for the difference, and for why it is drawn on the
  # word rather than on the fragment.
  #
  # Measured on the committed script, against a two-memory hoard: `nao`
  # spelled with its tilde, and `que`, each returned EVERY memory with
  # the scores of a search that had no terms in it at all. The same holds
  # for the Portuguese for "action", "are" and "only", and for any single
  # accented letter.
  #
  # RETURNING 0 HERE IS HALF THE ANSWER. It stops the store being handed
  # back as though it answered the question; it does not tell the user
  # their question was never asked, and an empty result reads as "nothing
  # in the hoard about that". The tokeniser puts one line on stderr for
  # exactly that, and skills/dig/SKILL.md relays it.
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
function is_finite(v,   t) {
  # Is v an ordinary number, as opposed to an infinity or a nan?
  #
  # THE TWO IDIOMS THAT ANSWER THIS EVERYWHERE ELSE BOTH FAIL ON THE awk
  # macOS SHIPS, which is the awk most users of this plugin will run.
  # Measured on the three this project meets, each named from what its own
  # version flag printed rather than from memory - awk version 20200816
  # (macOS 26.5.2), GNU Awk 5.4.1 and mawk 1.3.4 20260302 - same
  # expressions, same values:
  #
  #     v = "nan" + 0      v >= 1     v != v     sprintf("%.1f", v)
  #     awk 20200816           1          0      "nan"
  #     GNU Awk 5.4.1          0          0      "0.0"   (reads "nan" as 0)
  #     mawk 1.3.4             0          0      "0.0"   (reads "nan" as 0)
  #
  # So on the one awk that produces a nan at all, a nan compares as
  # GREATER THAN OR EQUAL TO 1 and is EQUAL TO ITSELF. Negating the range
  # test does not catch it and neither does the textbook `v != v`.
  #
  # WHAT DOES WORK IS THE FORMATTED VALUE, because printf is the C
  # library on all three and neither an infinity nor a nan can be spelled
  # with digits. `%.1f` of a finite double is always `-?<digits>.<digit>`;
  # of the others it is "nan", "inf", "+inf" or "-inf", all of which fail
  # this pattern on all three of those awks. Checked on all three, both
  # directions - including 1e300, which formats as three hundred digits and
  # correctly reads as finite.
  t = sprintf("%.1f", v)
  return (t ~ /^-?[0-9]+\.[0-9]$/)
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

  # FINITENESS IS DECIDED FIRST, AND THE CLAMPS ONLY THEN. `imp < 1` and
  # `imp > 5` are both false for a nan, so `importance: nan` walked
  # straight through a clamp that reads as though nothing could, and
  # carried the nan into the score and into the ordering key. The two
  # obvious repairs do not work here - see is_finite() for the
  # measurement - so the range tests below run only on a value already
  # known to be an ordinary number, and everything else takes the same
  # arm a value below the range takes.
  imp = m_importance + 0
  if (!is_finite(imp) || imp < 1) imp = 1
  else if (imp > 5) imp = 5

  # `uses` IS BOUNDED AT BOTH ENDS, AND OUT OF RANGE BUYS NO BOOST RATHER
  # THAN THE LARGEST ONE. A floor alone was the previous fix, and it
  # closed one direction of a defect that has two:
  #
  #   - BELOW: `uses: -1` printed `-inf` and `uses: -5` printed `nan`,
  #     from log(0) and log of a negative, straight into a field this
  #     script promises is a number with four decimal places. Measured on
  #     the script that had no floor.
  #   - ABOVE: `uses: 1e999`, or an integer of 400 digits, is +inf the
  #     moment it is read as a number, and a floor does not look up
  #     there. Measured on the floored script, one fixture, both sides:
  #     the +inf memory printed `inf` where its score belongs and stood
  #     at the TOP of the ranking, above a memory scoring 0.6286. That is
  #     the same failure the floor was added to stop, arriving from the
  #     other end - and it got WORSE when the order moved to the key
  #     below, because every sane ordering key is the log of a score
  #     under 1 and is therefore negative, while `sort -n` reads `inf`
  #     and `nan` as values above every negative one.
  #
  # ZERO, NOT THE CEILING, for a counter outside 0..1000000.
  # Reinforcement is earned by a memory actually being read, so a number
  # no reader could have produced must not buy the top of every search;
  # clamping it to the ceiling would hand it exactly that. The upper end
  # is deliberately a cliff and not a clamp for that reason, and 1000000
  # is far above anything a one-per-read increment reaches.
  uses = m_uses + 0
  if (!is_finite(uses) || uses < 0 || uses > 1000000) uses = 0

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
  # stays readable for centuries of staleness.
  #
  # EVERY TERM IS FINITE BECAUSE BOTH ENDS OF BOTH FIELDS ARE BOUNDED,
  # which is a stronger statement than the one that stood here and had to
  # be. This sentence used to read "uses is floored at 0" and offer that
  # as the reason nothing could be infinite. A floor bounds one end. With
  # `uses: 1e999` the key came out at +inf, and `sort -n` puts +inf above
  # every SANE key - all of which are negative, because a sane score is
  # below 1 and this is its logarithm. So the very change that made the
  # ranking survive decay also made a corrupted counter win the top,
  # where before it had sorted below a positive score. What holds now:
  # rel is in (0, 1] and non-zero (returned above), imp is clamped into
  # 1..5 by a test a nan cannot pass, and uses is zeroed unless it lies
  # in 0..1000000 - see the two clamps above and why each is written the
  # way it is.
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

  # Query tokens: lowercased, split on anything that is not an ASCII
  # letter or digit, with a small stopword set dropped. The stopword list
  # is deliberately tiny - it exists to stop "the" and "a" from making
  # every memory look half-relevant, not to be a linguistics project.
  #
  # A ONE-CHARACTER TOKEN IS KEPT WHEN THE USER TYPED ONE AND DROPPED
  # WHEN THIS TOKENISER MANUFACTURED IT. Those are two different things
  # and one rule on the LENGTH of the token answered them the same way,
  # which
  # lost the first of them outright:
  #
  #   - `c`, `r`, `x`, and so `c++`, `C++`, `C`, `R`, `C#`, `F#`, are
  #     real search terms that people really type. Measured on the
  #     committed script against a store holding
  #     `c++ move semantics bit us in the parser`: `c++`, `C++`, `C` and
  #     `R` each returned zero lines, exit 0, nothing on stderr - a store
  #     with a matching memory in it answering exactly like an empty one,
  #     which the header of this file calls the worst thing it can do.
  #   - the Portuguese for "no", "only" and "action" - each carrying a
  #     tilde, an acute or a cedilla, which this comment is kept ASCII
  #     and so cannot spell - are not one-character terms at all. The
  #     tokeniser replaces every byte that is not an ASCII letter or
  #     digit with a space, so each byte of a multi-byte character
  #     becomes a SEPARATOR, and the word for "no" arrives here as the
  #     two fragments `n` and `o`. Keeping those searches for whatever
  #     memory happens to carry a lone `n` or a lone `o`: measured on a
  #     twelve-memory
  #     bilingual store, accepting them made that word return three
  #     unrelated memories and the word for "action" six - ranked, scored
  #     and looking exactly like an answer. That is the lie scenario 22 of
  #     tests/test_hoard.sh exists to stop, re-arriving by a new route.
  #
  # SO THE TEST IS ON THE WORD, NOT ON THE FRAGMENT. A word carrying any
  # byte outside printable ASCII cannot be spelled in the alphabet this
  # tokeniser indexes, so it contributes only its runs of two characters
  # or more; a word spelled entirely in ASCII contributes all of its
  # runs, one character included. `c++` searches for `c`; `naive` written
  # with a diaeresis over the i searches for `na` and `ve`; the word for
  # "no" contributes nothing and is answered by the stderr line below.
  # `[^ -~]` is a BYTE range - space through tilde - which is well defined
  # because this awk runs under LC_ALL=C.
  #
  # `a`, `e` AND `o` JOIN THE STOPWORD LIST FOR THAT SAME CHANGE, and the
  # measurement is why. They are the English and Portuguese articles, and
  # they stand alone in ordinary titles constantly, so accepting
  # one-character tokens without them re-ranked queries that have nothing
  # to do with any of this: on the same fixture, `a race in the parser`
  # went from two memories tied at 0.4000 to seven, five of them matching
  # nothing but a lone `a` at 0.1500, and the top two swapped places.
  # With the three letters stopped, that query returns byte-identically
  # what it returned before. What a real one-character term gains is
  # unaffected - `c` and `r` are not articles.
  q_n = 0
  q_dropped = 0
  if (query != "") {
    nw = split(query, qwords, " ")
    for (w = 1; w <= nw; w++) {
      word = tolower(qwords[w])
      shredded = (word ~ /[^ -~]/)
      gsub(/[^a-z0-9]+/, " ", word)
      c = split(word, qparts, " ")
      for (i = 1; i <= c; i++) {
        t = qparts[i]
        if (shredded && length(t) < 2) continue
        if (t == "a" || t == "e" || t == "o") continue
        if (t == "the" || t == "and" || t == "for" || t == "que" || t == "com" || t == "para") continue
        q_n++
        q_tok[q_n] = t
      }
    }
    # The user gave terms and nothing usable survived. relevance() reads
    # this to tell that apart from a search with no terms at all - and
    # the caller is TOLD, because an empty stdout on its own says "the
    # hoard holds nothing about that", which is a different statement and
    # may well be false. One line, on stderr, so stdout stays exactly the
    # four-field format callers parse and the exit status stays 0.
    #
    # THE QUERY IS NOT ECHOED INTO IT. It is text the user typed and may
    # carry a newline, which would make this two lines instead of one.
    #
    # LIMIT, WRITTEN DOWN: this runs inside the awk pass, so a hoard that
    # is missing or holds no readable file exits above without printing
    # it. That state is the one where an empty answer is honest anyway -
    # the store really does hold nothing - and buying the line there
    # would mean a second copy of this tokeniser in the shell, which is
    # the drift this file spends its length avoiding.
    if (q_n == 0) {
      q_dropped = 1
      print "hoard-search: no usable search term - every term given was a stopword or held no letter or digit this reader can look for, so the hoard was not searched." > "/dev/stderr"
    }
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
  # A UTF-8 BOM sits in front of the first "---" and makes the same line
  # fail the same test, and the memory is lost to every search the same
  # way. Editors write one without being asked; a user cannot see it.
  #
  # ON EVERY LINE, NOT ONLY THE FIRST. This test used to sit in the
  # FNR == 1 rule below, where it caught the case an editor really
  # produces and nothing else. The same three bytes on line 9 instead of
  # line 1 made the key on that line "<BOM>title" rather than "title", so
  # memory had no title, and emit() drops a memory with no title without
  # a word - the store answering like an empty one again, from an input
  # no one can see. Reproduced. It is a LOW-REALISM input and it is
  # closed anyway, because closing it is one substr on a line this rule
  # already touches, which is cheaper than the paragraph that would have
  # had to explain why it was left open. (A BOM and CRLF together, which
  # is what a Windows editor actually writes, worked before this change
  # and works after it: the two strips are independent and the CR comes
  # off first.)
  if (substr($0, 1, 3) == bom) { $0 = substr($0, 4) }
}
FNR == 1 {
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
  # EVERY SIDE IS TRIMMED - both ends of the key and the tail of the
  # value - and each trim is load-bearing:
  #
  #   - the KEY kept whatever sat AFTER it, so `status : active` parses
  #     as the key "status " and matches nothing. The memory keeps every
  #     default instead: no title, and so no result at all.
  #   - the KEY kept whatever sat BEFORE it too, which is the same
  #     keystroke arriving from the other side of the word and cost the
  #     same memory. `  title: indented title` parses as the key
  #     "  title", matches nothing, the memory has no title, and emit()
  #     drops a memory with no title: zero bytes of stdout with `--all`
  #     and without, exit 0, nothing on stderr. Reproduced. This comment
  #     used to say that leading space was kept DELIBERATELY, because an
  #     indented key belongs to a nested YAML mapping. That described a
  #     parser this is not - there is no notion of nesting anywhere in
  #     this program - and what the reasoning actually bought was not
  #     "this key belongs to something else" but "this memory does not
  #     exist".
  #   - the VALUE kept whatever sat after it. `status: active ` - one
  #     trailing space, which no editor shows - is not "active", so
  #     the memory was excluded from every default search and returned
  #     only by `--all`. That is a memory deleted by a keystroke nobody
  #     can see, and skills/stash/SKILL.md tells the model to WRITE this
  #     field and skills/dig/SKILL.md to EDIT it on every read.
  #
  # WHAT THE LEADING TRIM COSTS, said rather than implied: in a file that
  # really did carry a nested mapping, an indented `title:` under some
  # other key is now read as the title of this memory, last one winning.
  # Nothing in squirrel-mode writes such a file - the frontmatter stash
  # writes is nine flat keys and dig edits two of them - and a memory
  # read slightly
  # wrong is recoverable where a memory that silently does not exist is
  # not.
  key = $0
  sub(/:.*$/, "", key)
  sub(/^[ \t]+/, "", key)
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
