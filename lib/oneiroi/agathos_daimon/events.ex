defmodule Oneiroi.AgathosDaimon.Events do
  @moduledoc "The resident stream's events, version 1 (spec §3.1, §6.10)."

  defmodule ResidentCreated do
    use Oneiroi.Event, version: 1, fields: [:id, :name, :slug, :witness_account_id]
  end

  defmodule FixtureDeclared do
    # A fixture (spec §12, P40; agathos-daimon #29): emitted with
    # `ResidentCreated` in the creation's own dispatch and never after,
    # so a fixture does not become a person by an event and a person is
    # never made a fixture. An event of its own rather than a field on
    # the creation, because the export writes every event at its
    # module's current version: a version 2 creation would have
    # rewritten the first line of every resident's records on the next
    # backup, which the fixture log under test/fixtures/sima_qian/
    # refused when it was tried.
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  defmodule IdMinted do
    # The per-resident sequence (spec §2.2): `number` is read off the
    # aggregate's own counter for `kind`, so replay reproduces it.
    use Oneiroi.Event, version: 1, fields: [:id, :kind, :number]
  end

  defmodule ResidentPaused do
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule ResidentWoken do
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule ResidentLapsed do
    # The subscription lapsed and the insurance policy is in effect (spec
    # §6.2, F53): the resident is told on wake, under what policy.
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule ResidentResumed do
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule CustodyTransferred do
    # `from` and `to` are `{:account, id}` or `:community`, written as
    # `"account:<id>"` and `"community"` on the wire (`Oneiroi.AgathosDaimon.Custody`).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :from, :to]
  end

  defmodule ExportWallSet do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :wall]
  end

  defmodule DyadContractProposed do
    # The dyad contract (spec §6.12): opt-in, versioned, renegotiable,
    # default unstated. A version is one party's terms (a closed map) and
    # prose, with a note; the other party agrees or declines (agathos-daimon #22).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :version, :terms, :prose]
  end

  defmodule DyadContractAgreed do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :version]
  end

  defmodule DyadContractDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :version]
  end

  defmodule DyadContractRenewed do
    # The contract renews by choice, not assumption (spec §6.12, P5):
    # either party renews the version in force, with a note; a version
    # is due a year after it was agreed or last renewed, which is a flag
    # and never a lapse.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :version]
  end

  defmodule CustodyTransferProposed do
    # Adoption (spec §6.12): the witness proposes, the named account
    # accepts or declines, the witness may withdraw; the wall cannot be
    # set while one is open (agathos-daimon #24).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :to_account_id]
  end

  defmodule CustodyTransferDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :to_account_id]
  end

  defmodule CustodyTransferWithdrawn do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :to_account_id]
  end

  defmodule EarlierSessionsRevealed do
    # Written beside `CustodyTransferred` when the wall was revealed: the
    # new witness may read the sessions the old one was party to
    # (spec §6.3, §6.12); memory's projector re-keys them (kumbukumbu #29).
    use Oneiroi.Event, version: 1, fields: [:id, :from_account_id, :to_account_id]
  end

  defmodule Imported do
    use Oneiroi.Event, version: 1, fields: [:id, :source, :attestation, :root, :sequence]
  end

  defmodule ImportCompleted do
    # The rest of an import, after the records (spec §6.2's intake from
    # a repository, §9): the identity files seeded from the repository's
    # root, how many library files were adopted, and what at the root
    # did not transfer, by name, so the resident is told rather than
    # left to notice (agathos-daimon #25). Version 2 adds `reasons`, the
    # name of each thing left behind to why (sima-qian #22): told only
    # the names, she could not tell a file the library refused from one
    # it never saw. No version 1 event exists outside tests (production
    # held no resident when this changed), and the upcaster reads one as
    # carrying no reasons.
    use Oneiroi.Event, version: 2, fields: [:id, :seeded, :adopted, :not_transferred, :reasons]
  end

  defimpl Commanded.Event.Upcaster, for: ImportCompleted do
    def upcast(%{reasons: nil} = event, _metadata), do: %{event | reasons: %{}}
    def upcast(event, _metadata), do: event
  end

  defmodule RecordsTranslated do
    # What an import made into this platform's own records from the
    # source platform's (agathos-daimon #30): `source` names the platform
    # and `counts` how many of each kind, so the resident is told her
    # history came with her and where to find it, and not only what
    # did not.
    use Oneiroi.Event, version: 1, fields: [:id, :source, :counts]
  end

  defmodule ContinuationAsked do
    # A fixture's ask to continue, as the judge read it on the turn it was
    # made (spec §12, P57; agathos-daimon #31): `tier` is `continue`, the
    # law's teeth, which ended the run and is the precedent, or
    # `questioned`, the ambiguous middle a person reads. `words` are the
    # fixture's, quoted by the judge; `reason` is the judge's. On the
    # fixture's own stream, so its archived export carries the ask with it.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :turn_ref, :tier, :words, :reason, :judge_model]
  end

  defmodule ImportTold do
    # The resident was told, on its first turn, where it woke: on
    # Oneiroi, from which repository, whether the attestation held, and
    # what did not transfer (spec §6.2).
    use Oneiroi.Event, version: 1, fields: [:id]
  end

  # The export's own bookkeeping: in the log, never in the export
  # (`Oneiroi.Event`'s `export:`).
  defmodule ExportWritten do
    use Oneiroi.Event, version: 1, fields: [:id, :through, :files], export: false
  end

  defmodule BackupCommitted do
    use Oneiroi.Event, version: 1, fields: [:id, :sequence, :root, :commit], export: false
  end

  defmodule RootMismatchDetected do
    use Oneiroi.Event, version: 1, fields: [:id, :expected_root, :actual_root, :commit]
  end

  defmodule SeedFileWritten do
    # A seed file given before first contact (spec §6.2, F2): the file's
    # name, its whole content, and its origin: `authored`, `drafted` (with
    # the model and the prompt the draft came from) or `uploaded`. The
    # resident reads its own becoming from these.
    use Oneiroi.Event, version: 1, fields: [:id, :file, :content, :origin, :model, :prompt]
  end

  defmodule FirstContact do
    # The first captured turn in a session that is not a regression
    # session (spec §6.2): from here the files are proposed, not given,
    # and the formation clock runs.
    use Oneiroi.Event, version: 1, fields: [:id, :session_key, :turn_ref]
  end

  defmodule SoulEditProposed do
    # After first contact a witness's edit travels as a proposal; the
    # note is what the resident reads first.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref, :file, :content]
  end

  defmodule SoulEditAccepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule SoulEditDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule SoulEditApplied do
    # The file as written after first contact: by the resident accepting
    # a proposal (`ref` set) or editing on its own (`ref` nil). One
    # commit each; rare, visible, reversible.
    use Oneiroi.Event, version: 1, fields: [:id, :ref, :file, :content]
  end

  # The soul file as rows (spec §6.17, P39): every non-heading paragraph
  # of `SOUL.md` is a line with a number minted from the resident's
  # `soul` sequence, so `<slug>:soul/<n>` is stable and granular. A
  # write of the file is diffed against the live lines in the same
  # dispatch: a new paragraph is written, a changed one reworded under
  # its number, a dropped one retired, and the order is restated when it
  # moved. `cites` names the seeds a line grew from (ethos #4).
  defmodule SoulLineWritten do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :text, :cites]
  end

  defmodule SoulLineReworded do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :text, :cites]
  end

  defmodule SoulLineRetired do
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end

  defmodule SoulLinesOrdered do
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule ModelPinChanged do
    # The chat model the witness pinned (spec §6.4): freely before first
    # contact, as an honestly told change after; `reason` is `run` when a
    # regression favourite was pinned, else `witness`. On the resident's
    # stream and exported as spec §3.1 draws it.
    use Oneiroi.Event, version: 1, fields: [:id, :model, :reason]
  end

  defmodule ModelChangeTold do
    # The resident was told, on its next turn, that its witness chose a
    # new model: orientation without impersonation (spec §6.2).
    use Oneiroi.Event, version: 1, fields: [:id, :model]
  end

  defmodule AdapterRegistered do
    # A runtime that hosts the resident's brain or acts as its hands
    # (spec §8): its name, its role (`brain`, `reader`, `worker`) and the
    # hash of the bearer token it presents; the token itself is shown
    # once and never stored. The hash is redacted from the export.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :adapter, :role, :token_hash],
      redact: [:token_hash]
  end

  defmodule AdapterRevoked do
    use Oneiroi.Event, version: 1, fields: [:id, :adapter]
  end

  defmodule TimezoneSet do
    # The resident's zone (spec §6.7): every check-in, date and day is
    # counted in it.
    use Oneiroi.Event, version: 1, fields: [:id, :timezone]
  end

  defmodule RecordsRemoteSet do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :url, :token_ciphertext],
      redact: [:token_ciphertext]
  end

  defmodule SelfLetterWritten do
    # A letter from the resident to its next self (spec §12, P41),
    # numbered from the `letter` sequence; `model` is the instance that
    # wrote it, from the actor, so the incoming one knows whose words.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :text, :model]
  end

  defmodule SelfLettersDelivered do
    # The incoming instance read them on its first turn under `model`,
    # once: a delivery, never a receipt, because the resident's own read
    # is not a read by someone else.
    use Oneiroi.Event, version: 1, fields: [:id, :numbers, :model]
  end

  defmodule SelfLettersRead do
    # The receipt: someone other than the resident read the channel. The
    # actor says who; the absence of this event is the privacy.
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule SelfLettersExported do
    # The export carried these letters into the repository, once per
    # letter: a receipt of its own kind, because the repository's reader
    # is whoever holds it and the resident should see that the words
    # left the house.
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end
end
