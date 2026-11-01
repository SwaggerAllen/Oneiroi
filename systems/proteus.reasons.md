# proteus: reasons

## #8
Conventions §9: every external sits behind a behaviour with a fake
that ships with the port, registered in `externals/0` with a kill
switch; spec §2.2: workspace filtering on every bridge query.

## #9
Conventions §9: "a hand-written fixture is a claim about the real
system, and a fake that disagrees with it hides the bug it was built
to catch", and "a fake refuses what the real system refuses". Both
were broken here at once: the bodies were the docs' claim, and the
in-memory Honcho took any shape, so a field the server does not read
went out on every turn of the resident's first live day while the test
that counts Honcho's messages passed. The record is read from the
server's own source at the deployed commit rather than from an SDK,
because an SDK is a second claim about the same server and the brief
was the server's word. The request is built in one place so the fake
and the transport cannot send two different bodies. Stricter than the
server on purpose: a name taken on sufferance or a field dropped
unread is a client that believes it set something; `tokens` was one.
The deployed commit is not in this repository (Render builds `main`
by hand), so nothing here can notice a redeploy; the record names the
commit and the step that re-reads it.

## #10
Spec §6.9: "tested against Honcho's own DDL from the pinned image." A
DDL the test has not read is a guess about the schema, which CLAUDE.md
in the orchestration repository records failing once already.

## #11
Conventions §10 and §12; sunna #11 for the roster read.

## #12
Spec §6.9: "one workspace per resident; peers witness-<id> and
resident-<id>"; "custom instructions name the two peers and are
rendered per resident."

## #13
Spec §5: "capture at the end of the turn"; conventions §8: an external
failure is retryable and never the turn's. The once-a-turn read before
the send is the night's lesson (eunomia #18) arriving at a second port.

## #14
Spec §6.9: "the card comes from git, always: set after a soul commit,
re-pinned by the weekly audit if a dream moved it."

## #15
Spec §5: "then Honcho's context, then the compaction summary and the
live transcript"; F12: every injection recorded with its reason.

## #16
The author, 10-31: "put honcho in the blueprint." A minted admin key
typed into the dashboard is a second copy of a secret that already
exists, and a `sync: false` value is not copied into a preview, which is
how the PR #13 preview failed on APSU's keys. Minting from the secret
Render generated means nothing about Honcho is typed but its provider
key. The token was checked outside this codebase: computed with Python's
hmac and decoded by PyJWT, the library Honcho verifies with.

## #17
The author, 10-31: "Can honcho be on our existing database?" and "the
same api key as everything else", which they chose to mean one
OpenRouter key for Honcho, the platform and the fixture run. A second
cluster was a second bill and a second backup story for derived memory;
one cluster with a role is the same isolation for accidents at neither
cost. The connection budget is a bound, not a measurement: Honcho's
defaults (ten and twenty of overflow per process) would have taken the
cluster's connections from the event store on their own.

The first live deploy (10-31) corrected two claims the local measurement
had made. It exercised Honcho's startup statements under the role, not
Honcho's Alembic, which connects with options of its own, so the
ownership split surfaced only as "permission denied for table
active_queue_sessions" on the live poller. And Render's private address
did not follow the port the server opened. Both are fixed by making the
two sides agree by construction rather than by trusting the platform's
report.

## #18
The author, 11-01: "All raw text should be in the repo unless there's a
really good reason." Honcho derives text about her that nothing else
holds. The reads were first taken from the released SDK paired with
v3.2.2, the nearest thing to the server's word then in hand, and are
now held to the deployed server's own record (#9).
Whole or not at all because a partial read written as the export would
say Honcho had forgotten what it had not. `port` is a parameter only so
the HTTP boundary's test can read through `Honcho.HTTP` while the suite's
setting stays the in-memory Honcho.

## #19
Every sync of the resident's first live day failed (29 `SyncFailed`,
all `rejected: 422`, 11-01) while each turn was captured, so Honcho
held none of her conversations and every read of it, the brain's
`honcho` section and the nightly export, read an empty memory. A
failure the bridge records is retryable (conventions §8), and the turn
is already ours to resend. In order and stopping at the first failure,
because Honcho numbers a session's messages as they arrive and a later
turn sent first would be read as said first. Keyed by the turn's ref in
the message's metadata because the server dedupes nothing (a batch
sent twice is stored twice) and a timeout after its commit is a
failure on our side and a success on its. On demand rather than on a
schedule: the smallest thing that recovers what was lost; a Honcho
that fails again leaves `rejected:` rows the `sync_failures` check
already counts.
