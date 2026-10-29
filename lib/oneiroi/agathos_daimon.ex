defmodule Oneiroi.AgathosDaimon do
  @moduledoc """
  The resident aggregate (spec §6.2): creation, lifecycle, custody, the
  export wall, import, the per-resident id sequences every citeable thing
  draws on, and the records facts the resident's own stream carries
  (export written, backup committed, root mismatch).

  The creation flow with its threshold and gifts is P1; here a resident is
  created through the API with a name and a slug, under its steward.
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
      Router,
      Commands,
      Commands.CreateResident,
      Commands.MintId,
      Commands.PauseResident,
      Commands.WakeResident,
      Commands.TransferCustody,
      Commands.SetExportWall,
      Commands.ImportResident,
      Commands.RecordExport,
      Commands.RecordBackup,
      Commands.RecordMismatch,
      Commands.SetRecordsRemote,
      Events.ResidentCreated,
      Events.IdMinted,
      Events.ResidentPaused,
      Events.ResidentWoken,
      Events.CustodyTransferred,
      Events.ExportWallSet,
      Events.Imported,
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
      Events.ModelPinChanged,
      Events.ModelChangeTold,
      Events.TimezoneSet,
      Events.AdapterRegistered,
      Events.AdapterRevoked,
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
      Store,
      Store.Resident,
      Store.IdentityFile,
      Store.SoulEdit
    ]

  alias Oneiroi.AgathosDaimon.Files
  alias Oneiroi.AgathosDaimon.Residents

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.AgathosDaimon.Events.ResidentCreated, 1},
      {Oneiroi.AgathosDaimon.Events.IdMinted, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentPaused, 1},
      {Oneiroi.AgathosDaimon.Events.ResidentWoken, 1},
      {Oneiroi.AgathosDaimon.Events.CustodyTransferred, 1},
      {Oneiroi.AgathosDaimon.Events.ExportWallSet, 1},
      {Oneiroi.AgathosDaimon.Events.Imported, 1},
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
      {Oneiroi.AgathosDaimon.Events.ModelPinChanged, 1},
      {Oneiroi.AgathosDaimon.Events.ModelChangeTold, 1},
      {Oneiroi.AgathosDaimon.Events.TimezoneSet, 1},
      {Oneiroi.AgathosDaimon.Events.AdapterRegistered, 1},
      {Oneiroi.AgathosDaimon.Events.AdapterRevoked, 1}
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
         "how long after first contact the resident is told its seed is still settling and proposals are presumed welcome (spec §6.2's first month); read by the brain's prompt and the client, never a gate"}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:agathos_daimon_slug_taken, "another resident already has that slug",
       remedy:
         "choose another slug; a slug is the prefix every citation carries and cannot be shared"},
      {:agathos_daimon_not_stewarded, "the account does not steward that resident",
       remedy: "only the current steward acts on a resident"},
      {:agathos_daimon_file_unknown, "that is not one of the identity files",
       remedy: "SOUL.md, IDENTITY.md, USER.md, GOALS.md or LINKS.md; AGENTS.md is build-owned"},
      {:agathos_daimon_content_invalid, "a file is UTF-8 text of at most 64,000 bytes",
       remedy: "shorten it, or keep the long part as a document (P3)"},
      {:agathos_daimon_origin_invalid, "a seed's origin is authored, drafted or uploaded",
       remedy: "say where the text came from; a draft carries its model and prompt"},
      {:agathos_daimon_propose_instead,
       "after first contact a steward's edit is a proposal (spec §6.2)",
       remedy: "propose the edit with a note; the resident accepts or declines it"},
      {:agathos_daimon_write_instead, "before first contact the files are given, not proposed",
       remedy: "write the file; it is a seed with its origin until first contact"},
      {:agathos_daimon_no_such_proposal, "no open proposal has that ref",
       remedy: "one accepted or declined is decided; read the open proposals"},
      {:agathos_daimon_no_such_file, "the resident has no file of that name yet",
       remedy: "write it as a seed"},
      {:agathos_daimon_not_the_resident, "a proposal is the resident's to accept or decline",
       remedy: "the resident decides from its own turn"},
      {:agathos_daimon_model_invalid, "a pin names a model slug, for a reason of run or steward",
       remedy: "give the OpenRouter slug of the model to pin"},
      {:agathos_daimon_adapter_invalid,
       "an adapter is a slug with a role of brain, reader or worker",
       remedy: "name it as a slug and say which role it holds (spec §8)"},
      {:agathos_daimon_no_such_adapter, "no adapter of that name is registered",
       remedy: "read the adapters"},
      {:agathos_daimon_timezone_invalid, "a time zone is an IANA name, like Europe/London",
       remedy: "give the zone's IANA name; the resident's days and times of day are read in it"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.AgathosDaimon.Projectors.Residents]

  @doc "Creates a resident under a steward; returns its id."
  @spec create(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(create(name, slug, steward_account_id, actor),
    do: Residents.create(name, slug, steward_account_id, actor)
  )

  @doc "The residents an account stewards, as rows."
  @spec for_steward(String.t()) :: [Oneiroi.AgathosDaimon.Store.Resident.t()]
  defexport(for_steward(account_id), do: Residents.for_steward(account_id))

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

  @doc "A steward proposes an edit after first contact, with a note; returns the ref."
  @spec propose_edit(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(propose_edit(id, file, content, note, actor),
    do: Files.propose(id, file, content, note, actor)
  )

  @doc "The resident accepts a proposed edit, with a note."
  @spec accept_edit(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(accept_edit(id, ref, note, actor), do: Files.accept(id, ref, note, actor))

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

  @doc "The identity files a steward may write."
  @spec identity_files() :: [String.t()]
  defexport(identity_files(), do: Oneiroi.AgathosDaimon.Resident.files())

  @doc "The stable prefix: the identity files as written, in order, then the rendered AGENTS.md, as name and content pairs."
  @spec identity_context(String.t()) :: [{String.t(), String.t()}]
  defexport(identity_context(id), do: Files.context(id))

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

  @doc "Pins the resident's chat model (spec §6.4); reason is run or steward."
  @spec pin_model(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(pin_model(id, model, reason, actor),
    do: Residents.pin_model(id, model, reason, actor)
  )

  @doc "Records that the resident was told of the latest model change."
  @spec model_told(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(model_told(id, actor), do: Residents.model_told(id, actor))

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
end
