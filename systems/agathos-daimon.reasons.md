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
tenancy test seeds two residents under two stewards and asserts each
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
