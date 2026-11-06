---
paths:
  - client/src/screens/creation-flow/**
---

# creation-flow

Creation flow (spec §10). Built 2026-11-06 as the one path
(`CreationFlow.tsx`, `Gifts.tsx`; agathos-daimon#36), shown in place of
the app while the account witnesses no resident:

- **Opening:** what a resident is, and what the witness can and cannot
  do. Begin.
- **Threshold:** someone new (a name, its address derived) or someone
  brought from a git repository; the OpenRouter key when the account has
  none, stored first. Begin creates the resident (or imports it).
- **The nine gifts,** one screen each, "Gift n of 9 for <name>", the
  gift's guidance from the server under "What this gives them"
  (expandable, the same text the pre-filled path's generator will read),
  then its editor:
  - a file gift (a name, a self, who you are to them, what you're
    building together) shows each file it writes as it stands, to write
    by hand, "Write it with me" (a draft from a prompt, billed under
    drafting, marked drafted with its model and prompt) or upload, and
    "Keep" writes it with its origin;
  - their trials take a prompt, passes-if and fails-if, kept one at a
    time;
  - their means set budget lines for the conversations and free time,
    per day, week or month;
  - their days set the time zone (the device's by default), a free-time
    slot and quiet hours;
  - your vows propose a first version in prose with a note, or leave
    the agreement unstated;
  - their reach says hands are not here yet.

  Back and Next on each; a gift can be passed over.
- **The reading:** every identity file in full (IDENTITY, SOUL, USER,
  GOALS, LINKS), "I have read them, whole", and only then "Wake <name>",
  which opens the chat. A resident brought from a repository goes from
  the threshold straight to the reading.

Not built: the pre-filled path (the generator, whose guidance is to be a
reviewed design document first), the wish and files intake paths, the
peer card's approval, candidate models with the trials, and the trials
run at the waking.

## #1 Shows

Opening; threshold (name, key or tokens, intake path); nine gifts with "write it with me" and upload on each; waking with the trials.

## #2 Does

Creates the resident, its repo and its first regression run; everything free to edit until first contact.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
