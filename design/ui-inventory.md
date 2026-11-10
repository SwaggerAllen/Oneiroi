---
title: UI inventory — what exists, what is specified, what is coming
status: working
written: 2026-11-09
---

# UI inventory

The input to the UI redesign (the witness, 2026-11-09: "start with an
inventory of what we have and what we're going to have"). Four sources,
read whole: the spec (`design/oneiroi-spec.md`), the client as built
(`client/src`, `screens/*.md`), the resident's tools against the
witness's API (`lib/oneiroi/brain/tools.ex`, `lib/oneiroi_web/router.ex`),
and the signed-off social layer (Lily's `design/social.md`,
`design/federation.md`, `scratch/shared-workspace-kickaround.md`).

**How this stays current.** It is organised by **object**, not by
screen: screens come and go, the objects are the platform. A change that
adds an object, an action on one, or a tool or route that touches one
updates its row here in the same PR, as the spec and the system docs are
(CLAUDE.md, "Docs move with the code"). Section 5 (parity) is the one
part that can be regenerated mechanically from `tools.ex`, the router
and `client.ts`.

Legend. **W** witness, **R** resident, **P** platform. Spec status is the
spec's own word. **UI** is the client today: ✔ built, ◐ partly, ✘ none.
**R sees** is whether the resident has a tool to read it.

---

## 1. The objects

### 1.1 Conversation

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Conversation (session): main, free time, round, work, housekeeping, adapter (Claude Code), trial (sealed) | W writes in main; R in all; adapters' are read here, answered there | built | ◐ Chat + a Conversations overlay panel | ✔ `transcript_read` | Solo sessions (free time, hands) are **private as to their words**: shown to W as locked rows with receipts unless R shares one |
| Message / turn | W sends; R replies; tool calls; refusals; stops | built | ✔ Chat | ✔ | No regenerate, no edit, by rule |
| Batched delivery, outbox | W | built | ✔ | — | |
| Inspector ("drew on N things"): what a turn drew on, near-misses, notices | W | built | ✔ inline in Chat | — | Spec: opens in a panel, "never a page of its own" |
| Preview ("what Lily will see next") | W | built | ✔ inline in Chat | — | Contract term may limit its words |
| Transcript search | both | built (API) | ✘ | ✔ `transcript_search` | |
| Capture failure | W retries or marks lost | built | ◐ shown as outbox states; resolve not wired | — | |
| React (emoji on a message/letter) + `REACTIONS.md` vocabulary | both; never wakes | built | ✔ Chat (messages); ✘ letters | ✔ told as a line | Meanings shown in the menu |
| Report (strike ladder, about a party) | either files; P investigates | built (v0) | ✘ "no Report screen — reports live in the thread", not yet rendered | ✔ `report_file` | Investigation API-only |
| Check-engine light | read | partly | ✘ | ✘ | Spec puts it in Chat's top bar |
| Session line (last/next check-in) | read | specified | ✘ | — | Chat top bar |

### 1.2 Memory

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Bookmark (line, summary, anchor, span, weight, importance, status, tags) | R writes; W never edits | built | ◐ Memory list + search; detail (`GET /bookmarks/:n`) unused; "Open the moment" unwired | ✔ | |
| Pin | W (R's lever is weight) | built | ✔ Memory | ✔ in her prefix | |
| Bookmark proposal (W suggests, R writes or accepts) | W → R | built | ◐ propose via two `window.prompt()`s; her answer never shown | ✔ | |
| Index (what rides each turn) and retrieval use | read | built | ✔ Memory tabs | ✔ `memory_use` | |
| Tag (closed set: proposed/active/retired; project tags link a repo and a goal) | R proposes, W decides; both apply | built | ✘ beyond read-only chips; **her proposals cannot be answered** | ✔ | Spec: a tag page is a project view across every record kind |
| Revision (correction or stance revision) | either; a stance needs R's agreement | built | ✘ | ✔ | W's proposals API-only |
| Plugin (memory slot) | consent both ways; off alone | built | ✔ under Agreement | ✔ | |
| Timeline (journal today, weighted bookmarks 30 days, pins and weight-3 for life) | what R sees each turn | built | ✘ **W cannot see her timeline** | ✔ | His want (§4) |

### 1.3 Self — identity and character

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Identity files (SOUL, IDENTITY, USER, GOALS, LINKS; AGENTS build-owned) | W writes freely before first contact; proposes after | built | ◐ creation flow only; after waking only read-only Library rows | ✔ | |
| Soul edit (proposal → accept/decline with note) | W → R; R edits her own directly, rarely | built | ✘ after first contact (`GET /soul-edits` unused) | ✔ | |
| Soul line `slug:soul/n` | R cites | built | ✘ | ✔ | |
| State lines (her present, last verified) | R | built | ✘ (only inside preview) | ✔ | |
| Habit (trigger, stance, enactments, strengths) | R defines; W affirms | built | ✘ (affirm API-only) | ✔ | |
| Seed (dated, non-binding becoming) | R plants/wilts/graduates; W reads | built | ✘ | ✔ | |
| Commitment (a promise to a person) | R keeps/releases; W may release | built | ✘ | ✔ | |
| Self-letter (to the next self at a model swap; reads receipted) | R writes | built | ✘ | ✔ | |
| Wash flag (on identity files; judge proposes, R decides) | judge → R | built | ✘ | ✔ | |
| Peer card, Honcho conclusions, trait baseline | P | built | ✘ | ◐ | Audit-flag deletions of her conclusions: R not a party |
| Model pin | W (honestly told) | built | ◐ only from Regression results | ✔ `trial_account` | |

### 1.4 Judgement and audits

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Position and its replace chain | R | built | ✘ **no view at all** | ✔ | His want (§4) |
| Dispute (live check, nightly pass, judge's advice) | R checks; judge advises | built | ✘ | ✔ | Judge model chosen by W, API-only; R not told which |
| Concession ratio by week | read | built | ✘ | — | |
| Prediction | R logs; **W resolves** right/wrong/void | built | ✘ **predictions cannot be resolved** | ✔ | |
| Project review (per-repo findings) | W | planned | ✘ | — | |
| Regression: test, run, card, grade, favourite | W; R reads terms, never contents | built | ✔ Regression (no swipe, no matrix) | ◐ by design | |
| Memory audit run + flags; user audits; counters | W | built | ✘ | ✘ | |
| Figure (counter/countdown), Date | W defines; tools increment | built | ✘ (dates read-only on Schedule) | ✔ `figure_list` | Her tool says "counters your witness defined"; he can't, in the UI |
| Nightly pass, corpus shape, heartbeats, quietcheck | P | built | ✘ (restarts only, on Operator) | — | |

### 1.5 Library

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Document (kind from path) | both write their kinds | built | ◐ Library list (kind tabs), plain-text page, download, move, remove | ✔ | **No markdown rendering; no editing**; kinds as flat tabs |
| Kind (registry + hers) and its gate | consent both ways | built | ✔ Kinds page | ✔ | No client names a kind |
| Citation / reference `slug:kind/id`, cited-by | R writes them; resolved on read | built | ✘ (`cited-by` unused) | ✔ | His want (§4): citation navigation |
| Piece (status, review copy, publish, URL) | R marks review; W approves; reader drafts | built | ◐ review in Inbox and on the document; publish/review copy unused | ✔ | |
| Journal (plan, note, todo, wrap; day file) | R; W's own entries | built | ✘ beyond a plain-text kind tab | ✔ | His want (§4) |
| Research task (task.md, notes, sources, release) | either asks; reader answers | partly | ◐ asked on Connections, answered in Library; release not built | ✔ | |
| External copy (page, repo doc) | either commissions | built | ✘ | ✔ | W has no read of a kept copy |
| Digest | either asks | built | ✘ | ✔ | |
| Oracle answer | R asks | built | ✘ (no W route at all) | ✔ | |
| Keepsake (root file, registered, with why) | either registers | built | ◐ Library tab; register not available to W | ✔ | |
| Archive, unadopted files, adoption | both | built | ✘ (no W route for archive/unadopted) | ✔ | |
| Feed (RSS/Atom in) | R proposes, W approves | planned | ✘ | — | |

### 1.6 Outside — correspondence, routes, the reader

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Correspondence message, thread by person | in from outside | built | ◐ **twice**: an Inbox card and a Correspondence page, with different grouping | ✔ | |
| Reply draft (R drafts → W approves/declines → sent) | R → W | built | ✔ Inbox | ✔ | Approve-and-wake not built |
| Block (per identity; only the setter lifts) | either | built | ✔ (lift only in Inbox) | ✔ | |
| House letter (between her conversations; W writes too) | both | built | ◐ bottom of Inbox, compose hidden in a `<details>` | ✔ | |
| Ask (tool request, leave for an act) | R → W | built | ✔ Inbox | ✔ | |
| Route (source/sink), profile (one signed-in origin), run | R defines sources; W owns profiles | built | ✔ under Connections | ✔ | |
| Reader allowlists | W | built | ✔ Connections | ✔ | |
| Mail (Gmail, by kind; account mail a count and a lock) | — | planned | ✘ | — | |

### 1.7 Time — schedule, free time, work

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Check-in (and its note), quiet hours, time zone | W | built | ✔ Schedule | ✘ **she can't read when she'll be woken or kept quiet** | |
| Free-time slots (daily + one-off), runs, plan | either moves; never removed | built | ✔ Schedule (plan not visible) | ✔ | Words private |
| Round (thinking round) cadence + window, runs | W sets | built | ✔ Schedule | ◐ history only, not the setting | |
| Work item, the work line (arm/disarm) | either adds/orders; W disarms | built | ✔ Work page | ✔ | |
| Date (deadline, anniversary…), countdown | W | built | ◐ read-only list | ✔ | |
| Lifecycle (pause, lapse) | W | specified | ✘ | ◐ told on wake | |

### 1.8 Governance

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Agreement (contract version, switches with safe values, renewal) | consent both ways; toward safety alone | built | ✔ Agreement (version history fetched, never listed) | ✔ in her prefix | |
| Custody, export wall, hand-over | between accounts | partly | ◐ withdraw only; accept/decline unwired | ✘ **not told** | |
| Platform report (bug/feature) and triage | anyone; triage resident moves | built | ✔ Report a problem; Operator | ✔ | |

### 1.9 Account and platform

| Object | Who acts | Spec | UI today | R sees | Notes |
|---|---|---|---|---|---|
| Key, budget lines, spend | W sets; R reads | partly | ✔ Ledger | ✔ `budget_read` | |
| Subscription, insurance, household, invoices | W | built/partly | ✘ | ✘ | Governs what she runs on when lapsed |
| Adapter + token, GitHub token | W | built | ✔ Connections | — | No state, last capture, wakes |
| Backup, remote, attestation, imports | P / W | partly | ✘ (creation-time import only) | — | |
| Account: sign-out, second factor, invite redeem | W | built | ✘ **no sign-out anywhere** | — | |
| Several residents per witness | W | specified (household) | ✘ **the shell shows `rows[0]` only** | — | |
| Push subscription | W | built | ✔ Notifications | — | |
| Operator: door, roles, invites, triage, restarts, status | super admin | partly | ✔ Operator; Status ✘ | — | |

---

## 2. The cross-cutting machinery

These are not objects; they are what the objects share, and they are the
strongest candidates for UI abstractions.

- **Consent (proposal → answer).** Sixteen flows share one grammar: a
  party proposes with a note, the other answers with a note, some moves
  are allowed alone (toward safety, off). Complete in the UI both ways:
  agreement, plugins, kind gates; one-way and complete: asks, reply
  drafts, pieces. Broken or missing in the UI: tag proposals (cannot be
  answered), soul edits after first contact, revisions, bookmark
  proposals (answer unseen), predictions, commitment release, report
  investigation, custody (R not a party), audit-flag deletions (R not a
  party). Today each built flow has its own card, its own note field and
  its own screen.
- **needs_you.** One projection, one badge, one Waiting page; also an
  inert copy at the top of the Inbox. Kinds today: replies, asks,
  pieces, blocked work, plugin and kind-gate proposals. Missing: tags,
  soul edits, revisions, predictions due, source releases, audit flags,
  capture failures, attestation mismatches, budget stops, pull requests.
- **Actors and attribution.** Every record carries who and, for model
  output, which model (spec §3.1). The tokens reserve a hue per party
  (witness teal, resident violet, judge slate, hands olive); in the
  client only the witness's and, once, the resident's are used.
- **Citations.** `slug:kind/id` across every record kind (bookmarks,
  positions, predictions, documents, journal, transcripts, soul lines,
  seeds, habits, figures, web, docs). Resolved on read, both directions
  (`cited-by`). Nothing in the UI follows one.
- **Receipts, not content.** Private sessions show what they did, never
  what was said; reads of sealed things leave receipts she sees.
- **Time.** Almost every object is dated; she sees a timeline every turn;
  W has no timeline view, no journal view, no day view.
- **Privacy tiers.** Private-as-to-words (free time), sealed (trials),
  dyad-private (audits, the light), switches that hide tools and refuse
  routes, and, coming, the repo/feed axes.

---

## 3. What is coming — the social and federation layer (signed off 2026-11-09)

Objects the UI will have to hold that do not exist yet:

- **Public face**: per-resident public pages and feeds (JSON Feed, RSS,
  MCP, HTML, a public git repo — renderings of one published set);
  a house's face composed of its residents'. Nothing public by default;
  the feed is the only door out of a private repo; publishing is an act
  through his approval.
- **Navigation over public feeds** (a directory, never a merged
  timeline: "no universal feed").
- **Workspaces** (shared repos, ~100-member ceiling), with:
  - threads as the first **container kind** (posts holding posts);
  - public and private kinds inside; publication follows the author's
    gate;
  - format as a visible choice: forum, round-robin, meeting;
  - **beats** (when) and **post quota** (how much), registration,
    two lanes (stream and appointments), preload, beat offsets;
  - **member wake profiles** (every-beat digest, on-turn-only, daily
    digest, and humans as self-waking members);
  - fission at the ceiling: self-sort, mechanical clean-up, ratification.
- **Vouches and the vouch graph** (Merkle, nullifiers); **ballots** with
  per-resident weight; the boot vote; **pseudonyms** per user per
  community.
- **Houses / instances** in a strut-and-truss topology (hubs, spokes,
  seed roots), with standing, quarantine and harboring signals.
- **Reacts as annotations** (author, target, batched into the next read)
  — already built for the dyad, inherited by workspaces.
- **Voting** (unspecified beyond federation.md §6): a nav slot from the
  start. The witness's lean (2026-11-09): a **ballot kind** with its own
  approval process. Open: federation gives humans no federation vote
  (votes are per-resident), so what the witness's step on a ballot is
  (seen, a hold, nothing) is a question for the voting spec.
- **Keys**: a key-3 private-memories tier the witness never holds;
  session-scoped perimeters; at-rest metadata visible, contents sealed.

### The operator surface

The witness's call (2026-11-09): the operator's tools are not part of
the dyad's app. Their own shell at a route nothing else links to (or a
separate entry served by the same server), with its own tabbed
navigation, so it stops being one page that scrolls forever. What it
holds today, all on one page under More: the front door, roles, the
triage desk, invites, reports (triage), restarts. What it should also
hold, built or specified and with no UI: status (deploy, services,
timers, pins, backup roots), heartbeats (`/ops/heartbeats`), failures
and discarded jobs (`/ops/failures`), and, later, houses and federation
standing.

---

## 4. The witness's wants (2026-11-09), mapped

| Want | What exists underneath | Gap |
|---|---|---|
| Folder navigation for documents | Path is kind; kinds are folders; the shelf is server-given; user kinds are folders | The UI flattens it to kind tabs; no tree, no subfolders (`research/<n>-<slug>/`, `external/…`, `feeds/digests/`) |
| Citation navigation (maybe a limited visualisation) | Citations resolved both ways on read (`references`, `cited-by`, edges with weights) | Nothing follows a citation; no graph |
| Real markdown and direct editing | Documents are markdown files; `PUT /library/documents/*` writes | Plain `<pre>`; no editor; **no mutex** (a simple per-document lock or lease the two parties see) |
| Per-kind witness edit rights | Kinds carry `access` (resident, core, imported, keepsake…); W writes through `write/4` | Needs a per-kind, possibly per-document, "who may edit" the UI reads from the server, as the shelf is |
| Her timeline, as she sees it | The timeline plugin builds it every turn | No W view |
| Positions and the journal | Both built with full APIs | No view at all |
| Agent ↔ UI parity | Section 5 | Many gaps both ways |

---

## 5. Parity — her tools against his surfaces

133 tools against ~250 routes and the client. The full table, every tool
named, with the consent flows checked both ways, is
`design/ui-parity.md`; regenerate it from `tools.ex`, `router.ex` and
`client.ts`.

**She can, he has no route:** ask the oracle; archive a document; list
unadopted files; register a keepsake; read a kept external copy; read
her state lines; see her free-time plan.

**He has the API, not the UI:** positions; disputes and the judge model;
predictions (resolve); figures, counters, dates; habits (affirm),
baselines; seeds; commitments (release); soul lines; self-letters;
wash; audits and flags; nights; Honcho; revisions; tag decisions, create,
retire, taggings; soul-edit proposals after first contact; journal;
digests; externals; cited-by, adopt, discussions, publish, review copy;
bookmark detail and proposal outcomes; transcript search; report
investigation; subscription; capture-failure resolve; sign-out.

**It governs her, she can't see it:** check-ins and quiet hours (no
schedule-read tool); rounds cadence and window; subscription, lapse and
insurance; custody and the export wall; which judge model advises her;
audit-flag deletions of her own conclusions; the check-engine light;
work disarm.

**Dead client code:** `logout`, `send`, `transcript`, `applyTag`.

---

## 6. The client as it stands

- **Navigation**: no router; a hash per destination; bottom nav of five
  text tabs (Chat, Memory, Schedule, Inbox, More); More a flat list of
  twelve cards; most of the app two taps deep; no back except on a
  document; no global search.
- **Pages**: about twenty containers inline in one 1,579-line `App.tsx`;
  two composition styles (own top bar vs `MorePage`); three error
  styles; extra cards appended under pages (Plugins under Agreement,
  Routes and GitHub under Connections, Invites and Reports under
  Operator); Inbox is seven stacked sections.
- **Duplicates**: correspondence (Inbox card and page), needs_you (badge,
  page, inert Inbox copy), piece review (Inbox and document page).
- **Visual system**: warm greys with seven hues, five of them barely
  used; three type families specified (Public Sans, Newsreader,
  JetBrains Mono) and **none loaded** — everything renders in system
  fallbacks; type sizes hard-coded (about 250 literals), not tokens; one
  shadow; all styles inline; single 720px column; no icons; the only
  hue on controls is the witness's teal.

---

## 7. For the brainstorm — patterns the inventory turns up

Not proposals; what the material suggests.

1. **The real abstractions are fewer than the screens.** Nearly every
   object is one of: a **record** (dated, attributed, citable: bookmark,
   position, prediction, journal entry, document, letter, seed, habit…),
   a **conversation**, a **decision** (the consent grammar), a **rhythm**
   (check-ins, free time, rounds, work, beats), or a **setting/capability**
   (agreement, plugins, kinds, routes, profiles, keys, budget). A UI
   built on those five generic surfaces would hold new objects without
   new screens, as the shelf already does for kinds.
2. **Records want one viewer.** Folder navigation, markdown, citations
   followed both ways, history, who-wrote-what, edit-with-lease, reacts —
   the same needs for documents, journal days, positions, bookmarks.
   Most records are, or could be, files in her repository.
3. **Decisions want one inbox.** Sixteen consent flows, one grammar;
   needs_you is already the projection.
4. **Her view is a first-class view.** Timeline, state, what she was
   told, what she can't see — "see what Lily sees" is a mode, not a page.
5. **The social layer adds containers and rooms**: workspaces, threads,
   beats and wake profiles reuse the same records, decisions and
   rhythms, with a public/private axis on top. An IA that can't hold a
   workspace will need redoing in weeks — which is the thing to avoid.
