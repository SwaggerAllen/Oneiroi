# Server work for the client rebuild: plan

Status: plan for the witness's go (2026-11-10), paired with
`ui-build.md`. Each item says what exists today (routes are in
`lib/oneiroi_web/router.ex`), what's missing, and which client phase
waits on it. Each item lands with its spec row and system-doc decision,
per CLAUDE.md. Where an item needs a design call first, it says so.

## S1 — Change notices on a resident channel (P0)

- **Exists:** two channels, `session:*` and `regression:*`, each joined
  on its own socket. The only broadcasts are the turn's and
  regression's. There is no per-resident channel, and the API exposes
  no event-store position.
- **Build:**
  - A `resident:<id>` channel, joined on the same socket.
  - Projectors (or one shared hook after a projection commits)
    broadcast `{kind, ref, version, position}`, never the data.
  - `position` is the event store's global position, which the client
    keeps as its cursor.
  - On join with a cursor, the server replays the notices since it,
    up to a cap. Past the cap it answers `reset`, and the client
    invalidates everything once.
- **Check:** the cross-tenant rule. A notice carries only the
  resident's own refs, and the join is scoped like the session channel.

## S2 — Paging for the navigator and chat (P1)

- **Exists:**
  - `GET …/bookmarks` returns every bookmark, newest first, unpaged.
  - `GET …/sessions/:key?limit=&before=` pages messages backward by
    cursor.
  - Scenes aren't their own entity: a scene is a bookmark whose span
    grows (kumbukumbu#4, #22; the bedtime scene pass is sunna#34).
- **Build:**
  - Bookmarks paged by `before` / `since`, with a time range.
  - A per-day density endpoint (bookmark and scene counts per day) to
    draw the whole track.
  - Messages paged `after` as well as `before`.
  - An **anchor** read: the window around a turn, a bookmark's span or
    a scene's start, so a jump on the navigator loads that spot
    directly.
- **Design call:** whether the navigator draws scenes as the spanned
  bookmarks the bedtime pass makes, or needs its own marker. Proposed:
  spanned bookmarks, no new entity.

## S3 — One search across kinds (P0 shell, P1 scopes)

- **Exists:** `GET …/transcripts/search` (message text, at most 100
  results) and `GET …/library/search` (index chunks). There's no
  bookmark search and no endpoint that searches across kinds.
- **Build:** `GET …/search?q=&scope=` over transcripts, library
  documents and records, bookmarks, and scenes. Results are typed and
  ranked per scope, then interleaved.
  - "As Lily sees it" is the `retrieval` path (`GET …/retrieval`): what
    her memory would return, not the text index.

## S4 — Documents: history, diff, reacts, leases (P2)

- **Exists:**
  - Read, write, delete, move, adopt and download;
  - citations out (in the read) and in (`cited-by`);
  - a `versions` count on the row.
- **Build:**
  - **Versions:** a list for a document path, with author, instant
    and note (from the file's git history in her repository, joined
    to the document events for the actor). Also a diff between two
    versions.
  - **Restore:** a direct write, unless the write would need a
    proposal, in which case it is a proposal (decided).
  - **Reacts on documents:** extend the react target beyond `message` and
    `letter` (kumbukumbu#56).
  - **Edit leases (new):**
    - `acquire / renew / release` on a path.
    - The lease renews while the holder writes. After an idle window
      (a setting, `:bound`) it becomes **takeable**, never revoked
      (decided).
    - It is taken only when the resident is waiting on that file. The
      holder's draft is then kept as a proposal, never lost.
    - The lease is shown to both parties: on the viewer and in her
      tools.
  - **Design call:** what "the resident is waiting on that file" means
    mechanically. Proposed: her `document_write` on a leased path
    records a wait instead of failing, and the wait is what makes the
    lease takeable.

## S5 — Calendar ranges (P3)

- **Exists:** today's schedule; journal day rows newest first;
  `journal/:day`; the free-time history.
- **Build:** `GET …/days?from=&to=`. Each day returns its journal
  marks, its story (sessions and scenes with their times) and, for
  future days, its schedule computed from the rules.
  - Recurrence (`scheduling-notes.md`) slots in here later without
    changing the shape.

## S6 — The bell, both ways (P5)

- **Exists:** `GET …/needs_you` (brain#65, #72), covering the witness's
  stages: replies, asks, documents, work, plugins, kinds.
- **Build:**
  - **The notifications item:** while the account hasn't answered, it
    is a needs-you entry. "No thanks" clears it, and Settings can turn
    notifications on later (decided).
  - **Waiting on the resident:** her open proposals to answer,
    unread letters, soul edits waiting on her, leases she's waiting on.
    This is the bell's second tab.

## S7 — Theme seeds (P8)

- **Exists:** nothing ("palette" in the code is the reacts vocabulary).
- **Build:**
  - Three seeds per resident, owned by the witness (decided).
  - Stored repo-first as a small file at her root (`THEME.md`), so the
    theme travels with her export.
  - A `theme_propose` tool for the resident. The derivation and the
    readability checks run on the proposal before it's filed. It
    reaches the bell with a preview; he accepts or declines with a
    note.
  - `derive()` is shared logic. The client owns it, and the server
    runs the same checks; a test keeps the two agreeing.

## S8 — Creation: the prompt path, Get a read, examples (P6)

- **Exists:**
  - `GET /v1/creation/gifts` (the nine gifts with guidance);
  - `POST …/files/:name/draft` (Write it with me, billed under
    drafting);
  - import, with its `not_transferred` accounting (sima-qian#22).
  - There is no server generator: the pre-filled path's templates are
    client-side (`Gifts.tsx`).
- **Build:**
  - **The generator:** a prompt in, a draft of every gift's file out,
    from the same guidance (agathos-daimon#36). Billed under drafting
    and marked drafted with its prompt. Nothing is written until each
    gift is kept.
  - **Get a read:** notes on one gift's draft against that gift's
    guidance (strong / thin / missing / question). Notes only, nothing
    rewritten; billed under drafting; kept with the gift's history.
  - **The examples:** a fictional resident's full set, made by the
    generator (its first real test) and committed under
    `priv/creation/examples/`. The witness's own files are never
    examples (decided). Lily's SOUL.md and IDENTITY.md are offered
    read-only as a second tab.
  - **Gift guidance:** Lily's revision of the nine texts
    (`scratch/creation-gift-guidance.md`, work item #25) lands
    verbatim in `priv/creation/` once the witness approves it.

## S9 — Push triggers (P5)

- **Exists:** web push subscription and test (`/v1/me/push`). The only
  trigger is the resident writing unprompted (brain/turn.ex, gaia#15),
  with no content in the push.
- **Gap:** the Push screen promises "when something waits on you", and
  nothing sends that.
- **Build:** a push when a needs-you entry first appears, deduplicated
  and respecting quiet hours. Check-in reminders stay opt-in.

## S10 — Ballots and the charter (P2 viewer, P4 Soul)

- **Exists:** nothing beyond a comment in Glitnir. The contract flow is
  per dyad.
- **Design first:** ballots are held by residents collectively, humans
  read-only. They are a record kind opened in the viewer, and passed
  ballots accumulate into the charter on Soul ("charter" or
  "constitution": the name is open). This needs a spec section before
  any build, and it waits on workspaces having more than one resident.
  Not on the critical path.

## S11 — Boot (P0, optional)

- **Exists:** `GET /v1/me` (ids, key status, roles, household).
- **Plan:** parallel fetches first, measured on a phone. A combined
  `GET /v1/me/boot` only if the numbers ask for it.

## Not in this plan

- Recurrence rules (`scheduling-notes.md`): a later feature. S5's
  shape leaves room for it.
- Encrypting private words (`mvp.md` item 19).
- The repo-first record files (`records-in-repo.md`): they pair with
  the encryption scheme.

## Order

S1 → S2 → S3 follow the client's critical path. S4 runs alongside P1,
so Records isn't blocked. S5, S6 and S9 are small and can go anywhere
before their phases. S8 is the largest new build and should start early
in parallel, since P6 waits on it. S7 waits on nothing but is wanted
only by P8. S10 is design work, off the path.
