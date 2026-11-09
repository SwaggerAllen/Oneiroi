---
paths:
  - client/src/screens/library/**
---

# library

Library (spec §10), partly built 2026-11-02: `client/src/screens/library/`
(`Library.tsx`, `paths.ts`, stories and tests), under More, loaded by
`LibraryContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/library` and `.../library/documents/*path`. The
state list lives in the stories (DESIGN §4).

Every list and every document is its own address (the witness,
2026-11-08, through Lily's letter #338; `route.ts`): `#library` is
every document, `#library/<kind>` one kind's list, and `#doc/<path>` a
document alone on its own page (`DocumentPage.tsx`, loaded by
`DocumentContainer`). The shell follows the hash when it changes, so a
link from anywhere and the back button land on the same place; a tab
moves the address. The waiting list's pieces (for review, to publish)
open the piece's own page, where the decision sits beside its words.
A document's page: its title and its kind and path in the top bar, a
way back to its kind's list, when it came into the library and when it
was last written and by whom, its versions and status, the piece's
review (Approve, Decline, each with a required note) when it waits on
you, and its words whole, or that the library holds nothing there.

Every list sorts (the same letter): by updated (last written), created
(first registered, `created_at` from the row's `registered_at`,
seshat#48), or title, each either way round; updated, newest first, is
the default, the working library's front page being what was touched
lately. A document with no time sorts after every one with one.

Built: a tab per kind across the top, All first and each with its
count, in the server's shelf order and under its names (seshat#35).
The client knows no kind: a kind with documents has a tab, so one the
server adds, such as the oracle's answers under `oracle/`, appears
with no change here once it holds a document, and a kind the shelf
does not name comes last under its own name. Yours (`human/`) is always
present so the first can be added. The tabs wrap on a phone rather
than scroll, so none is out of sight.
A row is the title (or the path), the path, its status when it has
one, and "missing from the repository" when the file is gone.
A Find box narrows the tab by title and path as you type; "Search the
words" runs the library's own index (`GET .../library/search?q=`, one
embedding call, so it is a button rather than per keystroke) and shows
the passages found for the tab, each opening its document. Keepsakes
carry why each mattered in the resident's words, or that she has not
said why yet (seshat#32); the shelf's server-given tabs now include Goals, At the root and Archive (seshat#43–#45), where an archived document reads whole with its frontmatter and its old path holds a tombstone saying where it went; a document opens on its own page and reads whole, as plain
text; scratch and human documents are removed with the
button turned into its consequence; every document but the kinds their
systems write (mail, feeds, correspondence, journal, the originals)
offers Move, a new path in place (a name alone at the root is a
keepsake), sent to `POST .../library/move` (seshat#39), the server
saying what may move where; a document of yours is added, on the
Yours tab, by pasting or from a .md or .txt file, under a name made safe
(`humanPath`). Not built:
writing by status with the review copy, publish, research tasks and
source release, digests, the journal's plan versus actuals, feeds,
adopting a file made outside the flow.

## #1 Shows

Writing by status with the review copy, references resolved, conversations, copy for publishing; research tasks with their sources and release state; digests; the journal with plan versus actuals; feeds with errors; design and other kinds; files made outside the flow.

## #2 Does

Copy; publish; release or withhold a source, a task's sources or a pass; add or remove a feed, approve or decline a proposal; adopt a file.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
