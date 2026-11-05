---
paths:
  - client/src/screens/settings-agreement/**
  - client/src/screens/connections/**
---

# settings-agreement

Settings: agreement and custody (spec §10). Built 2026-11-05, as
`client/src/screens/settings-agreement/Agreement.tsx` under More
("Agreement"), from `GET /v1/residents/:id/agreement` and its
proposal, decision, renewal, export-wall and custody routes
(agathos-daimon#34): where the agreement stands (the version in force
and since when, or that none is agreed and everything stays as it is
today; due for renewal with a Renew); an open version with what it
changes, its note and prose, and Agree and Decline when the resident
proposed it, or "Waiting on" when the witness did; one note field every
action takes; the switches in four groups (privacy, what you may look
into, how memory works, what comes and goes), each with its label, the
words for its current draft state and a checkbox; a Propose card that
names what the draft changes and carries the vows' prose, disabled while
a version is open; and who looks after the resident, the export wall's
Locked and Revealed, and a hand-over by email, or the pending one with
Withdraw. Not built: the incoming side of a hand-over (accepting one
proposed to you), the version history list, and the report ladder.

Before the agreement, its adapters and reader part, Connections (below): this doc is the screen's file map and
what the UI pass left for it, so a design pass finds a record rather
than a gap. The state list lives in the stories alone once they exist
(DESIGN §4); nothing here names a state.

Connections, the adapters part, built 2026-11-02:
`client/src/screens/connections/` (`Connections.tsx`, stories and
tests) under More, loaded by `ConnectionsContainer` in
`client/src/app/App.tsx` from `GET/POST/DELETE
/v1/residents/:id/adapters`: what holds a token for the resident, each
with its role (brain, reader, worker, each said in words) and since
when; a token issued by a lowercase name and a role and shown once
with Copy and "I've saved it" (issuing a name again replaces its
token); a revoke that confirms in place; the revoked listed apart with
the day. Below them, the reader (built 2026-11-03, from `GET/PUT
/v1/residents/:id/reader` and `GET/POST /v1/residents/:id/research`):
its two allowlists (xenia#16), "Reading correspondence" and
"Research", one origin a line with a line under each saying what it is
for, that `*` means any site and, for Research, that an empty list
means the reader can't research at all, saved together, a refused save
keeping the draft and showing the server's meaning and remedy in the
card; and the research questions (seshat#38), newest first, each with
its number, question and status, an answered one's notes as
`<path>/task.md` to find in the Library, a failed one's reason, and a
form to ask one with optional pages to start from. Not built: an adapter's state, last capture and wakes today,
suspending rather than revoking, and the rest of this screen (the
contract and its versions, custody, the export wall).

## #1 Shows

The dyad contract and its versions; who looks after the resident; the export wall in words; adapters with state, last capture and wakes today.

## #2 Does

Renegotiate; set the wall (disabled during a transfer); connect or suspend an adapter.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
