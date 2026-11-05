---
paths:
  - client/src/screens/more/**
---

# more

More (spec §10), partly built: `client/src/screens/more/` (`More.tsx`,
its stories and tests), the fifth bottom-nav destination, rendered by
`App` in `client/src/app/App.tsx` with no data of its own. The state
list lives in the stories (DESIGN §4); nothing here names a state.

A Notifications card heads the list (`Notifications.tsx`, gaia#15): on
this device, whether notifications can be had and how. An iPhone or iPad
not running from the Home Screen is told to add Oneiroi there first (only
the Home Screen app may ask); a blocked device and a server with no VAPID
key say so; otherwise "Allow notifications" asks the device, subscribes
through the service worker (`client/public/sw.js`, registered on every
load from `app/push.ts`) and sends the endpoint to `POST /v1/me/push`.
When on, "Send a test" pushes to every device of the account's and says
how each went, and "Turn off" unsubscribes. The card says plainly that a
notification says only that she wrote, never what. The manifest is
`client/public/manifest.json`; it names no icon until the logo's
canonical description lands (the witness's logo workshop, 2026-11-05),
so the Home Screen shows a snapshot of the page.

For a super admin, an Operator card follows (`Operator.tsx`, gaia#16):
the front door's state and note, three buttons to set it (closed, invite,
open), the platform roles held with a Revoke each, and a form to grant a
role by account email. Every change needs the note typed first; the
server checks the authority again on each one. It says how a transfer
goes (grant super admin, then revoke your own) and that the last super
admin cannot be revoked. Shown only when `/v1/me` names the caller's
super admin role.

Under it, for the same super admin, an Invites card (`Invites.tsx`,
gaia#18): a form to issue a code (who it is for, required; plan, list
price, discount, days of terms, uses, an optional expiry date, each
starting at the alpha's free code), the new code shown once in large
type with a line saying it is not shown again, and every code issued
with its terms and its standing (uses taken, spent, expired or revoked)
and a Revoke that takes the note above. Redeeming a code from the
client arrives with sign-up; the route exists (`POST /v1/me/invite`).

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
