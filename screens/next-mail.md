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
  - **a piece for review** (seshat#42): your last answer if there was
    one, a link to read it in Records, approve or decline with a note;
    **a piece drafted**: the Substack draft's link (never published
    without you).
  Answering refreshes the bell and the mail. Work, plugin and kind-gate
  entries still link out to where they are decided.
- **Chat → Mail** (`#/chat/mail`, beside Conversation and Sessions):
  - the letters between her conversations (kumbukumbu#44), open first
    or all, each with where it stands (answered, read, waiting on whom),
    the first line with the rest a click away, and a keepsake if one
    rode with it;
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
