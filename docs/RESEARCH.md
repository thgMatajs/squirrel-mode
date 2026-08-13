# Research foundation

## What this document is

This is the evidence log for `squirrel-mode`. 10 of the 16 base rules in `rules/base-rules.md`
trace to at least one finding below; every finding carries the citations behind it, tagged with the
population they rest on — measured, where the citation measured anyone, and marked as borrowed
reasoning where it did not. The other 6 rules are stated design decisions with no research claim
behind them — named plainly in "Rules with no research claim behind them" below, not folded into
the findings as if they had citations they do not have.

## Rules with no research claim behind them

Six of squirrel-mode's sixteen base rules are product and ergonomic decisions, not empirical
claims. They appear in no `Rules justified:` line below because there is nothing to cite —
inventing a citation for a product choice is exactly the failure this document exists to prevent.
Named plainly instead:

- **Rule 5 (Respect code style).** Whether someone processes code better seeing the block first or
  the steps first is a preference, not a measured effect; `code_style` is a switch, not a citation.
- **Rule 9 (Answer multiple questions in order).** Answering fewer questions than were asked is a
  correctness bug for any user, in any population — it needs no ADHD-specific citation to justify
  it.
- **Rule 10 (Confirm before switching topics).** Not silently changing the subject on someone is
  ordinary conversational courtesy, not a cognitive-load finding.
