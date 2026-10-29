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
Spec §6.3: "the steward never edits them", "only the steward decides the
set", "the steward pins, and may propose a bookmark, but does not author
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
Spec §6.3, F55: "a behaviour is self-description, and the resident's
words are never editable by the steward"; "two scores, never one",
because "a behaviour with high habit and low connection is a tic". The
closed trigger set is the spec's: "a trigger the assembler cannot match
is a behaviour never retrieved", so an open set would be a list of
things nothing ever matches. On read rather than nightly: the volumes of
P1 make the sum cheap, and the nightly job belongs to the pass that
also proposes enactments.

## #25
Spec §6.3: "Retrieval is memory's and choice is the brain's", with
"one or two enacting turns cited by id" because "for a new model they
are the resident's own voice doing the thing, which is stronger than any
description of it."

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
it does not". Every earlier session, because a steward who handed over
no longer stewards and the wall is all or nothing (spec §6.12).

## #30
Spec §6.3: "a correction is an event naming who made it and why,
visible to both parties; a stance is revised only with the resident's
agreement; a fact is corrected by either. The steward never rewrites
the resident's words in a bookmark; revision adds, it does not
overwrite." F13: "every edit logged for both".
