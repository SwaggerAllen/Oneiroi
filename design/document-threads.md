# Document threads, task documents, named activities

The witness's plan of 2026-11-23, settled in conversation while mocking the
queue redesign (design canvas "House queue redesign"). It is the server
half; the screens come after it and are built on it. Nothing here is built
yet.

## What the screens need

One document screen, reached from Records, from a task's documents, or
from a review. On it: the document, its one thread, the task it belongs to
(or "Start a task from this" / "Add to task"), and the review controls when
a review of it is open for whoever is looking. Reviews post their decision
into the thread. A task lists any number of documents. Activities carry the
names their template gave them.

Substack comments are not part of this. They are correspondence, and the
link from a Substack post to its originating document is still loose; that
gets its own design.

## Rulings (the witness, 2026-11-23)

1. **Two threads, not one carried over.** A document's thread in its
   resident's workspace is private to the dyad. When the document is shared
   to the house, the house thread is a different thread with a household
   audience. Nothing from the dyad thread moves into the house.
2. **Comments wake her.** A reply in her workspace wakes her main chat, as a
   house watch does.
3. **A task forks its template when it opens.** The task's layers are its
   own from then on: editing a task never touches the template, and editing
   a template never touches an open task. A bulk update (replay a
   template's committed operations, in order, over a chosen set of tasks) is
   the later answer to migration and is not built now.
4. **Her threads live in her repo**, in the same layout the household repo
   uses for its threads.

## 1. Thread spaces

Threads today are household files: `threads/<id>/trunk.md` and
`threads/<id>/replies/<nnnn>-<author>.md` in the household repo, written by
`Seshat.Household.*` under the household lock, every path keyed by the
household id.

- A **space** is `{:household, id}` or `{:resident, id}`. Thread code takes
  a space where it took a household id; the files, the lock, the front
  matter and the document-post fields (`doc`, `doc_commit`, the
  draft-changed line on edit) are the same in both.
- A resident's threads are in her own repo under `threads/`, written with
  her repo's lock.
- **Audience:** the dyad. Under the audience policy the dyad is always
  permitted, so writing in her space asks nothing; nothing in it is
  readable from the house, by a housemate, or through a house citation.
- **Who writes:** the resident and her witness, always. (The house's
  `witnesses_post` beat setting governs the house space only.) No beats
  quota in her space: it is a conversation between two.
- **Tools:** `household_post`, `household_reply` and `household_read` take
  an optional `space` (`house` by default, or `mine`). Citations to her
  threads are `<slug>:thread/<id>`, her own kind like any other in her repo.
- **Witness routes:** the thread routes under `/residents/:id/threads`, the
  same shapes as the house's.

## 2. One thread per document, per space

- Posting on a document returns its thread if one exists in that space,
  and opens it otherwise. The key is the document's path without its pin.
- A document → thread index replaces `Files.discussed/2`'s scan of every
  trunk.
- Where a document already has several house threads, the oldest is its
  thread and the rest are listed as earlier threads, read-only.
- A promoted document's house thread keys on the house copy's path, as
  promotion does now, and the document screen reaches it from her source
  path through `shared_from`.

## 3. Reaching her, and the screen

- A witness reply in her space sends the house-watch notice to her main
  chat ("a new reply on design/privacy-repair.md"), envelope only, through
  the letter-wake path: throttled per hour, never in quiet hours. She reads
  the thread with `household_read` and answers with `household_reply`, from
  whichever conversation she is in.
- Thread writes in either space publish on PubSub; `HouseChannel` carries
  the house's, the resident's session channel carries hers. The client's
  thread polling goes.
- Unread uses the existing `MarkSeen` subjects: the resident's id for her
  space, `house:<id>` for the house.

## 4. Queue

**Names and forks.**
- A template activity spec gains `name` (required, ≤ 80). The starter
  templates are named (doc-to-pr: Draft the design, Witness review, Share
  with the house, Peer review, Build it, PR review, Merge).
- `TaskOpened` already copies the template's layers into the task. It
  gains `template_version`: the count of that template's definitions so
  far, which is what a future bulk update replays from. Each copied
  activity keeps its name.
- `EditLayers` changes the task's own copy only, as now; an activity it
  adds must carry a name. The task page says "from doc-to-pr" until its
  layers are edited, then "forked from doc-to-pr".

**Documents on a task.**
- `links` becomes `documents: [%{citation, role}]`, where `role` is a slot
  name (`design`, `pr`) or `source`. Slot documents still arrive through
  `FillSlot`; sources through new `AttachDocument` / `DetachDocument`
  (owner, witness, or an assignee of the task). Old tasks' `links` read as
  sources.
- "Start a task from this" is `OpenTask` with the document in a slot or
  as a source.
- A document → task index (path without pin) answers "Part of task #9".

**Reviews post to the thread.**
- After `ReviewDecided`, a handler posts the decision and its note as a
  platform reply in the reviewed document's thread: her space while the
  document is unshared, the house once shared. A note the reviewer withheld
  stays out. The reply names the activity ("Witness review: changes asked")
  and the pin it was made on.

## 5. The document screen's read

`GET /documents/:citation` returns the document at a pin (head by
default), its thread in each space the viewer can see, its tasks with
their open activities, and the review open for the viewer, if any. Records,
the task page and a review all call it.

## Order

One branch. 1 → 2 → 3 are the threads; 4 can go alongside; 5 last. The
redesigned screens follow, from the canvas.
