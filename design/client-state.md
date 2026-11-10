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

**The repo is never loaded whole.** Scenes and bookmarks are paginated: boot takes the last ~24 hours of each (decided, below). The first load is a boot set,
fetched in parallel (or as one `GET /v1/me/boot` if the round trips
matter on a phone):

| Loaded at boot | Size | Why |
|---|---|---|
| me, subjects (the dropdown) | tiny | the shell |
| bell counts and items | small | the header |
| chat: the open session's last ~50 messages, the unread marker, the last 24 hours of scenes and bookmarks, the navigator's per-day density | 10s of KB | the first screen |
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

## Decided (the witness, 2026-11-10)

- **Industry standards where they exist:** TanStack Query and a small
  store. The same goes for CSS and theming (below).
- **Scenes and bookmarks are paginated lists, never loaded whole.**
  Boot loads the last ~24 hours. The navigator loads windows as it's
  scrubbed. To draw the whole track (bands and points across all time)
  without the rows, it takes a light density summary: counts per day.
- **Switching subjects uses fade-out, load, fade-in.** Each subject has
  its own theme, so that transition carries the most weight and is the
  one that genuinely waits.
- **Fetching: parallel fetches, unless refocus and reconnect turn out
  to need a full reload** (his lean). With the change notices (below),
  a refocus or reconnect is a *targeted* invalidation, not a full
  reload: the client keeps the last event-store position it saw and
  asks for the notices since then. Only past a retention cap does the
  server answer "reset", and that's the one full reload. So parallel
  fetches, measured; a boot endpoint only if the numbers ask for it.
- **GraphQL: not now.** It answers "fetch many shapes in one round
  trip", which parallel fetches over HTTP/2 mostly already do. It
  would add a second API surface beside the REST API that the
  OpenAPI spec, the agent tools and the adapters already share.
  Absinthe's subscriptions would duplicate the Phoenix channels we
  have. Worth revisiting if the client ends up needing many joined
  shapes per screen.

## Live state: what the shell always shows

Mocked on the canvas: `ChatLive`, `ChatOffline`, and the header's
`state` property.

- **What she's doing.** A line under her name in the header, on every
  tab: "IN FREE TIME · 41M", "WRITING A DOCUMENT · 0:14", "THINKING ·
  0:03", "LAST SEEN WRITING · 2M AGO" when offline. Her avatar's glow
  brightens while she works. It comes from the resident channel: a
  presence notice across all her sessions, not just the open chat.
  Free time shows that it's running, never what it says.
- **Generation timer.** The streaming bubble's header shows the current
  step (`TOOL · document_write`) and the elapsed time. A trail under the
  text shows the steps so far (`THOUGHT 0:04 · library_read ✓ ·
  document_write …`). The session channel's `status` events
  (brain#45) already carry queued / thinking / tool-and-name.
- **Stop.** While a turn runs, the send button becomes Stop. The
  composer stays open and queues ("Queue a message for Lily"); typing
  turns it back into Send. Stop needs the connection, so it's disabled
  offline.
- **Connection.** A dot on her avatar: green when connected, amber
  while retrying, red when it's given up. These are the unthemed
  status colours.
- **Offline bar.** "Offline · retrying in 4s", with "showing what you
  had at 09:02" under it, and a **Reconnect** button. The witness asked
  only for a frustration button, but it does real work here: it
  reconnects the socket immediately instead of waiting out the backoff,
  then asks for the notices since the last position. Data on screen
  stays (dimmed where it's a paused stream), and messages typed while
  offline wait as "waiting to send".
- **Jump buttons and the unread rule:** see `theming-notes.md`.

## Styling and the component layer

The theming design wants exactly one thing from the styling system:
**themes are CSS custom properties**. Seeds are derived into tokens in
TypeScript at runtime, then set as variables on the shell's root; a
subject switch swaps the variables during the fade. Any modern approach
can do that, which frees the choice to rest on everything else.

On Emotion: its runtime cost (styles serialized during render) is what
the field moved away from, and it sits awkwardly with React 19's
concurrent rendering. Its own maintainers' position is that new
projects should prefer zero-runtime tools. The successors keep the
co-located, typed styles and compile them to static CSS:

- **vanilla-extract** (recommended). Styles are TypeScript in `.css.ts`
  files, compiled at build, with no runtime. Its
  `createThemeContract` is exactly our seeds → tokens → CSS
  variables shape, and the contract is typed, so a component can't
  reference a token that doesn't exist. `recipes` handles variants.
  It works with Vite and Storybook.
- **Panda CSS**, the runner-up. Also zero-runtime, from the Chakra
  team, with semantic tokens and conditions (light and dark) built in.
  It's closer to Emotion's `css({...})` ergonomics, but more framework
  to buy into.
- Tailwind v4 also does variables-first theming well, but for a
  hand-designed, glow-heavy look like ours, the utility strings get
  long and the design lives in markup rather than in a typed token
  contract.

**The component layer: headless primitives.** We're drawing every
pixel ourselves, so a styled kit (MUI, Chakra) would be fought, not
used. What we need from a library is behaviour and accessibility:
menus, dialogs and sheets, the tabs, focus management, keyboard
handling.

- **React Aria Components** (Adobe), recommended. It has the most
  thorough accessibility and internationalization, it's unstyled, and
  it has good mobile and touch behaviour, which matters for a
  phone-first app.
- **Radix primitives** are the common alternative, also unstyled.

So the proposal: **vanilla-extract + React Aria Components +
TanStack Query + Zustand**, with versions checked when we pin them.
The existing `tokens.json` becomes the source the theme contract is
generated from.
