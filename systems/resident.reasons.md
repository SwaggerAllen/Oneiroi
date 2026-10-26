# resident: reasons

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
