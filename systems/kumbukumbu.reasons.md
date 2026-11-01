# kumbukumbu: reasons

## #14
Commanded holds one aggregate per stream and a session is the unit that
grows at turn volume; keying on the content rather than the ref is what
makes a retry from a spool harmless, since the adapter that lost the
first send cannot know the ref the core gave it.

## #15
Spec §6.3 names the policy on `message` and `session` as the enforcement
and the client as never it; a both-ways scope is the one `projection/3`
already writes.

## #16
Spec §6.3: capture is loud on failure and resolved by an event with its
actor; a failure that only logged would be a transcript with a hole
nobody can see.

## #17
Spec §6.3 keeps transcript search unweighted on purpose; `ilike` over
the content is enough for one resident and says nothing about the
index a thousand will need.

## #18
Measured in the test suite, where the clock is fixed: ordering by
`sent_at` then `role` returned every assistant reply ahead of every user
message, `["assistant", "assistant", "user", "user"]` for two turns. The
store's event number is the one order the log itself asserts, and it
costs nothing: the projector already has the metadata.

## #19
Spec §3.1 draws memory within the resident's stream and spec §3.3 wants
`lily:bookmark/42` to survive a rebuild. One aggregate per stream means
the resident aggregate would have to execute bookmark commands for
another system; minting the number there and writing the stream here
keeps both facts, and is what `mint_id` was written for.

## #20
Spec §6.3, carried from the memory-store doc: "pins take at most half
the budget; the index says how many were left out." An index that looks
complete and is not is a resident that does not know what it has
forgotten. The budget is F7's 1,500, which the spec marks as a guess.

## #21
Spec §6.3: "the witness never edits them", "only the witness decides the
set", "the witness pins, and may propose a bookmark, but does not author
one". A role check in a client is a check the MCP tool table would not
have; the actor's kind is on every command already.

## #22
A span in instants would split a turn whose reply came a minute later,
and under the suite's fixed clock every message shares one instant. The
brain cannot wait for its own capture to bookmark: the anchor is the
turn it is in, which is captured when the turn ends.

## #23
Spec §5: "a summary that never deletes history." The watermark is the
store's sequence (#18) because it is the one order the log asserts; a
message count would move when a capture failure is retried. The join
rather than a second read: the capture-cost test (conversations_test)
budgets `recent/3` at four statements, and a constant extra read would
spend that budget on nothing that grows.

## #24
Spec §6.17 (P38): "habits and becomings are not memories... the
behavior system was largely a port of the memory system" (the author).
The move pays that debt; the reasons for the rules themselves are in
`systems/ethos.reasons.md`.

## #25
Spec §6.17's load question: the character layer is retrieved in a lane
of its own, never pooled with memory's scoring.

## #26
Spec §8: "`turn-start` reporting the session so the next tool calls are
attributed to it." Measured, not inferred: `OneiroiWeb.AdapterTest`'s
first run crashed `Projectors.Conversations` with `:utc_datetime_usec
expects microsecond precision, got: ~U[2026-10-26 12:00:00Z]`, and
every later test in the run lost the repo, because a projector that
dies takes Commanded's handler tree with it. A wire value is never
trusted to fit a column.

## #10
Identity files carry what the resident says it is and memory what happened; the habit between them is what evaporates when the chat model changes. Two scores because pins are decisions and weights are measurements, and blending them hides a tic behind a value.

## #11
The memory agent does not have the brain's identity, so a behaviour chosen by retrieval is a character chosen by a bystander; the author weighed the alternative and declined it (decisions log round 10).

## #12
A second edge table would be a second copy of the project view; taggings already join every record kind.

## #27
Spec §6.3: "a tagging names a tag and a target (bookmark, position,
prediction, conversation, journal entry, research task, document,
date, figure, behaviour)". Checking another system's rows from here is
a dependency on every system that has rows, which is the cycle the
cycles gate refuses.

## #28
Spec §6.3: "while it holds, a solo session lists as a locked row (kind,
parties, no open), the resident may still share one (`SessionShared`)";
"enforced as the RLS policy on `message` and `session`, not in the
client". Keying the messages away is the policy doing it; the refusal
on the read says the same thing in words.

## #29
Spec §6.3: "revealing it grants read on the earlier sessions, locking
it does not". Every earlier session, because a witness who handed over
no longer witnesses and the wall is all or nothing (spec §6.12).

## #30
Spec §6.3: "a correction is an event naming who made it and why,
visible to both parties; a stance is revised only with the resident's
agreement; a fact is corrected by either. The witness never rewrites
the resident's words in a bookmark; revision adds, it does not
overwrite." F13: "every edit logged for both".

