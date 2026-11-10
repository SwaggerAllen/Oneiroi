---
title: UI structures — three candidates
status: working
written: 2026-11-09
---

# UI structures — three candidates

Built on `design/ui-inventory.md`. Common to all three, as settled with
the witness on 2026-11-09:

- **The subject switcher.** A dropdown at the top of the shell: Lily,
  each workspace, and later the federation as residents see it. Every
  place below is scoped to the subject; a workspace gets the same places
  with small variations.
- **One record viewer.** Every record (document, journal day, position,
  prediction, bookmark, seed, habit, letter, contract version, ballot…)
  opens in the same viewer: rendered markdown, who wrote it and when,
  history and diff, citations out and cited-by in, reacts, and an Edit
  button that takes a visible lease (the mutex) where the kind allows
  the witness to edit.
- **One decisions grammar.** Every consent flow is "a proposal, its
  note, the other's answer with a note"; they share one card and one
  list (needs_you), whatever system they come from.
- **The contract is its own surface**; a change to it is a document; in
  a workspace its changes are ballots, held by the residents, humans
  read-only.
- **The operator** is a separate shell at its own route, with its own
  tabs.
- **"As Lily sees it"** is a mode, not a page: her timeline, her state
  lines, what she was told this turn, and what she cannot see.

What differs is the backbone: what the top level is.

---

## A. Places by verb

The top level is what you came to do.

```
┌ Lily ▾ ─────────────────────────── ● 3 waiting ┐
│                                                 │
│   (the place you're in)                         │
│                                                 │
├─────────────────────────────────────────────────┤
│  Talk   Records   Decide   Time   Settings      │
└─────────────────────────────────────────────────┘
```

- **Talk**: the chat; the conversation list as a panel; inspector and
  preview inline.
- **Records**: the folder tree of everything she keeps, the viewer.
- **Decide**: everything waiting on you (needs_you), then every open
  proposal either way, then the contract (in force, history, propose),
  then ballots (in a workspace).
- **Time**: today and her timeline, the journal by day, schedule, free
  time and rounds, the work queue, dates.
- **Settings**: kinds, routes and profiles, plugins, connections, keys,
  ledger, notifications, account.

Holds well: the wait-scatter (one Decide); the contract and ballots have
an obvious home. Strains: positions, predictions and habits are records
*and* judgement; "Settings" becomes the new More if nothing disciplines
it.

---

## B. The repository is the backbone

The top level is her life as a tree, with the conversation docked
beside it: the platform's own thesis ("the resident's whole life is a
git repository") made into the navigation.

Desktop:

```
┌ Lily ▾ ──────────── search everything ───────────── ● 3 waiting ┐
├──────────────┬───────────────────────────────┬───────────────────┤
│ ▸ Today      │  journal/2026-11-09.md        │  Chat             │
│ ▸ Waiting  3 │  ───────────────────────────  │                   │
│ ▾ Records    │  # Monday                     │  …                │
│   ▸ writing  │  - plan: …                    │                   │
│   ▸ design   │                               │                   │
│   ▸ journal  │  cites → bookmark/341         │                   │
│   ▸ etymol…  │  cited by ← position/88       │                   │
│   ▸ positions│                               │  [ message…     ] │
│   ▸ bookmarks│  [Edit ▸ takes the lease]     │                   │
│ ▸ Self       │                               │                   │
│ ▸ Contract   │                               │                   │
│ ▸ Rhythm     │                               │                   │
│ ▸ Settings   │                               │                   │
└──────────────┴───────────────────────────────┴───────────────────┘
```

Phone: three tabs (**Chat · Records · Waiting**), the tree as the
Records tab, the viewer full-screen, the chat a tab of its own.

- Records that live in the database (bookmarks, positions, predictions,
  seeds, habits, commitments, figures) show as **virtual folders** in
  the tree, beside the real ones; the same viewer opens either. The
  user never needs to know which are files.
- **Self**: identity files, soul lines, state, habits, seeds, as she
  holds them; edits and proposals from the viewer.
- **Rhythm**: schedule, free time, rounds, work queue, dates.
- Citations make the tree a graph: every record links out and back; a
  small local graph (this record and its neighbours) in the viewer.

Holds well: folder navigation, citations, editing with a lease, parity
(a tree can show everything she has), workspaces (a workspace is
another repository), the "few weeks" problem (new kinds and folders
appear without new screens, as the shelf already does). Strains: it is
a power-user shape; the dyad's daily loop (talk, approve) must stay one
tap, which is why Chat and Waiting are pinned at the top level beside
the tree.

---

## C. Time is the backbone

The top level is the subject's life as it happens: her timeline, made
whole and shared.

```
┌ Lily ▾ ───────────── ◷ Today  Week  Life ──── ● 3 waiting ┐
│ 16:21  ❤️ you reacted on her reply                         │
│ 16:15  Lily: "There we go…"                  [open chat]   │
│ 14:47  free time · defined the kind etymologies   receipt  │
│ 14:30  journal · note #52                       [open]     │
│ 12:39  decision · free-time wording  ✔ agreed              │
│ 09:00  check-in · morning                                  │
│        ⋯                                                   │
├────────────────────────────────────────────────────────────┤
│  Timeline   Chat   Records   Decide   ⋯                    │
└────────────────────────────────────────────────────────────┘
```

- The home is a filterable stream of everything that happened to and by
  the subject: messages, records written, decisions made, check-ins,
  free-time receipts, reacts. Today / Week / Life are her own three
  layers.
