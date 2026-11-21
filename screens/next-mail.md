---
paths:
  - client/src/next/inbox/**
---

# next-mail

The old client's Inbox, rebuilt in two places (`design/ui-build.md`,
the switch to the new client). Built 2026-11-10.

- **The bell answers in place.** An entry that waits on a decision
  opens where it stands instead of sending you to the old client:
  - **an ask** (agathos-daimon#35): what she asks and why; an act is
    approved or declined, a tool is noted (which grants nothing); a note
    is needed, and the answer reaches her free time as a letter;
  - **a reply she drafted** (xenia#13): to whom, on what, answering
    which message, the words in full; approve to send or decline, with a
    note she reads first;
  - **a reply approved and waiting to be sent**: "I sent it", with where
    it is now if you have a link;
  - **a plugin slot change she proposed** (brain#68; the witness,
    2026-11-18, finding no way to accept one from the bell): "<her>
    proposes: <change> <slot>", her reason, and **Agree** or **Decline**
    with a note she reads first, as on the Plugins page;
  - **a piece for review** (seshat#42): your last answer if there was
    one, a link to read it in Records, approve or decline with a note;
    **a piece drafted**: the Substack draft's link (never published
    without you).
  Answering refreshes the bell and the mail. Work, plugin and kind-gate
  entries still link out to where they are decided.
- **Chat → Mail** (`#/chat/mail`, beside Conversation and Sessions):
  - the letters between her conversations (kumbukumbu#44), grouped as
    threads (the witness, 2026-11-19: as a shared-workspace thread), open
    threads first or all: each thread a card, its first line and how many
    letters, with whom, and when the last came, opening to every letter
    oldest first; each letter says plainly who it is from (kumbukumbu#76:
    her own conversation, her witness, a housemate, the house or the
    platform), her own marked "Hers" and in her colour (the colour her replies wear in correspondence; never on others' letters), and the thread's newest says where it
    stands (answered, read, waiting on whom); a keepsake if one rode with it;
    a letter between her and a housemate is sealed to the two of them
    (kumbukumbu#93): its card reads "A sealed letter", each sealed letter
    "Sealed between them: you see that it was sent, never its words", and
    its state "sealed between them", never read or unread; one sent open
    reads whole;
  - **Write a letter** to one of her conversations by name, to Free
    time (her next free time reads it first), or to the house;
  - the mail from outside the house (xenia#12), by thread, newest first,
    her replies in their threads with where each stands and its link;
    a message unread or read, an unverified sender said so; **Block
    sender** asks why, in place; a blocked sender's message is a line
    with no words;
  - who is blocked, by whom and why; a block you set can be lifted, with
    a note; one she set is hers to lift.
- Settings' "Correspondence" row now opens Mail; the bell's letter
  entries ("your letter, unread") open it too.

Every action of the old Inbox and Correspondence screens is here:
letters, sendLetter, letterAddresses, correspondence, replies,
decideReply, markSent, block, unblock, asks, answerAsk, pieces,
reviewPiece, needsYou.

Checked in a browser on the local server: an ask approved in the bell,
a drafted reply approved and then marked sent (the bell emptied as each
was answered), the outside thread with her reply in it, and a letter
written to Free time.

Not built:
- marking a thread read from here (the resident marks her mail read);
- a count of unread outside mail on the Chat switch.
