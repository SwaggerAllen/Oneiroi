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
      Store,
      Store.Resident
    ]

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
      {Oneiroi.AgathosDaimon.Events.RecordsRemoteSet, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:agathos_daimon_slug_taken, "another resident already has that slug",
       remedy:
         "choose another slug; a slug is the prefix every citation carries and cannot be shared"},
      {:agathos_daimon_not_stewarded, "the account does not steward that resident",
       remedy: "only the current steward acts on a resident"}
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
end
