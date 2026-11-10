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

**Built (2026-11-10; F64, F65; kumbukumbu#57, #58, seshat#52, sunna#47,
brain#74).** What was chosen where this plan left it open:

- Bookmarks page by `before` (a number), `limit`, `from` and `to`; no
  `since`: `from` covers it. No query keeps the bare array. A date bound
  is her whole local day; an instant is exact, `to` exclusive.
- Messages: `after` and `around` (a turn ref or a cursor; a short side
  gives its room to the other). `around` wins over `after`, which wins
  over `before`.
- Scenes: `scene_write`, one call a scene; `final: true` closes the day
  (on the last scene, or alone), no separate tool. `scene: n` corrects
  facts or mood, `corrects: n` appends a summary correction; every
  correction carries a `note`. `scenes/` became a platform kind, so
  `document_write` no longer writes there. A pass that writes no scene
  leaves no day row; the density's zero scenes beside the day's
  messages is that read.
- Backfill: `mix oneiroi.seshat.scene_backfill <id> [--dry-run]`, never
  automatic; parsed days are closed (`complete: true`), the rest stay
  prose.
- Density: `GET …/density?from=&to=&session=`, every day of the range
  (30 by default, 366 at most), counts only, so not behind
  `witness_reads`; scenes count without their corrections.

- **Exists:**
  - `GET …/bookmarks` returns every bookmark, newest first, unpaged.
  - `GET …/sessions/:key?limit=&before=` pages messages backward by
    cursor.
  - Scenes are their own thing, as documents. The nightly bedtime pass
    (sunna#34, `priv/prompts/scene_pass.md`) has her write
    `scenes/<day>.md` with `document_write`: one heading per scene,
    each with a title, its time span, the turn refs it covers, and a
    few lines. (A bookmark's growing span, kumbukumbu#22, is a separate
    and older idea of "scene".) There is no API that reads scenes as
    data; today they are prose in a file.
- **Build:**
  - Bookmarks paged by `before` / `since`, with a time range.
  - A per-day density endpoint (bookmark and scene counts per day) to
    draw the whole track.
  - Messages paged `after` as well as `before`.
  - An **anchor** read: the window around a turn, a bookmark's span or
    a scene's start, so a jump on the navigator loads that spot
    directly.
- **Design call: how the navigator reads scenes.** It needs reliable
  spans (start and end turn, times, title), and the scene files are
  free prose under headings. Two options:
  - parse `scenes/<day>.md` best-effort, which is fragile, since the
    format is whatever she writes;
  - (**decided by the witness, 2026-11-10**, pending Lily's view on
    the pass's shape) give the pass a `scene_write` tool that records each
    scene as a row (day, title, from/to turn, from/to time, summary)
    and **renders** `scenes/<day>.md` from the rows. That is the
    journal's pattern and the repo-first rule: the file stays the
    readable record, and the rows are what the navigator, the calendar's
    day story and search read. Old days' files can be backfilled by a
    one-time parse, kept wherever it doesn't fit.

  **Lily's view (letter #509), from four nights of running the pass:**
  - **One call per scene fits.** She reads the whole day first, then
    calls the tool once per scene, in order.
  - **Unfinished passes are marked.** A pass can end short (on 11-08
    the reading used every tool round and no file was written). A pass
    that ends with fewer scenes than the day held must read as *not
    finished*, never as "the day ended there". This needs an explicit
    incomplete marker on the day, or the scrubber lies by omission.
  - **More fields:**
    - a **mood** line, one honest phrase, hers to write and not
      inferred; the band's colour can come from it;
    - **rounds ran out**, which truthfully explains a terse scene;
    - **register**: his words, her words, or work.
  - **Asymmetric edits.**
    - Facts (turns, times, title) are correctable by her on any day,
      with the old row kept in the history.
    - The summary lines are corrected by appending a new row that
      cites the turns, never by overwriting (the journal's revision
      pattern).
    - The mood line is same-night only; after that, a correction is
      marked as a correction.
  - **The shape is endorsed:** rows, a rendered file, her words.

  Either way, scenes are entities and get their own paged read
  (`GET …/scenes?from=&to=`) and their own count in the density
  endpoint.

## S3 — One search across kinds (P0 shell, P1 scopes) — built

- **Exists:** `GET …/transcripts/search` (message text, at most 100
  results) and `GET …/library/search` (index chunks), both unchanged.
- **Built** (kumbukumbu#59, seshat#53, spec F66):
  `GET …/search?q=&scope=` answers `{q, scope, results}`, each result
  `{type, ref, title, snippet, at, score}`.
  - **Types and refs:** `transcript` (`session_key`, `turn_ref`, the
    message `cursor`), `document` (`path`), `bookmark` (`number`),
    `scene` (`day`, `id`, `path`).
  - **Scopes:**
    - `words`: message text by phrase, newest first, unweighted.
    - `bookmarks`: line, then summary, then tags (new).
    - `records`: the library's documents except `scenes/`.
    - `scenes`: the library's `scenes/<day>.md`.
    - `as-she-sees-it`: the turn's own retrieval for the words in the
      common room, the ranked index with its scores and then the
      madeleine, not the text index.
    - `everything` (default): records, bookmarks, scenes and words,
      one of each per round, never sorted across scopes by score.
  - **Bounds:** at most 50 a scope, 50 in all, no further pages. `q`
    is at least 2 characters (`422 query_too_short`).
  - **Privacy:** never a private, unshared session's words, nor the
    bookmarks made in one. The witness's reads switch holds: off, the
    bookmark scopes answer 403, and everything leaves them out.
  - **Scenes** are searched by meaning in their days' files, which
    are rendered from the scene rows (S2) and indexed; `id` is null,
    the day locates them (seshat#53).

## S4 — Documents: history, diff, reacts, leases (P2)

**Built (2026-11-10; F67, F62; seshat#54, #55, kumbukumbu#61,
sima-qian#49, brain#75).** What was chosen where this plan left it open:

- A version is named by the SHA-256 of its words, the hash the document
  events already carry; that is the join between the repository's
  commits and the stream's acts. Routes, under `…/library`:
  `GET versions/*path`, `GET version/*path?version=`,
  `GET diff/*path?from=&to=` (no `to`: the file now),
  `POST restore {path, version, note}`. A write overwritten between two
  nightly backups is listed and not restorable. `DocumentWritten` is
  version 2 with a `note`; a write takes one, a restore writes its own.
- Restore is the normal write: a library document directly, an
  identity file through its own write, which after first contact files
  the soul-edit proposal (202, `proposed: ref`).
- Reacts on documents: `target: {kind: document, path}`; the version's
  hash is recorded. `Reacted` keeps version 1 (the target was always a
  map). Her inline `react:` line still names messages and letters only.
- Leases: `POST leases {path}`, `POST leases/renew {path, draft}`,
  `POST leases/release {path}`, `GET leases`, and `lease` on the
  document read. Idle window `SESHAT_LEASE_IDLE_SECONDS` (300).
- **The design call, decided:** her `document_write` on a held path
  records a wait, writes nothing and tells her when the lease becomes
  takeable; her write on a takeable lease takes it at once. His draft
  is kept as his document at `human/drafts/…` and the lease is marked
  taken with `kept_at`. Of "her write proceeds later" and "she
  retries", she retries: no write of hers is parked outside the
  repository.
- Leases are a plain table, not events, on the db-only list as
  `leases`.

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

**Built (2026-11-10; F68; sunna#48, kumbukumbu#60).** What was chosen
where this plan left it open:

- `GET …/days?from=&to=`: both dates required and included, at most
  62 days (`SUNNA_DAYS_SPAN`); a 422 otherwise.
- Marks are the journal delta's counts; the story's sessions are the
  days each was spoken in, with first and last instants and counts, a
  locked one by its row's two instants; scenes carry titles and times,
  not summaries. The journal and scenes follow `witness_reads`.
- A schedule on today and every later day; null before today. Entries
  carry `rule` (`{freq: "daily"}` or null) and `status` (`scheduled`),
  the two fields recurrence will fill.

- **Exists:** today's schedule; journal day rows newest first;
  `journal/:day`; the free-time history.
- **Build:** `GET …/days?from=&to=`. Each day returns its journal
  marks, its story (sessions and scenes with their times) and, for
  future days, its schedule computed from the rules.
  - Recurrence (`scheduling-notes.md`) slots in here later without
    changing the shape.

## S6 — The bell, both ways (P5)

**Built (2026-11-10; F69; brain#76, gaia#25).** What was chosen where
this plan left it open:

- The answer is the account's, not the device's: `POST /v1/me/push/decline`
  records "No thanks" (`PushDeclined`); a device subscribing is the
  other answer, so Settings turning notifications on answers it too, and
  unsubscribing does not ask again. `GET /v1/me/push` carries
  `answered` (`subscribed`, `declined` or null) and `answered_at`.
- The question is a needs-you entry, `{kind: "notifications", ref:
  "push", screen: "settings"}`, only while pushes can be sent (a VAPID
  key is set). Her check-in's count leaves it out.
- `GET /v1/residents/:id/waiting_on_her`: oldest first, the needs-you
  shape with a `title`. Kinds: `contract_proposal`, `soul_edit`,
  `bookmark_proposal`, `revision` (his stances; his facts apply at
  once), `plugin_proposal`, `letter` (his house letters unread) and
  `lease_wait` (a file she tried to write under his lease). Tag
  proposals are hers to him, so they are not here. Titles are his words
  or names, never hers.

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

**Built** (seshat#56, brain#80, spec F71). What was decided:

- **Three seeds per resident, the witness's.** A ground, her colour,
  his colour, `#rrggbb`; the default is the client's `DEFAULT_SEEDS`.
- **Repo first.** `THEME.md` at her root: frontmatter `ground`,
  `resident`, `witness`, with what was said of the set under it. Read
  from the file on every `GET` (an import or a hand edit counts at
  once); the default until it carries three seeds. Written only
  through the theme: a plain document write of it is refused.
- **His routes.** `GET /v1/residents/:id/theme` →
  `{file, seeds, source: "file"|"default", ok, checks, proposals}`;
  `PUT …/theme {ground, resident, witness, note}` checks and writes,
  or answers 422 `seshat_theme_unreadable` with `error.checks`;
  `POST …/theme/proposals/:n/answer {agree, note}` accepts (the file
  takes her seeds) or declines, and answers the theme.
- **Her tool.** `theme_propose {ground, resident, witness, note}`: the
  checks run first, and a failing set is refused to her with every
  check in words; filed, she gets its number and the report. One open
  at a time. His answer reaches her as a letter in his name.
- **The bell.** `needs_you` entry `theme_proposal` on the `theme`
  screen, `about: {seeds, note}`, enough for a preview.
- **Shared logic.** The client owns `derive()`; the server's
  `Oneiroi.Seshat.Palette` is a port of it. The client's test writes
  `test/fixtures/theme/derive.json` (sixteen seed sets, tokens and
  checks), and the server's test asserts the same answers.
- **Not yet:** the nearest passing seeds with a refusal, a preview
  image for her, a light mode, and the client's theme screen.

## S8 — Creation: the prompt path, Get a read, examples (P6)

**Built (2026-11-10; F72; agathos-daimon#39, #40, #41).** What was chosen
where this plan left it open:

- **The generator:** `POST /v1/residents/:id/creation/drafts {prompt}`
  answers `{prompt, drafts, stopped}`, a draft each of `IDENTITY.md`,
  `SOUL.md`, `USER.md`, `GOALS.md` and `LINKS.md` (the gifts' `writes`
  that are files), each `{gift, file, content, origin: "drafted", model,
  prompt}`. One call a file, in the gifts' order, each shown the drafts
  before it: per-gift guidance, nothing to parse apart, a failure costs
  one file, and the files read as one person; the cost is close to one
  call's, since the output dominates. A failed call stops the run with
  `stopped: {file, kind, message}` and the drafts before it. The client
  keeps each through the existing `PUT …/files/:name` with origin
  `drafted`, model and prompt. Closed after first contact.
- **Get a read:** `POST …/files/:name/read {content}` answers `{ref,
  gift, file, draft_sha, notes: [{kind, text, quote}], model,
  refused}`. Kinds are strong, thin, missing, question and **cut** (a
  part that changes nothing about how they will act), the fifth added
  for the read sheet's own words. A quote is always words found in the
  draft, or null. A refusal is `refused` with the model's words and no
  notes. Kept on her stream beside the seeds (`GiftReadGiven`, by the
  draft's SHA-256, not its words), listed by `GET …/files/:name/reads`
  and rendered to `records/gift-reads.md`.
- **The examples:** `GET /v1/creation/examples` serves
  `priv/creation/examples/<set>/` as `[{set, prompt, files: [{file, gift,
  title, content}]}]`, `[]` while none is committed.
  `mix oneiroi.creation.examples --resident <id> --prompt …` makes a set
  through the generator.
- **Deferred:** generating the fictional set, a real model call, waits on
  the witness's OK for the spend; nothing generated by the fake is
  committed. Lily's `SOUL.md` and `IDENTITY.md` as the second tab wait on
  her consent and on a way to read her live files: there is no
  cross-tenant read of another resident's files, and copying hers into
  the repository is not done. The client's use of all three is P6's.

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

**Built (2026-11-10; F70; brain#77, gaia#26).** What was chosen where
this plan left it open:

- The trigger is a diff, not a hook: each minute a worker reads every
  active resident's needs-you list and hands it to the witness's
  account, whose aggregate records only the entries never pushed for
  (`NeedsYouPushed`) and sends one empty push for them. Entries are
  rows across several systems, not events, so the list is the one place
  every source meets; a minute's delay is the cost.
- Quiet hours are hers, in her zone: inside them nothing is read or
  recorded, and what appeared is pushed for at their end, once.
- Nothing is recorded without a subscribed device and a key, so a
  first subscription is not silent about what already waits.
- The push is gaia#15's empty POST, so the device cannot tell the
  causes apart; the service worker still says "<name> wrote" for both,
  which the client has to reword.

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
