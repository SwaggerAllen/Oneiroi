---
paths:
  - client/src/screens/inbox/**
---

# inbox

Writing (seshat#42), first when there is any: each piece marked for review as a card ("For review: …") with the last decision if it had one, a required note, Approve and Decline; an approved piece saying the reader drafts it next and it is never published without him; a drafted one with "Open the draft on Substack" and a line to press Publish there. (`Pieces.tsx`)

**Waiting on you** (brain#65), first on the screen: the server's `needs_you` list (`GET .../needs_you`), oldest first, one line each (a reply to approve, an approved reply to send, an ask, a piece to review or to publish, a work item blocked before sunna#42, on the words it was blocked on; work blocked on other work is the queue's, never listed here), how long it has waited, and "a long time" past two days; each a link to the card below where it is decided, or the screen it is decided on (Work, for work: sunna#38). The same list is its own page, Waiting on you, under More, whose entries open the thing itself (`screens/more.md`). The card has no button: nothing on it decides, sends or approves, and an old entry is only marked. (`Waiting.tsx`, `queue.ts`)

Asks (agathos-daimon#35), next when there are any: each open ask as a card, an act as "May I: …" with Approve and Decline, a tool as "A tool: …" with Noted and a line saying noting grants nothing; each with why and a required note; the last five answered below, each with its answer and note. (`Asks.tsx`)

Inbox (spec §10), partly built 2026-11-02: `client/src/screens/inbox/`
(`Inbox.tsx`, `letters.ts`, stories and tests), a bottom-nav
destination loaded by `InboxContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/letters`, `.../correspondence`, `.../replies`,
`.../blocks`, `.../letters/addresses`, `.../asks`, `.../pieces` and
`.../needs_you`, read again after every
action. The state list lives in the stories
(DESIGN §4); nothing here names a state.

Built: **Needs you** (`NeedsYou.tsx`): each reply the resident drafted,
with its envelope (platform, the account it goes from, to whom, its
thread) and when it was drafted, Approve to send / Decline and a note
(nothing decided without one); each approved reply waiting to be sent,
with I sent it and where it now is (the receipt, xenia#13); a draft she
replaced is not here (xenia#17). **Correspondence**, by thread
(`threads.ts`): every message that reached the resident (no reading
gate: F23 as amended, xenia#12) grouped by its platform's thread, or by
sender where it has none, with her replies in the thread they went to,
each marked from her and where it stands (a replaced draft left out);
each thread with whom, how many from them and how many from her, the
newest message open and the earlier ones one click away under "Earlier
in this thread"; threads by newest activity. A blocked sender's message
is a line with no words; Block sender asks why, in place. **Blocked**: each block with who set it
and why; Lift only on the ones you set. **The house letters** between
the resident's conversations (kumbukumbu#44), Open and All, newest
first, each with where it stands read off the letters (`letters.ts`),
and **Write a letter**: from you to a conversation by name, to Free time
(the default, the queue's front door) or to the house
(`POST /letters`, `GET /letters/addresses`).
Correspondence, replies and blocks are in the server's order (messages
and replies newest first). Not built: the rest of the
`needs_you` union (spec §5: proposals, releases, flags, predictions,
soul edits, failures), the nav badge, approve-and-wake, threads by
person across platforms, a declined list, mail by kind with
account mail as a count and a lock, pasting a message by hand
(`POST .../correspondence` takes it; the screen has no form yet).

## #1 Shows

Needs you; messages pending with summary first then text; threads by person; declined; mail by kind with account mail as a count and a lock.

## #2 Does

Reject, approve, or approve and wake, each with a note; paste a message; mark a reply sent.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
