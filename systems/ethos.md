---
paths:
  - lib/oneiroi/ethos/**
  - lib/oneiroi/ethos.ex
  - test/oneiroi/ethos/**
---

# ethos

**The character layer.** Greek, EE-thos.

> "moral virtue comes about as a result of habit, whence also its name (ethike) is one that is formed by a slight variation from the word ethos (habit)." — Aristotle, Nicomachean Ethics II.1, 1103a, trans. W. D. Ross (Oxford, 1925)

Ethos is character, and Aristotle hears habit inside it: the two words differ by one vowel, and he takes that as the lesson. Character is not stated; it is what repeated action leaves behind.

The character layer (spec §6.17, proposals P37 to P39, P42, P43): who the resident is becoming and how it tends to act, kept apart from what happened. It was a module inside memory in v0.1 (`Oneiroi.Kumbukumbu.Ethos`, the behaviours of spec §6.3) and became a system of its own in v0.2 when the author named the port-debt: a habit that lives as a memory votes like evidence, and one encounter acquires the weight of several independent signals. A kind that cites cannot vote.

Built in v0.2's machinery pass, after the law of the proposal batches and the research pass (`design/research-self-and-character.md`).

## #1 Owns

The character stream `ethos-<resident_id>` and its v1 events (`SeedPlanted`, `SeedWilted`, `SeedGraduated`, `SeedCited`, `HabitDefined`, `HabitChanged`, `HabitAffirmed`, `HabitCited`); the `ethos_seed`, `ethos_habit`, `ethos_citation` and `ethos_affirmation` projections under the resident's scope; the two scores; the trigger lane the brain reads; the `/v1/residents/:id/habits` and `/seeds` routes and the brain's habit and seed tools. The trait baseline and the measurement layer (P42, P43) are this system's to build next.

## #2 Standing decisions

- **#3 Habits and seeds are not memories.** They live on their own stream and cite memory's moments (a turn by ref, a bookmark by number) rather than being tagged onto them; the direction is always from the record here to the moment there. Memory never reads this system; this system reads memory's rows and writes none. A citation's target is checked at the command edge (a bookmark must exist), since the aggregate no longer sees memory's state.
- **#4 The ladder is explicit, and graduation is a receipted move.** Moments, then seeds (becoming), then habits (character) or the evaluative kinds (a position, a soul line), then soul lines (the constitution). A seed graduates by `SeedGraduated{to_kind, to_id}` with a note, and its row stays with its state and the citation to what it became; nothing transforms, a new record cites the old. Toward a habit the move is made by `define_habit/3` with a `seed_number`, so the habit and the graduation are one call and the graduation is refused first if the seed is unconfirmed; toward a position or a soul line by `graduate_seed/6`, with no citations asked; toward a soul line the line must be live, by its number (agathos-daimon #27), while a position cannot be checked from here since judgement reads this system and not the reverse.
- **#5 The fork counts days, not citations.** A seed may become a habit only once it has been cited on `ETHOS_PROMOTION_CONFIRMATIONS` distinct days (3, a bound and a guess at what "repeated" means; the research pass's §3 is its reason: an if-then contingency is a hypothesis, moderately reliable). The aggregate holds the days from the citations' instants and the required count travels on the command, so the rule is pure and the setting lives where settings live. Citations in one burst are one day.
- **#6 A seed wilts without ceremony and a closed seed is history.** `wilt_seed/3` asks no note; a wilted or graduated seed takes no more citations and no second graduation (`ethos_seed_closed`). Staleness is the audits' to flag, never an automatic wilt.
- **#7 The list is the resident's; the witness affirms, and gives first habits only before first contact.** As the behaviours were (spec §6.3): a witness defines a habit before first contact as it gives every seed, and after it only affirms with a note; seeds are the resident's alone to plant, cite, wilt and graduate, and the witness's to read. A blank seed is refused before a number is minted, so a slip burns no citeable number.
- **#8 Two scores, never one, computed on read, and shown to the brain as figures.** Habit strength is the decayed sum of a habit's citations under `ETHOS_HALF_LIFE_DAYS`; connection strength is pins on cited bookmarks (undecayed) plus affirmations and cited bookmarks (decayed). The brain's section shows both with the citation count and the days (the author's call: without them every habit weighs the same), as figures beside the words and never written into the habit's sentence (spec §1.13).
- **#9 The trigger lane is retrieval of its own, and seeds are counted, never loaded.** `how_i_act/2` matches the situation (the witness's words, the conversation's tags, the time of day) against every trigger with no model call and returns a section per match with up to `ETHOS_EXEMPLARS` cited turns in the resident's own words; the brain injects it as `character`, never pooled with the index's scoring (spec §6.17's load question). Open seeds are a count and a pointer to `seed_list`, so the prefix does not grow with the person; the vector index on triggers and content is the next step.
- **#10 Habits, seeds and soul lines are citeable, and a citation resolves to the words with the state.** `<slug>:habit/<n>` resolves to the habit's name and stance, `<slug>:seed/<n>` to the seed's text and state, `<slug>:soul/<n>` to the line's words, through the library's resolver (seshat #14); a soul line carries the numbers of the seeds it grew from (`cites`, agathos-daimon #27). The first slice's resolver clauses for habit and seed were unreachable, since the citation parser's kind list did not name them; the test that cites all three found it when the soul kind joined.
- **#11 The regression trials derive from habits.** Judgement reads `habits/1` where it read the behaviours (eunomia #8); the trial's wire field keeps its name, `behaviour_number`, because the event is a contract.

## #12 Initial vs target

Initial (v0.2's first machinery slice): #3 to #11, over the exports, the brain's seven tools and the routes; the second slice added soul lines as rows with minted ids that cite their seeds (P39, in the resident system, agathos-daimon #27). Target: the trait baseline with its drift band and the measurement layer's four markers (P42, P43; research §5 and §6), the vector lane over triggers and content, and tags as citations to the tree (P39, in memory).

## #13 Depends on

The resident system for the minted numbers and first contact; memory for the moments a habit or a seed cites, read and never written. The brain, judgement, the library and the web layer read this system; nothing here reads them.
