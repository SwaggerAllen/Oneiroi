# Client state and loading: for discussion

Status: a proposal for the rebuild, for the witness to argue with
(2026-11-10). It follows the witness's premises:
- no SSR, except perhaps a static landing page;
- route-based lazy loading buys little, because every tab stays
  mounted;
- one loading state for the first load;
- then work out what else loads, and where.

## Where it stands today

- React 19 and `phoenix`, nothing else. Each screen holds its data in
  `useState` and fetches its own (`client/src/app/App.tsx`, 1,579 lines).
- `onRefocus` (client#13) re-reads a screen when the page comes back,
  because nothing tells the client what changed.
- Two channels (`session:*`, `regression:*`), and each join opens its
  own socket.
- The built bundle is about 372 KB of JS and CSS. Size isn't the
  problem; freshness and duplication are.

## The split

**Server state** is anything the server holds: records, messages,
schedule, the soul, counts. It lives in a query cache keyed by resource
(`['document', path]`, `['messages', session, page]`, `['day', '2026-11-09']`).
TanStack Query is the obvious tool: it's small, it does caching,
deduplication, background refresh and optimistic updates, and it means
we write none of that by hand.

**Client state** is what only this device knows:
- each tab's navigation stack (also in the URL);
- drafts;
- scroll positions;
- the reader's place;
- held edit leases;
- local theme overrides.

That's a small store (Zustand, or a reducer in context; it's tiny
either way). Drafts persist to localStorage, and the stacks live in
the URL so reload and back work.

**Freshness: the event log does the work.** The backend is
event-sourced, so it already knows exactly what changed. Add one
`resident:<id>` channel that pushes a change notice per projection
update: `{kind, ref, version}`, never the data itself. The client
marks the matching queries stale, and mounted screens refetch only
what changed. This replaces `onRefocus`'s re-read of everything.
After a reconnect, the client asks for the notices since the last
version it saw, or simply invalidates everything once.

One socket, with channels multiplexed on it: `resident:`, the current
`session:`, and `regression:` for the operator.

## What loads at start, and what doesn't

**The repo is never loaded whole.** The first load is a boot set,
fetched in parallel (or as one `GET /v1/me/boot` if the round trips
matter on a phone):

| Loaded at boot | Size | Why |
|---|---|---|
| me, subjects (the dropdown) | tiny | the shell |
| bell counts and items | small | the header |
| chat: the open session's last ~50 messages, the unread marker, the scenes and bookmarks for the navigator's visible range | 10s of KB | the first screen |
| today and the next few days of the schedule | small | Time opens on today |
| the records tree: folders, names, counts, no bodies | small, grows with her | Records opens instantly |
| Soul: the contract, identity files, pins, state lines, plugin list | ~30–60 KB | Soul is all small text that rides every turn anyway |

**Order:**
1. The splash covers me, the subject and the chat window. Chat
   paints.
2. The other tabs' boot data is fetched while the browser is idle,
   so they're ready before anyone taps them.

**Loaded on demand and cached:**
- document bodies, history, diffs and citations-in;
- older chat pages;
- past days and months;
- search results;
- Sessions' history.

## Where loading states are needed

1. **First load.** A splash (the ground colour, her initial with its
   glow), until chat can paint.
2. **Switching subjects.** This is effectively a second boot. It's
   the one navigation that genuinely waits, and the natural home for
   the fade-to-ground pause.
3. **Opening a document or a peek.** A skeleton in the viewer or
   sheet. Citations in the messages on screen can be prefetched, so
   most peeks open warm.
4. **Chat scroll-back.** A small indicator at the top while the
   previous page arrives. Jumping to a bookmark or scene far back
   loads that window directly rather than paging through.
5. **Search.** Results show "searching…" in place.
6. **Past days and months.** Cheap, but they still need a placeholder
   for the first visit.
7. **Offline or reconnecting.** A thin bar, as the socket already
   reports. Stale data stays on screen instead of being blanked.

Tab switches and pushes within a tab that has already loaded never show
a loading state.

## Code splitting, by weight instead of by route

Split the heavy, rarely used parts into dynamic imports:
- the markdown editor and diff viewer (loaded on first Edit or
  History);
- the operator shell;
- the regression screens.

The markdown renderer is needed on every Lily message, so it stays in
the main bundle.

## Writes

- **Optimistic:** sending a message, reacts, pins, marking read.
- **Pessimistic:** anything with a server decision in it (proposals,
  approvals, edits under a lease). The button shows its state until
  the server answers.

## Memory, with everything mounted

- The chat list is virtualized: only what's near the viewport is in
  the DOM.
- Hidden tabs keep their state but pause their timers.
- The cache drops unused document bodies after a few minutes.

## Server work this implies

- The `resident:<id>` change-notice channel, fed from the projectors.
- A boot endpoint, optional; parallel fetches may do.
- Message pages fetched by anchor (a turn, a bookmark, a scene start)
  as well as by page number, for the navigator's jumps.

## Questions for the witness

- TanStack Query and Zustand as the two dependencies, or hand-rolled?
  I'd take the dependencies; the npm gate already audits them.
- Is a combined boot endpoint worth it, or parallel fetches first and
  measure?
- How much of the navigator's history loads at boot? All scenes and
  bookmarks are small rows, so loading them all may be simplest until
  it isn't.