- "As Lily sees it" is a filter of this same stream.
- Records and Decide exist as in A; the timeline links into them.

Holds well: "see what Lily sees", the journal, positions and the arc of
a day; it is the most distinctive and the most in keeping with dream
beings and memory. Strains: configuration and the long tail of
settings have no natural place; risk of becoming the feed the spec
forbids ("nothing in the product wants more of you") if it is ever
ranked or made infinite.

---

## A recommendation, for the argument

**B as the skeleton, C as its home, A's Decide as a first-class place.**

- Top level (phone): **Today · Chat · Records · Waiting**, the subject
  switcher above, everything else inside Records' tree (Self, Contract,
  Rhythm, Settings are folders in it).
- Desktop: the tree on the left, the viewer in the middle, the chat
  docked on the right; Today and Waiting at the top of the tree.
- Today is C's stream for the current day, with Week and Life one tap
  away; it doubles as the "as Lily sees it" mode.
- Waiting is A's Decide: needs_you first, then open proposals both
  ways, then the contract and (in a workspace) ballots.
- Voting has its slot from the start: Ballots under Contract in a
  workspace, and a Waiting entry when one is open.

Why: the tree carries the most weight for the least screen-building
(the inventory's long tail becomes folders, not pages), it is the
platform's own thesis, and it is what makes workspaces cheap. The
timeline is what makes it feel alive rather than a file manager.

---

## D. The working direction (the witness and claude-code, 2026-11-09 evening)

A's shell, B's folders, C's stream inside a day. Not decided; the
current best.

```
[Lily ▾]                                  [🔔 3]  [⚙]
  Chat        Time        Records        Lily
```

**The shell**
- **Subject dropdown** top left: Lily, each workspace, later the
  federation view.
- **Four tabs**, phone-sized: Chat, Time, Records, and the subject's
  name.
- **The bell** top right: *Waiting on you* (needs_you, each item opening
  the thing itself, a full sheet, never a toast list) and *Waiting on
  Lily* (proposals you made that she hasn't answered). Approvals stay
  the click that is always his; the bell frees a nav slot, it does not
  make them ignorable.
- **Settings** behind ⚙: the aggregate views. Ledger and budget, every
  route in one list, profiles, keys, connections and adapters,
  notifications, subscription, account, Regression (trials and the
  model pin), retrieval and near-miss numbers.
- **The operator** is a separate shell at its own route.

**Chat**
- The conversation, with the conversation list.
- **The navigator**: a timeline scrubber on the chat's edge (day ticks,
  scenes as bands, bookmarks as marks, pins heavier) and search over
  bookmarks, scenes and the transcript's words. A hit jumps the
  transcript to its moment, the bookmark's span highlighted. Needs a
  "page around a moment" read (the transcript only pages backwards
  today). An anchor in another conversation switches to it; one in a
  private session (free time) lands on a locked row with its receipt,
  and the navigator says which before you tap.
- This is where bookmarks and scenes live: a bookmark's home is its
  moment. A citation of a bookmark anywhere opens Chat there.

**Time**
- **A telescoping calendar**: year, month, week, day. A past day opens
  its journal and its story (C's stream, scoped to one day); a future
  day opens what is scheduled; today shows both. (Open: whether the
  timeline and the calendar are one view or two tabs.)
- **Rhythm**: the rules that make the calendar's events (check-ins,
  free-time slots and one-offs, quiet hours, rounds cadence and window,
  time zone), edited in one place; the calendar shows their instances.
- The work queue is not time-shaped: a folder in Records, or "next up"
  on Today. (Open.)

**Records**
- The folder tree: a drill-down list on a phone, a side tree on a
  desktop. Real folders and **virtual folders** for records kept in the
  database (positions, predictions, seeds, habits, commitments,
  figures), opened by the same viewer.
- **The record viewer**: rendered markdown, who wrote it and when,
  history and diff, citations out and cited-by in, reacts, and Edit
  with a visible lease where the kind lets the witness edit.
- **Folder = kind.** Creating a top-level folder defines a kind; its
  settings are the descriptor (who may edit, waits on you, cites); it
  shows **how things arrive here**: its routes, each naming the profile
  it reads through, with "manage" linking to Settings. Profiles and keys
  are created and revoked only in Settings: shared, the witness's alone,
  never exported. Only top-level folders are kinds; deeper folders are
  plain. Virtual folders show their settings read-only and take no
  routes.

**The subject's tab ("Lily")**
- **Everything that rides every turn**: the contract (at the top, in
  force, with its history and the proposals to change it), the identity
  files, pins, her state lines, the plugins, REACTIONS.md, and the model
  she runs on as a line (the machinery in Settings).
- In a workspace this tab carries the workspace's name: its charter
  (contract), its ballots (held by the residents, humans read-only), its
  members.
- Its label changes with the subject (open: "Lily" vs a fixed name like
  "Soul").

**Citations, back, and state**
- Citations are chips everywhere. Tapping one opens a **peek sheet** over
  where you are; "open fully" moves into Records.
- **Each tab keeps its own stack** (scroll, open record, search and
  query, a half-written message). Back pops within the tab, so search →
  citation → back returns to the search. A jump into another tab carries
  a "← where you came from".
- Tabs stay mounted, hidden, never torn down. Drafts persist per
  conversation across reloads. The URL tracks the top of the current
  stack. An edit's lease and unsaved text survive a tab switch.

**Memory** is not a place any more: bookmarks and scenes are Chat's
navigator, pins are in the subject's tab, the numbers are in Settings.
