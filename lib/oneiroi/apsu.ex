defmodule Oneiroi.Apsu do
  @moduledoc """
  The platform system (spec §6.16): fleet pins, the configuration module,
  deploy, observability, the status page. It owns the persistence spine
  (plan P0.2): the one Repo and the migrator, the event store and the
  Commanded application, Oban with the queues every system declares, the
  vault, the injected clock, and the audit checks that are Oneiroi's own
  (`gates`, `skips`, `tables`).
  """
  use Oneiroi.System, slug: :apsu

  require Logger

  alias Oneiroi.Component.Composer

  alias Ecto.Adapters.SQL
  alias Oneiroi.Apsu.Error
  alias Oneiroi.Apsu.Vault

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:http_port, "APSU_HTTP_PORT",
       cast: :integer,
       default: "8080",
       tag: :bound,
       usage: "the port the endpoint binds; the health probe reaches it directly"},
      # The origin the endpoint answers as, under the name Render gives
      # it: set on every web service, previews included, to the
      # service's own `https://…` URL, so a preview answers as itself and
      # never as production. A self-hosted instance sets the same name.
      #
      # Until this was declared nothing set the endpoint's `url:`, so
      # `OneiroiWeb.Endpoint.url/0` was `config.exs`'s localhost plus
      # the listener's port, and `OneiroiWeb.Plugs.Origin` held every
      # browser mutation to it. Measured on production, 2026-10-29: a
      # login carrying `Origin: https://oneiroi.onrender.com` was
      # refused 403, and one carrying `Origin: http://localhost:8080`
      # was answered 201. No browser can send the second, so no browser
      # could log in. The suite had not seen it because the contract
      # test read the expected origin from the same endpoint config the
      # plug did, and the two agreed with each other about a value
      # neither had been given (`config/test.exs` now sets one that is
      # not localhost for exactly that reason).
      {:public_url, "RENDER_EXTERNAL_URL",
       cast: &__MODULE__.cast_public_url/1,
       external: true,
       usage:
         "the origin the endpoint answers as (its url: at boot), which every browser mutation's Origin is checked against"},
      {:secret_key_base, "APSU_SECRET_KEY_BASE",
       cast: &__MODULE__.cast_secret_key_base/1,
       secret: true,
       usage: "signs the session cookie and every token the endpoint issues"},
      # A name imposed from outside, like RENDER_EXTERNAL_URL above: the
      # platform supplies the connection string under DATABASE_URL
      # (render.yaml binds it from the database) and every Postgres
      # client expects this key. The credential is the migrator's; the
      # application takes its own role on connect (Oneiroi.Repo).
      {:database_url, "DATABASE_URL",
       cast: &__MODULE__.cast_database_url/1,
       secret: true,
       external: true,
       usage: "the Repo's, the migrator's and the event store's connection; the owner credential"},
      {:pool_size, "APSU_POOL_SIZE",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage: "the Repo's connection pool; a bound until the first instance is measured"},
      {:event_store_pool_size, "APSU_EVENT_STORE_POOL_SIZE",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage: "the event store's own connection pool, beside the Repo's"},
      {:queue_concurrency, "APSU_QUEUE_CONCURRENCY",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage: "Oban's concurrency per declared queue; a bound until a queue is measured"},
      # Lifeline moves a job still `executing` after this long back to
      # `available`, or to `discarded` if it has no attempt left: the
      # rescue for a job orphaned when the node stopped mid-run, which on
      # Render is every deploy. It is time alone, so it must exceed the
      # longest job that is still legitimately running, or Lifeline
      # rescues a live job and it runs twice. The longest is a regression
      # run: EUNOMIA_RUN_MODELS_MAX x EUNOMIA_RUN_TESTS_MAX calls (8 x 32)
      # at up to NISABA_REQUEST_TIMEOUT_MS (120 s) each, 512 minutes;
      # Req does not retry a POST. 540 is that with a margin, and a test
      # holds it above the product of the three settings.
      {:lifeline_rescue_after_minutes, "APSU_LIFELINE_RESCUE_AFTER_MINUTES",
       cast: :integer,
       default: "540",
       tag: :bound,
       usage:
         "how long a job may stay executing before Oban's Lifeline takes it for orphaned and rescues it; a guess derived from the longest regression run the bounds allow at the request timeout, not a measured run, and it must stay above that product"},
      {:vault_key, "APSU_VAULT_KEY",
       cast: &Vault.cast_key/1,
       secret: true,
       usage: "the deployment key secrets at rest are encrypted under (Oneiroi.Apsu.Vault)"},
      {:clock, "APSU_CLOCK",
       cast: &__MODULE__.cast_clock/1,
       default: "system",
       usage: "the injected clock: system in every real build, fake in test (conventions §9)"}
    ]
  end

  @doc """
  Casts the endpoint secret, holding Plug.Session.Cookie's 64-byte floor.

  Two forms are accepted. A value of 64 bytes or more is used as given
  (`mix phx.gen.secret 64`). A base64 value decoding to 32 bytes or more
  is what Render's `generateValue` produces (render.yaml): 256 bits of
  key, in 44 characters, so short of the floor in length and not in
  entropy. It is expanded to 64 bytes with HMAC-SHA512 under a fixed
  label, deterministically, so every instance of a deployment derives
  the same secret from the same value.
  """
  @spec cast_secret_key_base(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def cast_secret_key_base(raw) when byte_size(raw) >= 64, do: {:ok, raw}

  def cast_secret_key_base(raw) do
    case Base.decode64(raw) do
      {:ok, key} when byte_size(key) >= 32 ->
        {:ok, Base.encode64(:crypto.mac(:hmac, :sha512, key, "oneiroi:apsu:secret_key_base"))}

      _ ->
        {:error,
         "must be at least 64 bytes (Plug.Session.Cookie's minimum), or base64 of at least 32, " <>
           "is #{byte_size(raw)} bytes"}
    end
  end

  @doc """
  Casts the public URL into the endpoint's `url:` options: the scheme,
  host and port `Phoenix.Endpoint.url/0` is built from, which is the
  string `OneiroiWeb.Plugs.Origin` compares a browser's `Origin` against.
  A path, query or fragment is refused rather than dropped: an origin has
  none, so a value carrying one was not the origin and dropping the rest
  would accept a mistake silently. The reason names no part of the value
  because the declaration is not a secret, but the report is one line
  per problem and the value is in the environment already.
  """
  @spec cast_public_url(String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def cast_public_url(raw) do
    case URI.parse(raw) do
      %URI{scheme: scheme, host: host, port: port, path: path, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             path in [nil, "", "/"] ->
        {:ok, [scheme: scheme, host: host, port: port]}

      _ ->
        # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
        {:error, "is not an origin (expected https://host, or http://host:port, with no path)"}
    end
  end

  @doc """
  Casts a database URL into the options the Repo and the store merge. A
  managed platform may append `?sslmode=require`, which Ecto's parser
  refuses, so the query string is stripped and TLS set explicitly. The
  reason names no part of the value: this one carries a password.
  """
  @spec cast_database_url(String.t()) :: {:ok, keyword()} | {:error, String.t()}
  def cast_database_url(raw) do
    [base | _query] = String.split(raw, "?", parts: 2)

    case URI.new(base) do
      {:ok, %URI{scheme: scheme, host: host}}
      when is_binary(scheme) and is_binary(host) and host != "" ->
        {:ok, [url: base, ssl: ssl_option(raw)]}

      _other ->
        # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
        {:error, "is not a database URL (expected scheme://user:password@host/database)"}
    end
  end

  defp ssl_option(raw) do
    if String.contains?(raw, "sslmode=require"), do: [verify: :verify_none], else: false
  end

  @doc "Casts the configured clock name to its module."
  @spec cast_clock(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_clock("system"), do: {:ok, Oneiroi.Clock.System}
  def cast_clock("fake"), do: {:ok, Oneiroi.Apsu.Clock.Fake}

  # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
  def cast_clock(other), do: {:error, "is #{inspect(other)}, expected \"system\" or \"fake\""}

  @impl Oneiroi.Component
  def errors do
    [
      {:apsu_not_ready,
       "the readiness probe's query raised: the database is unreachable or the pool has not started",
       remedy:
         "check the database's status and DATABASE_URL; the log line carrying this error's site names the exception's class"},
      {:apsu_enqueue_failed, "a job was not enqueued: Oban refused the insert",
       remedy:
         "the job's args or options were invalid, or the database refused the row; the log line carrying this error's site names the cause's class"}
    ]
  end

  @impl Oneiroi.Component
  def processes do
    [{:apsu_pubsub, :local}]
  end

  @impl Oneiroi.Component
  def telemetry_events do
    [[:oneiroi, :apsu, :repo, :query]]
  end

  @impl Oneiroi.Component
  def policies do
    [
      {Oneiroi.Apsu.Policies.Gates, "pipeline.config.json",
       policy: "conventions §2: the gate set is identical in CLAUDE.md, ci.yml and qualityGates"},
      {Oneiroi.Apsu.Policies.Skips, "test/**/*.exs",
       policy: "conventions §9: a skipped test names the ticket that owns it"},
      {Oneiroi.Apsu.Policies.Tables, "priv/repo/migrations/*.exs",
       policy: "conventions §12: every table has one owner, a scope column and a row-level policy"},
      {Oneiroi.Apsu.Policies.ErrorSite, "lib/**/*.ex",
       policy:
         "conventions §8: every error built or caught names a site, prefixed and written at one line"},
      {Oneiroi.Apsu.Policies.ProjectorScope, "lib/oneiroi/*/projectors/*.ex",
       policy:
         "conventions §12: a projector's query names its tenant, because it runs under the platform scope"}
    ]
  end

  @impl Oneiroi.Component
  def children do
    [
      {Phoenix.PubSub, name: :apsu_pubsub},
      Oneiroi.Repo,
      Oneiroi.Commanded,
      {Oban, oban_config()}
    ]
  end

  @impl Oneiroi.Component
  def ready? do
    match?({:ok, _}, SQL.query(Oneiroi.Repo, "SELECT 1", []))
  rescue
    # The probe answers a boolean; what it caught is named in the log
    # rather than swallowed, by its class alone.
    exception ->
      e = Error.caught(:apsu_not_ready, :apsu_ready_query_raised, exception)
      Logger.warning("apsu: the readiness probe's query raised", Oneiroi.Error.metadata(e))
      false
  end

  @doc """
  Oban's configuration, composed from every system's `oban_queues/0`:
  the queues at the declared concurrency and the crontab from the
  queues' `cron:` entries, and Lifeline's rescue of orphaned jobs. A
  root artifact composed from declarations, never edited (conventions
  §4). In test Oban runs in manual mode and starts no queue and no
  plugin.
  """
  @spec oban_config() :: keyword()
  def oban_config do
    inventory = Composer.inventory(Oneiroi.Boot.components())
    concurrency = Oneiroi.Config.fetch!(:apsu, :queue_concurrency)
    queues = for entry <- inventory.oban_queues, do: {entry.queue, concurrency}

    crontab =
      for entry <- inventory.oban_queues,
          {schedule, worker} <- Keyword.get(entry.opts, :cron, []),
          do: {schedule, worker}

    base = [repo: Oneiroi.Repo, queues: queues, plugins: plugins(crontab)]
    Keyword.merge(base, Application.get_env(:oneiroi, Oban, []))
  end

  # Lifeline is always on (eunomia #30): without it a job orphaned by a
  # deploy stays `executing` forever, and so does whatever it was doing.
  # It rescues every queue's orphans, not only the one that asked for
  # it; a rescued job with attempts left runs again, which every worker
  # must survive (conventions §7), and one that must not run twice
  # declares a single attempt and is discarded instead.
  defp plugins(crontab) do
    lifeline =
      {Oban.Lifeline,
       rescue_after: {Oneiroi.Config.fetch!(:apsu, :lifeline_rescue_after_minutes), :minutes}}

    case crontab do
      [] -> [lifeline]
      entries -> [{Oban.Plugins.Cron, crontab: entries}, lifeline]
    end
  end
end
