---
paths:
  - client/src/next/soul/**
---

# next-soul

The rebuilt client's Soul tab (`design/ui-build.md` P4), at
`/client/next.html#/soul`. Built 2026-11-10: everything that rides every
turn.

- **The agreement first,** with the witness's glow.
  - It shows the version in force (with its renewal due) or the open
    one: who proposed it, whom it waits on, and that the version in
    force stays meanwhile.
  - Enforced terms are tagged, the prose is rendered, and the proposer's
    note is named as theirs.
- **When a version of hers waits on the witness:**
  - Agree.
  - Decline: only with a note, for her to read.
  - Amend: edits the prose and proposes it as a new whole version, with
    a note. There is no separate amend endpoint; an amendment is a new
    version.
- **Who she is:** the identity files (SOUL, IDENTITY, USER, GOALS,
  LINKS), each rendered on demand.
- **Her pins:** her pinned bookmarks, in her words.
- **Reacts:** the vocabulary, each emoji with its meaning.
- **Plugins and model:** installed plugins on or off, and her chat model
  (or the platform default).

Not built:
- state lines (no read of them yet);
- the charter (passed ballots: S10);
- editing identity files from here (proposals stay in the current
  client until P5's bell carries them);
- the switches.
