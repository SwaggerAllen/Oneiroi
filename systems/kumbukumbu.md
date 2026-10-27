---
paths:
  - lib/oneiroi/memory/**
---

# kumbukumbu

**Memory.** Swahili, koom-boo-KOOM-boo.

> "1 remembrance, memory, mind, anniversary; souvenir. 2 records, minutes (of a meeting/conference): ~ za kihistoria annals" — TUKI Swahili–English Dictionary (Univ. of Dar es Salaam), entry kumbukumbu

In Swahili, *kumbukumbu* names the act of keeping: remembrance, commemoration, the anniversary — and "minutes," the written record of what a meeting said.

The memory subsystem is named for what it does rather than what it stores: it remembers, commemorates, and keeps the minutes. Remembering is something you do for someone; storage is something you do to something. That difference is the design.

Transcripts, bookmarks, tags, search, weighting, the memory agent's record. Spec §6.3. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/memory/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.3; the reason for each is there.

- **#3 Capture is full and idempotent and loud on failure; bookmarks are the resident's words and the steward never edits them; pins take at most half the budget; tags are a closed set the steward decides; the index says how many were left out.**
- **#4 A bookmark is a moment with a span, grown later by an event rather than a second bookmark; one kind of bookmark.**
- **#5 Tags cut across every record kind; a frontmatter tag outside the closed set is reported, never stored.**
- **#6 The steward pins and may propose a bookmark, and never authors one: the index is injected into the resident's context every turn.**
- **#7 Visibility is the RLS policy on `message` and `session`: a party to the conversation and the current steward read it; the export wall is what a custody transfer reveals or locks; solo sessions are readable by the steward by default and private only by a contract term.**
- **#10 Behaviours are rows the resident owns, with a trigger, a stance and tagged enactments (spec §6.3, F55).** Two scores kept apart: habit strength, a decayed measurement; connection strength, a decision trace of pins and affirmations. The brain self-tags enactments; the nightly memory pass only proposes.
- **#11 Retrieval is this system's and choice is the brain's.** Context assembly matches a closed set of situation tags against triggers with no model call and injects the matching behaviours with their enacting turns cited; whether to enact is the brain's thinking.
- **#12 Dates, figures and behaviours are tagging targets** beside the kinds a tagging already names, so the project view reaches them and no edge table is needed.

## #8 Initial vs target

Initial: not built; see spec §6.3. Target: the whole of spec §6.3,
built in P1 (spec §14).

## #9 Depends on

The platform and whatever spec §14's row for its phase names.
