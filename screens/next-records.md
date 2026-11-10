---
paths:
  - client/src/next/records/**
---

# next-records

The rebuilt client's Records tab (`design/ui-build.md` P2, first half),
at `/client/next.html#/records`. Built 2026-11-10.

- **The tree.**
  - One folder per kind with documents, plus any kind she owns.
  - Each folder says whether it is hers, how many documents it holds, and
    WAITS when a gate proposal of hers is open on it.
  - The gear opens the folder's settings.
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

Not built:
- history, diffs and restore; editing under a lease; reacts on
  documents (S4);
- the database-backed folders (with the readable copies,
  records-in-repo.md);
- ballots;
- proposing a kind change from the settings.
