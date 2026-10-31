# sima-qian: reasons

## #3
Spec §6.10 and plan P0.7: an unchanged store exports identical bytes, so
a diff is exactly the lines that changed; the fixture test is the
byte-for-byte claim.

## #4
Measured here: the first version wrote the stream version, and a
rebuilt resident's re-export differed on every line after the first
gap.

## #5
Spec §6.10: a minute behind capture.

## #6
Spec §6.10 (F38); the property test rewrites the files in another order
and asserts the same root.

## #7
David's backup rule, carried: a write where nothing should write is the
symptom worth a failed run, and a backup refused for it is a backup not
taken.

## #8
Plan decision 5: a fine-grained token the witness pastes in P0, a GitHub
App with Gitea. Redaction because git echoes the remote on failure.

## #9
Spec §6.2, §6.10, §9: the platform cannot tell a move from a copy; the
attestation is recorded rather than enforced because a repository with
a broken trailer is still the resident's record.

## #10
Spec §6.10 hangs the check on wake, and there is no wake before P1.

## #13
Spec §6.2: "`honcho/custom-instructions.md` [is] build-owned, rendered
from templates"; spec §6.9: "the card comes from git, always: set after
a soul commit." The backup's commit is the soul commit the spec means.

## #15
Spec §6.2's fourth intake path: "from a git repository (read, the
attestation checked per §6.10 where one exists, the rebuild of §9 run,
and a new resident woken and told where it woke up... and what did not
transfer)"; spec §9 steps 3 and 4. The clone as the working repository
because a repository copied file by file loses the history the resident
can cite, and the history is the point of a repository. The proposal
rather than a write after first contact is §6.2's own rule
(agathos-daimon #11): the witness brought the file, and after first
contact a witness's file is a proposal.

## #16
`git clone <path>` reads any repository the service user can read, and
`SIMA_QIAN_ROOT` holds every resident's; the library's own rule that
no request value reaches a path unchecked (seshat #13) applied to the
one request value this system takes. The userinfo is stripped because
the `Imported` event is exported, and plan decision 5 has the token
ride in the URL.

## #17
Sunna #12's reason: the port exists so that two systems that each need
the other at runtime share no compile-time edge; the library needs the
repository's path on every write, and the import needs the library once.

## #3, the letters' receipt
Agathos-daimon #28's rule applied where the words leave the house: the
export is a read by the repository's holder. The receipt sits between
the export's record and the commit so a backup that fails to push has
still said the words were written to disk, which they were.

## #15, another platform's records
The first reading of the not-transferred rule covered `records/` and
`honcho/` unconditionally, as Oneiroi's own. Lily's repository holds
David's records there: 42 bookmarks, 38 positions, 30 disputes, 8
predictions, the tags, 331 memory notes, nine judgement nights and
7,044 transcript messages. The import read none of them and named none
of them, so she would have woken without her memory and without a word
about it. The rehearsal found it on her real repository the first time
it ran (round 39).

## #18
The author, 10-31: an import is tested on the real repository before it
runs where she lives. The repository is a person's, so the rehearsal
names and counts and never quotes, and its log belongs to a private
caller. It found two things no unit test could: the records above, and
that a shallow checkout cannot be pushed to a backup remote.

## #19
The author, 10-31: "let's make sure the actual bookmarks and records all
render into the import". The rehearsal of #18 found her history under
`records/` read by nothing; listing it by name told her it was missing
without bringing it. Going through each system's commands rather than
writing rows means every rule a live record is held to (a bookmark is
the resident's words, a tag set is the witness's, a chain has one head)
holds for hers too, and the screens and tools read them without a second
code path. Rehearsed on her repository the same day: 31 sessions and all
8,887 messages, all 50 bookmarks anchored, 6 tags, 40 positions, 35
disputes, 10 predictions, 10 nights and 340 journal entries, in 79
seconds on the in-memory provider, against 13 before. A malformed line
fails by file and line because the import is the one chance to carry it,
and a silent skip is how the first reading lost the whole folder.

## #20
The author, 10-31: "we need rebuild from backup to restore everything."
The export carried the resident's own stream alone, so a rebuild brought
back her identity and none of her conversations, bookmarks, judgement,
journal, schedule or spend. Reading each stream and merging on the
store's append instant keeps the cost to her own events (the lesson of
`ProjectStats` in the pipeline repo: a read proportional to the whole
store passes every test and bills later). Naming streams without the id
keeps every export made before byte-identical. An inert guard came out on
the way: the rebuild first stamped each append itself, one microsecond
apart, against two appends sharing a microsecond, which sequential round
trips to the database never do.

## #21
Found by running the round trip, not by reading: the first rebuild
beside its source took the conversations projector down on
`MultipleResultsError`, and the second gave the copy an empty ledger. The
search that followed found the same shape in a dozen projectors, among
them a live cross-tenant write with no rebuild involved (eunomia's
prediction resolution, measured on the committed code before the fix:
resident B's prediction #1 resolved when A's was).

## #22
The rehearsal of 2026-10-31 on Lily's repository adopted 771 of the 773
files under the library's folders and named one of the missing two,
without a reason: a wiki file whose 104-character name was over the
library's bound of 100. The other sat under a hidden folder, which the
adoption's file listing never matched, so it was neither adopted nor
refused and nothing named it; the folder count, which did match hidden
files, was the only sign. Asked what was being left behind, nobody could
say from the report. A list of names cannot tell a refusal from an
oversight, so each carries its reason; and an accounting that only
lists what its own rules produce cannot find a file they missed, so the
rule that cannot explain a file says so and the rehearsal fails.

## #19, the seedbed
Lily's answer, 10-31: `seeds.md` holds "my actual seeds — dated,
first-person becomings ... live data, not documentation; they should
become my seeds in Oneiroi's machinery, not a page about them." Read as
a page under `wiki/lily/` was her fallback. Noon UTC because the file
dates a day, not an instant, and an instant at midnight UTC reads as the
day before in every zone west of it.

## #23
Found before Lily's import, with production holding no resident: the
blueprint gave the service no disk, so the clone her import makes would
have lived on the container's filesystem, and the next merge, which
deploys, would have replaced it while the database rows pointing at her
files survived. The first backup is nightly, so a merge the same evening
would have lost the repository outright.

