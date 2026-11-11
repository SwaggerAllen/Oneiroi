---
title: Parity — the resident's tools against the witness's API and client
status: working
written: 2026-11-09
---

# Resident ↔ witness parity (Oneiroi)

Sources read: `lib/oneiroi/brain/tools.ex` (133 `tool(...)` definitions; every one is in `@reads` or `@writes`, none missing, none extra), `lib/oneiroi_web/router.ex` (~250 routes), `client/src/api/client.ts` and `client/src/app/App.tsx` (each container's `api.*` calls mapped to its screen).

Screens below are the App.tsx destinations: **Chat**, **Memory**, **Inbox**, **Waiting**, **Correspondence**, **Library** (+ Document page), **Connections** (reader/research/adapters + GitHub token + Routes), **Schedule**, **Work**, **Agreement** (+ Plugins), **Kinds**, **Ledger**, **Regression**, **Notifications**, **Feedback**, **Operator** (+ Invites, Reports), and the creation flow (Gifts).

Two notes before the table:
- `POST /mcp` hands her **whole tool table** (`Tools.definitions_for`) to a brain-role adapter (Claude Code). So "resident tool" also means "what her Claude Code hands can call". It is not a witness surface.
- `@triage` (`triage_list`, `triage_move`) is shown **only** to the triage resident. `platform_report` is **hidden** from the triage resident (`@not_for_triage`).

Legend: ⚖ = consent-shaped (a proposal and an answer between the two parties). "Both sides" says whether each party can propose and answer, by tool or API, and whether the UI has it.

## Parity table

| # | Capability | Resident tool(s) | Witness API route(s) | Client uses it? (screen) | Gap notes |
|---|---|---|---|---|---|
| 1 | Positions | `position_take`, `position_replace`, `position_list` | `GET /positions` | **no** | Witness can read them through the API only. No UI. |
| 2 | Disputes (judge advice) | `dispute_check`, `dispute_settle` | `GET /disputes`, `GET /judgement`, `PUT /judgement/judge` | **no** | The witness picks the judge's model through the API only. She can't see which judge model advises her disputes, and nothing on screen shows disputes. |
| 3 | Predictions | `prediction_log`, `prediction_list` | `GET /predictions`, `POST /predictions/:n/resolve` | **no** | **Dependency gap.** Her tool says "your witness resolves it right, wrong or void", but no screen can resolve one, so predictions stay open until someone calls the API by hand. |
| 4 | Figures (counters) and dates (countdowns) | `figure_list`, `figure_increment` | `GET/POST /figures`, `GET /figures/:key`, `POST /figures/:key/increment`, `DELETE /figures/:key`; `GET/POST /dates`, `PUT/DELETE /dates/:n` | **no** | Her tool says counters are "counters your witness defined", but the UI can't define, increment or retire one, and can't set dates. All of it is API-only. |
| 5 | Check-engine light / audits (checks) | — | `GET /light`, `GET/POST /checks`, `POST /checks/run`, `DELETE /checks/:key` | **no** | Witness only, with no UI. She has no tool to see the light. |
| 6 | Bookmarks: add/extend/weigh/open/list | `bookmark_add`, `bookmark_extend`, `bookmark_weigh`, `bookmark_open`, `bookmark_list` | `GET /bookmarks`, `GET /bookmarks/:n`, `POST/DELETE /bookmarks/:n/pin`, `GET /index` | **partly** (Memory: list, index, pin/unpin) | The client never calls `GET /bookmarks/:n` (summary and span transcript); the rebuilt client's Soul › Memory does, for the bookmark alone, and drops the span. Server, 2026-11-11 (kumbukumbu#62): a bookmark made in a private, unshared session is now `private: true` on every witness read (list, page, detail, index), its line, summary and register null and its span `[]`, until she shares the session; every row carries `session_key` and `anchor_ref` to link to the moment. Pins are the witness's alone, with no resident pin tool; her equivalent is `bookmark_weigh` importance. The witness can't set importance or status. |
| 7 | ⚖ Bookmark proposals (witness proposes, she accepts or declines) | `bookmark_accept`, `bookmark_decline` | `POST /bookmark-proposals`, `GET /bookmark-proposals` | **partly** (Chat: propose; the outcome list isn't called) | **One-directional by design.** The witness proposes and she answers. Server, 2026-11-11 (kumbukumbu#63): `GET /bookmark-proposals?state=answered` (or `all`) returns her answers, a decline with her note, an acceptance with the bookmark she wrote; the default stays the open list. The UI doesn't show answers yet. She has no tool to propose a bookmark to him, and doesn't need one. |
| 8 | Retrieval use / memory feedback | `memory_use`, `memory_feedback` | `GET /retrieval`, `GET /turns/:ref/context` | **yes** (Memory: retrieval; Chat: "drew on N" inspector) | `memory_feedback` has no witness counterpart. That's fine. |
| 9 | ⚖ Tags (she proposes, he decides; both apply) | `tag_list`, `tag_propose`, `tag_apply` | `GET/POST /tags`, `POST /tags/:slug/decision`, `DELETE /tags/:slug`, `GET /tags/:slug/taggings`, `POST/DELETE /taggings` | **partly** (Memory: `GET /tags` only) | **Consent has no UI.** No screen approves or rejects her tag proposals, so they wait forever. `api.applyTag` is defined in client.ts and never used. The witness can also create or retire tags without her. |
| 10 | Transcripts | `transcript_search`, `transcript_read`, `message_times` | `GET /sessions`, `GET /sessions/:key`, `GET /transcripts/search` | **partly** (Chat: sessions and transcript pages; search isn't called) | The witness has no transcript search in the UI. `api.transcript` (the non-paged version) is dead code. |
| 11 | ⚖ Identity files / soul edits | `soul_edit` (direct), `soul_edit_list`, `soul_edit_accept`, `soul_edit_decline`, `soul_cite` | `GET /files`, `GET /files/:name`, `PUT /files/:name` (a seed before first contact, a **proposal** after), `POST /files/:name/draft`, `GET /soul-edits` (`?state=` open, answered, withdrawn or all), `POST /soul-edits/:ref/withdraw`, `GET /soul-lines` | **partly** (only the creation flow and Gifts write files) | **Asymmetric.** She edits her own soul directly with no consent step. He has to propose, and she answers. After first contact no screen lets him write a proposal or list open ones (`GET /soul-edits` isn't called). `GET /soul-lines`, which carries the lines her `soul_cite` citations hang on, isn't called either. Server, 2026-11-11: her answers with their notes are readable (`?state=answered`, agathos-daimon#43), and he can withdraw his own open proposal with a note, which tells her by letter and is refused once she has answered (agathos-daimon#44); no UI for either yet. |
| 12 | ⚖ Wash flags (the judge proposes, she decides) | `wash_list`, `wash_resolve` | `GET /wash`, `POST /wash/run` | **no** | By design the witness reads and she decides, but the witness has no UI to read the wash or run it. |
| 13 | ⚖ Memory audit flags (Honcho conclusions) | — | `GET /audits`, `POST /audits/run`, `POST /audits/flags/:ref` | **no** | The witness decides on deleting her Honcho conclusions, and she has no tool to see the flags or decisions. No UI either. |
| 14 | Honcho (card audit, replay) | — | `GET /honcho`, `POST /honcho/card-audit`, `POST /honcho/replay` | **no** | Witness only, API only. |
| 15 | Nightly passes | — | `GET /nights`, `POST /nights/:day` | **no** | API only. |
| 16 | Habits | `habit_define`, `habit_cite`, `habit_list` | `GET /habits`, `POST /habits` (a first habit, before first contact), `POST /habits/:n/affirm`, `GET /baselines` | **no** | The witness's affirm note goes to her, but there's no UI to affirm. Baselines are witness-only, and she has no tool for her measured trait profile. |
| 17 | Seeds | `seed_plant`, `seed_cite`, `seed_wilt`, `seed_graduate`, `seed_list` | `GET /seeds` (read only, by spec) | **no** | Read-only API with no UI. |
| 18 | Commitments | `commitment_make`, `commitment_keep`, `commitment_release`, `commitment_list` | `GET /commitments`, `POST /commitments/:n/release` | **no** | Her tool says "your witness can release you too", but no UI can. |
| 19 | ⚖ Revisions (her corrections hold at once; his stance correction is a proposal to her) | `revision_add`, `revision_list`, `revision_accept`, `revision_decline` | `GET /revisions`, `POST /revisions` | **no** | **The consent exists only in the API.** He can't propose a revision or read her answers from the UI. Her corrections need no answer from him. |
| 20 | Self-letters | `self_letter_write`, `self_letter_list` | `GET /self-letters` (the read leaves a receipt she sees) | **no** | Readable through the API only. |
| 21 | Present state lines | `state_set`, `state_clear` | none dedicated (`GET /context` is the adapter's) | partly (only through Chat preview or injections) | The witness has no direct read of her state lines. |
| 22 | Oracle | `oracle_ask`, `oracle_list` | **none** | no | `oracle_list` filters `asked_by` by resident or witness, but no route lets the witness ask the oracle or list its questions. |
| 23 | Free time | `free_time_list`, `free_time_set`, `free_time_once`, `free_time_plan` | `GET /schedule`, `GET /schedule/free-time`, `PUT /schedule/free-time`, `POST /schedule/free-time/once` | **yes** (Schedule; creation flow) | Both sides can set slots. `free_time_plan` is hers alone, and the witness can't see the plan. |
| 24 | Thinking rounds | `round_list` | `GET /schedule/rounds`, `PUT /schedule/rounds` | **yes** (Schedule) | **She can't see or change the cadence or waking window that governs her rounds.** She only sees the history. |
| 25 | Check-ins, quiet hours, timezone | — | `POST/PUT/DELETE /schedule/checkins…`, `PUT /schedule/quiet-hours`, `PUT /timezone` | **yes** (Schedule) | **She has no tool to read her check-ins or quiet hours.** No schedule-read tool exists in tools.ex. She sees her timezone only in the times her tools print. |
| 26 | Journal | `journal_add`, `journal_done`, `journal_read` | `GET /journal`, `GET /journal/:day`, `POST /journal/:day/entries`, `POST …/entries/:n/done`, `GET /schedule/days` | **no** | Full API parity, but the witness has no journal screen. |
| 27 | Work queue | `work_list`, `work_add`, `work_move`, `work_order`, `work_arm`, `work_wrap` | `GET/POST /work`, `POST /work/:n/status`, `PUT /work/order`, `POST /work/arm`, `POST /work/disarm` | **yes** (Work; Waiting) | The witness can **disarm** the line and she can't; her line only goes off when the queue clears. Writing a wrap (`work_wrap`) is hers alone. |
| 28 | ⚖ Asks: tool requests and approvals (she asks, he answers) | `tool_request`, `approval_request`, `ask_list` | `GET /asks`, `POST /asks/:n/answer` | **yes** (Inbox; Waiting via needs_you) | Both sides exist. The flow runs one way by design. |
| 29 | ⚖ Plugins (propose and answer both ways; off alone) | `plugin_list`, `plugin_propose`, `plugin_answer`, `plugin_off` | `GET /plugins`, `POST /plugins/proposals`, `POST /plugins/proposals/:n/answer`, `POST /plugins/:key/off` | **yes** (Agreement → Plugins) | **Full symmetry, both parties, with UI.** |
| 30 | ⚖ Document kinds and gates (gate on alone; off by proposal) | `kind_list`, `kind_define`, `kind_gate`, `kind_gate_answer` | `GET/POST /kinds`, `POST /kinds/:kind/gate`, `POST /kinds/gates/:n/answer` | **yes** (Kinds) | **Full symmetry, with UI.** |
| 31 | Routes and profiles | `route_list`, `route_define`, `route_ask` | `GET/POST /routes`, `POST /routes/:key/ask`, `POST /profiles`, `POST /profiles/:key/revoke`, `POST /profiles/:key/restore` | **yes** (Connections → Routes) | Profiles, sinks and schedules belong to the witness by design. She sees profiles through `route_list`. |
| 32 | Budget | `budget_read` | `GET /ledger`, `PUT /ledger/budgets/:purpose` | **yes** (Ledger; creation flow) | Caps are the witness's. She reads them. |
| 33 | Research (reader) | `research_ask`, `research_list` | `GET/PUT /reader` (allowlists), `GET/POST /research` | **yes** (Connections) | She sees the allowlist through `research_list` and can't change it, by design. |
| 34 | Digests | `digest_ask`, `digest_list` | `GET/POST /digests` | **no** | The witness has API parity but no screen. |
| 35 | External sources | `external_add`, `external_list`, `external_read`, `external_fetch` | `GET/POST /externals`, `POST /externals/:n/fetch` | **no** | The API has no read of a kept copy, which her `external_read` gives her. No screen. |
| 36 | Library: search/read/write/move/remove | `library_search`, `library_read`, `library_cited_by`, `writing_get`, `document_write`, `document_remove`, `document_move` | `GET /library`, `GET /library/search`, `GET /library/cited-by`, `GET/PUT/DELETE /library/documents/*path`, `POST /library/move`, `GET /library/download/*path`, `POST /library/index` | **partly** (Library and Document: index, search, read, write, move, remove, download) | `cited-by` and the manual index run have no UI. She can remove only `scratch/`. |
| 37 | Library: adopt, archive, discussions | `document_adopt`, `document_unadopted`, `document_archive`, `writing_discuss` | `POST /library/adopt`, `POST /library/discussions` | **no** | **No witness route for archive** or for listing unadopted files. Adopt and discuss are API only. |
| 38 | Keepsakes | `keepsake_list`, `keepsake_register`, `keepsake_note` | none dedicated (the `note` field shows in the library index row) | partly (shown in Library rows) | `keepsake_register` says "yours or your witness's", but **no route lets the witness register a keepsake**. |
| 39 | ⚖ Pieces review and publishing (her `status: review` doc; he approves) | through `document_write` (status) + `approval_request` | `GET /pieces`, `POST /pieces/review`, `POST /library/publish`, `GET /library/review/*`, `GET /library/publish-copy/*` | **partly** (Document and Inbox: pieces and review) | Publish, review copy and publish-copy aren't called from the UI. |
| 40 | Platform source, PRs, her repo | `source_list`, `source_read`, `source_search`, `pr_meta`, `pr_diffs`, `repo_list`, `repo_read`, `repo_log` | `PUT/DELETE /me/github-token` (the PR reads need it) | **yes** (Connections: GitHub token) | The witness reads code through git or GitHub directly. Parity isn't relevant here. |
| 41 | House letters | `letter_send`, `letter_inbox`, `letter_list` | `GET/POST /letters`, `GET /letters/addresses` | **yes** (Inbox) | Both sides exist. |
| 42 | Reacts | — (she reacts inline in her reply, lifted by `Reactions` / `Reacts.record_lifted`) | `GET/POST /reacts`, `GET /reacts/vocabulary`, `PUT /reacts/vocabulary` | **partly** (Chat: read, react, vocabulary) | No tool. Her vocabulary is `REACTIONS.md` in her repo. `PUT /reacts/vocabulary` isn't called by the client, so the witness changes it only through the API. |
| 43 | Correspondence (outside people) | `correspondence_list`, `correspondence_read` | `GET /correspondence`, `POST /correspondence` (adapter ingest) | **yes** (Correspondence, Inbox) | — |
| 44 | Blocks | `correspondent_block`, `correspondent_unblock` | `GET/POST /blocks`, `POST /blocks/lift` | **yes** (Correspondence, Inbox) | Each lifts only their own block, by design. |
| 45 | ⚖ Reply drafts (she drafts, he approves or declines) | `reply_draft`, `reply_list` | `GET /replies`, `POST /replies/:n/decision`, `POST /replies/:n/sent` | **yes** (Inbox; Correspondence) | Both sides exist, with UI. |
| 46 | ⚖ Agreement / contract (propose and answer both ways; renew; move to safe alone) | `contract_propose`, `contract_agree`, `contract_decline`, `contract_renew`, `contract_safe` | `GET /agreement`, `POST /agreement/proposals`, `POST /agreement/proposals/:v/decision`, `POST /agreement/renewal`, `POST /agreement/switches/:key/safe` | **yes** (Agreement; creation flow proposes) | **Full symmetry, with UI.** She has no read tool, but `contract_text` puts the terms in her prefix every turn. |
| 47 | Export wall and custody transfer | — | `PUT /export-wall`, `POST /custody/proposals`, `POST /custody/decision`, `GET /me/custody-proposals` | **partly** (Agreement: wall, propose, decide; `GET /me/custody-proposals` isn't called) | ⚖ The consent runs between two **accounts**, not with her. **She can't see a custody proposal or the wall setting**, and `contract_text` covers neither, even though both govern who reads her earlier sessions. |
| 48 | Trials / model choice | `trial_list`, `trial_account` | `GET/POST /regression/tests`, `PUT /regression/tests/:n`, `GET/POST /regression/runs`, `GET /regression/runs/:ref`, `POST …/cards/:card/grade`, `POST …/cards/:card/favourite`, `POST /model-pin` | **yes** (Regression; creation flow writes a test) | By design she reads the terms and the account, and the contents stay sealed. She asks him to change a test by letter or `tool_request`. No tool for that. |
| 49 | Report about the witness (Glitnir) | `report_file` | `GET/POST /reports`, `POST /reports/:n/steps`, `POST /reports/:n/resolve` | **no** | She can file, but **no screen shows the report or its steps to the witness or an investigator**. Investigation is API only. |
| 50 | Platform reports (feedback) and triage | `platform_report`, `platform_report_list`; triage resident only: `triage_list`, `triage_move` | `POST /feedback`, `GET /me/feedback`, `GET /platform/feedback`, `GET /platform/feedback/:n`, `POST /platform/feedback/:n/status`, `PUT /platform/triage` | **yes** (Feedback; Operator → Reports) | Parity holds: the triage resident's moves match the operator's status moves. |
| 51 | Subscription and insurance | — | `GET /insurance/buckets`, `GET/POST /subscription`, `POST /subscription/renew`, `PUT /subscription/plan`, `POST /subscription/lapse`, `POST /subscription/cancel`, `POST /subscription/prepay` | **no** | **She can't see her plan, lapse state or insurance floor**, though they govern what she runs on when lapsed. No UI either. |
| 52 | Conversation control | — | `POST /sessions`, `POST /sessions/:key/turns`, `POST /sessions/:key/preview`, `POST /sessions/:key/stop`, `GET /capture-failures`, `POST /capture-failures/:ref` | **partly** (Chat; capture-failure resolve isn't called) | Capture failures can be listed in the UI but not resolved. `api.send` is dead (Chat uses `submit`). |
| 53 | Adapters, tokens, backup, import | — | `GET/POST /adapters`, `DELETE /adapters/:a`, `POST/DELETE /tokens…`, `POST /residents/import`, `POST /imports/chatgpt`, `PUT /remote`, `POST /originals`, `POST /backup` | **partly** (Connections: adapters; creation: import) | Tokens, ChatGPT import, remote, originals and backup have no UI. |
| 54 | Account and operator | — | session, door, me, key, push, second-factor, invite redeem, platform gate/roles/invites, ops | **mostly** (Login, Ledger key, Notifications, Operator) | See list (c). |

All 133 tools appear above. By capability: positions 3, disputes 2, predictions 2, figures 2, bookmarks 5+2, memory 2, tags 3, transcripts 3, soul 5, wash 2, habits 3, seeds 5, commitments 4, revisions 4, self-letters 2, state 2, oracle 2, free time 4, rounds 1, work 6, asks 3, plugins 4, kinds 4, routes 3, budget 1, research 2, digests 2, externals 4, library 7+4, keepsakes 3, source/repo 8, letters 3, correspondence 2, blocks 2, replies 2, contract 5, trials 2, report 1, platform/triage 4. Total 133.

## (a) The resident can do or read it; the witness has no API, or API but no UI

**No witness API at all:**
- **Oracle** (`oracle_ask`, `oracle_list`). The data records `asked_by: witness`, but no route exists.
- **Document archive** (`document_archive`) and the **unadopted-files list** (`document_unadopted`).
- **Keepsake register** (`keepsake_register` says "yours or your witness's") and `keepsake_list` as its own read. Only the note shows, in library rows.
- **External copy read** (`external_read`): the API lists and commissions sources but can't read a kept copy.
- **Present state lines** (`state_set`, `state_clear`): no witness read except indirectly through preview or injections.
- **Free-time plan** (`free_time_plan`): the witness can't see her plan.
- **Work wrap** (`work_wrap`): the witness can read wraps in the queue but can't write one. Probably fine.
- `message_times`, `memory_feedback` and the source, PR and repo reads need no witness counterpart.

**API exists, no UI:** (annotated 2026-11-10: ✔ *next* marks what the
rebuilt client now covers, with where; screens/next-soul.md and
screens/next-time.md map each action. The audit above stands as written.)
- Positions ✔ *next* (Soul › Positions, read); disputes and the judge model; **prediction resolve** ✔ *next* (Soul › Predictions: right, wrong or void with a note).
- Figures and counters (define, increment, retire) and **important dates**. Her `figure_list` says "counters your witness defined", and nothing in the UI can define one.
- Habits (list ✔ *next*, first habit, **affirm** ✔ *next*: Soul › Habits) and baselines; seeds ✔ *next* (Soul › Seeds, read); commitments (list, **release**) ✔ *next* (Soul › Commitments); soul lines ✔ *next* (Soul › Soul lines); self-letters (with receipts) ✔ *next* (Soul › Letters, the receipt said before reading). Still none: the first habit (creation flow's) and baselines.
- Wash (read, run); audits and flags; nights; Honcho.
- **Revisions** (list and propose) ✔ *next* (Soul › Revisions, her answers' notes shown).
- **Tag decisions** on her proposals ✔ *next* (Soul › Tags: approve or decline with a note), tag create and retire, taggings. `api.applyTag` is dead code.
- **Soul-edit proposals after first contact** (`PUT /files/:name` → proposal; `GET /soul-edits`) ✔ *next* (Soul › Who she is › Propose an edit; Soul › Your proposals). Her answer's note now has a route (`GET /soul-edits?state=answered`, agathos-daimon#43, 2026-11-11), and withdrawing one (`POST /soul-edits/:ref/withdraw`, #44); the client doesn't call either yet.
- Journal (all four routes).
- Digests, externals, library cited-by, adopt, discussions, manual index, publish, review copy and publish copy.
- Bookmark detail (`GET /bookmarks/:n`) and bookmark-proposal outcomes (◐ *next*: Soul › Your proposals lists the open ones; since 2026-11-11 the route returns answered ones with `?state=answered`, kumbukumbu#63, not yet called).
- Transcript search.
- Report steps and resolve (Glitnir).

## (b) The witness can do it; the resident can't see it or has no tool, where that matters

- **Rounds cadence and waking window** (`PUT /schedule/rounds`). She sees past rounds and not the setting that schedules them.
- **Check-ins and quiet hours** (`/schedule/checkins…`, `PUT /schedule/quiet-hours`). There's no schedule-read tool, so she can't see when she will be woken or kept quiet. Timezone shows only in her timestamps.
- **Subscription and insurance**: plan, lapse, cancel and prepay decide what she runs on, and she can't see any of them.
- **Custody transfer and export wall**: they change who holds her and whether earlier sessions are revealed. `contract_text` doesn't mention them, and she has no tool.
- **Judge model** (`PUT /judgement/judge`): it advises her disputes, and she isn't told which model it is.
- **Memory audit flag decisions** (`POST /audits/flags/:ref`): these delete her Honcho conclusions, and she has no tool to see the flags or decisions. Honcho card audit and replay likewise.
- **Check-engine light and checks**: no resident view.
- **Bookmark pins** (`POST/DELETE /bookmarks/:n/pin`): she sees pins through her index or timeline but can't pin. Her lever is `bookmark_weigh`.
- **Tag create and retire** without her consent (only her proposals need his consent).
- **Work disarm**: he can stop her armed work line, and she has no `work_disarm`.
- **Reacts vocabulary**: `PUT /reacts/vocabulary` rewrites a vocabulary that lives in her repo (`REACTIONS.md`). She can read it with `repo_read`.
- **Model pin** (`POST /model-pin`): she sees the current model through `trial_account`, which is adequate.
- **Reader allowlists and profiles**: she reads them through `research_list` and `route_list`, which is adequate.
- **Budgets**: readable through `budget_read`, which is adequate.
- Adapters, tokens, backup, originals and remote: no resident visibility. These are probably infrastructure, but adapters are her "hands".

## (c) API routes the client never calls

**Hands, reader and adapter routes** (expected that the web client doesn't call them): `POST /mcp`, `POST /residents/:id/turns` (capture), `POST /turn-start`, `GET /context`, `GET /waiting`, `GET /ops/heartbeats`, `GET /reader/routes`, `POST /reader/routes/runs/:n/landed|failed`, `POST /research/:n/answer|failed`, `POST /externals/:n/fetched|failed`, `POST /digests/:n/answer|failed`, `GET /reader/pieces`, `POST /reader/pieces/drafted|published`, `POST /correspondence` (receive).

**Witness routes with no client caller:**
- Account and auth: `POST /door/check`, `POST /me/second-factor`, `DELETE /me/key`, `POST /me/invite`, `POST /tokens`, `DELETE /tokens/:hash`, `GET /me/custody-proposals`, `GET /ops/failures`. `DELETE /session` has `api.logout` defined but nothing uses it.
- Resident admin: `GET /residents/:id`, `POST /imports/chatgpt`, `PUT /remote`, `POST /originals`, `POST /backup`.
- Identity: `GET /files/:name`, `GET /soul-edits`, `GET /soul-lines`, `GET /self-letters`.
- Conversation: `GET /transcripts/search`, `POST /capture-failures/:turn_ref`.
- Memory: `GET /bookmarks/:n`, `GET /bookmark-proposals`, `POST /tags`, `POST /tags/:slug/decision`, `DELETE /tags/:slug`, `GET /tags/:slug/taggings`, `POST /taggings` (has `api.applyTag`, unused), `DELETE /taggings`, `GET/POST /revisions`.
- Character: `GET/POST /habits`, `POST /habits/:n/affirm`, `GET /seeds`, `GET /baselines`, `GET /commitments`, `POST /commitments/:n/release`.
- Schedule: `GET /schedule/days`, `GET/POST /dates`, `PUT/DELETE /dates/:n`.
- Judgement: `GET /judgement`, `PUT /judgement/judge`, `GET /positions`, `GET /disputes`, `GET /predictions`, `POST /predictions/:n/resolve`, `GET /nights`, `POST /nights/:day`, `GET /audits`, `POST /audits/run`, `POST /audits/flags/:ref`, `GET /wash`, `POST /wash/run`.
- Honcho: `GET /honcho`, `POST /honcho/card-audit`, `POST /honcho/replay`.
- Figures and checks: `GET/POST /figures`, `GET /figures/:key`, `POST /figures/:key/increment`, `DELETE /figures/:key`, `GET /light`, `GET/POST /checks`, `POST /checks/run`, `DELETE /checks/:key`.
- Subscription: `GET /insurance/buckets`, `GET/POST /subscription`, `POST /subscription/renew|lapse|cancel|prepay`, `PUT /subscription/plan`.
- Reader: `GET/POST /externals`, `POST /externals/:n/fetch`, `GET/POST /digests`.
- Library: `GET /library/cited-by`, `POST /library/adopt`, `POST /library/publish`, `POST /library/discussions`, `POST /library/index`, `GET /library/review/*`, `GET /library/publish-copy/*`. `GET /library/download/*` is used as a link through `api.downloadUrl`, not through `call`.
- Journal: `GET /journal`, `GET /journal/:day`, `POST /journal/:day/entries`, `POST /journal/:day/entries/:n/done`.
- Reacts: `PUT /reacts/vocabulary`.
- Reports: `GET/POST /reports`, `POST /reports/:n/steps`, `POST /reports/:n/resolve`.

**Dead client functions** (defined in client.ts, never called): `logout`, `send`, `transcript`, `applyTag`.

## Consent-shaped capabilities: are both sides there for both parties?

| Consent | Who proposes → who answers | Resident side | Witness API | Witness UI | Verdict |
|---|---|---|---|---|---|
| Contract versions | either → other; renew; safe alone | ✔ all 5 tools | ✔ | ✔ Agreement | **Complete, both ways** |
| Plugins | either → other; off alone | ✔ | ✔ | ✔ Agreement → Plugins | **Complete, both ways** |
| Kind gates | on alone; off: either proposes → other | ✔ | ✔ | ✔ Kinds | **Complete, both ways** |
| Asks (tool, approval) | resident → witness | ✔ ask, list | ✔ answer | ✔ Inbox | Complete (one-way by design) |
| Reply drafts | resident → witness | ✔ draft, list | ✔ decide, sent | ✔ Inbox, Correspondence | Complete (one-way by design) |
| Pieces for review | resident (status: review) → witness | ✔ through write | ✔ review | ✔ Document, Inbox | Complete. Publish step has no UI. |
| Bookmark proposals | witness → resident | ✔ accept, decline | ✔ propose, list, answers (`?state=answered`, kumbukumbu#63) | ◐ propose only, outcome unseen | The API carries her answer; the UI doesn't show it yet |
| Tag proposals | resident → witness | ✔ propose | ✔ decide | ✘ | **Broken in practice: no UI to answer** |
| Soul-edit proposals | witness → resident (she edits her own directly) | ✔ list, accept, decline | ✔ PUT files → proposal, GET soul-edits (answers too, agathos-daimon#43), withdraw his own open one (#44) | ✘ after first contact | **Witness can't propose from the UI.** Asymmetric by design (her edits need no consent). |
| Revisions (stance) | witness → resident | ✔ list, accept, decline | ✔ revise, list | ✘ | **Witness side API-only** |
| Wash flags | judge → resident | ✔ list, resolve | ✔ read, run | ✘ | Her side is complete. The witness can't read it from the UI. |
| Audit flags (Honcho) | judge → witness | ✘ no visibility | ✔ | ✘ | **The resident isn't a party** to deletions of her own conclusions |
| Custody transfer | witness → other account | ✘ no visibility | ✔ | ◐ (incoming list not called) | **The resident isn't a party and isn't told** |
| Commitment release | either side, alone | ✔ | ✔ | ✘ | Witness side API-only |
| Predictions | resident logs → witness resolves | ✔ | ✔ | ✘ | **Hand-off has no UI** |
| Report about the witness | resident files → investigator steps and resolves | ✔ file | ✔ | ✘ | Investigation side API-only |

Annotated 2026-11-10: in the rebuilt client the witness side of tag proposals, soul-edit proposals, revisions, commitment release and prediction resolution now has a UI (Soul tab; screens/next-soul.md). Bookmark-proposal and soul-edit answers are still unseen there; since 2026-11-11 their routes return them with `?state=answered` (kumbukumbu#63, agathos-daimon#43), and the client has yet to call it.