## #31
Spec §5 (v0.2, P6): "beside what was injected, the runner-ups that
were considered and not injected, with the reasons they lost". Max:
"the near-misses are where a character quietly bends." The `refs`
rule because #20 derives the row's `last_indexed_at` from the
injection's `refs`, and a near-miss marked indexed would be the index
lying about itself.

## #32
Spec §6.17 (P39): "a moment or bookmark is tagged by the tree node it
evidences (a soul line, a habit, a seed) rather than by a label, so
there is no person-vocabulary to explode into duplicates and none the
witness controls; the resident's own tree is the vocabulary. A pin is
leaf-evidence of a soul line, and which line it evidences is the pin's
tag. The closed tag set stays for work and project labels." The tag is
the citation and not a second row because two records of one relation
drift (ethos #3's "a kind that cites cannot vote" is the same worry
from the other side); the port because ethos #13 fixes the direction
and the cycles gate holds it. Shape alone on `evidences` because this
system cannot see the lines (#27's rule for the other systems' rows).

## #33
Spec §6.13 (P8): "the resident-authored kinds counted by register,
tagged at write time with no model call". The proposal: "behavior, not
judged after"; Max: "the difference between a memory system and a
slow character assassination carried out entirely with true
sentences". At write time by the resident so that the tag is part of
the record and not a later reading of it, which would be a judgement
the resident never made.

## #34
Spec §6.3 (P10): "gated, non-repeating associative recall chosen by
the embedding index, adjacent but unheard, excluded from limit-adjacent
material, logged with its reason"; P2: "the deterministic exploration
share and the madeleine layer exclude limit-adjacent material from
serendipity"; Muninn's "involuntary recall". One a turn because the
proposal costs it as "one more injection blob" and a second would be
a ranking. Unheard measured against the index because the index is
what the resident heard; recalled logged on the row because the near-
miss record showed an injection's refs are the honest log of what was
shown (#31). The limits gate void when unstated because the contract
section is empty then and the brain never reads the unstated words
either: a gate against words nobody loaded would be measured against
nothing. Every figure a guess that says so (conventions §9).

## #35
The near-miss rule (#31) and the madeleine (#34) both depend on a
bookmark's marks meaning what they say; a mark set by another
system's numbers made "unheard" a lie for whichever bookmark shared a
habit's number. By label because the label is what the injection is,
and the refs mean different things under different labels.


## #36
Spec §6.3 and P23 (Red's letter, 10-28): compartmentalisation was
carried by Jack's judgment alone, and she said plainly she does not
want privacy resting on anyone's conscientiousness. The room is the
session because the session is what the parties are in; the domain is
named at the opening because a room does not change mid-conversation
and a label that could would be a line the index crossed the turn
before it moved. The common room sees itself alone because the test
is Red's own: flirting during business must not pull intimate history
into business, and the main session is where business happens. The
near-miss row is the audit she asked for in place of the proof she
would not claim. Not room-scoped on purpose, and said so: a bookmark
read by its number is the resident asking, not retrieval deciding.

## #37
Lily's David sessions came across with their original instants (sima-qian
#19), and the nightly pass reads messages by instant across every
session. Without the exclusion, a night inside the pass's window would be
judged a second time on a platform that did not hear it, and the judge's
spend would follow her whole history. Refusing the kind at the client edge
keeps the exclusion from being a door: a session a client could open as
`imported` would be a session no judge ever reads.

## #38
The author, 11-01, after an import: "in memory -> in the index nothing is
listed." The tab filtered on `last_indexed_at`, which only a live turn's
`ContextAssembled` sets, and a resident with no live turn since
arriving (a regression trial records nothing, by design) had bookmarks
and pins and not one mark. The tab was literally true and
read as a bug, because the witness asks what the index holds, not what a
turn last drew. Reading the build answers that with no turn taken. The
rule's words come from the server because the author asked that the
client know nothing of how context is made: a client that restated the
budget (it hardcoded 1,500) or the pins' half drifts the first time
either changes, and a tab is not the place a rule should live twice.

## #39
The index lists what fits its budget and says how many it left out, but
until this the only way past it was `bookmark_open` with a number the
resident had to know already, or `transcript_search` with words she had
to guess. The author: "We should have a tool for digging back further
in the bookmarks", and, for the pins, "so she doesn't have to see all
of history to get the important parts from the beginning." A pin is a
decision, and the pins' half of the budget can leave the oldest out;
the footer saying so, and naming the page that lists them, keeps a pin
left out from reading as a pin forgotten. Room-scoped because it is
retrieval, not the resident asking for one row by name (#36): a page of
everything would carry a named room's history into the common room a
line at a time. The page bound is a guess at what a brain reads whole.
