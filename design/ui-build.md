# The client rebuild: plan

Status: plan for the witness's go (2026-11-10). It gathers what the
redesign decided:
- `ui-inventory.md`, `ui-parity.md`, `ui-structures.md` (structure D,
  the look, the canvas decisions);
- `theming-notes.md`, `client-state.md`, `scheduling-notes.md`,
  `records-in-repo.md`;
- the canvas (artifact 4haSkJuEEbpei98HwNRorr, private to the witness).

The server work it depends on is in `ui-server-work.md`; each phase
names the items it needs (S1…).

## Stack (accepted)

- vanilla-extract for styles and the theme contract (zero runtime).
- React Aria Components for behaviour and accessibility.
- TanStack Query for server state, and Zustand for device state.
- Phoenix channels on **one** socket.

Versions are pinned when installed, and the npm gate audits them. React
19 and Vite stay. No SSR: the landing page is a static page built from
the same tokens.

## How it replaces the old client

The current client is one 1,579-line `App.tsx` plus 14 screen folders,
calling a 437-line `api/client.ts` of about 134 calls. Rewriting
screens inside it would carry its structure along. Instead:

- The new client grows under `client/src/next/`, served at `/next`, and
  shares the API module, which is typed and kept. The old client keeps
  `/`.
- Each phase merges as it lands, so nothing waits on a big-bang branch,
  and the witness uses `/next` daily as it grows.
- **The switch** happens when every row of `ui-parity.md` is either
  reached in `/next` or deliberately dropped with a reason. `/` then
  serves `next`, and the old tree is deleted in the same PR.
- `screens/*.md` is rewritten screen by screen as each one lands in
  `/next` (CLAUDE.md, "Docs move with the code").

## Rules every phase holds

- **Tokens only:** no hex in a component. The palette is the output of
  `derive(seeds)` (theming-notes), pinned by a test. Token names carry
  roles (`accent-resident`, `accent-witness`), never colours. Status
  colours are a separate, unthemed set.
- **Responsive from the first component.** One breakpoint at 900px.
  Below it: bottom tabs, sheets and one column. Above it: the rail,
  side panels and up to three columns (ChatWide, RecordsWide). Not a
  late pass.
- **Every tab stays mounted.** Each tab has its own stack, kept in the
  URL. Drafts persist, and edit leases survive tab switches.
- **One search:** the header icon, or ⌘K. No screen owns a search bar.
- **One `ScrollArea` everywhere,** with its edge fades as a mask.
- **Motion:** tabs cross-dissolve; pushes slide; a subject switch fades
  out, loads, and fades in. Reduced motion makes all of them instant.
  The two dissolves get compared side by side before choosing.
- **Accessibility:** React Aria for the controls, live regions for her
  new messages and her status, and axe checks in the Storybook test run.
- **Copy:** Lily's pad (`scratch/copy-landing-and-creation.md`) is the
  source for onboarding words, set verbatim. Functional labels follow
  the design system's wording rules.

## Phases

| # | Phase | What it includes | Needs |
|---|---|---|---|
| P0 | **Foundation** (built 2026-11-10: `screens/next-shell.md`) | Token contract and `derive()` with the palette test. App shell: header with subject, search, bell and settings; tab bar, or rail at desktop width. Per-tab stacks in the URL. Query client and store. One socket. Boot splash. Connection dot, offline bar and Reconnect. `ScrollArea`. A global search shell. Storybook on the new tokens. | S1 (falls back to refetch-on-focus until it lands) |
| P1 | **Chat** | Conversation: virtualized, streaming, status line under her name, step trail and timer, Stop, queueing while she works. Unread rule, "↓ n new". Reacts. Citation chips open a peek sheet, or a side panel on desktop that stays open while you chat. Sessions (running, planned, today). The navigator scrubber. | S2 for the navigator; S3 for search scopes |
| P2 | **Records** | The tree: folders as kinds, and the database-backed folders shown as readable copies. Viewer: markdown, citations in and out, reacts. Folder settings: kind descriptor, how things arrive (routes). History and diff. Editor with lease. Ballots in the viewer, once they exist. | S4 (history, diff, leases, document reacts); S10 for ballots |
| P3 | **Time** | Calendar month and day: journal, story, sessions. Rhythm: check-ins, free time and one-offs, rounds, quiet hours, zone. | S5 for month and day ranges; Rhythm uses existing endpoints |
| P4 | **Soul** | The agreement first: agree, amend (a new whole version), decline. Identity files, pins, state lines, plugins, REACTIONS.md, model. The charter, once ballots exist. | Existing endpoints; S10 for the charter |
| P5 | **Bell and Settings** | Waiting on you, and Waiting on Lily. The notifications item that stays until answered. Settings rows (ledger, routes, profiles and keys, connections, notifications, Regression, every kind and tag, export). Feedback sheet. "Report this" on failures. | S6, S9; feedback exists (gaia#20) |
| P6 | **Onboarding** | Landing (static; "Ask for one" mails allen.strut@pm.me). Auth ("Welcome in"). Creation: threshold with the prompt option, nine gifts with Write it with me, Get a read, Example and upload, the reading, the wake. Import with its accounting. The first-day panel in Chat. The push explainer. | S8 for the prompt path, Get a read and examples; the rest exists |
| P7 | **Operator** | A separate shell at its own route, with its own accent: Status, Door, Roles and invites, Triage, Heartbeats, Failures, Restarts. | Existing platform endpoints |
| P8 | **Theme** | Seeds per resident, swapped during the subject fade. Lily's proposal lands in the bell with a preview. Local overrides. | S7 |

P0 → P1 → P2 is the critical path. P3, P4 and P7 use mostly existing
endpoints and can run in parallel with P2. P6 is last among the
user-facing phases because its server half (S8) is the largest new
build. P8 can land at any point after P0, because the token contract
makes theming a data change.

## Verification

- Unit tests (vitest) for `derive()`, the stores, and the query keys
  and invalidation map.
- Storybook stories for every component, with axe in its test run. The
  canvas boards are the reference for each story.
- Playwright end-to-end tests for the flows that cross screens:
  - sign in → chat → stream → stop;
  - citation → peek → open in Records;
  - edit under a lease → another device sees it held;
  - offline → reconnect;
  - the creation flow to waking.
  Playwright runs locally against the dev server; CI keeps the existing
  gate line.
- The client gate line (CLAUDE.md) passes at every merge:
  `npm ci && npm run lint && npm run typecheck && npm test && npm run build-storybook`.
