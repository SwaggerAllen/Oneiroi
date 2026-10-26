defmodule Oneiroi.Records do
  @moduledoc """
  Export, replay, attestation, git providers, backups (spec §6.10).

  The event log is canonical and the repository is its projection and
  export: `records/events/<day>.jsonl` holds the resident's own stream,
  keys and rows in a fixed order, so an unchanged store exports identical
  bytes. A backup commit's message carries `Oneiroi-Sequence` and
  `Oneiroi-Root`, a Merkle root over the export, which is what makes a
  repository on a provider the platform does not host verifiable. A
  rebuild replays a repository into a fresh store as a new resident, told
  where it woke.

  Three cross-tenant jobs take the platform scope by name: the nightly
  backup and the attestation check walk every resident with a remote,
  and the rebuild's check for a repository already imported reads every
  resident's import row.
  """
  use Oneiroi.System, slug: :records

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.Resident,
      Commanded,
      Ecto,
      Ecto.Query,
      EventStore,
      Jason,
      Oban
    ],
    exports: [Backup, Error, Export, Git, Merkle, Rebuild]

  alias Oneiroi.Records.Backup
  alias Oneiroi.Records.Rebuild

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:root, "RECORDS_ROOT",
       default: "/var/lib/oneiroi/records",
       usage:
         "the directory each resident's working repository lives under, one subdirectory per resident id"},
      {:watermark_seconds, "RECORDS_WATERMARK_SECONDS",
       cast: :integer,
       default: "60",
       tag: :bound,
       usage:
         "how far behind capture the export stays, so a turn still being written is never half-exported (spec §6.10)"}
    ]
  end

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:records_nightly,
       cron: [
         {"0 3 * * *", Oneiroi.Records.BackupWorker},
         {"30 4 * * *", Oneiroi.Records.AttestationWorker}
       ]}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:records_already_imported,
       "a resident was already rebuilt from that repository at that root",
       remedy:
         "an import is always a new resident; to try again, back up the source to a new root first"},
      {:records_stray_files, "something wrote outside the paths the backup commits",
       remedy:
         "read the listed paths; the rest of the backup landed and the run failed after it, on purpose"}
    ]
  end

  @impl Oneiroi.Component
  def telemetry_events, do: [[:oneiroi, :records, :backup], [:oneiroi, :records, :rebuild]]

  @doc "Sets the resident's remote; the token is encrypted before it enters the log and redacted from every export."
  @spec set_remote(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_remote(resident_id, url, token, actor),
    do: Backup.set_remote(resident_id, url, token, actor)
  )

  @doc "Exports, commits by class with the attestation trailers, and pushes; the nightly job's unit."
  @spec backup(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(backup(resident_id, actor), do: Backup.run(resident_id, actor))

  @doc "Rebuilds a repository into a fresh store as a new resident under `steward_account_id`."
  @spec rebuild(String.t(), String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(rebuild(url, steward_account_id, actor),
    do: Rebuild.run(url, steward_account_id, actor)
  )

  @doc "Recomputes the root over a resident's export and compares it with the last backup's."
  @spec attest(String.t(), Oneiroi.Actor.t()) ::
          {:ok, :held | :mismatch | :none} | {:error, term()}
  defexport(attest(resident_id, actor), do: Backup.attest(resident_id, actor))
end
