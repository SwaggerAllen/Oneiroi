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
- **Her pins:** her pinned bookmarks, in her words, then **Her
  bookmarks, and what she sees every turn** (`memory`).
- **Memory** (`memory`), the current client's Memory screen ported, so
  that screen is no longer needed (ui-structures.md D: Memory is not a
  place; it lives beside her pins):
  - **Every turn** (the default view): the bookmarks the index lists
    (`GET /index`, today her pins), the server's own description of the
    index, and what it leaves out: how many are ranked per turn under
    the budget instead, and how many are ranked only in their room.
  - **All:** every bookmark, newest first, twenty a page with **Older
    bookmarks** (`GET /bookmarks?limit=&before=`).
  - **Pinned:** every pin, newest first.
  - **Use:** how retrieval has used each target (considered, returned,
    used, last used; `GET /retrieval`), shown only when the server
    answers it, as before.
  - A search over the line and summary, and a filter by each active tag
    (`GET /tags`), over the view's rows; on All they read the pages
    loaded so far, and the page says older ones may match too.
  - Each row: number, day, span, who pinned it, whether every turn
    carries it, the line, the summary, the tags; **Open** and **Pin** or
    **Unpin** (`POST`/`DELETE /bookmarks/:n/pin`). A pin is the witness's
    decision, recorded with who made it; the route takes no note, so
    none is asked.
  - **One bookmark** (`memory/<n>`, also reachable by URL): the line,
    the summary, when, the span's length, who bookmarked, proposed and
    pinned it, when a turn last listed it, the tags, and Pin or Unpin,
    from `GET /bookmarks/:n`. **The span's words are not shown.** That
    route returns the span's messages even when the bookmark is anchored
    in her private, unshared session, and nothing in its body says
    whether the session is private, so the client cannot tell which
    spans it may show. It keeps only the bookmark and drops the span as
    it arrives (it is never cached or rendered), and the page says why.
    When the route withholds a private session's words, or marks them,
    the span can come back.
  - The view, tag and search are kept per resident while a bookmark is
    open on top of the list.
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

Every call the current client's MemoryContainer makes is here:
`bookmarks` (the Every turn and Pinned views, and the root's pins),
`tags` (the tag filter), `indexNow` (Every turn), `retrieval` (Use),
`pin` and `unpin` (each row and the bookmark page). Beside them,
`bookmarksPage` pages All, and `bookmarkDetail` (the same
`GET /bookmarks/:n` as `bookmark`, typed as the server sends it,
`{bookmark, span}`) opens one. The current client's Memory offered
"Open the moment" only to a caller that passed it, and its container
did not; here Open is the bookmark page.

Every action the current client's AgreementContainer and
PluginsContainer offer is here: `proposeContract`, `decideContract`,
`renewContract`, `setWall`, `proposeCustody`, `decideCustody`
(withdraw), `moveToSafety`, `proposePlugin`, `answerPlugin`,
`pluginOff`.

Checked in a browser (the worktree's Vite server, its `/v1` calls
forwarded to the local server by Playwright) against Mira: the root and
every page render from the real routes. Memory was checked against the
real routes (Mira has no bookmarks locally: the empty views, and a
bookmark that is not there) and against bookmark fixtures served in
their place (paging, the tag filter and search, Pin and Unpin, the
bookmark page with a span that does not appear). Writes are covered by component
tests (a note gates every consent action; the letters are not read
until you choose; an edit is proposed with its note).

Not built:
- a bookmark's span (above), and pinning as a soul line's evidence
  (`POST /bookmarks/:n/pin` with `evidences`), which no client offered;
- retrieval by kind (`GET /retrieval?kind=`): Use lists every kind;
- `api.bookmark`'s declared type is flat (`Bookmark & {messages}`) and
  the server's body is `{bookmark, span}`, so the chat peek's bookmark
  reads `line` off the wrong level; the peek is Chat's to fix;
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