- **Rule 12 (Respond in the user's language).** Table-stakes usability: no citation makes an
  assistant answering in the wrong language acceptable, and none is needed to make it
  unacceptable.
- **Rule 13 (Safety override).** A deliberate product guardrail — brevity rules never suppress a
  warning about a destructive operation, security issue, or data loss — because the other fifteen
  rules exist, not because of a finding about ADHD.
- **Rule 16 (Match tone).** `tone` is a register preference (`neutral`/`warm`/`terse`); nothing
  here claims one register improves comprehension over another for anyone.

## What this document is not

This is not a systematic review. It is not exhaustive, it was not produced by a structured search
protocol with pre-registered inclusion criteria, and no claim here should be read as "the
literature says" — only as "these specific, verified sources say, in this specific population."

The population tags exist so a reader can weigh each claim's category of evidence at a glance,
without reading every paper. That promise is about category, not about every distinction within
one: the tag alone cannot separate a clinical diagnosis from an ADHD-symptom-severity score in a
non-clinical sample — both sit under the same `ADHD` label, and telling them apart means reading
the finding's prose (Findings 8 and 12 are the dimensional case, and say so there). Nor can the tag
separate a population a paper *measured* from one it merely writes *for*: Speicher & Chandrasekar
(2025), under Finding 4, carries `borrowed from adjacent accessibility work` but recruited nobody,
and Finding 4 states that in prose because the tag cannot. Where a citation measured no one in any
population, the honest move is no tag at all rather than the nearest-fitting one — the *Tether*
entry under "Related work" carries none, and says why in place of it. A rule justified by a large
ADHD-population finding and a rule justified by sound reasoning borrowed from a different
disability population are not the same strength of evidence, and this document never lets them look
the same.

## Citation policy

**All four of the following must hold before a citation enters this document. Identity alone is
not verification** — see the note below the checklist for why that distinction exists at all.

1. **Identity** — exact title, full author list in order, year, and venue, checked against a
   primary source (the paper, its abstract page, or its publisher/indexing record). A working link
   is recorded for each.
2. **Support** — the paper's own abstract or results state the thing this document attributes to
   it — not something adjacent to it, not a looser version of it, and never the opposite of it.
3. **Whose finding it is** — the sentence being leaned on is the paper's *own* result, not its
   summary of a third party's finding. A paper citing someone else's work is not evidence for that
   work; cite the third party directly, and verify the third party against all four checks too.
4. **Population** — tag it with exactly one or more of these three labels, and no other label
   exists:
   - `ADHD` — measured in an ADHD population: a clinical diagnosis, or, where the finding's prose
     says so explicitly, ADHD-symptom severity scored in a non-clinical, dimensional sample. The
     tag alone cannot distinguish the two; Findings 8 and 12 are both the dimensional case, and say
     so in their prose — read it before weighing the tag.
   - `general working memory` — measured in a general population, not specific to ADHD.
   - `borrowed from adjacent accessibility work` — sound reasoning, applied to ADHD by inference,
     from research on a *different* disability population.

If a claim does not clear all four checks, it does not appear here — not softened, not hedged, not
footnoted as "attributed to." It is either removed outright or rewritten to rest only on what
checks 1 through 4 actually support. See "Corrections" and "What we could not verify" below for
every place this happened.

**Check 2 is the one that gets skipped, and skipping it is worse than a typo.** An earlier
verification pass on this file checked identity only and passed five citations that were
bibliographically pristine and substantively wrong — including the opening claim, whose flagship
source stated in its own abstract that it found *no* group difference in how much increasing load
disrupted working-memory performance, the opposite of what this file claimed on its strength. A
correctly identified paper used to support something it does not say is the failure a hostile
reader finds first, and it is worse than an uncited claim, because it *looks* verified. All five
identity misattributions from the first pass, every substance failure the second pass turned up, and
the ten corrections a third pass found on top of both — among them a finding that asserted the
reverse of its own source's result, and a population tag resting on a source that never mentions
that population — are recorded in full in "Corrections" below. Both of those had sat in this file
since it was written, through both earlier passes, because neither pass was scoped to re-read a
citation nobody had flagged. Being checked once is not the same as being checked.

---

## Finding 1: Working memory capacity is the bottleneck

Working memory holds a small number of chunks and loses content when new stimuli compete for the
same limited store.

**Population:** general working memory

**Citations:**
- Cowan, N. (2010). *The Magical Mystery Four: How Is Working Memory Capacity Limited, and Why?*
  Current Directions in Psychological Science, 19(1), 51–57.
  <https://pubmed.ncbi.nlm.nih.gov/20445769/>

Working memory is not a single undifferentiated buffer, either: Baddeley & Hitch's model separates
it into parallel subsystems (a phonological loop, a visuospatial sketchpad, a central executive)
rather than one shared store. It is cited here only for that architectural point, not for the
capacity number above, which is Cowan's alone — the two claims are compatible but distinct, and
folding them into one sentence was overreach corrected below (see Corrections).

**Population:** general working memory

**Citations:**
- Baddeley, A. D., & Hitch, G. J. (1974). *Working Memory*. In G. H. Bower (Ed.), *Psychology of
  Learning and Motivation*, Vol. 8, pp. 47–89. Academic Press.
  <https://www.sciencedirect.com/science/article/abs/pii/S0079742108604521>

⚠ Cowan's discrete-chunk account is not settled science, and this document previously presented it
as though it were. A competing family of models treats working memory as a continuous resource
shared out across items, with no fixed limit on how many are held — on that view it is the *quality*
of each representation, not a count of slots, that sets performance. This is a live dispute, not a
retraction: no replication failure, two accounts that each fit substantial evidence, and no
resolution to report. Nothing built on Cowan here needs the number to be four, or to be a count of
discrete items at all. What the rules below actually lean on is that concurrent capacity is small and
is exceeded easily — common ground between both accounts, and all that is claimed.

**Population:** general working memory

**Citations:**
- Ma, W. J., Husain, M., & Bays, P. M. (2014). *Changing concepts of working memory*. Nature
  Neuroscience, 17(3), 347–356. <https://pubmed.ncbi.nlm.nih.gov/24569831/> — cited for the
  existence of the dispute, not to settle it. Its own abstract names the account under contest
  ("Working memory is widely considered to be limited in capacity, holding a fixed, small number of
  items, such as Miller's 'magical number' seven or Cowan's four") and states the alternative in its
  own voice: "It has recently been proposed that working memory might better be conceptualized as a
  limited resource that is distributed flexibly among all items to be maintained in memory."

Adolescents and young adults with ADHD show a disproportionate drop in working-memory accuracy as
load increases, specifically more so than neurotypical peers at the same load levels.

**Population:** ADHD

**Citations:**
- Mukherjee, P., Hartanto, T., Iosif, A.-M., Dixon, J. F., Hinshaw, S. P., Pakyurek, M., van den
  Bos, W., Guyer, A. E., McClure, S. M., Schweitzer, J. B., & Fassbender, C. (2021). *Neural basis
  of working memory in ADHD: Load versus complexity*. NeuroImage: Clinical, 30, 102662.
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC8175567/> — its own Results state a significant
  diagnosis-by-load interaction, and the figure caption states plainly: "the ADHD, versus NT group,
  showed greater drop in accuracy due to increased load." Ages 12–23 (50 ADHD, 82 neurotypical);
  described here as adolescents and young adults, not "adults," to match the sample.

**Rules justified:** 3, 4, 6 — cap the number of steps shown at once in multi-step task work (3),
keep one idea per paragraph (4), and never present more than the configured number of decisions at
once (6).

---

## Finding 2: Incremental presentation and external cues reduce load — inference, not a direct ADHD-population test

External storage, explicit cues, and incrementally delivered information keep the amount of
information held open at any one moment below the small concurrent capacity Finding 1 establishes,
rather than adding to it — "small," not "four," because Finding 1 records that the exact form of that
limit is disputed. No source found tests cues or incremental presentation directly in an ADHD
sample: the two citations previously attached to this finding do not support it on inspection.
Mukherjee et al. (2021)'s sentence about external storage and cues sits in its Introduction,
explicitly attributed there to "earlier work," not to its own experiment — its own result is the
diagnosis-by-load interaction now cited correctly in Finding 1. Martinussen et al. (2005) is a
diagnostic meta-analysis of working-memory *impairment magnitude* in children with ADHD; its own
abstract reports effect sizes by WM subcomponent (marked deficits in spatial storage and the
spatial central executive, modest deficits verbally) and says nothing about cues, external storage,
or presentation format at all. Both are removed from this finding; see Corrections.

What remains is general reasoning, not ADHD evidence: Finding 1 already establishes, via Cowan
(2010), that working memory holds only a handful of chunks at once, and via Mukherjee et al. (2021)'s
own result, that ADHD-population accuracy is *more* load-sensitive than controls, not less. Keeping
concurrent load low by presenting information incrementally and marking it with explicit cues
follows from that capacity limit whether or not any study has tested cues themselves in an ADHD
sample — the same kind of borrowed, inference-based reasoning this document already labels honestly
in Finding 4, applied here instead of imported from a different population.

**Population:** general working memory

**Citations:**
- Cowan, N. (2010). *The Magical Mystery Four: How Is Working Memory Capacity Limited, and Why?*
  Current Directions in Psychological Science, 19(1), 51–57.
  <https://pubmed.ncbi.nlm.nih.gov/20445769/> — cited already in Finding 1 for the same capacity
  limit; repeated here because it is what this finding's inference rests on.

**Rules justified:** 3, 8 — numbered or checklist steps act as the external cue; the progress recap
carries state across turns instead of asking the reader to hold it. Weaker justification than most
findings in this file: these rules also stand on Finding 1 directly, and would not fall if this
finding were removed entirely.

---

## Finding 3: Working memory and processing speed are separable, and the load runs memory → speed

⚠ The planning draft, and both earlier verification passes, asserted that "slower processing keeps
capacity occupied by ongoing work rather than freeing it up." That is the *reverse* of what this
finding's own flagship citation reports. Kofler et al. (2020) carries the subtitle *Evidence for
directionality of effects* precisely because it tested that direction and did not find it. The
clause is retired here rather than softened (see Corrections).

Increasing working-memory demand measurably slows information processing. Experimentally slowing
information processing does *not* measurably change working-memory performance. In an ADHD sample
the two behave like separable impairments rather than one driving the other, and children with ADHD
fall behind specifically when a task requires holding and recalling material rather than merely
taking it in.

**Population:** ADHD

**Citations:**
- Kofler, M. J., Soto, E. F., Fosco, W. D., Irwin, L. N., Wells, E. L., & Sarver, D. E. (2020).
  *Working memory and information processing in ADHD: Evidence for directionality of effects*.
  Neuropsychology, 34(2), 127–143. <https://doi.org/10.1037/neu0000598> — 86 children (45 with
  ADHD, 41 without), eight fully crossed experimental tasks. Its own Results state that "increasing
  working memory demands produced significant reductions in information processing speed," while
  "experimentally reducing children's information processing speed did not significantly change
  their working memory performance." The ADHD and non-ADHD groups "showed equivalently high accuracy
  under the encoding-only conditions" but "differed significantly under high working memory
  conditions (encoding + recall)." Its stated conclusion: working-memory deficits and slowed
  information processing speed "appear to be relatively independent impairments in ADHD."

Both functions do track academic outcomes in children with ADHD — the part of the original claim
that survives intact:

**Population:** ADHD

**Citations:**
- Hulsbosch, A.-K., Van der Oord, S., & Tripp, G. (2025). *Academic Achievement in Children with
  ADHD: the Role of Processing Speed and Working Memory*. Research on Child and Adolescent
  Psychopathology, 53(10), 1469–1484. <https://doi.org/10.1007/s10802-025-01346-6> — 504 children
  aged 6–12 diagnosed with ADHD; its own abstract reports that the association between inattention
  symptom severity and achievement across mathematics, reading and spelling "is statistically
  mediated by PS and WM sequentially."

**These two citations disagree with each other, and this document does not paper over it.** Hulsbosch
et al. build on "recent evidence [that] suggests both cognitive functions are related, where slower
PS underlies WM deficits," and their own mediation analysis reports that processing speed
"statistically mediated the relation between inattention symptom severity and WM performance" —
processing speed acting *on* working memory. Kofler et al. manipulated processing speed
experimentally and found no such effect on working memory, concluding the two are relatively
independent. A correlational mediation path and a null experimental manipulation are not the same
kind of evidence, and they do not resolve each other here. What both support — and all this finding
claims — is that working memory and processing speed are separable contributors in ADHD and that
both track academic outcomes. The *direction* between them is contested, and nothing in this
document rests on settling it. This is the same tension the Baddeley & Hitch tightening records in
Corrections, surfaced here rather than left for a reader to discover.

**Rules justified:** 1, 4 — **applied inference, not a measured effect**, flagged the way Findings 2,
4 and 7 flag theirs. Neither paper studies answer position, paragraph length, or reading order; they
measured laboratory tasks and school achievement. The step taken here starts from Kofler et al.'s
own ADHD-population result that encoding *plus recall* is where the ADHD group fell behind while
encoding alone was not: a response stating its answer first is closer to the encoding-only case,
where the groups performed equivalently, whereas a response that buries the answer behind setup asks
the reader to hold that setup and recall it when the answer finally arrives (1). Shorter paragraphs
reduce how much must be held at once, for the same reason (4). Rule 4 does not depend on this
finding — Findings 1, 10 and 11 reach it independently — but rule 1 rests on this finding alone, so
the inferential step above is the whole of rule 1's support, and is stated plainly rather than
implied.

---

## Finding 4: Extraneous content is not neutral

Content held in working memory is abandoned to make room for new stimuli, and cognitive load theory
distinguishes load that is intrinsic to a task from load added by how the material is presented —
the latter is pure cost with no benefit.

⚠ The planning draft, and an earlier verification pass on this file, cited Sweller (1988) for this
distinction. That paper (*Cognitive Load During Problem Solving: Effects on Learning*) is about
means-ends problem solving versus worked examples; the words "intrinsic" and "extraneous" do not
appear in it anywhere. The intrinsic/extraneous distinction was introduced later, and is cited
correctly below (see Corrections).

**Population:** general working memory

**Citations:**
- Sweller, J., & Chandler, P. (1994). *Why Some Material Is Difficult to Learn*. Cognition and
  Instruction, 12(3), 185–233. <https://doi.org/10.1207/s1532690xci1203_1> — its own abstract states
  the distinction directly, as assumption (e) of the six it lists: "High levels of element
  interactivity and their associated cognitive loads may be caused both by intrinsic nature of the
  material being learned and by the method of presentation." It concludes "that an analysis of both
  intrinsic and extraneous cognitive load can lead to instructional designs generating spectacular
  gains in learning efficiency."

A code-presentation application of this reasoning exists, aimed at blind and low-vision developers
rather than ADHD. It is included as sound cognitive-load reasoning applied by inference to a
different population, and it is labelled that way, not as ADHD evidence.

⚠ It is also not a study, and this file twice said it was. Correction #2 below already re-examined
this citation and fixed its population framing, while leaving the claim that it *studied* that
population untouched — a good illustration of how a correction can fix the error it went looking for
and walk past the one beside it. The paper has no participants. Its own abstract states what it
does: "we identify aspects of CL that impact performance and learning in programming," and "We
propose an initial design 'recommendations' for presentation of code." Nobody was recruited,
interviewed, or tested. It is a theoretical paper proposing design recommendations *for* a
population, not a measurement *of* one, which makes the inference this document draws from it one
step longer than the population tag alone suggests.

**Population:** borrowed from adjacent accessibility work

**Citations:**
- Speicher, N., & Chandrasekar, P. (2025). *Theoretical basis for code presentation: A case for
  cognitive load*. arXiv:2511.14636 [cs.HC]. <https://arxiv.org/abs/2511.14636> — a theoretical
  paper about **blind and low-vision developers**, with no participants and no empirical
  measurement; it frames its proposed recommendations as reducing cognitive load for that
  population, not for ADHD.

**Rules justified:** 2, 7 — no preamble/postamble and no tangents are both instances of "content
that was not asked for is not free," applied to the assistant's own output.

---

## Finding 5: Chunking instructions is ordinary classroom guidance — general-education, not ADHD-measured

⚠ This finding used to claim that guidance for ADHD converges on three specific accommodations —
one topic at a time, staying goal-oriented, and chunking instructions into smaller pieces — under an
`ADHD` population tag. Reading both sources' own text retired most of that claim and the tag with it
(see Corrections). Meltzer & Basho (2010), the only source of the three recommendations, is a
general-education chapter: across the publisher's posted chapter text — the whole chapter body,
running through its own concluding section, though not the book's consolidated reference list —
"ADHD," "attention deficit" and "attention-deficit" occur zero times.

Of the three recommendations, one survives, in the chapter's own words: "Information should be
broken down into manageable chunks or steps." A second is weaker than it was made to sound — the
chapter asks teachers to make the classroom *environment* "goal-oriented," which is a claim about
classroom culture, not about sequencing instruction. The third, "one topic at a time," appears
nowhere in the chapter and is retired outright. The chapter addresses every student in a
general-education classroom — "All students—including high achievers, low achievers, and students
with diagnosed learning and attention problems" — which is general guidance that happens to include
students with attention problems, not guidance measured in an ADHD population.

**Population:** general working memory

**Citations:**
- Meltzer, L., & Basho, S. (2010). *Creating a Classroomwide Executive Function Culture That Fosters
  Strategy Use, Motivation, and Resilience*. In L. Meltzer (Ed.), *Promoting Executive Function in
  the Classroom*. Guilford Press. <https://www.guilford.com/excerpts/meltzer2.pdf> — a
  practitioner-oriented classroom chapter, not an empirical trial; cited for the chunking
  recommendation quoted above and for nothing else.

Guidance written specifically for students with ADHD does exist, and does discuss working-memory
weakness in the classroom. Its own abstract carries none of the three recommendations above, and its
full text is paywalled, so this document does not attribute them to it:

**Population:** ADHD

**Citations:**
- Martinussen, R., & Major, A. (2011). *Working Memory Weaknesses in Students With ADHD:
  Implications for Instruction*. Theory Into Practice, 50(1), 68–75.
  <https://www.tandfonline.com/doi/abs/10.1080/00405841.2011.534943> — a review article, not a new
  measurement. Its own abstract states that it "highlights recent studies examining working memory
  functioning in students with ADHD" and that "the authors discuss how educators can address working
  memory weaknesses in the classroom." Per check 3, the studies it highlights are third parties' and
  are not evidence here; per check 2, none of the three recommendations appears in its abstract.

**Rules justified:** 3 — multi-step work is always chunked and enumerated, one phase visible at a
time. This now rests on the Meltzer & Basho chunking recommendation, which is `general working
memory`, not `ADHD`. Rule 3 does not depend on this finding at all: Findings 1, 2 and 10 reach it
independently, and two of those three are ADHD-population results.

---

## Finding 6: Context switching destroys the mental model; recovery is expensive

Working-memory weaknesses in ADHD manifest concretely as trouble with context-switching and
difficulty remembering what one was doing before an interruption.

**Population:** ADHD

**Citations:**
- Liebel, G., Langlois, N., & Gama, K. (2024). *Challenges, Strengths, and Strategies of Software
  Engineers with ADHD: A Case Study*. In Proceedings of the IEEE/ACM 46th International Conference
  on Software Engineering: Software Engineering in Society (ICSE-SEIS 2024). Also arXiv:2312.05029
  <https://arxiv.org/abs/2312.05029>.

A widely repeated "~23 minutes to recover from an interruption" figure, often attributed to Gloria
Mark's UC Irvine research, does **not** trace to a primary peer-reviewed source (see Corrections).
It has been removed; this finding rests on Liebel et al. alone.

**Rules justified:** 8, 14 — the progress recap and the checkpoint/Done-log mechanism exist
specifically to make resuming after an interruption cheap instead of expensive.

---

## Finding 7: Difficulty starting, finishing, and staying on a task

⚠ The planning draft, and an earlier verification pass, framed this finding as "ADHD developers
tend toward over-engineering tasks they find enjoyable and have trouble stopping, tied to
response-inhibition regulation," citing Liebel et al. alone. Two separate problems were found in
that sentence on closer reading, and both are corrected below rather than hedged (see Corrections).

First, the over-engineering claim is not Liebel et al.'s own finding. Liebel, Langlois & Gama
(2024) write: "The rare SE literature (Gama and Lacerda, 2023) on neurodiversity brings some
evidence of ADHD developers tending to do over-engineering in tasks they enjoy and have trouble
stopping" — Liebel et al. are citing Gama & Lacerda (2023) for it, not reporting it themselves.
Per this policy's check 3, that makes Gama & Lacerda (2023) the citation this claim needs, not
Liebel et al. Gama, K., & Lacerda, A. (2023), *Understanding and Supporting Neurodiverse Software
Developers in Agile Teams* (SBES 2023, DOI 10.1145/3613372.3613384), is a real, identifiable pilot
study of ADHD and autistic developers — identity and population check out. Its own full text sits
behind the ACM Digital Library paywall; every route tried to reach it directly failed (ACM abstract
and full-text pages, Google Scholar, ResearchGate, Semantic Scholar, the OpenAlex and Unpaywall
indexing records, the authors' institutional pages) and its indexed abstract is a general pilot-study
summary that does not itself mention over-engineering. Check 2 — support, from the paper's *own*
abstract or results — could not be cleared. Per this file's policy, an unverified claim does not
stay dressed as a finding: the over-engineering claim is retired here rather than re-attached to a
citation this document could not read (see "What we could not verify").

Second, the response-inhibition citation was tied to the wrong theme. Liebel et al.'s own
discussion of response inhibition is not about enjoyable-task hyperfocus at all — it is about the
opposite problem: "Challenges such as Doing Boring Tasks or Starting and Finishing are related do
delayed aversion and the search for quick rewards (Fleming and McMahon, 2012; Crone and van der
Molen, 2004) but also difficulties regulating response inhibition for stopping tasks (Nigg et al.,
2005)" [sic]. That sentence *is* Liebel et al.'s own synthesis of their case study, correctly attributed.
But "difficulties regulating response inhibition for stopping tasks" is itself genuinely ambiguous
between two readings: inhibiting perseveration on the task already in front of you, or inhibiting a
drift toward a different, more rewarding one. The quoted sentence does not disambiguate between
them — nothing in Liebel et al.'s text picks one reading over the other. What rule 15 needs is the
second reading, and adopting it here is an **applied inference**, not something the quote states
unambiguously on its own, matching how Findings 2 and 4 flag their own inferential steps rather than
letting them pass as direct results. On that reading: the pull toward starting something more
rewarding instead of finishing the declared task is response inhibition failing in the
task-switching direction, which is what drifting off the declared task during a conversation looks
like in practice.

**Population:** ADHD

**Citations:**
- Liebel, G., Langlois, N., & Gama, K. (2024). *Challenges, Strengths, and Strategies of Software
  Engineers with ADHD: A Case Study*. ICSE-SEIS 2024. arXiv:2312.05029
  <https://arxiv.org/abs/2312.05029> — own finding, quoted above, on difficulty doing boring tasks
  and starting-and-finishing work, tied to delay aversion and response-inhibition regulation.

**Rules justified:** 15 — the scope guard flags drift once, in one line, and offers to park it
rather than letting the pull toward a more rewarding tangent continue unremarked.

---

## Finding 8: ADHD and the memory of one's own accomplishments

The planning draft framed this as "ADHD blurs the memory of one's own accomplishments," sourced to
practitioner and case-study accounts. That specific framing — often called "success amnesia" in
ADHD coaching literature — has no peer-reviewed source behind it (see "What we could not verify").
What does have peer-reviewed support, in a non-clinical sample screened for ADHD-symptom severity,
is a **negative memory bias**: higher ADHD-symptom scores are associated with stronger recall of
negative material relative to positive material. This is adjacent to, not identical with, the
original claim, and the finding below is restated to say only what the citation supports.

The sample itself is worth naming precisely: 675 adults screened to *exclude* current or past
psychiatric or neurological diagnoses, scored on a continuum of self-reported ADHD-symptom
severity — a non-clinical, dimensional sample, not a clinically diagnosed ADHD population. The tag
below is the closest fit among the three available, but weigh it accordingly.

**Population:** ADHD

**Citations:**
- Vrijsen, J. N., Tendolkar, I., Onnink, M., Hoogman, M., Schene, A. H., Fernández, G., van Oostrom,
  I., & Franke, B. (2018). *ADHD symptoms in healthy adults are associated with stressful life
  events and negative memory bias*. Attention Deficit and Hyperactivity Disorders, 10(2), 151–160.
  <https://pubmed.ncbi.nlm.nih.gov/29081022/>

**Rules justified:** 14 — the Done log exists to put the record of finished work back in front of
the user rather than leaving it to memory, which this finding suggests is systematically biased
against retaining exactly that record.

---

## Finding 9: Time blindness breaks estimation

Time-discrimination difficulty affects deadline management and estimation in ADHD, per the same
case study covering context-switching and hyperfocus.

**Population:** ADHD

**Citations:**
- Liebel, G., Langlois, N., & Gama, K. (2024). *Challenges, Strengths, and Strategies of Software
  Engineers with ADHD: A Case Study*. ICSE-SEIS 2024. arXiv:2312.05029
  <https://arxiv.org/abs/2312.05029>.

The planning draft additionally asserted that "practitioner guidance converges on task atomicity of
≤45 minutes," with no source. A search for that consensus did not find one: ADHD time-management
practitioner sources recommend anywhere from 15 to 60 minutes depending on the person and the task,
with no convergent figure. `/squirrel:plan`'s 45-minute cap on Phase-1 steps is a **design choice**,
not a research finding, and is described that way rather than dressed up with a citation it does
not have.

**Rules justified:** 11 — concrete, non-vague time language in every response.

---

## Finding 10: Reading comprehension in ADHD is measurably affected by presentation format

⚠ This finding used to locate the scoping review's most prominent effect on tasks demanding that a
reader hold and integrate a greater volume of text. The review says something different: the effect
was most prominent where readers had to *produce* something from what they read. The volume-of-text
reading is retired (see Corrections).

Reading comprehension is impaired in ADHD as a general finding across the literature, and *how* it
is measured changes the picture. The review's most prominent effect was in studies where
participants "retell or pick out central ideas in stories" — a demand on what the reader can give
back, not on how much text there was — and some studies found ADHD performance improved "when
reading comprehension task demands were low." Presentation format is not incidental either: removing
the need for self-directed eye movements by presenting text serially, one piece at a time, improved
comprehension for ADHD readers specifically.

**Population:** ADHD

**Citations:**
- Parks, K. M. A., Moreau, C. N., Hannah, K. E., Brainin, L., & Joanisse, M. F. (2022). *The Task
  Matters: A Scoping Review on Reading Comprehension Abilities in ADHD*. Journal of Attention
  Disorders, 26(10), 1304–1324. <https://pubmed.ncbi.nlm.nih.gov/34961391/> — 34 articles met
  inclusion criteria. Its own Results state that "the evidence as a whole suggests reading
  comprehension is impaired in ADHD" and that "the most prominent effect was found in studies where
  participants retell or pick out central ideas in stories"; its Conclusion is that "performance in
  ADHD depends on the way reading comprehension is measured." The title's own point.
- Moussaoui, S., Siddiqi, A., Cheung, T., & Niemeier, M. (2025). *Reading without eye movements:
  Improving reading comprehension in young adults with attention-deficit/hyperactivity disorder
  (ADHD)*. Journal of the International Neuropsychological Society, 31(9–10).
  <https://doi.org/10.1017/S1355617725101628>

**Rules justified:** 3, 4 — numbered/chunked steps and one concept per paragraph are exactly the
"serial, one piece at a time" presentation this finding supports, applied to prose instead of a
reading-comprehension task. That linkage rests on Moussaoui et al. (2025)'s serial-presentation
result, not on the Parks et al. review: the review's contribution here is that reading comprehension
is impaired in ADHD and that the measurement task matters, neither of which is a claim about text
length.

---

## Finding 11: Plain language for neurodivergent readers — a knowledge gap, not yet an established effect

⚠ The planning draft, and an earlier verification pass, opened this finding by asserting
plain-language guidance as a settled, proven benefit for neurodivergent readers generally, citing
the scoping review below as if it confirmed that. It does not, and its own Introduction states the
opposite of a settled effect: "it is unclear what type of information there is in the literature
regarding accessible written communication for neurodivergent individuals, the theories and
approaches used when doing research in this area, and the type of involvement — if any —
neurodivergent individuals have." A paper whose own framing is "it is unclear" cannot support a
claim of a settled, proven effect. That framing is cut outright; nothing softer is substituted in
its place, because nothing softer is what the citation supports either — the honest claim is
narrower still, below.

What the review *does* support: a 2026 scoping review of 25 peer-reviewed studies on accessible
written communication for neurodivergent people found the evidence base concentrated on autism,
dyslexia, intellectual disability, mild cognitive impairment, general learning disabilities, and
complex communication needs — it does not surface ADHD-specific studies, and its own
framing is that the field's evidence base is thin and its shape is not yet clear. This is included
as a documented knowledge gap adjacent to this project's own reasoning, not as evidence that plain
language works — explicitly labelled as such, not stretched into a claim it does not contain.

**Population:** borrowed from adjacent accessibility work

**Citations:**
- Casimiro, C., Sousa, C., & Heron, M. J. (2026). *What Matters in Accessible Written Communication
  for Neurodivergent People? A Scoping Review*. Scandinavian Journal of Disability Research, 28(1),
  71–86. <https://sjdr.se/articles/10.16993/sjdr.1297>

**Rules justified:** 4 — one concept per paragraph, kept short, is this project's own bias toward
plain wording; it does not rest on this citation, which documents a gap rather than an effect.

---

## Finding 12: Higher ADHD-symptom scores cost more effort and less recall in a multimedia study

⚠ This finding used to attach a condition to its result — that the cost held specifically where the
redundant subtitles were present — and to call it a direct ADHD-population confirmation of Finding
4's reasoning. The paper's abstract reports no such conditional, and no interaction between symptom
severity and the redundancy manipulation. It reports a main effect, unqualified by condition. The
full text is paywalled, so per check 2 the interaction cannot be asserted here; the condition is cut
rather than hedged (see Corrections and "What we could not verify").

Adding subtitles to a narrated multimedia presentation is redundant information by cognitive-load
theory's own definition, and the study did manipulate exactly that: "The redundancy group included
subtitles with a narrated multimedia presentation, and the nonredundancy group included the same
presentation with narration only." What its abstract then reports is stated flat, across the study:
"an increase in ADHD symptoms resulted in an increase in mental effort and a decrease in recall and
transfer." That is a genuine, ADHD-dimensional cost on the three outcomes this project cares about —
effort, recall, transfer. It is not, on the abstract alone, a demonstration that the *redundant*
content is what imposed it.

The paper's abstract describes its participants only as "learners," scored on ADHD-symptom
severity rather than by clinical diagnosis; the venue (a journal on educational multimedia) and the
descriptor tags on the indexed record ("Preservice Teachers," "Graduate Students," "Higher
Education") point to a higher-education sample, but the abstract itself does not state this plainly.

**Population:** ADHD

**Citations:**
- Brown, V., Powers, J., Toussaint, M., & Lewis, D. (2020). *Subtitles in a Multimedia Learning
  Environment: The Interplay of Recall, Transfer, and Perceived Mental Effort for Students with
  Attention-Deficit Symptoms*. Journal of Educational Multimedia and Hypermedia, 29(2), 133–150.
  <https://eric.ed.gov/?id=EJ1252029>

**Rules justified:** 2, 7 — no preamble/postamble and no tangents. Stated honestly, this finding is
weaker support for those two rules than it was written to be: it establishes that ADHD-symptom
severity carries a measurable cost in effort, recall and transfer, not that unrequested content is
what imposes that cost. The "content that was not asked for is not free" step belongs to Finding 4's
general cognitive-load reasoning, and rules 2 and 7 rest on it there. What this finding contributes
is ADHD-population evidence that the outcomes that reasoning is about are genuinely at stake in this
population — and no more than that.

---

## Related work: Tether

*Tether* explores the broader category — an LLM-based personalized assistant for developers with
ADHD — combining local activity monitoring, retrieval-augmented generation, and gamification. It
does not validate that category, and does not claim to: its only reported evaluation is "preliminary
validation through self-use," and its abstract states plainly, "While not yet evaluated by target
users."

**No population tag, deliberately.** The three tags in this document name a population a citation was
*measured* in. Tether reports no evaluation in any population — no sample, no participants, self-use
only — so there is nothing to tag, and reaching for `ADHD` because the tool is aimed at people with
ADHD is precisely the slip the tag system exists to catch. This entry justifies no rule in
`rules/base-rules.md`; it is here as related work, not as evidence.

**Citations:**
- Shah, A., Magalhaes, C., Gama, K., & de Souza Santos, R. (2025). *Tether: A Personalized Support
  Assistant for Software Engineers with ADHD*. Accepted, ASE 2025 NIER (New Ideas and Emerging
  Results) track. arXiv:2509.01946 <https://arxiv.org/abs/2509.01946>.

`squirrel-mode` is deliberately smaller: it covers the *communication layer* — how an assistant's
responses are shaped — with **no background process, no activity monitoring, and no
infrastructure**. Tether is the heavier, complementary direction for anyone who wants that; the two
are not competing designs, they operate at different layers.

---

## Corrections

Three errors were identified before this file was written, and are recorded here rather than
silently fixed.

### 1. arXiv:2312.05029 — wrong first author, missing venue

The planning draft cited this paper as "Gama et al." three separate times. The actual author order
is **Liebel, Langlois, and Gama** — Gama is the third author, not the first or an implied sole
author. It is now cited everywhere in this file as Liebel, G., Langlois, N., & Gama, K. The paper
was also missing its venue: it appears in the IEEE/ACM 46th International Conference on Software
Engineering, Software Engineering in Society track (**ICSE-SEIS 2024**), confirmed against the
conference program (`conf.researchr.org`), in addition to its arXiv preprint.

### 2. arXiv:2511.14636 — wrong population

The planning draft treated this as ADHD-adjacent reasoning without stating plainly that its actual
study population is **blind and low-vision developers**. The paper's own framing is about reducing
cognitive load for that population's code-reading experience; it says nothing about ADHD. It is now
tagged `borrowed from adjacent accessibility work` everywhere it appears, and Finding 4 states the
population explicitly in prose, not just in the tag.

### 3. The ~23-minute interruption-recovery figure

The planning draft attributed this figure to "Gloria Mark's work at UC Irvine" as if it were a
number from a peer-reviewed paper. Investigation (tracing the figure through the papers most
commonly cited for it, including Mark, Gudith, & Klocke's 2008 CHI paper "The Cost of Interrupted
Work: More Speed and Stress," which reports the opposite pattern — interrupted tasks completed
*faster*, with more stress) found no primary printed source containing "23 minutes" or "23 minutes
15 seconds." The figure traces to a 2006 Gallup interview in which Gloria Mark stated it verbally;
it was never published as a formal research finding. It has been **removed** from this file. The
context-switching-is-expensive claim (Finding 6) rests on Liebel et al. alone, and does not cite a
recovery-time figure at all.

### Additional corrections found during this verification pass

The task of verifying two other citations the planning draft had not yet confirmed turned up two
more author-attribution errors, beyond the three already known:

- **"Karalunas et al., PMC6996017"** — the draft flagged this ID as unverified. PMC6996017 is real
  and is titled *Constraints on Information Processing Capacity in Adults With ADHD*, but its
  authors are **Roberts, Milich, and Fillmore** (Neuropsychology, 2012), not Karalunas. There is no
  paper by Karalunas with this title. Corrected to Roberts, W., Milich, R., & Fillmore, M. T.
  (2012) — identity fixed at the time, but a second pass (below) found the paper does not support
  what it was attached to and removed it from Finding 1 entirely; see substance failure 1 below.
- **"Salari et al., NeuroImage: Clinical, 2021"** — no author named Salari appears anywhere in this
  paper's eleven-author byline. The actual first author is **Mukherjee**. Corrected to Mukherjee,
  P., et al. (2021) — identity fixed at the time, but a second pass (below) found this paper's own
  result belongs to Finding 1, not the finding it was attached to; it has since been moved. See
  substance failure 1 and substance failure 5 below.

### Substance failures found in a second verification pass

The corrections above all fixed **identity**: right paper, wrong name attached to it. A second
pass — prompted by a reviewer who checked whether each paper's own text actually said what this
file claimed it said — found five citations that were bibliographically correct and substantively
wrong anyway. This is the failure mode check 2 of the citation policy exists to catch, and it is
worse than a typo: every one of these looked verified.

1. **Finding 1's flagship ADHD claim, sourced to the wrong paper.** Roberts, Milich & Fillmore
   (2012) was cited for "adults with ADHD show reduced working-memory accuracy across load
   conditions, and that reduction worsens as load increases." Its own abstract says the opposite for
   working memory specifically: "there was no group difference in the degree to which increasing
   processing load disrupted performance" on the n-back task. The ADHD-specific, load-dependent
   deficit it actually reports is in **response-selection capacity**, on a different task (PRP), and
   the paper frames this explicitly as a **dissociation** between intact working memory and impaired
   response selection — the opposite of a load-dependent working-memory deficit. Removed from
   Finding 1. Replaced with Mukherjee et al. (2021), previously cited (correctly, on identity) in
   Finding 2 for a sentence its own text does not support (see failure 5) — its *own* result, a
   significant diagnosis-by-load interaction with "the ADHD, versus NT group, show[ing] greater drop
   in accuracy due to increased load," is exactly the claim Finding 1 needed, and is now cited there
   instead.
2. **Finding 7 attributed a third party's finding to Liebel et al.** The over-engineering /
   trouble-stopping claim, and its tie to response-inhibition regulation, were both cited to Liebel,
   Langlois & Gama (2024) as if it were their own finding. On inspection, the over-engineering claim
   is Liebel et al. explicitly citing a third party — "The rare SE literature (Gama and Lacerda,
   2023) on neurodiversity brings some evidence of ADHD developers tending to do over-engineering in
   tasks they enjoy and have trouble stopping" — and per check 3 (whose finding it is), that makes
   Gama & Lacerda (2023) the citation needed, not Liebel et al. Gama & Lacerda (2023)'s own full text
   could not be reached to confirm check 2 despite trying every route available (see "What we could
   not verify"), so the claim is retired rather than re-attached to an unread source. Separately, the
   response-inhibition citation was tied to the wrong theme entirely: Liebel et al.'s own
   response-inhibition discussion is about difficulty with boring tasks and starting-and-finishing
   work, not enjoyable-task hyperfocus. It has been reattached to that correct theme instead of
   dropped, since it is Liebel et al.'s own synthesis there. See Finding 7 for the full rewrite.
3. **Sweller (1988) does not contain the intrinsic/extraneous distinction.** Finding 4 (and, by
   reference, Finding 12) cited Sweller, J. (1988), *Cognitive Load During Problem Solving*, for
   cognitive load theory's intrinsic/extraneous distinction. That paper is about means-ends problem
   solving versus worked examples; the words "intrinsic" and "extraneous" do not appear in it. The
   distinction was introduced in Sweller, J., & Chandler, P. (1994), *Why Some Material Is Difficult
   to Learn*, whose own abstract states it directly. Finding 4 now cites the 1994 paper instead.
   Sweller (1988) was also checked against Finding 1's general working-memory claim (holding ~3–5
   chunks, losing content to new stimuli) and found not to support that either — it is not about
   chunk capacity at all — so it has been removed from this file entirely rather than left in a
   place it fits no better. This citation is not in the reviewer's original list; it was found while
   fixing the one the reviewer did flag.
4. **Finding 11's framing contradicted its own citation.** The finding opened by asserting
   plain-language guidance as a settled, proven benefit for neurodivergent readers generally,
   citing Casimiro, Sousa & Heron (2026) as if it confirmed that. That scoping review's own
   Introduction states the opposite of a settled effect: "it is unclear what type of information
   there is in the literature regarding accessible written communication for neurodivergent
   individuals." A citation whose own framing is "it is unclear" cannot support a claim of a
   settled, proven effect. That framing is cut outright; Finding 11 is reframed as documenting a
   knowledge gap, which is what the citation actually supports.
5. **Finding 2 had no primary ADHD-population support for its own mechanism.** Mukherjee et al.
   (2021)'s sentence about external storage, cues, and incremental presentation reducing load sits in
   its Introduction, explicitly attributed there to "earlier work" — not its own experiment, which
   tests a load-versus-complexity interaction instead (now correctly cited in Finding 1). Martinussen
   et al. (2005) is a diagnostic meta-analysis of working-memory impairment magnitude and says
   nothing about cues, external storage, or presentation format anywhere in its own abstract. Both
   removed from Finding 2. Finding 2 is reframed as general cognitive-load inference (retagged
   `general working memory`), not ADHD-population evidence, matching how Finding 4 already labels
   its own borrowed reasoning.

Two further tightenings, smaller than the five substance failures above but found the same way —
by reading what a citation or rule actually says instead of assuming the gloss attached to it was
accurate:

- Baddeley & Hitch (1974) was cited in Finding 1 for a unitary "one shared store" framing that its
  own contribution — a multi-component model with separate parallel subsystems — sits in tension
  with. Narrowed to what it actually establishes (working memory has structure, not that it is one
  store); Cowan (2010) alone now carries the capacity-limit claim.
- Finding 1's rule-linkage gloss said rule 3 caps "the number of items on screen at once," which is
  broader than rule 3's actual text (multi-step task work specifically; rule 9's multiple-question
  handling is explicitly exempt). Tightened to match. Finding 11's rule-linkage to rule 11 (concrete
  time estimates) did not fit a claim about jargon-free prose either; dropped, keeping only rule 4.

