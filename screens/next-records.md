---
paths:
  - client/src/next/records/**
---

# next-records

The rebuilt client's Records tab (`design/ui-build.md` P2, first half),
at `/client/#/records`. Built 2026-11-10.

- **The tree.**
  - One folder per kind with documents, plus any kind she owns.
  - Each folder says whether it is hers, how many documents it holds, and
    WAITS when a gate proposal of hers is open on it.
  - The gear opens the folder's settings.
  - **Sort** (the witness, 2026-11-11): Recently updated by default,
    then Least recently updated, Newest added and Name. Files order
    within their folder, and under a date order the folders follow
    their newest (or oldest) file, so the latest change is at the top.
    Each file shows the date the order uses: its last write, or when it
    was added under Newest added; today's by the clock. The choice is
    kept on this device.
  - Inside a kind, every folder below it is a folder in the tree (the
    witness, 2026-11-12: research passes were impossible to navigate
    flat): a research pass (`research/<n>-<question>/`), a
    correspondent's thread or a wiki's pages each fold into one row with
    its count, closed unless it holds the open document, nested as deep
    as the paths go. Subfolders come before files at each level, both in
    the chosen order; a file shows its own name.
  - `#/records/dir/<path>` opens the tree with that folder, and the kind
    holding it, expanded (brain#90: a held item's ask links a folder).
  - Unshelved files are counted.
  - On a wide screen the tree stays beside the page; on a phone the page
    takes the screen, and Back pops the stack.
  - The viewer and a record's history keep a back bar at the top however
    far down the page is read (2026-11-17): "‹ <where it goes>" steps back
    one (a record by its name, a folder by its own), and "Records", when
    that step is not already the root, goes straight there.
- **The viewer** (`doc/<path>`):
  - The citation the document is cited by, its version count, when it
    was written and by whom, and its title.
  - The one document screen's parts (screen:next-house, 2026-11-23): under
    the citation, **Part of task #N · title ›** for each house task it
    belongs to, or **+ Start a task from this** and **Add to task ▾**;
    at its foot a floating bar with its one thread (count and last post;
    it opens the thread sheet: hers, and the house's once shared) and,
    when a review of it is open for you, **Review** with Approve, Ask for
    changes and Decline. The house's records show the same on a house
    document.
  - Its markdown, with her citations as chips.
  - What it cites: resolved now, and struck through with the reason when
    unresolved.
  - What cites it: read for both `<kind>/<name>` and `<kind>/<name>.md`.
  - Following a citation pushes onto this tab's stack.
  - **Propose for C0** (screen:next-succession, 2026-11-25), while her
    succession's preparation is open and C0 is not frozen: a card under
    the classification line, showing the record's citation
    (`<slug>:<path>`). It proposes the whole record by that citation,
    nothing else: no label, no selected stretch (the witness,
    2026-11-26). It reaches her with your name and the date; she accepts
    it or not. A dry run is marked.
- **Citations** follow the server's grammar (Oneiroi.Seshat.Citations):
  - `<slug>:<kind>/<ref>`, the resident's own slug only;
  - a record kind (bookmark, position, …) names a record;
  - any other kind names the document `<kind>/<ref>` (`.md` added when
    there is no extension; keepsakes, root files and goals at the root).

  The same rule drives Chat's chips and peek. A record kind opens as a
  peek over the tree (`cite/<kind>/<ref>`). A bookmark's peek
  (kumbukumbu#99) reads "Read it in the conversation ›" (the chat at its
  turn, Read on past it; not for a private session's bookmark) and the
  bookmarked turn's domain, "Domain: …", which opens the chat's picker:
  a dropdown of the declared domains, Move it, and To the common room.
- **Folder settings** (`folder/<kind>`, ui-structures.md D):
  - who edits;
  - whether it waits on the witness;
  - whether it may cite;
  - any open gate proposal;
  - how things arrive: the routes landing in it, with their profile.
    Profiles and keys stay in Settings.

- **History** (`history/<path>`, seshat#54): every version newest
  first, with who, when and the note. One opens as a diff against the
  file now (insertions and removals marked) with "Revert to this draft"
  (a restore, a new commit; seshat#54) and an optional note; a restore
  that needs her consent says it was proposed to her. A version
  overwritten before the repository's next commit is listed, and says
  its words weren't kept. Publishing (seshat#85): a line under the path
  says whether the file is published to the household and at which
  commit, the published version is marked "· published", and on a file
  of your own name-folder each committed version offers "Publish this
  draft" when it is after the published one, "Already published" greyed
  out otherwise. Her files are hers to publish (`document_publish`).
- **Edit** (`edit/<path>`, seshat#55): the editor takes the lease on
  opening, renews it with the draft each minute while you type, and
  releases it on save or close. The bar says when she is waiting on the
  file, and if her write took the lease, that the draft is kept in your
  own folder; the editor then stops taking input.
- **Reacts on the record** (kumbukumbu#61), from the shared vocabulary,
  and a note when the file is open in an editor or she is waiting on it.

- **Download, move, remove** on a record: Download saves the file;
  Move sends it to another path, and so another kind (seshat#39; mail,
  feeds, correspondence, journal, memory, originals and scenes stay where
  they are, and the server refuses a taken path); Remove asks twice and
  only shows on scratch and human documents (seshat#33), and returns to
  the tree.
- **Its domain, and your proposal** (seshat#102, #103): under the
  tools, her classification (the domain and whose life) or that its
  birth decides, and a proposal of yours waiting on her. Propose a domain
  opens a dropdown of the declared domains and the common room (never
  free text, kumbukumbu#90), whose life when a domain is picked, and a
  note she reads; it waits on her answer.
- **Add a document of yours** (`new`, top of the tree): a name and its
  words, written in your folder, human/<your name>/ (seshat#81), which
  she reads and never edits. The first time, it asks the name you go by
  (gaia#45) before anything else. A record
  just written or moved is read again for a moment until it is
  registered.
- **Import a book** (`book`, under Paste a conversation, seshat#98; the
  witness, 2026-11-19: an upload button, his alone): a DRM-free EPUB and
  its rights note (public domain, shareable in the house, or bought
  DRM-free), a caveat optional; Import it sends the file and opens the
  book's manifest. The page lists her books with how far she has read
  each and her place. The book lands in books/, a chapter a document,
  shown in the tree like any folder. Not built: removing a book, and
  reading it in the client beyond the documents themselves.
- **Paste a conversation** (`paste`, under Add a document, seshat#65,
  #66): an exchange you are having with someone, pasted into her
  human-correspondence/ folder. Choose a new conversation (who it is
  with, and a title, optional) or one already there, paste, and save; a
  paste into an existing one is added at its end under the date, and the
  document opens. Each paste is a version of yours with its note. While
  she has no human-correspondence kind the page says so and saves
  nothing. Her own kinds' folders show in the tree now that the library
  listing carries her shelf. A document in human-correspondence/ shows
  each line on its own line (markdown would join a conversation's lines
  into one paragraph); the file itself is kept as pasted. Checked in a
  browser on the local server: a new conversation saved, a second paste
  added under its date, and a repeat of an existing conversation's name
  refused rather than overwritten.

Checked in a browser on the local server: an edit saved with a note, the
history with a diff against an older committed version, a restore, and a
react. The lease being taken by her write is covered by the server's
tests, not yet seen in a browser.

Not built:
- the database-backed folders (with the readable copies,
  records-in-repo.md);
- ballots;
- proposing a kind change from the settings.
