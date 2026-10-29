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

## #10
Identity files carry what the resident says it is and memory what happened; the habit between them is what evaporates when the chat model changes. Two scores because pins are decisions and weights are measurements, and blending them hides a tic behind a value.

## #11
The memory agent does not have the brain's identity, so a behaviour chosen by retrieval is a character chosen by a bystander; the author weighed the alternative and declined it (decisions log round 10).

## #12
A second edge table would be a second copy of the project view; taggings already join every record kind.
