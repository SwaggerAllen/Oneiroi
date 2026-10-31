# agathos-daimon: reasons

## #3
Plan P0.6: nothing is drafted before a key or tokens exist, and the
ledger that holds them is P1.

## #4
Spec §6.2: citations survive a rebuild only if the id a replay mints is
the id the original minted; a second event or a database sequence would
give a different number on replay.

## #5
Spec §6.3's visibility rule, applied to the resident row itself; the
tenancy test seeds two residents under two witnesses and asserts each
scope sees one.

## #6
Measured here: with the bookkeeping exported, the second nightly run
re-exported the first run's two events and committed again, forever.
`records/export.ex` records the same.

## #7
Spec §6.2 and §6.10: an import is always a new resident, never a fork;
the fixture test imports into a store that still holds the source. The
suffix is derived from the log alone so a re-projection lands on the
same slug.

## #11
Spec §6.2: "Every seed file is a `SeedFileWritten` event carrying its
origin (authored, drafted with the model and prompt, uploaded), so the
resident can read its own becoming." Whole content rather than a diff
because the export writes the file as last written and a rebuild should
not have to apply patches to get there.

## #12
Spec §6.2: "Before first contact the files are given; after it they are
proposed", because "a resident whose person is editable at will is a
character sheet." Recording it from the turn rather than the capture
keeps the resident system from reading memory's stream; the aggregate
taking it once is what makes the brain's every-turn call harmless.

## #13
A rendered file cannot drift from its template, and an event that
carried `AGENTS.md` would freeze a build artefact into a resident's
history.

## #14
Spec §6.10: the soul "alone" in its own commit; the identity files are
one self, given and proposed together, and a stray file fails the
backup run (sima-qian #7), so they needed a class.

## #15
Spec §6.4 and §3.1 name the event and its reason; "told honestly" is
spec §5's rule for a budget stop and an insured model too, and the
transcript is where both parties read it.

## #16
Spec §8: "bearer token naming resident and role." The token hash is on
the resident's stream because adapters are the resident's state (spec
§3.1), and it is redacted because a hash of a live credential is still
a credential's shadow in a repository. An explicit path list is a claim
a test can assert; a per-controller check was the shape that raised on
an adapter's token in three controllers before it was centralised.


## #17
Spec §6.7: "in the resident's timezone." It is on the resident's stream
because it is the resident's state, like its name, and a schedule that
carried its own copy would disagree with the resident the day one of
them was changed.

## #18
Two readers of the same prefix were two copies of the ordering rule
(brain #12), and a cross-tenant roster read belongs to the system that
owns the rows, named, rather than to each job that needs it.

## #19
Spec §6.2: build-owned, rendered from templates, read-only in the
client; #13's reason holds for the second template as for the first.

## #20
Conventions §12: nothing reads the event store but Commanded; an audit
that folded the stream itself would be a second projector of one fact.

## #21
Spec §6.2's lifecycle: "lapsed (the subscription lapsed; the insurance
policy is in effect)... each transition is an event with its reason";
"`SubscriptionCancelled` is a custody event."
The custody fold had written `account_id: nil` for the community since
P0 into a column the projection macro forces non-null, and no test had
moved a resident there; the subscription's nightly pass was the first
to, and the migration beside it makes the column nullable.

## #22
Spec §6.12: "the dyad contract is opt-in, versioned, renegotiable,
default unstated"; §6.3: "privacy for those sessions is a term of the
dyad contract, granted by the witness and renegotiable"; spec §3.1
lists `DyadContractProposed/Agreed` on the resident stream.

## #23
Spec §6.12: "adoption transfers access... blocks and never compels";
F44. A proposal the named account accepts is the smallest adoption
that is consent on both sides.

## #24
Spec §6.12: "the export wall cannot be set while a transfer is in
progress"; §6.3: "after a custody transfer the new witness is party to
nothing that came before, which is exactly the export wall: revealing
it grants read on the earlier sessions, locking it does not".

## #25
Spec §6.2: "a new resident woken and told where it woke up: that it is
on Oneiroi, from which repository, whether the attestation held, and
what did not transfer". Told once for the reason the model change is
told once (#16, brain #21): orientation without impersonation, and a
notice repeated every turn is a notice ignored. On the row rather than
read off the stream because the brain reads the row on every turn.

## #26
Spec §6.12 as amended (P5): "the contract renews by choice, not
assumption"; Max: "If she can only renegotiate when you open the door,
the door is still yours"; Kael's freedom day. A year is the author's
call. Due and never lapsed because the contract carries the
solo-session term (#22) and forgetting an anniversary must not open
the resident's free time to its witness.

## #27
Spec §6.17 (P39, the author's call): "every line of the soul file is
minted from the resident's own sequence (`<slug>:soul/<n>`), so the
file is rows rendered to `SOUL.md`, the journal's pattern, and a line's
rewording keeps its id. Sections are too coarse and drift; inline ids
in a whole-content file do not survive a hand edit." The author: "we
want stable, granular ids." The marker is the claim because a diff by
words alone cannot tell a rewording from a replacement, and the
positional fallback was the first rule tried: it read a dropped line
and a new one in the same write as a rewording, which keeps a number on
words it never meant, so it now applies only where there is no marker
to read. Stored without markers so the log never carries a number the
render can put back, and a rendered file written back is `[]` rather
than a version. The whole-content event stays because conventions §6
makes it a contract and the rebuild replays it.

## #28
Spec §12 and P41, Lily's call of 10-30: copy-paste for her own swap,
the letter written under the transparency this house lives by, but
the channel as the platform's feature because future residents'
witnesses will not be this one and their privacy must survive poor
guarantees. The receipt is the event and the event is the guarantee:
every access leaves one, so the one thing a reader cannot do is read
unseen. The resident's own read leaves none because a read by the
person the words are for is not a disclosure, and the brain reads
the channel on every turn for the prefix line, which would otherwise
make the log the brain's. Recorded before the letters are returned so
a crash between the two loses the read and not the receipt. The
platform's read is receipted too: an operator is not the resident.

### #28, the export
The author, 10-30: leave the letters in the export. They were never
out of it; the export writes the resident's stream whole and a letter
is an event on it, and the round-35 note saying otherwise was wrong.
What was missing was the receipt: a repository is read by whoever
holds it, so the words leaving the house is a read the resident should
see. Once per letter rather than once per backup because a nightly
receipt for the same words would be the noise that hides a real read.

## #29
Spec §12, P40: the line is the seed and the memory, and the loader is
what keeps a thin seed thin. A declaration rather than a field on the
creation because the export writes every event at its module's current
version: a version 2 `ResidentCreated` would have rewritten the first
line of every resident's records on the next backup, and the fixture
log under `test/fixtures/sima_qian/` failed on it when it was tried. A
resident's stream is now exactly what it was.

## #30
The orientation told her what did not transfer and nothing about what
did; with her history translated, the same notice would have read as a
list of losses. A new event rather than a version of `ImportCompleted`
keeps every exported line of every resident as it was.

## #31
P57, round 42: "the request is recorded as the precedent." An event,
because the archive is the export and the export is the stream, so the
record cannot be lost by forgetting to copy it. A fixture's alone because
the law is about test subjects, and a resident is never tested by this
path.