### Corrections found in a third verification pass

A third pass re-read every remaining citation against its own primary source. The failures below are
recorded in the same style as the two passes above. Two of them are the worst class this file
defines — a citation asserting the reverse of its source's result, and a population tag resting on a
source that never mentions that population.

1. **Finding 3 asserted the mechanism its own citation tested and rejected.** The finding paired a
   defensible first clause — that working memory and processing speed are at least partly
   independent impairments in ADHD — with a second one reading "slower processing keeps capacity
   occupied by ongoing work rather than freeing it up." That second clause is processing speed
   acting on working memory. Kofler et al. (2020) — subtitled *Evidence
   for directionality of effects* — tested exactly that and reports the opposite: increasing
   working-memory demand "produced significant reductions in information processing speed," whereas
   "experimentally reducing children's information processing speed did not significantly change
   their working memory performance." Its conclusion is that the two "appear to be relatively
   independent impairments in ADHD." The retired clause was not a loose paraphrase of that result;
   it was its reverse, and it had survived two prior verification passes: the first checked identity
   only, and the second — a genuine substance pass — re-read the citations a reviewer had flagged,
   which did not include this one. An unflagged citation was therefore never substance-checked at
   all, which is a gap in how the passes were scoped, not in what either pass did. Finding 3 is rewritten to state only the
   verified direction (memory → speed) plus the ADHD-specific encoding-versus-recall result, and its
   heading, which asserted the same retired direction, is rewritten with it.
