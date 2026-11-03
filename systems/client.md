---
paths:
  - client/**
  - storybook/**
---

# client

The React application and its Storybook. Spec §6.15. Vite, React 19,
Storybook 10 and the design system's tokens (P0.3), then the shell and
its screens from P0.4 on. This doc is its file map, the standing
decisions the spec records, and what is built against them.

## #1 Owns

`client/**`: the shell (`src/app/App.tsx`, `Login.tsx`, the channel
client `socket.ts`), the JSON client and its types (`src/api/client.ts`,
`src/api/types.ts`), the components under `src/components/` (`ActorChip`,
`BookmarkCard`, `BottomNav`, `BudgetLine`, `Button`, `Card`,
`ConnectionDot`, `EmptyState`, `ErrorNotice`, `Field`, `RefusalBlock`,
`Tabs`, `TagChip`, `TimeField`, `TopBar`), the tokens (`src/tokens.json`,
`src/theme.css` generated from it by `scripts-tokens-to-css.mjs`, the
`Swatch` story), and the screens under `src/screens/`: chat (Chat,
Conversations, the outbox and paging), memory, schedule, inbox (with
Needs you), more, library, connections, ledger and regression. Storybook's
config is `client/.storybook/`; the stories sit beside what they render
(eleven files). `vite build` writes `priv/static/client/`. `storybook/**`
holds nothing; the stories are under `client/`.

## #2 Standing decisions

Carried from spec §6.15; the reason for each is there.

- **#3 Mobile-first, built only against the OpenAPI client and the typed channel client.** Mobile-first holds. The JSON client is not generated: `src/api/types.ts` is written by hand against OneiroiWeb's routes, because the document at `/v1/openapi.json` types its bodies as bare objects and arrays, so a generated client would type everything `unknown`; the hand-written types are what a generated client replaces once the document carries schemas.
- **#4 One Storybook story per state per screen, which is what the design agent produces and the manual test gate drives.** Every built screen has a stories file except Inbox's Needs you, which Inbox's stories render.
- **#5 Built from the Oneiroi design system: `tokens.json` unchanged, the twenty components under `client/src/components/` as the only source for those patterns, with the five rules they enforce (attribute everything; the resident's words are never editable by the witness; every approval carries a note; refusal renders in the resident's words; the check-engine light reports the engine).** Twelve of the twenty are built (`Button`, `ActorChip`, `TagChip`, `RefusalBlock`, `BudgetLine`, `BookmarkCard`, `Field`, `Tabs`, `Card`, `EmptyState`, `TopBar`, `BottomNav`); `Citation`, `ApprovalBar`, `StatusLight`, `EventRow`, `DiffView`, `Toggle`, `ListRow` and `Icon` are not. Three are the client's own: `ConnectionDot`, `ErrorNotice` and `TimeField`. The tokens become `src/theme.css`, not `tokens.css`.
- **#8 Chat is home and the nav holds five.** `BottomNav` shows Chat, Memory, Schedule, Inbox and More (spec §10); More opens Library, Connections, Ledger and Regression and stays lit while one of them is open. The destination is the URL's hash. The first resident the account witnesses is the one shown.
- **#9 A message is never lost on the wire.** The outbox (`screens/chat/outbox.ts`, brain #45) holds every message under the client's own ref until its turn lands; one never acknowledged is sent again under the same ref, which the server answers as a duplicate. Chat's top bar carries `ConnectionDot`: connected, connecting or offline, its meaning in words for a screen reader and on hover.
- **#10 Memory opens on Every turn.** Its tabs are Every turn (what the server says is in front of every turn, with the server's own description as a caption), All, Pinned, Use when a retrieval is shown, and one per tag in use.
- **#11 The Library's shelf is the server's.** One tab per kind across the top, in the order and under the names the server's shelf gives (seshat #35); a kind the shelf does not name comes last under its own name. A find field narrows the tab by title and path as you type, and a search asks the server for passages, nearest first.
- **#12 Schedule's times are the resident's zone, and a time is chosen from selects.** A Time zone card names the zone every time on the screen is read in, offers the device's zone when it differs, and sets it (`PUT /v1/residents/:id/timezone`). (2026-11-03: the resident's zone was never set, so free time set for 14:30 and 22:30 ran at 6:30 and 14:30 Pacific.) `TimeField` picks hour and five-minute step from two selects rather than `<input type="time">`, which on iPhone Safari shows a time while its value is empty.
- **#13 Coming back to the page reads it again.** (The witness, 2026-11-03: "I hop around a lot and I think I'm missing updates.") `app/refocus.ts`'s `useRefocus` calls a screen back when the page is shown again (`visibilitychange`), its window focused, the network back (`online`), or the page restored from the back-forward cache (`pageshow` persisted), once per return, with how long it was away. The chat reads the open conversation and the list again, and joins its stream again with a fresh socket token when it was not connected or the page was away more than thirty seconds: the token lasts five minutes and the socket's own retries reuse it, so a phone that slept left the stream refused until a reload. Memory, Inbox, Connections, Schedule and Ledger read themselves again. Library and Regression do not, so a search or an open run is not reset under the reader.

## #6 Initial vs target

Initial: the skeleton (P0.3), then the shell with Chat, Memory and Ledger
(2026-10-29), Regression (2026-11-01), and Schedule, Inbox, More, Library
and Connections (2026-11-02). Target: the whole of spec §6.15 and the
screens of spec §10, in P1 (spec §14).

## #7 Depends on

The platform's JSON surface and channels, and whatever spec §14's row for
its phase names.
