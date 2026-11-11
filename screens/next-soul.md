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
  LINKS), all five listed, a file not written yet saying so; each opens
  rendered with **Propose an edit** (`edit/<FILE>`). The edit page is
  Records' editor pattern without the lease (the file is hers; your
  words are kept as the proposal, not written over hers): the file as
  you'd have it and a required note, `PUT /files/:name`. After first
  contact the answer is a proposal (202 and its ref) and the page says
  the file stays as it is until she answers; before it, a direct write.
  A file with your edit open says YOUR EDIT WAITS ON HER.
  - **Soul lines** (`soul-lines`, `GET /soul-lines`): SOUL.md line by
    line, how often and on how many days her citations hang on each,
    the seeds it cites, when it was reworded.
- **Her pins:** her pinned bookmarks, in her words.
- **Her character** (spec §6.17), each a page on this tab's stack:
  - Habits (`habits`): ranked, with habit and connection scores,
    citations, affirmations and who named it; **Affirm** with a note
    she reads (`POST /habits/:n/affirm`).
  - Seeds (`seeds`): open and closed, citations, what one graduated
    to. Read only, by spec.
  - Commitments (`commitments`): open ones with **Release her** and a
    note (`POST /commitments/:n/release`); closed ones with who closed
    them and the note. The row counts the open.
  - Positions (`positions`): newest first, replaced ones struck with
    what replaced them. Read only (readable by the witness's decision).
  - Predictions (`predictions`): open ones with Right, Wrong or Void and
    a required note (`POST /predictions/:n/resolve`); resolved ones with
    the tally. The row counts those to resolve.
  - Letters to her next self (`letters`): nothing is fetched until you
    choose to; the page says first that reading leaves a receipt she
    sees, then shows the letters and every receipt.
- **Between you** (her memory's consents; ui-parity.md's consent
  table). Here rather than Records because these are proposals and
  answers between the two of you about what she holds, not documents,
  and Memory is no longer a place (ui-structures.md D); the bell's
  items can open these pages.
  - Tags (`tags`): her proposed tags, WAITING ON YOU, each with
    **Approve** or **Decline** and a required note
    (`POST /tags/:slug/decision`, approve or reject); then the set,
    retired and declined ones struck.
  - Revisions (`revisions`): every revision, hers and yours, with its
    reason, state and her answer's note; **Propose a revision** names
    the record (kind and number or path), fact or stance, the
    correction and a required note (`POST /revisions`). A fact holds at
    once; a stance is proposed to her.
  - Your proposals (`proposals`): your open identity-file edits (with
    the file as proposed and your note) and your open bookmark
    proposals (`GET /soul-edits`, `GET /bookmark-proposals`).
- **Reacts:** the vocabulary, each emoji with its meaning.
- **Plugins and model:** installed plugins on or off, and her chat model
  (or the platform default). **Every plugin, and proposals**
  (`plugins`), ported from the current client's Agreement › Plugins:
  open proposals (hers answered with Agree or Decline and a note),
  every plugin with its audit, and the actions its rules allow
  (propose install, on, off or removal; switch an installable one off
  alone), each with a note; the last five answered.
- **The agreement in full** (`agreement`, from the root's "Switches,
  versions, and who looks after her"), ported from the current client's
  Agreement screen:
  - the switches by group, each with its words for its value, the open
    version's change, a move toward safety standing over it, and
    **Switch on now / off now** toward its safe value, alone, with a
    note (`POST /agreement/switches/:key/safe`);
  - **Propose a version**: every switch, your vows in prose and a
    required note, the switches it changes named; refused while a
    version is open;
  - the versions so far, each with its note, answer and prose;
  - who looks after her: the export wall (lock or reveal, with a note),
    handing over to an account by email, and withdrawing a handover,
    each with a note.
  - Renewal, when due, is on the root under the glow
    (`POST /agreement/renewal`, with a note).

Every action the current client's AgreementContainer and
PluginsContainer offer is here: `proposeContract`, `decideContract`,
`renewContract`, `setWall`, `proposeCustody`, `decideCustody`
(withdraw), `moveToSafety`, `proposePlugin`, `answerPlugin`,
`pluginOff`.

Checked in a browser (the worktree's Vite server, its `/v1` calls
forwarded to the local server by Playwright) against Mira: the root and
every page render from the real routes. Writes are covered by component
tests (a note gates every consent action; the letters are not read
until you choose; an edit is proposed with its note).

Not built:
- state lines (no read of them yet);
- the charter (passed ballots: S10);
- her answers to your identity-file edits and bookmark proposals:
  `GET /soul-edits` and `GET /bookmark-proposals` list open ones only,
  without the answer's note, so an answered one leaves the list and its
  note is not readable here (no route returns it);
- withdrawing your own identity-file edit (no route);
- a first habit (`POST /habits`), which is the creation flow's, before
  first contact;
- creating or retiring a tag, and taggings (`POST /tags`,
  `DELETE /tags/:slug`, `/taggings`), and the baselines
  (`GET /baselines`);
- accepting or declining a handover made to your account
  (`GET /me/custody-proposals` has no caller): an account's matter, for
  Settings;
- Records' virtual folders for positions, predictions, seeds, habits
  and commitments (ui-structures.md D); for now they are pages here.