2. **Finding 3's two citations contradict each other, and the finding did not say so.** Hulsbosch et
   al. (2025) builds on "recent evidence [that] suggests both cognitive functions are related, where
   slower PS underlies WM deficits" and reports processing speed statistically mediating the path to
   working-memory performance; Kofler et al. (2020) manipulated processing speed and found no effect
   on working memory. This file flags exactly this kind of tension for Baddeley & Hitch above, and
   now flags it here too: the finding states plainly that the direction is contested and that nothing
   in this document rests on settling it.
3. **Finding 5's `ADHD` population tag rested on a source that never mentions ADHD.** The finding
   attributed three recommendations — one topic at a time, staying goal-oriented, chunking
   instructions — to Martinussen & Major (2011) and Meltzer & Basho (2010) jointly, under a single
   `ADHD` tag. The Meltzer & Basho chapter was downloaded and searched — the publisher's posted
   chapter text, covering the whole chapter body through its concluding section, though not the
   book's consolidated reference list: "ADHD," "attention deficit" and "attention-deficit" occur
   zero times in it, and it addresses "All students" in a general-education classroom. Only the chunking recommendation is actually in it ("Information
   should be broken down into manageable chunks or steps"); "goal-oriented" is there but describes
   the classroom environment rather than instructional sequencing; "one topic at a time" is not
   there at all. Martinussen & Major (2011) genuinely is about students with ADHD, but it is a review
   article whose abstract carries none of the three recommendations, and whose full text is paywalled
   — so per check 2 it cannot carry them either. The finding is split into two correctly tagged
   blocks, the chunking claim is retagged `general working memory`, and "one topic at a time" is
   retired. The chapter's title was also mis-transcribed as "classroom-wide"; the printed title reads
   "Classroomwide," and is corrected.
4. **Finding 12's headline required an interaction its source's abstract does not report.** The
   finding stated that higher symptom scores meant more effort and less recall specifically where
   the redundant subtitles were present, and called that a direct ADHD-population confirmation of
   Finding 4. Brown et al. (2020)'s abstract reports a main effect with no condition attached: "an
   increase in ADHD symptoms resulted in an increase in mental effort and a decrease in recall and
   transfer." The study does have redundancy and nonredundancy groups, but the abstract never reports
   symptom severity interacting with them, and the full text is behind a paywall — so check 2 cannot
   be cleared for the conditional. The conditional is cut, the main effect is stated as the paper
   states it, and the finding's own rule-linkage now says plainly that it is weaker support for rules
   2 and 7 than it was written to be. Rules 2 and 7 do not fall: they rest on Finding 4's general
   cognitive-load reasoning, which is where the "unrequested content is not free" step actually
   lives.
5. **Finding 4 called a theory paper an empirical study.** Speicher & Chandrasekar (2025) was
   described as having *studied* blind and low-vision developers. It has no participants: its own
   abstract says the authors identify aspects of cognitive load and propose an initial set of design
   recommendations for presenting code. Nobody was recruited, interviewed, or tested. This one is
   worth naming twice, because Correction #2 above is a correction that already looked at this exact
   citation, fixed its population framing, and left the "studied" claim standing right next to what
   it was fixing. The population tag was never wrong after #2; the verb was. Finding 4 now describes
   it as a theoretical paper proposing recommendations for that population, and says explicitly that
   this makes the inference one step longer than the tag alone implies.
6. **Baddeley & Hitch (1974) named the wrong editor.** The volume's editor was given as "G. A.
   Bower." *Psychology of Learning and Motivation*, Vol. 8 (Academic Press, 1974) was edited by
   **Gordon H. Bower** — "G. H. Bower" — confirmed against the publisher's own listing for the
   series and the volume's catalogue records. The wrong middle initial is not a typo this file can
   shrug at: it is a check-1 identity failure of exactly the kind the citation policy opens by
   insisting on, and it propagates, since the "G. A." form circulates widely in secondary reference
   aggregators that copy each other rather than the volume. Corrected in the citation.
7. **Finding 10 reframed its source's most prominent effect as being about text volume.** The
   finding placed the scoping review's most prominent effect on tasks requiring a reader to hold and
   integrate a greater amount of text. Parks et al. (2022) report it elsewhere: "the most prominent
   effect was found in studies where participants retell or pick out central ideas in stories" — an
   output demand, what the reader can give back, not an input demand about length. The review's own
   conclusion is that "performance in ADHD depends on the way reading comprehension is measured,"
   which is the point its title makes and which the old framing quietly replaced with a different,
   more convenient one. Restated to the review's own wording. The rule linkage is unaffected: rules
   3 and 4 rest on Moussaoui et al. (2025)'s serial-presentation result, and Finding 10 now says so.
8. **Tether was described as validating a category it explicitly has not.** The related-work entry
   credited *Tether* with validating the broader category of ADHD assistants, and carried an `ADHD`
   population tag with no sample behind it. Shah et al. (2025)'s own abstract reports "preliminary validation through
   self-use" and states, "While not yet evaluated by target users." A tool built for people with
   ADHD is not a measurement in an ADHD population, and the tag said it was. The verb is corrected to
   "explores," the paper's own two statements about its evaluation status are quoted, and the
   population tag is **removed rather than swapped** — none of the three tags fits a paper that
   measured nobody, and the entry now says so in place of the tag. Low severity, since this entry
   justifies no rule, but the tag system is only worth anything if it is not applied by vibe.
9. **Cowan's discrete-chunk account was presented as settled.** Finding 1 stated the small-chunk
   capacity limit flatly, and Finding 2 leaned on it by naming a specific four-chunk figure as
   something Finding 1 had established. Cowan (2010) is not retracted and has not failed replication,
   so nothing is removed
   here — but a competing family of continuous-resource models disputes the discrete-slot framing,
   and a document whose whole value is being trustworthy about its own limits should say so rather
   than let a reader assume consensus. Finding 1 now records the dispute, cited to Ma, Husain & Bays
   (2014), which names Cowan's four as the account under contest and states the alternative in its
   own abstract. Finding 2's specific-number wording is replaced with "small concurrent capacity,"
   which is what its argument actually needs and what both accounts agree on.
10. **Sweller & Chandler (1994) was misquoted inside quotation marks.** Finding 4 presented the
    abstract's assumption (e) as reading "may be caused by both the intrinsic nature of the material
    being learned"; the abstract reads "may be caused both by intrinsic nature of the material being
    learned." The reordering is small and changes no meaning, which is exactly why it is worth
    recording: a document that puts quotation marks around a sentence is promising the sentence is
    the source's, not a tidied version of it, and once one quotation is known to be smoothed a reader
    is entitled to doubt the rest. Corrected to the published wording. The second quotation in the
    same citation was checked at the same time and is **accurate as printed** — the abstract does
    conclude "that an analysis of both intrinsic and extraneous cognitive load can lead to
    instructional designs generating spectacular gains in learning efficiency" — so it is left
    alone, and the fuller "an analysis" is restored to the quotation's start.

---

## What we could not verify

Everything in this section was searched for, not found against a primary source, and removed or
reframed rather than kept with a hedge.

- **The ~23-minute interruption-recovery figure.** See Corrections #3. Removed entirely; no
  specific recovery-time number appears anywhere in this file.
- **"Practitioner guidance converges on task atomicity of ≤45 minutes."** No convergent practitioner
  source was found — ADHD time-management guidance ranges from 15 to 60 minutes depending on source
  and person. Reframed in Finding 9 as a design choice made by `/squirrel:plan`, not a citation-
  backed finding.
- **"ADHD blurs the memory of one's own accomplishments" / "success amnesia."** This specific
  framing is widespread in ADHD coaching and blog content but has no peer-reviewed source. Finding
  8 rests instead on a verified, narrower claim — a negative memory bias correlated with
  ADHD-symptom severity in a non-clinical sample — and says explicitly that this is adjacent to,
  not identical with, the original claim.
- **A Kofler paper specifically named "time-based resource-sharing model."** The time-based
  resource-sharing account of ADHD working-memory deficits is real (Kofler and colleagues have
  published on it under related titles), but rather than cite a title from memory, Finding 3 cites
  the specific, directly-verified Kofler et al. (2020) paper on directionality of working-memory
  and processing-speed effects, which supports the same point without relying on an unconfirmed
  title.
- **Gama, K., & Lacerda, A. (2023)'s own text, for the over-engineering / trouble-stopping claim
  Finding 7 used to attribute to Liebel et al.** Identity checks out (SBES 2023, DOI
  10.1145/3613372.3613384, a real pilot study of ADHD and autistic developers), but its own abstract
  or results could not be read to confirm check 2. Every route tried failed: the ACM Digital Library
  abstract and full-text pages both return HTTP 403; Google Scholar and the authors' institutional
  pages list the paper with no PDF link; ResearchGate and Semantic Scholar carry no full-text
  copy; Unpaywall returns no open-access location for its DOI; the OpenAlex-indexed abstract is a
  general pilot-study summary that does not itself mention over-engineering. The claim is retired
  from Finding 7 rather than kept on the strength of a paper this file could not actually read — see
  Finding 7 for what replaced it.
- **Whether Brown et al. (2020)'s effect interacts with their redundancy manipulation**, for Finding
  12. The study ran a redundancy group (subtitles plus narration) and a nonredundancy group
  (narration only), but its abstract reports only a main effect — "an increase in ADHD symptoms
  resulted in an increase in mental effort and a decrease in recall and transfer" — with no
  condition attached and no interaction stated. The full text sits behind the journal's paywall.
  Finding 12 previously asserted the interaction anyway; it now states only the main effect, and the
  claim that redundant content specifically is what costs ADHD readers is left where it is actually
  supported, as Finding 4's general cognitive-load reasoning rather than an ADHD-population result.
- **Any direct empirical test of external cues or incremental presentation reducing working-memory
  load in an ADHD sample**, for Finding 2. Both citations previously attached to that finding turned
  out not to test this (see Corrections, substance failure 5), and a further search for a source that
  does test it directly did not surface one against a primary source. Finding 2 is reframed as
  general cognitive-load inference rather than kept on citations that do not support it.
