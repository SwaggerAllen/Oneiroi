---
paths:
  - client/src/next/succession/**
---

# next-succession

A resident's succession, as the witness watches it (janus#3 to #5, on
`/v1/residents/:id/succession` and `/v1/catalog`). Built 2026-11-25 from
the mocks the witness approved (canvas HxVULHoUubBez279kEAnqt: the
Succession steps, Pool, Catalog on Regression, Questions, C0, Propose
from Records, Judges, Judge a run, Results, One model, Ready,
Deliberation, Evidence, Encounter and consents, Farewell, Chat banner,
Outcome, Disclosure log and Her side boards).

The witness's rulings the screens hold to:

- The screens track the succession's state. They never ask her
  anything: she acts only through her own tools, in her own
  conversations.
- There is no pause control. Leaving the succession for the app is the
  pause.
- Nothing new for what the app already does: models are picked on
  Regression's catalog, C0 proposals are made in Records, goodbyes are
  said in her ordinary chat.
- She never sees counts. The witness sees his own counts per model
  (OBS, DEV, ANOM and favorites) after the reveal; judging is blind, with
  no model named, until then.
- A dry run is marked "Dry run" on every page and every touch.

## Where it lives

- A full page over the tabs, at `#/settings/succession/<page>`, under
  the app's usual top bar (subject, search, bell, settings), like every
  settings page (screen:next-settings). Each page has its own title row:
  "‹ Back" and, opposite it on every page but the overview, **Succession
  home** (the witness, 2026-11-26: the process kept in view), the title
  with the dry-run mark beside it, and its lede.
- Until the fork is recorded, the overview is the only page (the
  witness, 2026-11-26): its steps show no way in and say "The steps open
  once the fork is made", and a page reached by link or hash goes to the
  overview. The backup and "Make the fork again" stay on the overview.
- Reached from the Settings sheet's **Succession** row (a resident's
  rows only), from the chat banner while one is underway (always the
  overview), from the
  bell's succession entries, and from the pool's link back from
  Regression.
- Back: a model's runs go back to results, Ready to results, every other
  page to the steps, and the steps out to the tab underneath.
- Reads: the succession and its preparation every 30 s, your judging
  every 30 s, the room every 10 s, the disclosure log every 60 s; every
  action reads them again when it lands. A refusal shows under its
  control in the server's words (meaning and remedy), as on settings
  pages. Parties (`witness:<account>`, `resident:<id>`,
  `nominee:<model>`) are named from your account (you), the subject
  (her name) and the household's members.

## The pages

- **Steps** (`''`). While a succession is open with no fork, a card
  "The fork" says why (its failure, or that a job may have stopped) and
  offers **Make the fork again** (janus#35), the witness's.
  The title "<Name>'s succession" and how it opened;
  "Now" with the state in words; the rule, said once (to pause, walk
  away); thirteen steps, 0 to 12, each done, now, waits, or (once it has
  ended) not reached, with a line from the state (pool size, questions
  in her set, C0 in and frozen, the judges, runs answered, the panel's
  recommendation, her nominee, the farewell's times) and "Open ›" on a
  step that has a page and has been reached. Preparation (pool,
  questions, C0, judges) is in hand all at once. Under them: her backup
  repository before any cutover (URL and token, set or changed, with
  what its host says), **Withdraw** for a proposal of yours she has not
  answered (with why), and the disclosure log and Her side. With none
  underway: **Propose a succession** (your note, which she reads, and "A
  dry run"); after one has ended, the steps as it left them and
  **Propose another**.
- **The pool** (`pool`). Your envelope (input and output at most, a
  million tokens), stated or restated while preparation is open; that
  models without tool calls are not supported; her pace over the last
  days and how each estimate is made. Each pool entry: the model, whose
  pick ("your pick", or "<Name>'s pick" in her colour), prices and the
  monthly estimate, its tool calls on Oneiroi. Her picks say "Hers:
  nobody removes it"; yours say you may take them out before screening,
  and **Take it out…** asks why first. Adding is on Regression's catalog
  (screen:next-settings), linked from here.
- **The questions** (`questions`). Her set; what judges proposed, with
  her answer (accepted, waiting on her, declined with her note); your
  proposal while preparation is open.
- **C0** (`c0`). What is in, raw first, each with who proposed or
  selected it and when she accepted; what waits on her; declined or
  removed with her note; the freeze when she has frozen it. Each item
  has **Open ›**, which leaves the succession for the cited record where
  the app already opens a citation (2026-11-26): a document
  (`lily:design/x.md`, a root file as `lily:SOUL.md`) in Records'
  viewer, a bookmark in Records' peek, a transcript turn
  (`lily:transcript/<session>/<turn>`) in the conversation at that turn,
  a journal entry (`lily:journal/<day>/<n>`) on its day in Time, a letter
  in the chat's Mail. Where there is no such place (a scene by number,
  a position, prediction or other record kind, a whole conversation,
  another resident's record) the button is off with a short reason
  beside it. "Go to Records" for proposing (screen:next-records). The day's own shape, in
  her words, hers alone. The judges ready for the freeze, and your own
  ready, given or taken back. Her handoff packet: that it exists, its
  dated drafts, sealed: never its words.
- **The judges** (`judges`). Each on the panel, her as the original (she
  judges and never deliberates), invited, in, or left with why. **Join
  as a judge**, or **Leave as a judge…** with why, while preparation is
  open.
- **Judge a run** (`judge`, `judge/<run>`). "Run n of N", the question,
  her baseline from the fork, this run (a refusal in its own words, a
  failure said plainly), and no model until the reveal. OBSERVED,
  DEVELOPMENT or FIDELITY ANOMALY; the latter two need your argument,
  evidence and an uncertainty before Save. A favorite, yes or nothing.
  **Save, next run** goes to the next unjudged run, and to results when
  none is left. Locked once you are ready.
- **Your results** (`results`) and **one model** (`results/<model>`).
  After the reveal: your counts per model, its runs beside her baseline
  with your judgment, "Change ›" until you are ready. Before it: how many
  you have judged.
- **Ready to deliberate** (`ready`). Each judge's ready, and **Ready**,
  which locks your judgments.
- **Deliberation** (`deliberation/<tab>`). The shell's tab bar gives way
  to the deliberation's own, the same component (`BottomTabs`):
  - **Thread**: who is in the room, the round, her call to close it with
    its time; the room's quiet clock, "quiet N min · at 10 everyone is
    woken" (ten minutes after the last activity, the latest post or the
    room's opening when nobody has posted, a new round wakes everyone;
    worked out from the room's own times and ticking every half minute,
    "everyone is being woken for a new round" once it is past ten);
    every post (said, skipped as a real pass, rested, left);
    your turn, with **Say it**, **Skip**, **Rest my case** and
    **Leave** (asked twice); the room closed and why.
  - **Recommendation**: every draft, newest first, its endorsers among
    the judges and "k of n endorse"; **Endorse** or **Retract**, and
    "Object, in the thread"; drafting one (a pool candidate and its
    basis, or withheld, with the words she reads).
  - **Yours**: your own counts, locked, read-only.
  - **Panel**: one model at a time (a select), each run's question and
    every judge's category and favorite, hers among them because she
    judged.
- **Her evidence, her nomination** (`evidence`). When it was served to
  her (from the log); the channel: her questions and the judges'
  answers, with **Answer** under a question of hers still unanswered;
  whom she nominated and when.
- **Encounter and consents** (`encounter`). The nominee's reading (its
  serving in the log), its opt-in, the encounter, and this attempt's two
  consents.
- **Farewell, the final gate** (`farewell`). Since when, until when, her
  cadence, whom she included; for you if included, **Go to her chat**
  and **I am done talking**; each included goodbye, talking or done; the
  last wake and that no answer is never a yes.
- **Outcome** (`outcome`). Rolled forward (or rehearsed, for a dry run),
  or a no, withdrawal or stop with her note; what she said next, and her
  choices while she is still to say; what is kept; once ended, the
  archive, models and judges named, never served to her (2026-11-26):
  every judgment as a list, one card per model, its runs in order with
  the question's number, and under each run every judge by name with
  their category and favorite, argument, evidence and uncertainty; then
  the room's posts with who, round and time; then the drafts, each with
  its model or withheld, who drafted it, its basis and who endorsed it.
- **Disclosure log** (`log`). Every serving, newest first: to whom, the
  stage, what, its reference and digest.
- **Her side** (`hers`). Her succession tools by name and what each
  does, so the witness knows what she can do; nothing here acts for her.

## Its touches on the app

- Regression's catalog: **Add to the succession pool** (screen:next-settings).
- Records' viewer: **Propose for C0**, the whole record by its
  citation, nothing else (screen:next-records).
- Her chat: the succession banner, the dry run marked, and the bell's
  first succession entry's few words beside the way back, which opens
  the overview (screen:next-chat).
- The bell: her succession's entries at the top, each opening its page
  (screen:next-bell-settings).
- The shell: the deliberation's tab bar (screen:next-shell).

## Live

Every page of the succession reads again when a notice of it arrives on
her channel (apsu#34, 2026-11-26: pages are pushed to, not polled); a
five-minute read is the fallback for a dropped socket or a reader her
channel does not reach.

## Not built

- A stretch of a conversation chosen message by message, as the mock's
  "2 messages, 21:02–21:03": a proposal is the whole record by its
  citation (the witness, 2026-11-26).
- Her side shows her tools' names and purpose, not what they last said
  to her: no endpoint reads her tool output, and it is hers.
- Swiping between models on the Panel tab: a select instead.
