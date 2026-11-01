# proteus: reasons

## #8
Conventions §9: every external sits behind a behaviour with a fake
that ships with the port, registered in `externals/0` with a kill
switch; spec §2.2: workspace filtering on every bridge query.

## #9
Conventions §9: "a hand-written fixture is a claim about the real
system, and a fake that disagrees with it hides the bug it was built
to catch." A body nobody has seen answered is written as a claim or
not at all.

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
holds. The brief was not to guess endpoints: the client's own paths were
read from v3.2.2's routers but its bodies from docs, so the reads were
taken from the released SDK paired with that version instead, the
nearest thing to the server's own word this side of the pinned image.
Whole or not at all because a partial read written as the export would
say Honcho had forgotten what it had not. `port` is a parameter only so
the HTTP boundary's test can read through `Honcho.HTTP` while the suite's
setting stays the in-memory Honcho.
