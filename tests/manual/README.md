# Manual tests

Judged tests against a running preview, in `Checks`, before reconcile
(orchestration's DESIGN §9). One file per test: `tests/manual/<id>.md`.
None exist yet: the first screen with a story is P1's, and a manual test
without a preview to run against is a claim nothing checks.

**They replace the brittle integration layer, not the unit suite.** The
fast deterministic tests under `test/` stay exactly as they are. These
are for the defect a green unit suite keeps missing: a seam where both
sides are correct and the crossing is unasserted.

## The front matter is the selection

```
---
covers:
  - system:sima-qian
  - screen:status
---
```

`covers` names the **docs that own the code the test exercises**, never
path globs. The globs already live in each `systems/*.md` and
`screens/*.md` front matter, and the pipeline reads a diff through them;
restating them here would be a second copy of one rule. Per PR, a test
runs when the diff touches a seam it covers; the whole set runs at the
milestone boundary. A test covering a seam no doc declares fails the
audit: it could never be selected and so could never fail.

## What a test file contains

Preconditions, steps, expected observations, and **what would make this
test wrong**. The judge is told to report it if that condition now
holds, and to give the verdict the test as written produces anyway.

## The rules that will surprise you

- **A pass with no evidence is a failure.** Screenshots, transcripts and
  the observation log are run artifacts.
- **The judge never sees the diff**, the implementation or the ticket;
  its checkout is this directory and `pipeline.config.json`.
- **A new test is proven by breaking the thing.** Run it against the
  feature commit reverted and record the failure beside the test.
- **Two verdicts differing for one test on one commit is a finding about
  the judge**, recorded `neutral`, filed to Triage, not counted against
  the ticket.
- **Nothing a manual test does calls a paid model on the platform's
  account.** A test that needs the resident to answer runs on the
  steward's key, and says so in its preconditions.
