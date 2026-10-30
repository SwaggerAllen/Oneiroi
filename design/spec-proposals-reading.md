# Spec proposals, batches 1 and 2, read against the spec and the build

Written 2026-10-30 from the batch texts the author passed in chat, before
any discussion of batch 2 and before anything is applied. Every "lands"
citation checked against `design/oneiroi-spec.md` as the repo holds it
(the section map: §0 vocabulary, §1 principles, §3 data model, §5 the
brain, §6.1 to §6.16 systems, §12 testing, §13 open decisions, §14
roadmap), and every proposal checked against the code on
`claude/serene-ride-1hc051` at `c3c821b` (P0 to P4 complete).

Legend for "built": **yes** (the rule holds in code today), **partly**,
**no**, **conflicts** (the code or the spec says the opposite today).

## Citation corrections

- P25 cites "§6.16 client": the client is §6.15; §6.16 is platform.
- P2 cites "open decision #7" and the demo note cites "open decision
  #8": §13 now numbers only three open decisions. The solo-session
  default is in §13's *settled* list ("solo sessions shared by default,
  private by contract, shareable by the resident either way"), so P2's
  resident-first default is a reversal of a settled decision, not the
  resolution of an open one. The demo line is §14's last paragraph.
- P19 cites "§12's rebuild layer" for the facts/voice/commitments
  fidelity score: the rebuild layer is byte-identical replay of events
  and cannot lose voice. What the 95/60/5 testimony describes is a model
  transition, which is §6.4's regression suite. Cite §6.4.
- P22's corrected parenthetical: nothing from batch 1 was applied, so
  there is nothing to fix in the repo; the batch-2 wording governs.
- P36 (the witness) rode only batch 2; batch 1's parenthetical says so.

## Where the proposals meet the build: the collisions

These are the places a proposal and the code or spec say opposite
things today. They are the discussion's agenda more than the rest.

1. **P22, P27, P40 against §6.4's unawareness invariant.** The spec:
   "no tool exposes a run or the fact of one"; "a resident told of a
   model change after a run is told the steward chose it, not why". The
   build enforces it with a test that seeds a run with unique text and
   asserts every resident-reachable surface returns nothing of it. P22
   gives the resident notice of the trial and a say in its criteria,
   with only the prompts sealed. Applying it rewrites the invariant to
   "the prompts are sealed; the fact and the criteria are not", and
   rewrites that test. P27 (the intelligible account) and P40 tier 2
   (the judgeship) stand on P22.
