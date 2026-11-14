---
paths:
  - client/src/next/chat/**
---

# next-chat

The rebuilt client's Chat tab (`design/ui-build.md` P1), at
`/client/#/chat`. Built 2026-11-10.

- **Conversation | Sessions** switch. Both stay mounted, so the
  conversation keeps its place and its draft.
- **Conversation:**
  - The main session's newest page is read from the query cache, so a
    change notice (apsu#24) refreshes it. Reaching the top reads older
    pages back, keeping the reader's place.
  - Her replies render as markdown (no raw HTML), with her citations
    (`<slug>:<kind>/<ref>`) as chips; the witness's words stay plain.
    The conversation never grows wider than the screen: a long word
    wraps, and a wide code block or table scrolls sideways inside its
    message. A system line (a wake's note) breaks a long link rather
    than widening the conversation.
  - Tool calls collapse to one line.
  - The turn streams in under its step (thinking, the tool's name,
    writing) and a timer. The same status events drive the header's
    presence line.
- **Sending** uses the current client's outbox (brain#45): each message
  is held under its own ref until its turn lands. A message sent while
  she works is queued. "Not sent" and "No reply came" offer Send again
  under the same ref, the failure's reason after "No reply" (and
  "No reply: OpenRouter is out of credits" when the provider refused
  for credit, brain#88). A turn of this conversation that failed with no
  message of his waiting on it (a check-in, a wake) shows as a line in
  the conversation with when and the provider's words, "Add credits"
  when it was refused for credit, "Run it again" (or "Topped up? Run it
  again", brain#89) and Dismiss; the failures are read on
  arrival and every minute, so one that happened while he was away is
  there when he comes back. A message taken and then never heard of again (a
  queue lost to a restart, or a send answered as a duplicate of a claim
  that died with it) is sent again under its ref every half minute once
  it has sat past the server's turn timeout, so the dead claim is taken
  again (STUCK_MS, 330s, over BRAIN_TURN_TIMEOUT_MS). Every queued,
  sending, failed or unsent message also offers Remove, which takes this
  browser's copy off the screen; a message the server still holds may
  yet run, and lands in the transcript if it does.
- **The domain (kumbukumbu#72):** above the box, "In <domain>", a chip
  naming the domain the next message goes in: the conversation's
  current one (the session's `domain`), or the common room. It opens a
  picker of the domains this conversation has named, the common room,
  and a new one as a slug ("Use"); what is picked shows "· next
  message", rides that message's turn (`domain` on the submit, kept
  when it is sent again) and clears once sent, the server carrying it
  forward. A rule, "— <domain> —", is drawn where the transcript moves
  into another domain, the first message of a page too when it is in
  one.
- **Stop** replaces Send while she works and the box is empty.
- **The box** grows with what is written, up to 180px, then scrolls.
  With a keyboard, Enter sends and Shift+Enter breaks the line; on a
  touch screen (`pointer: coarse`) Enter breaks the line and the arrow
  sends, and the keyboard's key says so.
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
  - **Places** (the witness, 2026-11-12): a band or point also opens
    the track out into a panel beside it, and ≡ at the track's top
    opens it with nothing chosen. Her scenes (time span, mood, title,
    summary) and bookmarks (number, pin, time, line, summary) over the
    same two weeks, in time order under each local day, focused on the
    one chosen (else the newest). A place jumps the conversation there.
    A bookmark from a private session shows its number and time only.
    At the top, a day and time (this browser's zone) jumps to the
    message nearest it (kumbukumbu#68). × or Escape closes it. A place
    this conversation does not hold (a bookmark made in another
    session) leaves the reader where they are.
  - Search is the one global search, not a drawer here (decided).

- **On her replies:** "What she was given" lists that turn's context,
  part by part, with its size and why it was there (and its words where
  the server shows them); "Suggest a bookmark" proposes a line and why,
  which she accepts, rewrites or declines in her own words; "Domain:
  <domain>" moves the turn, and every untagged turn after it up to the
  next named one, to another domain or the common room (`POST
  .../turns/:turn_ref/domain`).
- **Mail**, the third view beside Conversation and Sessions: letters,
  outside mail and blocks (`screens/next-mail.md`).

Not built:
- places further back than the two weeks (the day-and-time jump
  reaches any time);
- a day-level zoom on the navigator: on the two-week track, scenes
  minutes apart overlap, and only the top one takes a pointer (the
  keyboard reaches each);
- reading a non-main session's transcript from Sessions;
- message virtualization;
