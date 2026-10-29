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
Plan decision 5: a fine-grained token the steward pastes in P0, a GitHub
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
