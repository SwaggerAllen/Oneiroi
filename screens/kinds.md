---
paths:
  - client/src/screens/kinds/**
---

# kinds

Kinds (seshat#51), built: `client/src/screens/kinds/` (`Kinds.tsx`, its
stories and tests), a page of its own opened from More, rendered by
`KindsContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/kinds`.

One card. A line says what a gate is: a document of that kind at
status: review waits on the witness; on at either word, off a proposal
the other answers. A note field above everything, required for a
proposal off and for an answer.

- **Open gate proposals**: each by its number, kind, on or off, who
  proposed it and the note; hers with Agree and Decline, his saying it
  waits for her. Her proposals are also on Waiting on you
  (`kind_gate_proposal`), opening this page.
- **Kinds**: every kind in the server's shelf order, each with its label,
  name, folder, whether it waits on him, and, for one of hers, who
  defined it. A system kind with a gate offers "Gate on" (at once) or
  "Propose gate off"; a kind with an open proposal says so instead.
- **A kind of hers**: a name (its folder; refused here when it is not
  lowercase letters, digits and `-`, or names a system kind), a label,
  whether its citations make edges, and whether a document at review
  waits on him, with what he is asked. Defining a name she already has
  rewrites it. The server's safe subset is the authority.
- **Lately answered**: the last five answered proposals.

Not built: removing a kind of hers, and editing one in place beyond
defining it again.
