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
  - Unshelved files are counted.
  - On a wide screen the tree stays beside the page; on a phone the page
    takes the screen, and Back pops the stack.
- **The viewer** (`doc/<path>`):
  - The citation the document is cited by, its version count, when it
    was written and by whom, and its title.
  - Its markdown, with her citations as chips.
  - What it cites: resolved now, and struck through with the reason when
    unresolved.
  - What cites it: read for both `<kind>/<name>` and `<kind>/<name>.md`.
  - Following a citation pushes onto this tab's stack.
- **Citations** follow the server's grammar (Oneiroi.Seshat.Citations):
  - `<slug>:<kind>/<ref>`, the resident's own slug only;
  - a record kind (bookmark, position, …) names a record;
  - any other kind names the document `<kind>/<ref>` (`.md` added when
    there is no extension; keepsakes, root files and goals at the root).

  The same rule drives Chat's chips and peek. A record kind opens as a
  peek over the tree (`cite/<kind>/<ref>`).
- **Folder settings** (`folder/<kind>`, ui-structures.md D):
  - who edits;
  - whether it waits on the witness;
  - whether it may cite;
  - any open gate proposal;
  - how things arrive: the routes landing in it, with their profile.
    Profiles and keys stay in Settings.

- **History** (`history/<path>`, seshat#54): every version newest
  first, with who, when and the note. One opens as a diff against the
  file now (insertions and removals marked) with "Restore this version"
  and an optional note; a restore that needs her consent says it was
  proposed to her. A version overwritten before the repository's next
  commit is listed, and says its words weren't kept.
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
- **Add a document of yours** (`new`, top of the tree): a name and its
  words, written under human/, which she reads and never edits. A record
  just written or moved is read again for a moment until it is
  registered.
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
