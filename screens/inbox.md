---
paths:
  - client/src/screens/inbox/**
---

# inbox

Inbox (spec §10), partly built 2026-11-02: `client/src/screens/inbox/`
(`Inbox.tsx`, `letters.ts`, stories and tests), a bottom-nav
destination loaded by `InboxContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/letters`. The state list lives in the stories
(DESIGN §4); nothing here names a state.

Built: **Needs you** (`NeedsYou.tsx`): each reply the resident drafted,
with Approve to send / Decline and a note (nothing decided without
one); each approved reply waiting to be sent, with I sent it and where
it now is (the receipt, xenia #13). **Correspondence**: every message
that reached the resident, newest first (no reading gate: F23 as
amended, xenia #12); a blocked sender's message as a line with no words;
Block sender asks why, in place. **Blocked**: each block with who set it
and why; Lift only on the ones you set. **The house letters** between
the resident's conversations (kumbukumbu #44), Open and All, newest
first, each with where it stands read off the letters (`letters.ts`).
Not built: threads by person, mail by kind with account mail as a count and a lock, pasting a
message by hand (the route takes it; the screen has no form yet).

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
