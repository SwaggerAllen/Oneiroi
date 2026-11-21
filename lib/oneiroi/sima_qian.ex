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
      # The household its repository belongs to, and its members, for the
      # copy a resident's backup carries (sima-qian#53).
      Oneiroi.Gaia,
      # Seeds an import carries from another platform's seedbed (sima-qian#19).
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Commanded,
      Commanded.Event.Upcaster,
      Ecto,
      Ecto.Query,
      EventStore,
      Jason,
      Oban,
      # Gitea's API (sima-qian#55).
      Req,
      Req.Response
    ],
    exports: [
      Backup,
      Gitea,
      Gitea.HTTP,
      Gitea.Fake,
      GiteaMigration,
      GiteaQueue,
      Repos,
      Repos.Local,
      Repos.Gitea,
      Repos.Cache,
      DryRun,
      Error,
      Export,
      Git,
      Household,
      Import,
      Library,
      Merkle,
      Originals,
      Rebuild
    ]

  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.ChatGPTImport
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.Import
  alias Oneiroi.SimaQian.Originals
  alias Oneiroi.SimaQian.Rebuild
  alias Oneiroi.SimaQian.Repos

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:import_max_bytes, "SIMA_QIAN_IMPORT_MAX_BYTES",
       cast: :integer,
       default: "524288000",
       tag: :bound,
       usage:
         "the largest ChatGPT export zip the upload takes, in bytes (sima-qian#47); a heavy export runs to a gigabyte, most of it media this import does not unpack"},
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
      {:household_travels, "SIMA_QIAN_HOUSEHOLD_TRAVELS",
       cast: &__MODULE__.cast_on_off/1,
       default: "on",
       usage:
         "whether a resident's backup carries a copy of its household's repository under household/, titled by the membership (sima-qian#53): on is the resident's lean on the open question of export travel (design household-communication §8), off makes no copy and leaves one already committed as it was"},
      # Where every repository is read and written (sima-qian#57). Local
      # until an operator turns Gitea on, once its admin token is set: the
      # boot after that moves the records disk over (sima-qian#58), so
      # there is never a build reading a Gitea it cannot reach.
      {:repos_client, "SIMA_QIAN_REPOS",
       cast: &__MODULE__.cast_repos_client/1,
       default: "local",
       usage:
         "which repositories' port answers every read and write: gitea (the source of truth, once SIMA_QIAN_GITEA_URL and SIMA_QIAN_GITEA_TOKEN are set; the boot after the switch moves the records disk over) or local (a git repository per resident and household on the records disk: test, development, a self-hoster without Gitea, and production until the switch)"},
      {:gitea_client, "SIMA_QIAN_GITEA_CLIENT",
       cast: &__MODULE__.cast_gitea_client/1,
       default: "http",
       usage:
         "which repositories' port implementation answers: http (Gitea's API) in every real build, fake in test"},
      {:remote_check_client, "SIMA_QIAN_REMOTE_CHECK_CLIENT",
       cast: &__MODULE__.cast_remote_check_client/1,
       default: "github",
       usage:
         "which port asks a backup remote's host whether it is private and the token may push (sima-qian#65): github (GitHub's API) in every real build, fake in test"},
      {:gitea_url, "SIMA_QIAN_GITEA_URL",
       required: false,
       usage:
         "the Gitea service's base URL, e.g. https://oneiroi-git.onrender.com (sima-qian#55): where repositories are pushed and witnesses sign in"},
      {:gitea_token, "SIMA_QIAN_GITEA_TOKEN",
       secret: true,
       required: false,
       usage:
         "an admin user's Gitea token with every scope the admin API needs (sima-qian#55); unset, nothing is sent to Gitea"},
      {:gitea_admin, "SIMA_QIAN_GITEA_ADMIN",
       default: "oneiroi-admin",
       usage:
         "the login of the Gitea admin whose token the core writes with (sima-qian#59): a push by it is the core's own write, never one from outside"},
      {:gitea_webhook_secret, "SIMA_QIAN_GITEA_WEBHOOK_SECRET",
       secret: true,
       required: false,
       usage:
         "the secret of Gitea's system webhook (sima-qian#59), which signs each push so a push from outside re-indexes its resident's library; unset, the webhook is refused"},
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

    if schemes == [] do
      # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
      {:error, "is empty, expected a comma-separated list"}
    else
      {:ok, schemes}
    end
  end

  def cast_schemes(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected a comma-separated list"}
  end

  @doc false
  def cast_on_off("on"), do: {:ok, true}
  def cast_on_off("off"), do: {:ok, false}

  def cast_on_off(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected on or off"}
  end

  # The module as an atom rather than an alias, as the schedule names
  # its wake (sunna#12): the library reads this system for the
  # repository's path, so an alias here is the cycle the port avoids.
  @doc false
  def cast_library("seshat"), do: {:ok, :"Elixir.Oneiroi.Seshat"}

  def cast_library(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected \"seshat\""}
  end

  @doc false
  def cast_repos_client("gitea"), do: {:ok, :"Elixir.Oneiroi.SimaQian.Repos.Gitea"}
  def cast_repos_client("local"), do: {:ok, :"Elixir.Oneiroi.SimaQian.Repos.Local"}

  def cast_repos_client(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected \"gitea\" or \"local\""}
  end

  @doc false
  def cast_gitea_client("http"), do: {:ok, :"Elixir.Oneiroi.SimaQian.Gitea.HTTP"}
  def cast_gitea_client("fake"), do: {:ok, :"Elixir.Oneiroi.SimaQian.Gitea.Fake"}

  def cast_gitea_client(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected \"http\" or \"fake\""}
  end

  @doc false
  def cast_remote_check_client("github"),
    do: {:ok, :"Elixir.Oneiroi.SimaQian.RemoteCheck.GitHub"}

  def cast_remote_check_client("fake"), do: {:ok, :"Elixir.Oneiroi.SimaQian.RemoteCheck.Fake"}

  def cast_remote_check_client(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected \"github\" or \"fake\""}
  end

  @impl Oneiroi.Component
  def externals do
    [
      {:remote_check,
       adapter: Oneiroi.SimaQian.RemoteCheck.GitHub,
       fake: Oneiroi.SimaQian.RemoteCheck.Fake,
       kill_switch: :sima_qian_remote_check_off,
       classification: :operational},
      {:gitea,
       adapter: Oneiroi.SimaQian.Gitea.HTTP,
       fake: Oneiroi.SimaQian.Gitea.Fake,
       kill_switch: :sima_qian_gitea_off,
       classification: :customer_content}
    ]
  end

  @impl Oneiroi.Component
  def feature_flags, do: [:sima_qian_gitea_off, :sima_qian_remote_check_off]

  @impl Oneiroi.Component
  def processes, do: [{:sima_qian_blobs, :local}]

  @impl Oneiroi.Component
  def children, do: [Oneiroi.SimaQian.Repos.Cache, Oneiroi.SimaQian.GiteaMigration]

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
      {:sima_qian_backup_failed, "a nightly backup failed for one or more residents",
       remedy:
         "each failed resident is logged with its error's kind and site; run POST /v1/residents/:id/backup for the error itself"},
      {:sima_qian_attestation_failed, "a nightly attestation failed for one or more residents",
       remedy: "each failed resident is logged with its error's kind and site"},
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
       remedy: "give both; a repository with records names itself"},
      {:sima_qian_import_unreadable,
       "the ChatGPT export could not be read: not a zip, no conversations file in it, or a path in it that points outside it",
       remedy: "upload the zip ChatGPT emailed, as it came; the details name what was wrong"},
      {:sima_qian_git_failed,
       "git refused, in its own words, with any credential in a URL redacted",
       remedy:
         "read git's words; for an import, the URL and the token's read access, for a backup, the remote and its token"},
      {:sima_qian_git_unstarted, "git could not start on this server",
       remedy:
         "the details name the binary and why: enoent is a runtime image without git (test/oneiroi/runtime_image_test.exs holds the image to it)"},
      {:sima_qian_import_mismatch,
       "a file the library took or offers is not the source's bytes at the imported commit",
       remedy:
         "nothing was made the platform's; the paths are named: read them against the source, and import again once the cause is found"},
      {:sima_qian_copy_failed, "the clone could not be copied into the records root",
       remedy:
         "the cause is the file system's reason; check the disk under SIMA_QIAN_ROOT, its space and its owner"},
      {:sima_qian_not_the_witness, "the originals import is the witness's",
       remedy: "the resident's witness runs it, from their own session"},
      {:sima_qian_commit_invalid,
       "the originals import reads the source at a commit named by its full sha, never a branch",
       remedy: "give the commit's full 40-character sha (64 for a SHA-256 repository)"},
      {:sima_qian_paths_invalid,
       "the paths are a non-empty list of patterns inside the source tree: relative, no `..`",
       remedy:
         "leave them out for the defaults (memory/*.md, memory/dreaming/**, MEMORY.md, DREAMS.md), or name patterns like those"},
      {:sima_qian_original_mismatch,
       "a copied file's git blob sha is not the source tree's, so nothing was adopted and this run's copies were removed",
       remedy:
         "the paths are named; check the disk under SIMA_QIAN_ROOT, then run the import again at the same commit"},
      {:sima_qian_gitea_unrouted,
       "the household is routed to a Gitea instance this build does not know (sima-qian#60)",
       remedy:
         "set the household's gitea_instance to one the build is configured for, or configure that instance"},
      {:sima_qian_remote_invalid,
       "that is not a repository's address: a backup remote is an https, ssh or git URL with a host and a path, or user@host:path (sima-qian#65)",
       remedy: "paste the repository's clone URL, e.g. https://github.com/<owner>/<repo>.git"},
      {:sima_qian_remote_absent,
       "the remote's host has no such repository, or the token cannot see it (sima-qian#65)",
       remedy: "check the URL, and that the token can read the repository"},
      {:sima_qian_remote_check_failed,
       "the remote's host could not be asked what the repository is (sima-qian#65); it is read as unknown",
       remedy: "nothing is needed: the remote is kept, and the next backup asks again"},
      {:sima_qian_remote_unpushable,
       "the token cannot push to that repository: its host says so, or cannot see it (sima-qian#65)",
       remedy: "give a token with write access to the repository, or check the URL"},
      {:sima_qian_gitea_off, "the repositories' server is not set up on this platform",
       remedy: "an operator sets SIMA_QIAN_GITEA_URL and SIMA_QIAN_GITEA_TOKEN"},
      {:sima_qian_repos_absent, "no file at that path in the repository",
       remedy: "read the tree for what is there"},
      {:sima_qian_repos_conflict,
       "the file changed, or appeared, since it was read: nothing of the write landed (sima-qian#57)",
       remedy: "read it again and write on what is there now"},
      {:sima_qian_gitea_unavailable,
       "the repositories' server did not answer, so the write was refused (sima-qian#57)",
       remedy: "nothing was written; try again once Gitea is back"},
      {:sima_qian_gitea_failed, "Gitea did not answer, or refused the request",
       remedy: "the push is retried by its queue; if it keeps failing, read Gitea's log"},
      {:sima_qian_gitea_unsigned,
       "the push's signature is missing or is not the webhook secret's (sima-qian#59)",
       remedy: "give Gitea's system webhook the secret SIMA_QIAN_GITEA_WEBHOOK_SECRET holds"},
      {:sima_qian_gitea_invalid, "a Gitea password is at least twelve characters",
       remedy: "choose a longer one"},
      {:sima_qian_household_invalid, "a household's repository is named by the household's id",
       remedy: "read the id off the household; it is the founding account's"},
      {:sima_qian_append_failed, "the event store refused the repository's records",
       remedy:
         "the cause is the store's reason; the runs before it were written under the new id, so import again rather than resume"}
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

  @doc "The witness's set of a backup remote (sima-qian#65): its shape, its host asked, unpushable refused, public kept and answered for the warning."
  defexport(set_remote_checked(resident_id, url, token, actor),
    do: Backup.set_remote_checked(resident_id, url, token, actor)
  )

  @doc "Exports, commits by class with the attestation trailers, and pushes; the nightly job's unit."
  @spec backup(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(backup(resident_id, actor), do: Backup.run(resident_id, actor))

  @doc "Removes the working repository of a resident deleted before their first turn (agathos-daimon#49); the log keeps the tombstone."
  @spec discard_repository(String.t()) :: :ok
  defexport(discard_repository(resident_id), do: Backup.discard(resident_id))

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

  @doc "Imports the originals of the resident's memory from its source repository at a pinned commit, byte for byte, each registered with its provenance (sima-qian#40); the witness's."
  @spec import_originals(String.t(), map(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(import_originals(resident_id, request, actor),
    do: Originals.run(resident_id, request, actor)
  )

  @doc "The resident's working repository on disk, made a repository if it is not one: where the library's files live (spec §6.5)."
  @spec repository_dir(String.t()) :: {:ok, Path.t()} | {:error, term()}
  defexport(repository_dir(resident_id), do: Backup.repository_dir(resident_id))

  @doc "Puts a file in the resident's repository through the repositories' port (sima-qian#57): one commit under the actor's name, over whatever is there."
  @spec repository_put(String.t(), String.t(), iodata(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t() | :nothing} | {:error, term()}
  defexport(repository_put(resident_id, path, content, message, actor),
    do:
      Repos.write(
        {:resident, resident_id},
        [{:put, path, content, :any}],
        message,
        Repos.author(actor)
      )
  )

  @doc "The resident's repository at its head, `%{path => sha}` (sima-qian#57)."
  @spec repository_files(String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  defexport(repository_files(resident_id), do: Repos.snapshot({:resident, resident_id}))

  @doc "A file of the resident's repository through the repositories' port (sima-qian#57): its bytes, or nil."
  @spec repository_text(String.t(), String.t()) :: binary() | nil
  defexport(repository_text(resident_id, path), do: Repos.text({:resident, resident_id}, path))

  @doc "The history of the resident's repository, or of one path in it, newest first (brain#46)."
  @spec repository_log(String.t(), String.t() | nil, pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  defexport(repository_log(resident_id, path, limit),
    do: Repos.log({:resident, resident_id}, path, limit)
  )

  @doc "The commits that changed one path of the resident's repository, newest first, each with the blob the path held after it (sima-qian#49, for seshat#54)."
  @spec repository_history(String.t(), String.t(), pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  defexport(repository_history(resident_id, path, limit),
    do: Repos.history({:resident, resident_id}, path, limit)
  )

  @doc "One blob's bytes from the resident's repository, by the sha `repository_history/3` named."
  @spec repository_blob(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  defexport(repository_blob(resident_id, blob), do: Repos.blob({:resident, resident_id}, blob))

  @doc """
  A push Gitea reports (sima-qian#59), its signature checked over the
  bytes as they arrived: `{:ok, {:resident, id}}` when it came from
  outside into a resident's repository, `{:ok, :ignored}` for the core's
  own writes, the household's repository, another branch or a repository
  no resident has.
  """
  @spec gitea_pushed(binary(), String.t() | nil) ::
          {:ok, {:resident, String.t()} | :ignored} | {:error, term()}
  defexport(gitea_pushed(raw, signature), do: Gitea.pushed(raw, signature))

  @doc "Where a witness reaches Gitea (sima-qian#55): the server, the user and the repositories they read, or nil when it is not set up."
  @spec gitea_access(String.t()) :: map() | nil
  defexport(gitea_access(account_id), do: Gitea.access(account_id))

  @doc "Sets the witness's Gitea password, making the user if there is none (sima-qian#55)."
  @spec gitea_set_password(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  defexport(gitea_set_password(account_id, email, password),
    do: Gitea.set_password(account_id, email, password)
  )

  @doc "The history of the household's repository, or one path in it, newest first, each commit with its author."
  @spec household_log(String.t(), String.t() | nil, pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  defexport(household_log(household_id, path, limit),
    do: Repos.log({:household, household_id}, path, limit)
  )

  @doc "Recomputes the root over a resident's export and compares it with the last backup's."
  @spec attest(String.t(), Oneiroi.Actor.t()) ::
          {:ok, :held | :mismatch | :none} | {:error, term()}
  defexport(attest(resident_id, actor), do: Backup.attest(resident_id, actor))

  @doc "Takes a ChatGPT export's zip into a resident's records (sima-qian#47): what came across, and the report's path and text for the library."
  @spec import_chatgpt(String.t(), Path.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(import_chatgpt(resident_id, zip, witness_account_id, actor),
    do: ChatGPTImport.run_zip(resident_id, zip, witness_account_id, actor)
  )
end
