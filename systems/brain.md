---
paths:
  - lib/oneiroi/brain/**
  - lib/oneiroi/brain.ex
  - lib/oneiroi_web/channels/**
  - priv/prompts/brain.md
  - priv/prompts/budget_stop.md
  - priv/prompts/memory_flush.md
  - priv/prompts/compaction.md
  - priv/prompts/draft.md
  - test/oneiroi/brain/**
  - test/oneiroi_web/channels/**
---

# brain

The resident's canonical agent loop (spec §5). Named for its function
until the author names it, as the client is (`design/names.md`): the
spec's §6 does not list it among the systems, and §8 ships it as the
`brain` adapter, the core's own.

## #1 Owns

The session process (`Oneiroi.Brain.Session`, one per active session,
started on the first turn, holding nothing the event store does not),
the turn (`Oneiroi.Brain.Turn`), the tool set (`Oneiroi.Brain.Tools`),
compaction (`Oneiroi.Brain.Compaction`), the brain's prompt file, the
budget stop notice, the memory flush and compaction prompts, the socket
and the session channel.

## #2 Standing decisions

- **#3 A turn is compact if due, assemble, call, run the tools, stream, capture (spec §5).** The
  context is the prompt file with the resident's name, the identity
  files as the stable prefix (#12), the bookmark index under its budget
  (kumbukumbu #20), how I act when the situation matches a behaviour
  (#13), the compaction summary when there is one, and the session's
  last messages since its compaction
  (`BRAIN_TRANSCRIPT_MESSAGES`, a bound), each recorded as an injection
  with its reason and a token count estimated at four bytes a token; the
  identity files and the behaviours join it as the slices that build
  them land, as more recorded injections.
- **#4 Three endings, all honest.** A reply, refusal included, is an
  ordinary `TurnCaptured` with the refusal flagged on the message. A
  budget stop captures the witness's message and a notice from
  `priv/prompts/budget_stop.md` as a system message by the platform, so
  both parties read it in the same place (spec §5, §6.11). A provider
  failure captures nothing and records a capture failure the witness can
  mark lost.
- **#5 One process per session, and turns on it run one at a time.** Two
  messages sent at once capture as two turns in order rather than
  interleaving; the process is a `GenServer` under a `DynamicSupervisor`
  found through a `Registry`, both declared in `processes/0`.
- **#6 The socket's principal is a token, never the cookie.** Phoenix's
  session on a socket wants a CSRF token this app does not keep (its
  CSRF defence is the Origin check, `systems/gaia.md` #5); the client
  mints a five-minute socket token at `POST /v1/me/socket-token`, a
  script uses its API token, and `check_origin` against the endpoint's
  own host is the socket's equivalent of the Origin check.
- **#7 The chat model is a setting until the pin lands.**
  `BRAIN_CHAT_MODEL` is a placeholder the witness's pin
  (`ModelPinChanged`, spec §6.4) replaces; its default was chosen for
  being cheap and widely served, not measured.
- **#10 The tools are the resident's memory functions and never a witness operation.** `Oneiroi.Brain.Tools` offers `bookmark_add`, `bookmark_extend`, `bookmark_open`, `bookmark_accept`, `bookmark_decline`, `tag_list`, `tag_propose`, `tag_apply` and `transcript_search` (spec §8's memory table, the part built so far), run against the core's exports under the resident's actor, so the role checks of kumbukumbu #21 hold for a tool call as for a route. A round is one streamed call; tool calls go back as `tool` messages for the next round, up to `BRAIN_TOOL_ROUNDS` (a bound), after which the model's last words stand. Every call the model made is captured in the turn as a `tool` message naming the call and its answer, so the transcript is full (spec §6.3). A tool the model misuses answers in words rather than failing the turn.
- **#12 The identity files are the stable prefix, and first contact is the turn's to record.** `SOUL.md`, `IDENTITY.md`, `USER.md`, `GOALS.md`, `LINKS.md` as written, then the rendered `AGENTS.md`, each a system message and a recorded injection labelled by name, in a fixed order so the cached prefix holds until a file changes (spec §5). The prompt carries the formation line while `formation_until` is ahead of the clock (agathos-daimon #12). After every capture the turn records first contact; the aggregate takes it once. The soul-edit tools (`soul_edit`, `soul_edit_list`, `soul_edit_accept`, `soul_edit_decline`) are the resident's side of the proposal path; `SOUL.md` reaches the prefix rendered with its line markers, and `soul_edit` and `soul_edit_accept` take `cites`, the seed numbers a new or reworded line grew from, checked here against the seeds because the resident system cannot read the character system (agathos-daimon #27, ethos #13).
- **#13 The behaviours are retrieved by memory and shown, never enforced.** The situation is the witness's words, the conversation's tags and the clock; a match injects memory's "how I act" section as `behaviours` with the numbers as refs (kumbukumbu #25). `behaviour_define`, `behaviour_enact` (on the turn in flight) and `behaviour_list` are the resident's; the brain self-tags at turn time, which is cheap and in character.
- **#14 Drafting lives here.** "Write it with me" (spec §6.2) is a call under the `drafting` purpose from `priv/prompts/draft.md` with the files written so far; it returns the content with its model and prompt and writes nothing, so the seed the witness saves names where it came from. It is the brain's because the ledger reaches the resident system for the key, and a system cannot depend on one that depends on it.
- **#15 The chat model is the resident's pin, and a change is told on the next turn.** `row.chat_model` over `BRAIN_CHAT_MODEL` (#7); when `model_told` is false the turn captures `priv/prompts/model_changed.md` as a system message by the platform ahead of the witness's message, once, and records it told (agathos-daimon #15).
- **#16 The sealed session's context is the prefix and nothing else.** The regression run builds it (eunomia #10) from this system's prompt file, with no formation line, and the resident system's identity context (agathos-daimon #18): no index, no behaviours, no transcript, nothing naming a run. It was this system's function until the judgement tools made the brain depend on Eunomia, and a system cannot depend on one that depends on it.
- **#11 Compaction opens the turn that finds the session over the line, with a memory flush first.** When the messages since the last compaction reach `BRAIN_COMPACT_AFTER_MESSAGES` (80, twice the live window, a guess), the turn opens by giving the resident those messages and its tools under `memory_flush.md`, then asks for a summary under `compaction.md` folding in the previous one, and records `Compacted` with the watermark (kumbukumbu #23). Both calls are chat on the ledger. If either fails the turn goes on uncompacted and the next one tries again. Compaction never deletes a message.
- **#17 A wake is a turn opened by the core's note, and the dates are a section of every turn.** `wake/4` implements `Oneiroi.Sunna.Wake` (sunna #12): the note is captured as a system message by the platform in the witness's place, answered under the purpose the caller names (`chat` for a check-in, `free_time` for free time), streamed and captured like any turn. Every turn injects the schedule's `dates_text/1` as `dates` when there is one, with the countdowns derived on that read (sunna #15).
- **#18 The judgement tools are the resident's.** `position_take`, `position_replace`, `position_list`, `dispute_check`, `dispute_settle`, `prediction_log` and `prediction_list` (spec §8's table) run against Eunomia's exports under the resident's actor on the turn in flight, so a position names the session and turn it was taken in; a live check answers in words with the judge's advice and the dispute's ref, or says the judge did not answer in time, and the resident settles it afterwards.
- **#19 Honcho's context is a section, and every captured turn is synced through the bridge.** `Oneiroi.Proteus.context/1` is injected as `honcho` between the dates and the summary when there is any (proteus #15); after capture the turn calls `Oneiroi.Proteus.sync_turn/5` and goes on whatever it answers, because the bridge records its own failure (proteus #13) and a turn captured already is not the bridge's to fail.
- **#20 The figures are a section and two tools.** `Oneiroi.HuginnMuninn.figures_text/1` is injected as `figures` when there is a counter, derived on the read (huginn-muninn #10); `figure_list` and `figure_increment` are the resident's, the increment carrying the resident's actor (huginn-muninn #9, #13).
- **#22 The library's tools are the resident's, and the kinds come from the registry.** `library_search`, `library_cited_by`, `writing_get` (the review copy with references resolved), `writing_discuss` (this session linked to the piece), `document_write`, `document_adopt` and `document_unadopted` (spec §8's table) run against the library's exports under the resident's actor; `document_write`'s description lists the writable kinds from `Oneiroi.Seshat.Kinds` so a new kind reaches the model with its row (seshat #13). Publishing is not a tool: it is the witness's (seshat #19).
- **#29 The character layer is a section and seven tools.** `Oneiroi.Ethos.how_i_act/2` is injected as `character`, the trigger lane (ethos #9) with the vector lane's near matches beside it (ethos #16; the turn passes the resident's actor, so the one embedding is billed to the dyad), with the open seeds counted and the nearest few named, never loaded whole; `habit_define` (with `seed_number` and a note to graduate a seed into it), `habit_cite`, `habit_list`, `seed_plant`, `seed_cite`, `soul_cite` (the turn evidenced a soul line: the line cites it, tags as citations, ethos #14), `seed_wilt` (no note), `seed_graduate` (toward a position or a soul line, with a note) and `seed_list` run against the character layer under the resident's actor; `habit_cite` and `seed_cite` need the turn in flight, as `bookmark_add` does (kumbukumbu #26).
- **#27 The contract rides the prefix, the near-misses are rows, the capacity alarm flags the turn, and the summary is machine-state.** The assembly order is the prompt, the identity files, the `contract` section, then the index and the rest (spec §5, v0.2 P2): the contract and its limits are never scored, budgeted, decayed or compacted, and the section is read fresh on every turn, so a renegotiation lands on the next one; the sealed session reads the same text (eunomia #24). Beside the index's injection the turn records a `near-miss` row for every bookmark the index ranked and did not take, with the reason it lost and no `refs`, so a near-miss is never marked as indexed (kumbukumbu #31, P6). The tokens of the prefix (the prompt, the files, the contract) are summed against `BRAIN_CONTEXT_TOKENS` and a `capacity` row flags the turn at `BRAIN_CAPACITY_ALARM_PERCENT` (both bounds; P9). The compaction summary is written by `priv/prompts/compaction.md` in the third person as the machinery's record and injected under a header that says so, never in the first person as the resident (P1, P24).
- **#28 The trials' terms and the account of a choice are the resident's to read; the prompts stay sealed.** `trial_list` reads the tests' numbers and what passes and fails each, never a prompt; `trial_account` reads the latest run's models, tests, each model's pass rate over the trials fully graded, the favourites and the chat model now, never an answer or a grade (eunomia #12 as narrowed, spec §6.4 P22 and P27). `priv/prompts/model_changed.md` names `trial_account` so a resident told of a pin can ask what informed it.
- **#26 Where it woke is told on the first turn after an import, once.** When the row's `import_told` is false (agathos-daimon #25), `priv/prompts/imported.md` is captured as a platform system message ahead of the turn: the source, whether the attestation held in words (held, failed, or none to check), and the not-transferred names; then `import_told/2`. Captured, so both parties read it, and the witness sees what the resident was told.
- **#25 Revisions are four tools, and a bookmark opens with its revisions.** `revision_add` (a fact or a stance, with a note), `revision_list`, `revision_accept` and `revision_decline` run against memory under the resident's actor (kumbukumbu #30); `bookmark_open` reads the bookmark's words and then every applied or proposed revision on it, so a correction is seen where the memory is and the words are never rewritten.
- **#24 The agreement is a section in the prefix, and reports and the contract are tools.** `Oneiroi.AgathosDaimon.contract_text/1` is injected as `contract` when a version is in force, open or due (agathos-daimon #22, #26), in the always-loaded prefix ahead of the index (#27), so the resident always knows which setting its solo sessions live under (spec §6.3); `contract_propose`, `contract_agree`, `contract_decline` and `contract_renew` are the resident's side of the contract, and `report_file` files a report in the resident's own words (glitnir #9), each with a note the witness reads first.
- **#23 Today's journal is a section and three tools.** `Oneiroi.Seshat.journal_text/1` is injected as `journal` when the day has a row (seshat #23), rendered on that read; `journal_add`, `journal_done` and `journal_read` are the resident's, and the check-in prompt asks for the plan line at the day's first check-in and the wrap line at the last.
- **#21 Under a lapse the policy's model stands in for the pin, and the lapse is told once.** `Oneiroi.Nisaba.lapse/1` on every turn: its model over the pin and the setting, and `priv/prompts/lapsed.md` captured as a system message by the platform ahead of the turn, once per lapse, naming the model, the free time, the term and the day it began (nisaba #17): orientation without impersonation.

## #8 Initial vs target

Initial (P1, slices 2 to 4): #1, over the main session, with the memory
and soul tools, the identity files, the index, the behaviours and
compaction in the context, and drafting. Target: free-time sessions on
their own budget line, sessions opened by wake, the rest of the MCP tool
table by role, the pinned chat model (spec §5).

## #9 Depends on

The ledger for every model call; memory for capture, the transcript and
the context record; the resident system for the resident's name, its
files, its pin and its identity context; the schedule for the dates,
and the schedule reaches back only through its wake port; judgement for
the resident's positions, disputes and predictions, and judgement never
reaches back; the bridge for Honcho's context and the sync, and the
bridge never reaches back; the audits for the figures, and the audits
never reach back; the library for its tools, and the library never
reaches back.
