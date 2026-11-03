---
paths:
  - client/src/screens/more/**
---

# more

More (spec §10), partly built: `client/src/screens/more/` (`More.tsx`,
its stories and tests), the fifth bottom-nav destination, rendered by
`App` in `client/src/app/App.tsx` with no data of its own. The state
list lives in the stories (DESIGN §4); nothing here names a state.

Built: a card per screen that is built and is not one of the four daily
destinations, each with a line saying what it holds and a button that
opens it: Library, Connections, Ledger, Regression, in that order. Each
opens in place of More (the destination is kept in the URL's hash), and
the nav keeps More lit while any of them is open (`BottomNav`). Not
built: the five collapsed groups (Library, Judgement, the resident,
Account, Platform), each header's waiting count from `needs_you`, and
the left rail above 720px; until the groups exist the list is the built
screens alone.

## #1 Shows

Five collapsed groups, Library, Judgement, the resident, Account and Platform, each header carrying its waiting count from `needs_you`; under each, the screens it holds.

## #2 Does

Open a screen.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
