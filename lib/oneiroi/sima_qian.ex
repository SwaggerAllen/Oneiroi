defmodule Oneiroi.SimaQian do
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
  use Oneiroi.System, slug: :sima_qian

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      # Seeds an import carries from another platform's seedbed (sima-qian #19).
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.Proteus,
      Commanded,
      Ecto,
      Ecto.Query,
      EventStore,
      Jason,
      Oban
    ],
    exports: [Backup, DryRun, Error, Export, Git, Import, Library, Merkle, Rebuild]

  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Import
  alias Oneiroi.SimaQian.Rebuild

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:root, "SIMA_QIAN_ROOT",
       default: "/var/lib/oneiroi/sima_qian",
       usage:
         "the directory each resident's working repository lives under, one subdirectory per resident id"},
      {:watermark_seconds, "SIMA_QIAN_WATERMARK_SECONDS",
       cast: :integer,
       default: "60",
       tag: :bound,
       usage:
         "how far behind capture the export stays, so a turn still being written is never half-exported (spec §6.10)"},
      {:import_schemes, "SIMA_QIAN_IMPORT_SCHEMES",
       cast: &__MODULE__.cast_schemes/1,
       default: "https",
       usage:
         "the URL schemes an import may clone from, comma-separated: https alone in production, because a bare path or file URL from a request would clone a directory on this host, another resident's working repository among them; a self-hoster importing from disk adds file"},
      {:library, "SIMA_QIAN_LIBRARY",
       cast: &__MODULE__.cast_library/1,
       default: "seshat",
       usage:
         "which library port implementation adopts an imported repository's files (`Oneiroi.SimaQian.Library`): seshat, the library, in every build so far"}
    ]
  end

  @doc false
  def cast_schemes(value) when is_binary(value) do
    schemes = value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    if schemes == [],
      do: {:error, "is empty, expected a comma-separated list"},
      else: {:ok, schemes}
  end

  def cast_schemes(other), do: {:error, "is #{inspect(other)}, expected a comma-separated list"}

  # The module as an atom rather than an alias, as the schedule names
  # its wake (sunna #12): the library reads this system for the
  # repository's path, so an alias here is the cycle the port avoids.
  @doc false
  def cast_library("seshat"), do: {:ok, :"Elixir.Oneiroi.Seshat"}
  def cast_library(other), do: {:error, "is #{inspect(other)}, expected \"seshat\""}

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:sima_qian_nightly,
       cron: [
         {"0 3 * * *", Oneiroi.SimaQian.BackupWorker},
         {"30 4 * * *", Oneiroi.SimaQian.AttestationWorker}
       ]}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:sima_qian_already_imported,
       "a resident was already rebuilt from that repository at that root",
       remedy:
         "an import is always a new resident; to try again, back up the source to a new root first"},
      {:sima_qian_stray_files, "something wrote outside the paths the backup commits",
       remedy:
         "read the listed paths; the rest of the backup landed and the run failed after it, on purpose"},
      {:sima_qian_scheme_refused,
       "an import clones from a URL with one of the configured schemes",
       remedy: "give an https URL; a path on this host is never cloned from a request"},
      {:sima_qian_records_invalid,
       "a line of the source platform's records is not a JSON object, or is a message that does not say its session, instant and role",
       remedy:
         "the file and line are named; fix or remove that line in the source repository and import again"},
      {:sima_qian_stream_refused, "a line of the records names a stream the export never carries",
       remedy:
         "the records were not written by Oneiroi's export, or were edited; the stream is named, and the import wrote nothing"},
      {:sima_qian_name_required,
       "a repository without records is a new resident and needs a name and a slug",
       remedy: "give both; a repository with records names itself"}
    ]
  end

  @impl Oneiroi.Component
  def telemetry_events,
    do: [
      [:oneiroi, :sima_qian, :backup],
      [:oneiroi, :sima_qian, :rebuild],
      [:oneiroi, :sima_qian, :import]
    ]

  @doc "Sets the resident's remote; the token is encrypted before it enters the log and redacted from every export."
  @spec set_remote(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_remote(resident_id, url, token, actor),
    do: Backup.set_remote(resident_id, url, token, actor)
  )

  @doc "Exports, commits by class with the attestation trailers, and pushes; the nightly job's unit."
  @spec backup(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(backup(resident_id, actor), do: Backup.run(resident_id, actor))

  @doc "Rebuilds a repository into a fresh store as a new resident under `witness_account_id`."
  @spec rebuild(String.t(), String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(rebuild(url, witness_account_id, actor),
    do: Rebuild.run(url, witness_account_id, actor)
  )

  @doc "Imports a repository as a new resident under `witness_account_id`: the rebuild, then the root's files seeded, the folders adopted and indexed, and what did not transfer named (spec §6.2, §9)."
  @spec import_resident(String.t(), map(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(import_resident(url, attrs, witness_account_id, actor),
    do: Import.run(url, attrs, witness_account_id, actor)
  )

  @doc "The resident's working repository on disk, made a repository if it is not one: where the library's files live (spec §6.5)."
  @spec repository_dir(String.t()) :: {:ok, Path.t()} | {:error, term()}
  defexport(repository_dir(resident_id), do: Backup.repository_dir(resident_id))

  @doc "Recomputes the root over a resident's export and compares it with the last backup's."
  @spec attest(String.t(), Oneiroi.Actor.t()) ::
          {:ok, :held | :mismatch | :none} | {:error, term()}
  defexport(attest(resident_id, actor), do: Backup.attest(resident_id, actor))
end