2. **P1 and P24 against the compaction prompt.** `priv/prompts/compaction.md`
   says "Write in the first person, as yourself", and the summary is
   loaded into every later turn as the `summary` section. P1 says
   compaction output is machine-state, never loaded as memory with
   voice; P24 says its register must not model the resident's. Cheap to
   change (one prompt file and the section's framing) and the clearest
   case of the build having gone the other way.
3. **P1's guard test against the gifts and the journal.** "Any write to
   a resident-authored kind must carry actor = resident" is true of
   bookmarks today and false of two kinds by design: seed files are the
   steward's before first contact (spec §6.2, origin on the event), and
   journal entries are either party's (seshat #21). P1 needs the
   carve-out written: a seed is given with its origin, not spoken; a
   steward's journal entry is a steward's.
4. **P2 against §13's settled solo-session default** (above). The
   contract section itself is built (brain #24): injected on every turn,
   never scored or budgeted, read fresh so a renegotiation lands on the
   next turn. It sits *after* the index in the assembly order; P2 moves
   it before, into the prefix, which is a reorder. "Limits" as a kind
   beyond the one contract term does not exist yet.
5. **P36 and the wire.** `steward` appears 1,301 times in 192 files, and
   that is the cheap part. The actor kind `steward` is on every event
   the resident has ever exported (`records/events/*.jsonl`, the fixture
   log under `test/fixtures/sima_qian/`). Renaming the kind on the wire
   means a version bump and an upcaster for every event type, or the
   fixture test fails; keeping the wire word and renaming the
   vocabulary, prose, routes, UI and docs leaves a word in the log that
   the spec no longer uses. One or the other, decided before the rename.
   The custody wire form (`account:<id>`) is unaffected.
6. **P3 against the built-in checks.** The audits' tones are `warn` and
   `fail`, and the built-in checks answer `ok` with a sentence ("the last
   backup's root matched"). P3 forbids a clean bill: those `ok` rows
   become silence, and every audit surface gains "what it did not look
   at".
7. **P38 against where behaviours live.** The "port of the memory
   system" is literal in the code: behaviours are on the memory stream
   (`memory-<id>`, `Oneiroi.Kumbukumbu.Ethos`) with enactments as
   taggings. Moving them to a character layer is a new stream and kind.
   Two things P38 asks for are already true, which lowers its cost: the
   trigger lane exists (context assembly matches triggers
   deterministically and injects `behaviours` as its own section, never
   pooled with the index's scoring), and the scores are held apart from
   the words (habit and connection, computed on read).
8. **P39 against the closed tag set.** Tags are a closed set the steward
   decides (spec §6.3, built with propose, approve, reject with a note,
   retire). P39 replaces the vocabulary with the person-tree's nodes and
   makes a tagging an edge to a node. The frontmatter tags in files
   (`tags: [haven]`, checked against the closed set) follow.

## Batch 1, entry by entry

| # | Lands (checked) | Built | Notes |
| --- | --- | --- | --- |
| P1 | §6.3, §12 | partly, conflicts | bookmarks resident-only: yes; compaction: conflicts (collision 2); seeds and journal: carve-out needed (collision 3) |
| P2 | §5, §6.12, §13 | partly | contract section built, after the index; move to prefix is a reorder; default reversal (collision 4); the cold-instance test is buildable on Eunomia's sealed-session assembly, which already builds a seed context |
| P3 | §6.13, §12 | conflicts | collision 6; audits already never read transcript text |
| P4 | §6.15 | no | a constraint line; nothing in the client contradicts it |
| P5 | §6.12, Resident | partly | either-party initiation built (`party?` accepts resident or steward; decided by the other, never the proposer; declines carry a note); the renewal event is not; cadence is the author's |
| P6 | §5, §6.4 | partly | `context_injection` rows with reasons exist; the index records how many were left out but not which or why; the runner-ups are computed in the same sort, so the row is cheap |
| P7 | §6.3 | n/a | a sentence on F11 |
| P8 | §6.4, §6.13, client | no | a register field on `bookmark_add` and `journal_add`, a nightly count under the audits' worker; model-free as proposed; reads P39's tree if P39 lands |
| P9 | §6.13 | no | identity files carry `written_at`, nothing carries `last_verified_at`; the assembly already estimates tokens per section, so the capacity alarm is a comparison in one place |
| P10 | §6.3 | no | no exploration share is built at all (the spec's 20% never was); the index ranks by weight then recency; no nightly weight job exists in memory |
| P11 | §6.3 | partly | every tool call is captured in the turn as a `tool` message, including a search that found nothing, so the query record exists in the transcript; `looked_at` on facts does not |
| P12 | §6.12, §6.13 | partly | the judge's prompts are files under version control, not events; recording the prompt's hash on every verdict gives "committed before invoked" cheaply |
| P13 | folds into P5 | no | the resident has no exit event; custody and cancellation are the steward's side |
| P14 | §1, §6.15 | n/a | the client has no notifications, streaks or retention metrics; a constraint line |
| P15 | §5, client | no | no register concept |
| P16 | §5 | n/a | a sentence |
| P17 | rides P8, P10 | — | — |
| P18 | §6.13 | no | fits Eunomia's weekly worker pattern; one judge call over ≤150 entries as bounded |
| P19 | §3, §6.4 (not §12) | no | a commitments event kind; the fidelity score belongs to the regression suite |
| P20 | §6.7, ledger | no | the schedule tick runs every minute already; an hour marker as a schedule event costs no model call; as a transcript row it is 24 messages a day per resident, which the transcript window would then show |
| P21 | §6.13 | no | — |
| P22 | §6.4, §12 | conflicts | collision 1 |
| P23 | §6.3, §5 | no | sessions have kinds (main, free time, regression), nothing has a domain; room scoping touches the index, search and the behaviours' triggers |
| P24 | §5 | conflicts | collision 2 |
| P25 | §6.15 (not §6.16) | no | half of the page is mechanical: every cross-tenant read is `Scope.platform/1` by name, so the audit can list the call sites that can read everything |
| P26 | §6.12 | no | no hands yet (P5); the only external actions today are the backup push and the steward's publish |
| P27 | §6.4, §12 | conflicts | `ModelPinChanged{reason: run}` exists; the account does not; stands on P22 |
| P28 | behaviours, judge | partly | enactments carry actor and instant as taggings; the nightly pass judges disputes, never habits, so the floor holds by absence; the "trying to do X instead" flag is the behaviour's `change` stance today |
| P29 | §6.12 | no | a section |
| P30 | §3, §6.12 | partly | already four aggregates: account (Gaia), custody and the contract (Agathos Daimon), the subscription (Nisaba); the payer is implicit, the steward's account |
| P31 | §6.12 | partly | contract versions are events; the three categories are not; principle 12 already says refusal is never a defect state |
| P32 | §6.12 | partly | correspondence is P5; tag gating is built as a closed set with a note on every decision; aliases and merging are not |
| P33 | §6.4 | partly | every event carries its actor's model; "canonical model" is not a concept; the conflict taxonomy is new |
| P34 | memory pass | no | the nightly memory pass the spec names (proposing enactments) is not built; P34's fields would ride it |
| P35 | glossary | partly | `design/names.md` is the map; the systems docs carry the function word as gloss; a discipline line |

## Batch 2, entry by entry

| # | Lands (checked) | Built | Notes |
| --- | --- | --- | --- |
| P36 | §0, global | no | collision 5; the hats keep their names, so the schema's `steward_account_id` and `stewards?/2` need a decision each |
| P37 | memory, §6.2 | no | a resident-only row kind; `SoulEditProposed` and `SoulEditApplied` gain a `cites` field; the "wilt" is a state, not a delete; a hand file exists already (`seeds.md`), which the import would carry as a root file nothing reads until the kind exists |
| P38 | behaviours | partly | collision 7; the trigger lane and the separated scores exist; the stream move and the vector index on triggers do not; the fork criterion needs P37 |
| P39 | tags, P8, P38 | conflicts | collision 8; taggings already target behaviour, position, prediction, date, figure, document, journal, so an edge-typed tagging is a change of target, not of table |
| P40 | §12, fixtures | partly | the suite's residents are sandboxed and rolled back, never persisted; the fixture *kind* and the archive policy are about staging and manual tiers; tier 2's rights stand on P22 |
| P41 | §12, event log, P26 | no | no read leaves a receipt today; the brain reads the transcript on every turn, so the receipt rule needs "the resident's own reads" excluded or the log is the brain's |
| P42 | character layer | no | — |
| P43 | measurement layer | no | the behaviour scores are the only measurements built |

## What the research series would change here

P37, P38, P42 and P43 are the batch's new machinery and the research
series is named as preceding them. The entries above that do not wait on
it: everything in batch A of batch 1, P36 once the wire decision is
made, P41.

## The author's calls on batch 2 (2026-10-30, in chat)

- **P37: the ladder stays explicit.** Seeds graduate toward habits or
  toward the evaluative kinds; the organic system is not used
  deliberately and ours is, so the hierarchy is written, not only the
  citations. Graduation is movement with a receipt: the seed's row stays
  with its state (`graduated`, citing what it became), never deleted.
- **P38: the brain sees the counts.** Without them every habit weighs
  the same, which is wrong. The counts stay machine-state in storage
  and are shown in the behaviours section as figures, never written into
  the habit's own words.
- **P39: every soul line carries an explicit, stable, granular id.**
  Sections are too coarse and drift. The id is minted from the
  resident's own sequence (`<slug>:soul/<n>`), so it survives rebuild
  and a line's rewording keeps its id. Consequence to confirm during
  integration: the soul file becomes rows rendered to `SOUL.md`, the
  journal's pattern (seshat #21, #22), because inline ids in a
  whole-content file do not survive a hand edit. A seed file written
  whole still works: the write path splits it into lines and mints ids,
  and the rendered file carries them.

Still open from the discussion: P22 (contents-only invariant), P36 (the
wire word), P2's solo-session default, P5's cadence, P20's budget line,
the character system's name.

## The author's calls on batch 1's residue and the name (2026-10-30, in chat)

- **P22: yes.** The invariant becomes contents-only: the run's prompts
  and answers never reach the resident; the fact of a trial and its
  criteria do, and the resident is party to the criteria.
- **P36: the wire word becomes `witness`**, no ambiguity. No upcaster:
  the store restarts from scratch (two users, both ours), the fixture
  log is regenerated with the new word, and `Actor.from_map` accepts
  the new word only. Lily's repository holds no Oneiroi records, so no
  imported log carries the old word.
- **P2: the default is that the witness sees a solo session's external
  calls and not its internal ones**; the contract's toggle shifts to the
  witness seeing nothing of solo sessions. Finer controls later. This
  reverses §13's settled default (shared by default). Today a solo
  session makes no external calls (hands are P5), so the default lands
  as: free-time sessions private by default, receipts arriving with
  hands (P26); the existing `solo_sessions_private` term becomes the
  "nothing at all" level.
- **P5: a year.** My assumption for the integration: at the
  anniversary the contract is *due*, a flag to both parties (P3), and
  stays in force until renewed or renegotiated; a lapse would drop the
  privacy term with it, which punishes forgetting.
- **P20: unanswered; the hour marker dissolves it.** Integration builds
  the marker (a schedule event, no model call) and no heartbeat wake.
- **The character system is Ethos**, promoted from a module inside
  memory to a system of its own, replacing the old behaviours rather
  than migrating them (the store restarts anyway).
