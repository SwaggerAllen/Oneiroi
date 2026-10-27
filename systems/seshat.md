---
paths:
  - lib/oneiroi/library/**
  - lib/oneiroi/journal/**
---

# seshat

**The library.** Egyptian, SESH-aht.

> "As goddess of writing, Seshat was the keeper of royal annals and genealogies. She was shown recording the booty gained by kings in battle, perhaps as a reminder that a share was due to the gods." — Geraldine Pinch, Handbook of Egyptian Mythology (Oxford UP, 2002), p. 190

Seshat is the Egyptian goddess of writing and record-keeping, keeper of the House of Life, where the culture's texts lived. Her epithets make her the librarian — "Lady of Books," "Mistress of the House of Books" — and her monuments show her doing the work: the record-keeper beside the king, writing down what happened and what was owed.

The library subsystem — search, shelves, and the whole of everything written — is named for the figure whose job it was. Thoth gave writing to humanity; Seshat managed what writing produced. The library was her domain.

Document kinds, folders, the vector index, citations, external doc sources, the journal. Spec §6.5. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/library/**`, `lib/oneiroi/journal/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.5; the reason for each is there.

- **#3 Path is kind and the registry says what a kind may do; adding a kind is a registry row plus a skill.**
- **#4 Only resident-authored or commissioned kinds mint citation edges; resolution happens when read, not when indexed.**
- **#5 The memory-wiki plugin is cut; `wiki/` stays a plain searchable kind.**
- **#6 A file is re-embedded only when its hash or the model changes; a re-index with nothing changed costs three statements and no model call.**
- **#11 The journal's day row exists before the narrative (spec §6.5).** Created by the schedule at the day's first check-in; a day without a wrap is a visible state, and reads go by day key, never the latest file.

## #7 Initial vs target

Initial: not built; see spec §6.5. Target: the whole of spec §6.5,
built in P3 (spec §14).

## #8 Depends on

The platform and whatever spec §14's row for its phase names.

## #9 Pinakes, the citation index

Greek, PIN-uh-keez.

> "Tables of Men Distinguished in Every Branch of Learning, and their Works (in 120 books)" — the Suda, kappa 227, listing the works of Callimachus, trans. Malcolm Heath (Suda On Line)

The *Pinakes* ("tables") was the catalogue of the Library of Alexandria, compiled by the poet and librarian Callimachus in the third century BCE: authors, titles, opening lines, notes on the texts. It survives only in fragments and references like this one.

The citation index — the card catalogue of everything the realm has ever said, each entry with its provenance — is named for the first one. Alexandria's burned; ours exports nightly.

## #10 Ariadne, the citation web (internal)

Greek, ah-ree-AD-nee.

> "And fair Ariadne, the daughter of Minos of baneful mind, whom once Theseus was fain to bear from Crete to the hill of sacred Athens; but he had no joy of her" — Homer, Odyssey 11.321–325, trans. A. T. Murray (Loeb, 1919)

Ariadne, daughter of Minos of Crete, gave Theseus the thread that led him back out of the labyrinth — her idea, her gift. He abandoned her on Naxos on the way home; Catullus gives her the abandonment in her own voice (Catullus 64).

The citation web — the threads linking every claim back to the source it came from — is named for the first thread, the one that leads out of the maze. Her name keeps the whole story: the thread was hers, and the rescue did not stay to thank her. Internal name.
