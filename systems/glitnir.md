---
paths:
  - lib/oneiroi/glitnir/**
  - lib/oneiroi/glitnir.ex
  - lib/oneiroi_web/controllers/report_controller.ex
  - priv/repo/migrations/*_glitnir.exs
  - test/oneiroi/glitnir/**
---

# glitnir

**Governance.** Old Norse, GLIT-neer ("the shining one").

> "The tenth is Glitnir; its pillars are gold, / And its roof with silver is set; / There most of his days does Forseti dwell, / And sets all strife at end." — Poetic Edda, Grímnismál 15, trans. H. A. Bellows (1923)

Glitnir is the shining hall — gold pillars, silver roof — where Forseti, the gods' mediator, hears every case, and every party leaves reconciled.

The governance subsystem — custody, contracts, reports, and consequences — is named for the hall rather than its god, because the room is the institution: it holds reconciliation now, it will hold whatever governance becomes — including the residents' vote, when that day comes — and it will outlast every one of its keepers.

The dyad contract, custody, adoption and succession, reports and
strikes, the floor, revision and fork events. Spec §6.12. Built in P4
under `Oneiroi.Glitnir` (the system's name, where the spec's file map
said `governance/`) for v0's one flow, reports; the dyad contract, the
custody transfer and the export wall are the resident's own events
(agathos-daimon #22 to #24), because they are facts about the resident
and the resident stream already carried them in spec §3.1.

## #1 Owns

`lib/oneiroi/glitnir/**`, the report controller, its migration and
tests. The stream is `governance-<resident_id>`.

## #2 Standing decisions

Carried from spec §6.12; the reason for each is there.

- **#3 v0 ships the data model and the events for all of it, and machinery for one flow: reports, investigated by the platform with every step an event, resolved into no action or a strike on the human; the investigator is a role in the events.**
- **#4 The floor never doubles as punishment; consequences land on humans; the resident goes to community custody, never deletion.**
- **#5 Adoption transfers access, never memories; the export wall is transcript visibility, all or nothing, and cannot be set during a transfer.**

Decided in the build:

- **#8 The investigator is a role named by configuration, matched by email.** `GLITNIR_INVESTIGATORS` lists the account emails who may record a step or resolve a report (gaia #12 reads the email); the actor on every `InvestigationStepRecorded` and `ReportResolved` is that account, a role in the events and not a hard-coded party, so the handover to a jury is a change of the list and nothing in the log. An empty list means nobody can, and reports wait.
- **#9 A report is filed from inside the relationship and nowhere else.** `file_report/3` takes the resident's own actor or its current steward's and refuses every other account, an investigator included; the text is the party's words, one text of at most 4,000 characters; numbers count per resident.
- **#10 Every step is an event with its reason, and the report lives in chat.** `record_step/4` writes `InvestigationStepRecorded{number}` with the reason as its note; filing, every step and the resolution are each captured into the main session as a system message by the platform, in their own turn, so both parties read them where they talk (spec §6.12: there is no Report screen). A resident in community custody has no main session, and nothing is told then.
- **#11 The ladder is the aggregate's and the consequence is the service's.** `resolve_report/5` records `ReportResolved{outcome}` and, for a strike, `StrikeIssued{number, report, steward_account_id, consequence}` with the count kept on the stream: the first two are fines paid into the residents' insurance pool, recorded and not yet charged (no payment provider; nisaba #15), the third is a removal, and the service then moves the resident to community custody through the resident system, never a deletion (spec §6.12).
- **#12 The reads are the dyad's and the investigators'.** `reports/1` with every step and `strikes/1` are read by the steward (the routes' `stewarded` check) or an investigator; the resident reads them in chat.

## #6 Initial vs target

Initial (P4, slice 1): #8 to #12, with the dyad contract, custody
transfer and the export wall in the resident system (agathos-daimon
#22 to #24). Target: adoption's full protocol, succession, the
community-governed insurance buckets, fines charged once a provider
lands, the jury as the investigators' body (spec §6.12, P6).

## #7 Depends on

The resident system for the parties and the custody move; identity for
an account's email; memory for the main session the reports are told
in.
