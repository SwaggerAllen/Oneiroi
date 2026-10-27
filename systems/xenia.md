---
paths:
  - lib/oneiroi/inbound/**
---

# xenia

**Inbound.** Greek, ZEN-ee-ah ("guest-friendship").

> "Nay, stranger, it were not right for me, even though one meaner than thou were to come, to slight a stranger: for from Zeus are all strangers and beggars" — Homer, Odyssey 14.56–58, trans. A. T. Murray (Loeb, 1919)

Xenia is the Greek bond of host and guest: feed the stranger and shelter him before you ask who he is; send him off with a gift; the guest owes courtesy in return. Zeus himself is its patron — a stranger might be a god in disguise. The Odyssey is founded on it, both ways: on its observances, and on what breaking it costs — the Cyclops who eats his guests, the suitors in the hall.

The inbound subsystem — the reader, the mail, the feeds, the approval queue where third parties arrive — is named for the practice. Welcome first, vetting second, gifts at departure: hospitality with consequences attached.

The reader, mail, feeds, the digest, correspondence and its approval queue. Spec §6.6. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/inbound/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.6; the reason for each is there.

- **#3 The reader is a hands agent that never holds the soul, a git token or a core credential; the core copies plain `.md` files from its scratch directory, bounded.**
- **#4 Sources are links the steward releases, never retained text.**
- **#5 Mail and feeds are sorted by script before any model sees them, every figure a bound; account mail is a count and a lock, never a subject line.**
- **#6 The approval queue is the steward's reading; summarising is not a security boundary; wake text names the thread, never the text. Trusted correspondents are per verified identity, revocable.**

## #7 Initial vs target

Initial: not built; see spec §6.6. Target: the whole of spec §6.6,
built in P5 (spec §14).

## #8 Depends on

The platform and whatever spec §14's row for its phase names.
