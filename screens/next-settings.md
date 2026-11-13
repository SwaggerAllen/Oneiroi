---
paths:
  - client/src/next/settings/**
---

# next-settings

The rebuilt client's Settings pages (`design/ui-build.md` P5, the rows
behind the gear), at `/client/#/settings/<section>`. Built
2026-11-10. With these, the witness needs the current client only for
Correspondence (being rebuilt as Mail) and the screens the bell still
links to.

## Where they live

A section is a full page over the tabs, inside the house shell, at
`#/settings/<section>`: `ledger`, `kinds`, `connections`,
`notifications`, `regression`, `work`.

- The Settings sheet's row closes the sheet and opens the page.
- The header and the tab bar stay; the four tabs stay mounted under it,
  hidden and inert, so nothing they hold is lost.
- "‹ Back" closes the page and the URL returns to the tab's own hash;
  so does tapping any tab, the browser's back, or any link to a tab's
  path (Folder settings, a research answer in Records).
- A settings hash loads straight into its page.

Why this shape: the shell already keeps the URL and the per-tab stacks
in step, and `#/operator` showed a second kind of hash living beside
the tabs. A page in the shell's store (`page`), read from and written to
the hash by the same sync, needs no fifth tab and no push onto a tab's
stack. Pushed onto a tab, a settings page would change what that tab's
back means, and leave the tab bar pointing at a tab it does not belong
to; as its own shell, like Operator, it would lose the header and the
bell. While a page is open the tab bar still marks the tab underneath,
which is where Back goes.

Each page reads under `['resident', id, 'settings', …]`; change notices
on the ledger, kinds, routes, work and xenia streams re-read it
(`live/notices.ts`), and every action re-reads the page when it lands.
What an action did, or why the server refused it, shows as a line under
it, in the server's own words.

## The sections

- **Ledger** (spec §10):
  - your key's state, with "Rotate it" / "Store one" opening
    Profiles, keys and connections, where the key is kept;
  - budget lines per purpose, with spent of cap ("no limit" when it has
    none, "stopped" when exceeded); "Change" on a line puts it in the
    form; the form sets a purpose's cap (blank for no limit) per day,
    week or month;
  - spend since the period's start, by purpose, by model and by actor.
- **Kinds and routes** (seshat#51, xenia#19):
  - one note for the next change, which a gate off, an answer, a route's
    run and a definition carry;
  - open gate proposals, Agree or Decline on hers (with a note), "waiting
    for her" on yours;
  - every kind, where it lives, its gate and whose it is; "Gate on" at
    once, "Propose gate off" as a proposal; "Folder settings ›" opens
    the folder's settings in Records (`screens/next-records.md`) rather
    than repeating them here;
  - defining a kind of hers (name, label, citations make edges, waits on
    you, what you are asked);
  - lately answered gate proposals;
  - every route, built-in and hers, with direction, profile and cadence,
    "unable" and why, what a route of hers reads for, and "Ask a run";
  - the last ten runs, and defining a route of hers (name, what it reads
    for, a standing profile, a landing kind). "Profiles ›" goes to the
    profiles.
- **Profiles, keys and connections:**
  - your OpenRouter key: stored since, store or rotate (password field,
    never shown back);
  - your GitHub read token (gaia#24, UI-configurable by the witness's
    call): store, replace, and revoke on a second tap;
  - what holds a token for her (xenia#11): connected adapters with their
    role in words, revoke on a second tap; "Connect something new" with
    a name and a role (brain, reader, worker) issues a token shown once
    with Copy and "I've saved it"; revoked ones listed;
  - profiles (xenia#19): each with its one site, who it is signed in as,
    and the routes using it; revoke and restore with a note; make a
    profile on one https origin;
  - the reader's sites (xenia#16): the two allowlists, one origin a
    line, saved together; a refused save keeps the draft;
  - research (seshat#38): the questions, their state and who asked, an
    answered one linking to its notes in Records; ask one, with pages
    to start from.
- **Notifications** (gaia#15, gaia#25):
  - this device: on, off, or why it can't (unsupported, the iPhone's
    Home Screen step, blocked in the device's settings, not set up on
    the server); "Turn on notifications" asks the browser then and only
    then; "Turn off" unsubscribes this device;
  - "What they're for ›" opens the bell's explainer;
  - your account: how many devices are on, "Send a test" to all of them
    with what each said, and the account's answer (yes, no thanks, or
    not yet) with its date; while unanswered, "No thanks, on every
    device" answers it.
- **Regression** (spec §6.4, eunomia#30, #31):
  - Trials | Runs;
  - write a trial (what you say, passes if, fails if); edit one;
  - "Suggest some" (agathos-daimon#42): trials drafted from her files,
    with an optional steer; each kept only with "Keep this trial", or
    put in the form with "Edit it first";
  - start a run: models by OpenRouter name, every trial or some;
  - runs listed with their models, trials, answers and state; a run
    opens to its deck, live while it answers (the run channel), its
    cards grouped by trial and blind until every answer to the trial is
    graded; each answer as words, a refusal in its own words, or a
    failure said plainly; how she got there (the trace, reads and
    mocked steps); Passes, Fails, Favourite;
  - results by pass rate, with "Pin for chat" asked twice and the chat
    model marked.
- **Work queue** (sunna#33, #35, #38, #42, #43, #54, #55, #58):
  - the line in words: running, resting, runs today, armed by whom and
    what is left of its cap; "Arm the work line" when it is off and
    something is open, "Turn the work line off" when armed; once a run has been used today, how many of the day's runs are used and "Reset today's runs" with a note she reads (sunna#53);
  - the live items in order: status, who added it, done when, the
    last wrap (shipped, slipped, why), the note; with a note: Blocked on
    another item, Unblock, Done, Drop; "Move up";
  - on an item that has run, how long it has been in work (sunna#58):
    "running 1h 30m this run · 6h 30m in work over 4 runs since
    2026-11-11", ticking while it runs; a run past an hour turns the
    line amber with "running long: worth a look"; an item that ran
    before the time was kept says only its runs; the line above says
    "Running item #n now, for …";
  - "Hold for me…" opens an ask field ("What #n waits on you for") and
    Hold, required; a held item says "held for you" and "HELD · she asks
    you: <ask>" (or "you held it"), and "Release", with the note she
    reads, moves it open again (sunna#54, #55); the line says it steps
    over what is held;
  - add work (what, done when); the last five finished.

## The current client's actions, each covered

| Old screen | Call | Here |
|---|---|---|
| Ledger | `ledger`, `setBudget` | Ledger |
| Ledger | `storeKey` | Profiles, keys and connections |
| Kinds | `kinds`, `defineKind`, `kindGate`, `answerKindGate` | Kinds and routes |
| Routes | `routes`, `defineRoute`, `askRoute` | Kinds and routes |
| Routes | `setProfile`, `revokeProfile`, `restoreProfile` | Profiles, keys and connections |
| Connections | `adapters`, `registerAdapter`, `revokeAdapter` | Profiles, keys and connections |
| Connections | `reader`, `setReader`, `research`, `askResearch` | Profiles, keys and connections |
| GitHub token | `me` (github), `storeGithubToken`, `revokeGithubToken` | Profiles, keys and connections |
| Notifications | `pushConfig`, `subscribePush`, `unsubscribePush`, `testPush` | Notifications |
| (new) | `declinePush` | Notifications |
| Regression | `regressionTests`, `regressionRuns`, `regressionRun`, `writeTest`, `changeTest`, `startRun`, `grade`, `favourite`, `pinModel`, `socketToken` with the run channel | Regression |
| (new here) | `suggestTrials` | Regression |
| Work | `work`, `addWork`, `moveWork`, `orderWork`, `armWork`, `disarmWork`, `resetWorkRuns` | Work queue |
| (new) | `holdWork` | Work queue |

Not built:
- Correspondence (the Mail view replaces it);
- subscription, export, retrieval and near-miss numbers
  (ui-structures.md D lists them under Settings; no screen exists yet);
- the results' fidelity numbers (facts, voice, commitments), which the
  current client does not show either;
- re-reading on returning to the window: these pages re-read on change
  notices and after each action instead.
