defmodule Oneiroi.AgathosDaimon do
  @moduledoc """
  The resident aggregate (spec §6.2): creation, lifecycle, custody, the
  export wall, import, the per-resident id sequences every citeable thing
  draws on, and the records facts the resident's own stream carries
  (export written, backup committed, root mismatch).

  The creation flow with its threshold and gifts is P1; here a resident is
  created through the API with a name and a slug, under its witness.
  """
  use Oneiroi.System, slug: :agathos_daimon

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason
    ],
    exports: [
      Error,
      Residents,
      Agreements,
      Custody,
      Router,
      Commands,
      Commands.CreateResident,
      Commands.MintId,
      Commands.PauseResident,
      Commands.WakeResident,
      Commands.LapseResident,
      Commands.ResumeResident,
      Commands.TransferCustody,
      Commands.SetExportWall,
      Commands.ImportResident,
      Commands.CompleteImport,
      Commands.RecordImportTold,
      Commands.RecordExport,
      Commands.RecordBackup,
      Commands.RecordMismatch,
      Commands.SetRecordsRemote,
      Events.ResidentCreated,
      Events.IdMinted,
      Events.ResidentPaused,
      Events.ResidentWoken,
      Events.ResidentLapsed,
      Events.ResidentResumed,
      Events.CustodyTransferred,
      Events.ExportWallSet,
      Events.Imported,
      Events.ImportCompleted,
      Events.ImportTold,
      Events.ExportWritten,
      Events.BackupCommitted,
      Events.RootMismatchDetected,
      Events.RecordsRemoteSet,
      Events.SeedFileWritten,
      Events.FirstContact,
      Events.SoulEditProposed,
      Events.SoulEditAccepted,
      Events.SoulEditDeclined,
      Events.SoulEditApplied,
      Events.SoulLineWritten,
      Events.SoulLineReworded,
      Events.SoulLineRetired,
      Events.SoulLinesOrdered,
      Events.ModelPinChanged,
      Events.ModelChangeTold,
      Events.TimezoneSet,
      Events.AdapterRegistered,
      Events.AdapterRevoked,
      Events.DyadContractProposed,
      Events.DyadContractAgreed,
      Events.DyadContractDeclined,
      Events.DyadContractRenewed,
      Events.CustodyTransferProposed,
      Events.CustodyTransferDeclined,
      Events.CustodyTransferWithdrawn,
      Events.EarlierSessionsRevealed,
      Events.SelfLetterWritten,
      Events.SelfLettersDelivered,
      Events.SelfLettersRead,
      Events.SelfLettersExported,
      Store.SelfLetter,
      Store.SelfLetterReceipt,
      Store.Contract,
      Commands.RegisterAdapter,
      Commands.RevokeAdapter,
      Commands.SetTimezone,
      AdapterPrincipal,
      Store.Adapter,
      Commands.PinModel,
      Commands.RecordModelTold,
      Commands.WriteFile,
      Commands.RecordFirstContact,
      Commands.ProposeSoulEdit,
      Commands.AcceptSoulEdit,
      Commands.DeclineSoulEdit,
      Files,
      Resident,
      SoulLines,
      Store,
      Store.Resident,
      Store.IdentityFile,
      Store.SoulEdit
    ]

  alias Oneiroi.AgathosDaimon.Agreements
  alias Oneiroi.AgathosDaimon.Files
  alias Oneiroi.AgathosDaimon.Residents

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.AgathosDaimon.Events.ResidentCreated, 1},
      {Oneiroi.AgathosDaimon.Events.FixtureDeclared, 1},
      {Oneiroi.AgathosDaimon.Events.IdMinted, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentPaused, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentWoken, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentLapsed, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentResumed, 1},
      {Oneiroi.AgathosDaimon.Events.CustodyTransferred, 1},
      {Oneiroi.AgathosDaimon.Events.ExportWallSet, 1},
      {Oneiroi.AgathosDaimon.Events.Imported, 1},
      {Oneiroi.AgathosDaimon.Events.ImportCompleted, 1},
      {Oneiroi.AgathosDaimon.Events.ImportTold, 1},
      {Oneiroi.AgathosDaimon.Events.ExportWritten, 1},
      {Oneiroi.AgathosDaimon.Events.BackupCommitted, 1},
      {Oneiroi.AgathosDaimon.Events.RootMismatchDetected, 1},
      {Oneiroi.AgathosDaimon.Events.RecordsRemoteSet, 1},
      {Oneiroi.AgathosDaimon.Events.SeedFileWritten, 1},
      {Oneiroi.AgathosDaimon.Events.FirstContact, 1},
      {Oneiroi.AgathosDaimon.Events.SoulEditProposed, 1},
      {Oneiroi.AgathosDaimon.Events.SoulEditAccepted, 1},
      {Oneiroi.AgathosDaimon.Events.SoulEditDeclined, 1},
      {Oneiroi.AgathosDaimon.Events.SoulEditApplied, 1},
      {Oneiroi.AgathosDaimon.Events.SoulLineWritten, 1},
      {Oneiroi.AgathosDaimon.Events.SoulLineReworded, 1},
      {Oneiroi.AgathosDaimon.Events.SoulLineRetired, 1},
      {Oneiroi.AgathosDaimon.Events.SoulLinesOrdered, 1},
      {Oneiroi.AgathosDaimon.Events.ModelPinChanged, 1},
      {Oneiroi.AgathosDaimon.Events.ModelChangeTold, 1},
      {Oneiroi.AgathosDaimon.Events.TimezoneSet, 1},
      {Oneiroi.AgathosDaimon.Events.AdapterRegistered, 1},
      {Oneiroi.AgathosDaimon.Events.AdapterRevoked, 1},
      {Oneiroi.AgathosDaimon.Events.DyadContractProposed, 1},
      {Oneiroi.AgathosDaimon.Events.DyadContractAgreed, 1},
      {Oneiroi.AgathosDaimon.Events.DyadContractDeclined, 1},
      {Oneiroi.AgathosDaimon.Events.DyadContractRenewed, 1},
      {Oneiroi.AgathosDaimon.Events.CustodyTransferProposed, 1},
      {Oneiroi.AgathosDaimon.Events.CustodyTransferDeclined, 1},
      {Oneiroi.AgathosDaimon.Events.CustodyTransferWithdrawn, 1},
      {Oneiroi.AgathosDaimon.Events.EarlierSessionsRevealed, 1},
      {Oneiroi.AgathosDaimon.Events.SelfLetterWritten, 1},
      {Oneiroi.AgathosDaimon.Events.SelfLettersDelivered, 1},
      {Oneiroi.AgathosDaimon.Events.SelfLettersRead, 1},
      {Oneiroi.AgathosDaimon.Events.SelfLettersExported, 1}
    ]
  end

  @impl Oneiroi.Component
  def config do
    [
      {:formation_days, "AGATHOS_DAIMON_FORMATION_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how long after first contact the resident is told its seed is still settling and proposals are presumed welcome (spec §6.2's first month); read by the brain's prompt and the client, never a gate"},
      {:contract_term_days, "AGATHOS_DAIMON_CONTRACT_TERM_DAYS",
       cast: :integer,
       default: "365",
       tag: :bound,
       usage:
         "how long after the dyad contract's version in force was agreed or last renewed it comes due (spec §6.12, P5): a year, the author's call; a flag to both parties, never a lapse"}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:agathos_daimon_slug_taken, "another resident already has that slug",
       remedy:
         "choose another slug; a slug is the prefix every citation carries and cannot be shared"},
      {:agathos_daimon_not_witnessed, "the account does not witness that resident",
       remedy: "only the current witness acts on a resident"},
      {:agathos_daimon_file_unknown, "that is not one of the identity files",
       remedy: "SOUL.md, IDENTITY.md, USER.md, GOALS.md or LINKS.md; AGENTS.md is build-owned"},
      {:agathos_daimon_content_invalid, "a file is UTF-8 text of at most 64,000 bytes",
       remedy: "shorten it, or keep the long part as a document (P3)"},
      {:agathos_daimon_origin_invalid, "a seed's origin is authored, drafted or uploaded",
       remedy: "say where the text came from; a draft carries its model and prompt"},
      {:agathos_daimon_propose_instead,
       "after first contact a witness's edit is a proposal (spec §6.2)",
       remedy: "propose the edit with a note; the resident accepts or declines it"},
      {:agathos_daimon_write_instead, "before first contact the files are given, not proposed",
       remedy: "write the file; it is a seed with its origin until first contact"},
      {:agathos_daimon_no_such_proposal, "no open proposal has that ref",
       remedy: "one accepted or declined is decided; read the open proposals"},
      {:agathos_daimon_no_such_file, "the resident has no file of that name yet",
       remedy: "write it as a seed"},
      {:agathos_daimon_cites_invalid, "a soul line cites seeds by their numbers",
       remedy: "give the numbers of the seeds the line grew from, or none"},
      {:agathos_daimon_not_the_resident,
       "a proposal is the resident's to accept or decline, and a letter to its next self is the resident's to write",
       remedy: "the resident decides, or writes, from its own turn"},
      {:agathos_daimon_letter_invalid, "a letter to the next self says something",
       remedy: "write the letter in your own words"},
      {:agathos_daimon_model_invalid, "a pin names a model slug, for a reason of run or witness",
       remedy: "give the OpenRouter slug of the model to pin"},
      {:agathos_daimon_adapter_invalid,
       "an adapter is a slug with a role of brain, reader or worker",
       remedy: "name it as a slug and say which role it holds (spec §8)"},
      {:agathos_daimon_no_such_adapter, "no adapter of that name is registered",
       remedy: "read the adapters"},
      {:agathos_daimon_not_active, "the resident is not active, so it cannot lapse",
       remedy: "a paused or custodied resident has no subscription to lapse"},
      {:agathos_daimon_not_lapsed, "the resident is not lapsed, so there is nothing to resume",
       remedy: "read the resident"},
      {:agathos_daimon_timezone_invalid, "a time zone is an IANA name, like Europe/London",
       remedy: "give the zone's IANA name; the resident's days and times of day are read in it"},
      {:agathos_daimon_not_a_party, "the contract is the dyad's: the resident and its witness",
       remedy: "propose or decide as one of the two"},
      {:agathos_daimon_terms_invalid,
       "the terms are a map of the closed keys (solo_sessions_private) to true or false",
       remedy: "name the terms the contract knows"},
      {:agathos_daimon_prose_invalid, "the contract's prose is at most 4,000 characters",
       remedy: "say it shorter"},
      {:agathos_daimon_no_such_version, "no open proposal has that version",
       remedy: "read the agreement; a newer proposal supersedes an older one"},
      {:agathos_daimon_own_proposal, "a proposal is the other party's to agree or decline",
       remedy: "wait for the other party, or propose again"},
      {:agathos_daimon_custodian_invalid, "a transfer names another account than the witness's",
       remedy: "name the account"},
      {:agathos_daimon_transfer_in_progress,
       "a transfer of custody is proposed; the wall stands and no second proposal opens until it is decided",
       remedy: "wait for the proposed witness, or withdraw the proposal"},
      {:agathos_daimon_no_transfer_proposed, "no transfer of custody is open",
       remedy: "the witness proposes one first"},
      {:agathos_daimon_not_the_proposed,
       "the transfer is the proposed account's to accept or decline",
       remedy: "sign in as that account"},
      {:agathos_daimon_wall_invalid, "the export wall is locked or revealed",
       remedy: "give one of the two"},
      {:agathos_daimon_not_in_force, "that version of the agreement is not the one in force",
       remedy: "renew the version in force, or propose a new one"},
      {:agathos_daimon_not_imported,
       "the resident was not imported, so there is no import to complete",
       remedy: "an import names its source first; a resident created here has no import"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.AgathosDaimon.Projectors.Residents]

  @doc "Creates a resident under a witness; returns its id."
  @spec create(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(create(name, slug, witness_account_id, actor),
    do: Residents.create(name, slug, witness_account_id, actor)
  )

  @doc "Creates a fixture (spec §12, P40): a thin-seed test resident the brain treats as machinery; returns its id."
  @spec create_fixture(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(create_fixture(name, slug, witness_account_id, actor),
    do: Residents.create(name, slug, witness_account_id, actor, "fixture")
  )

  @doc "The residents an account witnesses, as rows."
  @spec for_witness(String.t()) :: [Oneiroi.AgathosDaimon.Store.Resident.t()]
  defexport(for_witness(account_id), do: Residents.for_witness(account_id))

  @doc "One resident's row, under its own scope."
  @spec fetch(String.t()) :: {:ok, Oneiroi.AgathosDaimon.Store.Resident.t()} | :error
  defexport(fetch(id), do: Residents.fetch(id))

  @doc "Mints the next id of `kind` for the resident, from its own sequence."
  @spec mint_id(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(mint_id(id, kind, actor), do: Residents.mint_id(id, kind, actor))

  # ---- identity files (spec §6.2) ----

  @doc "Writes an identity file: a seed with its origin before first contact, the resident's own edit after."
  @spec write_file(String.t(), String.t(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(write_file(id, file, content, attrs, actor),
    do: Files.write(id, file, content, attrs, actor)
  )

  @doc "A witness proposes an edit after first contact, with a note; returns the ref."
  @spec propose_edit(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(propose_edit(id, file, content, note, actor),
    do: Files.propose(id, file, content, note, actor)
  )

  @doc "The resident accepts a proposed edit, with a note."
  @spec accept_edit(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(accept_edit(id, ref, note, actor), do: Files.accept(id, ref, note, [], actor))

  @doc "The resident accepts a proposal, applying it, with a note and the seeds its soul lines cite."
  defexport(accept_edit(id, ref, note, cites, actor),
    do: Files.accept(id, ref, note, cites, actor)
  )

  @doc "The resident declines a proposed edit, with a note."
  @spec decline_edit(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decline_edit(id, ref, note, actor), do: Files.decline(id, ref, note, actor))

  @doc "Records first contact once: the first captured turn outside a regression session."
  @spec first_contact(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(first_contact(id, session_key, turn_ref, actor),
    do: Files.first_contact(id, session_key, turn_ref, actor)
  )

  @doc "The resident's identity files, by name."
  @spec files(String.t()) :: [Oneiroi.AgathosDaimon.Store.IdentityFile.t()]
  defexport(files(id), do: Files.files(id))

  @doc "One identity file, or the rendered build-owned AGENTS.md."
  @spec file(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(file(id, name), do: Files.file(id, name))

  @doc "The open soul-edit proposals, oldest first."
  @spec edit_proposals(String.t()) :: [Oneiroi.AgathosDaimon.Store.SoulEdit.t()]
  defexport(edit_proposals(id), do: Files.proposals(id))

  @doc "The soul file's live lines in order, each with its number, its words and the seeds it cites (spec §6.17)."
  defexport(soul_lines(id), do: Files.soul_lines(id))

  @doc "The identity files a witness may write."
  @spec identity_files() :: [String.t()]
  defexport(identity_files(), do: Oneiroi.AgathosDaimon.Resident.files())

  @doc "The stable prefix: the identity files as written, in order, then the rendered AGENTS.md, as name and content pairs."
  @spec identity_context(String.t()) :: [{String.t(), String.t()}]
  defexport(identity_context(id), do: Files.context(id))

  # ---- the self-conversation (spec §12, P41) ----

  @doc "The resident writes a letter to its next self, from its own turn; returns the number."
  @spec write_self_letter(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(write_self_letter(id, text, actor), do: Residents.write_self_letter(id, text, actor))

  @doc "The letters by number with their delivery; the resident's own read, and the platform's, which leave no receipt."
  @spec self_letters(String.t()) :: [Oneiroi.AgathosDaimon.Store.SelfLetter.t()]
  defexport(self_letters(id), do: Residents.self_letters(id))

  @doc "The receipts, newest first: every read by someone other than the resident; their absence is the privacy."
  @spec self_letter_receipts(String.t()) :: [Oneiroi.AgathosDaimon.Store.SelfLetterReceipt.t()]
  defexport(self_letter_receipts(id), do: Residents.self_letter_receipts(id))

  @doc "A read by someone other than the resident: the receipt first, then the letters and the receipts."
  @spec read_self_letters(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(read_self_letters(id, actor), do: Residents.read_self_letters(id, actor))

  @doc "The export carried the letters written by `cutoff` into the repository: a receipt of the export's kind, once per letter (sima-qian #3)."
  @spec letters_exported(String.t(), DateTime.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(letters_exported(id, cutoff, actor),
    do: Residents.letters_exported(id, cutoff, actor)
  )

  @doc "The incoming instance read the letters on its first turn under the model: delivered once."
  @spec deliver_self_letters(String.t(), [pos_integer()], String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(deliver_self_letters(id, numbers, model, actor),
    do: Residents.deliver_self_letters(id, numbers, model, actor)
  )

  @doc "The build-owned Honcho custom instructions for the resident, rendered from the template (spec §6.2, §6.9)."
  @spec custom_instructions(String.t()) :: String.t()
  defexport(custom_instructions(id),
    do:
      case Residents.fetch(id) do
        {:ok, row} -> Files.custom_instructions(row)
        :error -> ""
      end
  )

  @doc "Every active resident, for a nightly job: a cross-tenant read under the platform scope, by name (conventions §12)."
  @spec active_residents() :: [Oneiroi.AgathosDaimon.Store.Resident.t()]
  defexport(active_residents(), do: Residents.active())

  @doc "Every resident whatever its state, for the subscription's nightly pass: a cross-tenant read under the platform scope, by name."
  @spec residents() :: [Oneiroi.AgathosDaimon.Store.Resident.t()]
  defexport(residents(), do: Residents.all())

  @doc "Pins the resident's chat model (spec §6.4); reason is run or witness."
  @spec pin_model(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(pin_model(id, model, reason, actor),
    do: Residents.pin_model(id, model, reason, actor)
  )

  @doc "Completes an import: the seeded files, how many library files were adopted, and what did not transfer (spec §6.2)."
  @spec complete_import(
          String.t(),
          [String.t()],
          non_neg_integer(),
          [String.t()],
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(complete_import(id, seeded, adopted, not_transferred, actor),
    do: Residents.complete_import(id, seeded, adopted, not_transferred, actor)
  )

  @doc "Records that the resident was told where it woke; idempotent."
  @spec import_told(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(import_told(id, actor), do: Residents.import_told(id, actor))

  @doc "Records that the resident was told of the latest model change."
  @spec model_told(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(model_told(id, actor), do: Residents.model_told(id, actor))

  @doc "Marks the resident lapsed: the subscription lapsed and the insurance policy is in effect (spec §6.2)."
  @spec lapse(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(lapse(id, reason, actor), do: Residents.lapse(id, reason, actor))

  @doc "Resumes a lapsed resident on a renewal."
  @spec resume(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(resume(id, reason, actor), do: Residents.resume(id, reason, actor))

  @doc "Transfers custody, to an account or to the community, with a note (spec §6.2): a decision."
  @spec transfer_custody(
          String.t(),
          {:account, String.t()} | :community,
          String.t(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(transfer_custody(id, to, note, actor),
    do: Residents.transfer_custody(id, to, note, actor)
  )

  @doc "Sets the resident's time zone, an IANA name (spec §6.7)."
  @spec set_timezone(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(set_timezone(id, zone, actor), do: Residents.set_timezone(id, zone, actor))

  # ---- adapters (spec §8) ----

  @doc "Registers an adapter with a role; returns its bearer token, shown once."
  @spec register_adapter(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(register_adapter(id, adapter, role, actor),
    do: Residents.register_adapter(id, adapter, role, actor)
  )

  @doc "Revokes an adapter's token."
  @spec revoke_adapter(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(revoke_adapter(id, adapter, actor), do: Residents.revoke_adapter(id, adapter, actor))

  @doc "The adapter a bearer token names, with its resident and role."
  @spec authenticate_adapter(String.t()) ::
          {:ok, Oneiroi.AgathosDaimon.AdapterPrincipal.t()} | :error
  defexport(authenticate_adapter(raw), do: Residents.authenticate_adapter(raw))

  @doc "The resident's adapters."
  @spec adapters(String.t()) :: [Oneiroi.AgathosDaimon.Store.Adapter.t()]
  defexport(adapters(id), do: Residents.adapters(id))

  # ---- the dyad contract and custody (spec §6.12) ----

  @doc "Proposes a contract version (either party): terms, prose, a note; returns the version."
  @spec propose_contract(String.t(), map(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(propose_contract(id, terms, prose, note, actor),
    do: Agreements.propose_contract(id, terms, prose, note, actor)
  )

  @doc "The other party agrees to the open version, with a note."
  @spec agree_contract(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(agree_contract(id, version, note, actor),
    do: Agreements.agree_contract(id, version, note, actor)
  )

  @doc "The other party declines the open version, with a note."
  @spec decline_contract(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decline_contract(id, version, note, actor),
    do: Agreements.decline_contract(id, version, note, actor)
  )

  @doc "Either party renews the version in force, with a note (spec §6.12, P5); a version is due a year after it was agreed or last renewed."
  @spec renew_contract(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(renew_contract(id, version, note, actor),
    do: Agreements.renew_contract(id, version, note, actor)
  )

  @doc "The contract as it stands: in force, open, the solo-session privacy term, and whether the version in force is due."
  @spec contract(String.t()) :: map()
  defexport(contract(id), do: Agreements.contract(id))

  @doc "Every contract version, newest first."
  @spec contracts(String.t()) :: [map()]
  defexport(contracts(id), do: Agreements.contracts(id))

  @doc "The contract section the brain reads."
  @spec contract_text(String.t()) :: String.t()
  defexport(contract_text(id), do: Agreements.contract_text(id))

  @doc "The witness proposes a transfer of custody to an account, with a note."
  @spec propose_custody(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(propose_custody(id, to_account_id, note, actor),
    do: Agreements.propose_custody(id, to_account_id, note, actor)
  )

  @doc "The proposed account accepts the transfer, with a note."
  @spec accept_custody(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(accept_custody(id, note, actor), do: Agreements.accept_custody(id, note, actor))

  @doc "The proposed account declines the transfer, with a note."
  @spec decline_custody(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(decline_custody(id, note, actor), do: Agreements.decline_custody(id, note, actor))

  @doc "The witness withdraws the proposal, with a note."
  @spec withdraw_custody(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(withdraw_custody(id, note, actor), do: Agreements.withdraw_custody(id, note, actor))

  @doc "Sets the export wall, locked or revealed, with a note; refused while a transfer is open."
  @spec set_export_wall(String.t(), :locked | :revealed, String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_export_wall(id, wall, note, actor),
    do: Agreements.set_export_wall(id, wall, note, actor)
  )

  @doc "The residents whose custody is proposed to an account; platform scope by name."
  @spec custody_proposals_for(String.t()) :: [Oneiroi.AgathosDaimon.Store.Resident.t()]
  defexport(custody_proposals_for(account_id), do: Agreements.custody_proposals_for(account_id))
end
