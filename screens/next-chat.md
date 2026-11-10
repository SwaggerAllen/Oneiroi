---
paths:
  - client/src/next/chat/**
---

# next-chat

The rebuilt client's Chat tab (`design/ui-build.md` P1), at
`/client/next.html#/chat`. Built 2026-11-10.

- **Conversation | Sessions** switch. Both stay mounted, so the
  conversation keeps its place and its draft.
- **Conversation:**
  - The main session's newest page is read from the query cache, so a
    change notice (apsu#24) refreshes it. Reaching the top reads older
    pages back, keeping the reader's place.
  - Her replies render as markdown (no raw HTML), with her citations
    (`<slug>:<kind>/<ref>`) as chips; the witness's words stay plain.
  - Tool calls collapse to one line.
  - The turn streams in under its step (thinking, the tool's name,
    writing) and a timer. The same status events drive the header's
    presence line.
- **Sending** uses the current client's outbox (brain#45): each message
  is held under its own ref until its turn lands. A message sent while
  she works is queued. "Not sent" and "No reply came" offer Send again
  under the same ref.
- **Stop** replaces Send while she works and the box is empty.
- **Unread:** the conversation opens on the first unread reply, under a
  "New since HH:MM" rule. The read mark advances whenever the reader is
  at the bottom. "↓ n new" jumps to the rule, or to the bottom.
- **Reacts (kumbukumbu#56):** his reacts show on her replies, hers on
  his messages. The React menu lists each emoji with its meaning, from
  the reacts vocabulary.
- **Peek:**
  - A citation chip opens a sheet over the chat on a phone, or a side
    panel at desktop width. The panel stays open while the witness
    keeps talking (decided 2026-11-10).
  - Documents and bookmarks render in the peek; other kinds offer
    "Open in Records".
- **Sessions:**
  - Running now: the main thread while she works, and any other
    session active in the last ten minutes. Free time is marked "words
    private" and is never read.
  - Planned: check-ins and free time still ahead today, plus one-offs.
  - Today's other conversations.

Not built:
- the navigator scrubber (it waits on S2's scenes, paging and density);
- reading a non-main session's transcript from Sessions;
- message virtualization;
- motion.
