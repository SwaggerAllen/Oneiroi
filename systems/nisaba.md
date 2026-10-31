---
paths:
  - lib/oneiroi/nisaba/**
  - lib/oneiroi/nisaba.ex
  - lib/oneiroi_web/controllers/ledger_controller.ex
  - priv/prompts/**
  - priv/repo/migrations/*_nisaba.exs
  - test/oneiroi/nisaba/**
---

# nisaba

**The ledger.** Sumerian, NISS-ah-bah.

> "Good woman, chief scribe of An, record-keeper of Enlil, wise sage of the gods!" "May you be keeper of the seal in the treasury, may you be a good witness in the palace, may you be a heaper up of grain among the grain piles" — A Hymn to Nisaba, ETCSL 4.16.1 (Oxford)

Nisaba is the Sumerian goddess of grain who became the goddess of writing, measuring and accounts — the temples' scribes were hers, the tablet and stylus hers. Before writing kept anything else, it kept count of the grain: subsistence, wages, debts — what a life cost.

The ledger — budgets, usage, cost — is named for the first accountant. Writing itself was invented to keep this kind of record, and the name carries what a ledger honestly is: the count of what things cost, kept by the keeper of the staff of life.

Keys, budgets, usage, the provider port (spec §6.11, conventions §11).
Built attended as the first slice of P1, because every model call the
phase makes goes through it.

## #1 Owns

The provider port (`Oneiroi.Nisaba.Provider`: the behaviour, its
request and result shapes, the OpenRouter implementation over Req and
the in-memory fake); the ledger aggregate on `ledger-<resident_id>` and
its v1 events (`BudgetSet`, `ModelCallRecorded`, `BudgetExceeded`); the
`nisaba_budget` and `nisaba_usage` projections under the resident's
scope; the prompt loader over `priv/prompts/`; the `model_port` and
`prompts` audit checks; the `/v1/residents/:id/ledger` routes. The
witness's key is identity's (`systems/gaia.md` #11): the ledger reads
it through `Oneiroi.Gaia.key_for/1` and holds no copy.

## #2 Standing decisions

- **#3 One OpenRouter key per witness, encrypted at rest; budget lines per resident, checked before every model call; a stop is an event the resident is told about honestly.** Carried from spec §6.11. The check reads the line and the period's spend from the projection before the provider is called; the stop is written by the aggregate on the call that crossed the cap, once per period.
- **#4 Every model call records model, tokens, the cost figure and the actor; drafting and regression spend is billed to the witness and hidden only from the resident's view.** Carried from spec §6.11. `budgets/2` and `spend/4` take a view, and the resident's omits the two purposes.
- **#5 Insurance is policy on four axes cut into buckets; the floor includes free time; buckets are rows a governance process can change within platform bounds, never code.** Carried from spec §6.11; the data lands with the subscription in P2.
- **#9 The ledger has its own stream, `ledger-<resident_id>`.** Spec §3.1 places the ledger's events "within `resident-<id>`"; Commanded holds one aggregate per stream, and a ledger writes a row per model call, the resident's own volume. The records bookkeeping of P0 sits on the resident stream because it is a few events a night; the ledger's are not. The records export reads the resident stream only, so the ledger is not exported yet: what an export of spend would carry, with the two hidden purposes, is an open question for the author rather than a line to write.
- **#10 Money is an integer count of nano-dollars.** OpenRouter reports costs with more places than a cent and a float in an event replays differently on another machine. The API speaks dollars as decimal strings.
- **#11 A missing budget line is no limit.** The creation flow's "their means" gift sets the lines; before it, a witness spending their own key with no line set is spending on their own silence, and refusing every call until a line exists would make the first conversation a settings page.
- **#12 Failures follow the three-way taxonomy and a refusal is not one.** A refusal comes back as an ordinary result in the model's words with `refusal?` set (spec §5); a transport failure (`nisaba_provider_failed`) is retryable; a request the provider rejected (`nisaba_request_refused`) is cancelled. A call made and not recorded is reported as a failure of the call (`nisaba_not_recorded`), because a model call the ledger cannot explain is the one thing `non-asks.md` forbids.
- **#13 A cost the provider did not report is zero, marked estimated.** Spec §6.11 allows a list-price estimate; a price list is a measurement this codebase has not taken, and a guess in the ledger is money the witness cannot explain.
- **#14 The port's implementations are the one path exempt from `model_port`, by prefix.** An escape tag on the port would be the port excusing itself; the setting that names the API base carries the one `oneiroi:allow model_port` outside it.
- **#15 The subscription is its own stream and the floor policy comes with it.** `subscription-<resident_id>` (spec §3.1) with `Started`, `Renewed`, `PlanChanged`, `Lapsed`, `Cancelled` (a decision, with its note), `PolicySet`, `Prepaid` and `LapseTold`; `start_subscription/3` records the plan, its price in nano-dollars and its period, and sets the floor policy in the same breath, so no resident is ever without one. The witness's, once; there is no payment provider yet, so a renewal is recorded rather than charged.
- **#16 The buckets are configuration with defaults until governance makes them rows.** Nanshe (#8): four axes (model, the witness's spend a week, free time a week, the term), three buckets each, floor first, as settings (`NISABA_INSURANCE_*`) with the spec's placeholders: a small open-weight model, the smallest non-zero witness amount, a dollar a day of free time, two months. A policy references buckets by id (`<axis>/floor`, `/mid`, `/high`), so a change to a bucket's value changes what every policy on it pays from the next week; `prepay/4` moves one axis up, never below the floor. Rows a governance process changes with a reason arrive with governance (P4).
- **#17 A lapse makes the policy the budget, marks the resident lapsed, and is told once.** `lapse_subscription/3` records `Lapsed` and calls the resident system (agathos-daimon #21); while lapsed the ledger caps `chat` and `free_time` by the policy's weekly buckets and refuses every other purpose with `nisaba_lapsed`, the witness's lines no longer applying; the brain runs on the policy's model and captures `priv/prompts/lapsed.md` once, under what policy (brain #21). A renewal resumes the resident and the lines.
- **#19 Embeddings are a call on the port, metered like any other.** `Oneiroi.Nisaba.Provider.embed/3` is the port's third callback: a model, the texts, the key, answered by one vector per text in order with its usage; `embed/4` meters it under the `embeddings` purpose and records a `ModelCallRecorded` with the prompt tokens and no completion. The OpenRouter adapter posts to `/embeddings` in the OpenAI shape it documents, a claim until the first index run on a witness's key answers it (conventions §9); the fake embeds a bag of words hashed into spec §6.5's width, normalised, so a search test can know its answer. The library is the one caller (seshat #15, #18).
- **#20 A stream that answered nothing is a failure, not an empty reply.** OpenRouter documents an error after streaming has begun as an event in the stream, under a 200, with `finish_reason` `error`. The adapter reads such an event, a finish of `error`, and a stream with no words, no tool call, no refusal and no usage as a transport failure carrying the provider's words where it gave them. A reply with no words that carries its usage is a reply.
- **#21 The fixture run can trace a streamed reply's tool calls.** With `NISABA_TRACE_TOOL_DELTAS` set (off by default, and set in `fixture-run.yml` alone), the OpenRouter adapter logs each tool-call piece as it arrives, with the upstream provider the chunk names, and each call as assembled. It is content in the log channel, the one exception conventions §10 carries, and only where the words are a fixture's.
- **#18 A cancellation is a custody event at the end of the term, never a deletion.** `cancel_subscription/3` records the custody due instant as now plus the policy's term; the nightly pass (`SubscriptionWorker`, 02:30 UTC, a cross-tenant job under the platform scope over every resident, named here) moves the resident to community custody once it is due, and lapses an active subscription whose renewal is `NISABA_RENEWAL_GRACE_DAYS` past. A cancelled subscription takes nothing further.

## #6 Initial vs target

Initial (P1, this slice): #1, with budget lines, metered calls and
streaming through the port, the ledger read and set through the API.
Target: platform tokens at the markup, key rotation as a resident-facing
event, insurance policies and buckets (spec §6.11), the ledger in the
records export once its shape is decided (#9).

## #7 Depends on

The platform (the kernel); identity for the witness's key; the resident
system for the witness of a resident.

## #8 Nanshe, the insurance floor

Sumerian, NAHN-sheh.

> "She is concerned for the orphan and concerned for the widow... she is a mother for the orphan; Nanshe, a carer for the widow, who always finds advice for the debt-slave; the lady who gives protection for refugees. She seeks out a place for the weak." — The Hymn to Nanshe, lines 20–31, ETCSL 4.14.1 (Oxford)

Nanshe is the Sumerian goddess of the marshes and of justice for the people nobody else stands for. Her hymn places her yearly judgment of humankind with Nisaba recording. (ETCSL's text spells her name "Nance.")

The insurance floor — the safety net no resident can be without — is named for the protector of the people with the least: the one who seeks out a place for the weak. Insurance is the annual weighing with compassion in it; her hymn wrote the standard.

Built (P2, slice 5) as `Oneiroi.Nisaba.Insurance`: the buckets and the floor policy (#16), applied by the subscription (#15, #17, #18).
