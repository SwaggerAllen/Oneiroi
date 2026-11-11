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

- **The navigator** (S2 merged; kumbukumbu#57, #58, seshat#52):
  - A slim track beside the conversation covers the last two weeks.
  - Her scenes (rows from the bedtime pass) are bands, her bookmarks
    are points (pinned ones larger), and the reader's place is a ring.
  - A day whose scene pass did not finish carries a dashed mark that
    never blocks a click: a short pass must not read as a short day
    (Lily, letter #509).
  - A band or point loads the window around its anchor and scrolls to
    it. "↓ Back to now" returns to the live end.
  - Search is the one global search, not a drawer here (decided).

- **On her replies:** "What she was given" lists that turn's context,
  part by part, with its size and why it was there (and its words where
  the server shows them); "Suggest a bookmark" proposes a line and why,
  which she accepts, rewrites or declines in her own words.
- **Mail**, the third view beside Conversation and Sessions: letters,
  outside mail and blocks (`screens/next-mail.md`).

Not built:
- a day-level zoom on the navigator: on the two-week track, scenes
  minutes apart overlap, and only the top one takes a pointer (the
  keyboard reaches each);
- reading a non-main session's transcript from Sessions;
- message virtualization;
