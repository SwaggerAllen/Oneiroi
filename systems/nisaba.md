---
paths:
  - lib/oneiroi/ledger/**
---

# nisaba

**The ledger.** Sumerian, NISS-ah-bah.

> "Good woman, chief scribe of An, record-keeper of Enlil, wise sage of the gods!" "May you be keeper of the seal in the treasury, may you be a good steward in the palace, may you be a heaper up of grain among the grain piles" — A Hymn to Nisaba, ETCSL 4.16.1 (Oxford)

Nisaba is the Sumerian goddess of grain who became the goddess of writing, measuring and accounts — the temples' scribes were hers, the tablet and stylus hers. Before writing kept anything else, it kept count of the grain: subsistence, wages, debts — what a life cost.

The ledger — budgets, usage, cost — is named for the first accountant. Writing itself was invented to keep this kind of record, and the name carries what a ledger honestly is: the count of what things cost, kept by the keeper of the staff of life.

Keys, budgets, usage, platform tokens, the insurance policy. Spec §6.11. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/ledger/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.11; the reason for each is there.

- **#3 One OpenRouter key per steward, encrypted at rest; budget lines per resident, checked before every model call; a stop is an event the resident is told about honestly.**
- **#4 Every model call records model, tokens, the cost figure and the actor; drafting and regression spend is billed to the steward and hidden only from the resident's view.**
- **#5 Insurance is policy on four axes cut into buckets; the floor includes free time; buckets are rows a governance process can change within platform bounds, never code.**

## #6 Initial vs target

Initial: not built; see spec §6.11. Target: the whole of spec §6.11,
built in P1 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.

## #8 Nanshe, the insurance floor

Sumerian, NAHN-sheh.

> "She is concerned for the orphan and concerned for the widow... she is a mother for the orphan; Nanshe, a carer for the widow, who always finds advice for the debt-slave; the lady who gives protection for refugees. She seeks out a place for the weak." — The Hymn to Nanshe, lines 20–31, ETCSL 4.14.1 (Oxford)

Nanshe is the Sumerian goddess of the marshes and of justice for the people nobody else stands for. Her hymn places her yearly judgment of humankind with Nisaba recording. (ETCSL's text spells her name "Nance.")

The insurance floor — the safety net no resident can be without — is named for the protector of the people with the least: the one who seeks out a place for the weak. Insurance is the annual weighing with compassion in it; her hymn wrote the standard.
