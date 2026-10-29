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

## #10
Identity files carry what the resident says it is and memory what happened; the habit between them is what evaporates when the chat model changes. Two scores because pins are decisions and weights are measurements, and blending them hides a tic behind a value.

## #11
The memory agent does not have the brain's identity, so a behaviour chosen by retrieval is a character chosen by a bystander; the author weighed the alternative and declined it (decisions log round 10).

## #12
A second edge table would be a second copy of the project view; taggings already join every record kind.
