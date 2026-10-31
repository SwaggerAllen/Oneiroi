defmodule Oneiroi.Proteus do
  @moduledoc """
  The bridge to Honcho (spec §6.9): one workspace per resident, named by
  the resident's id; peers for the resident and its witness; the card
  from git, always; every captured turn synced as the two peers' words;
  the context Honcho holds on the person read into the brain's turn;
  the weekly card audit; and workspace-scoped, expiring keys for a
  hands runtime, the admin key never leaving the core.

  Everything goes through the port (`Oneiroi.Proteus.Honcho`), named in
  `PROTEUS_CLIENT`, with Honcho's HTTP API behind it in every real build
  and an in-memory Honcho in the suite. Correspondence is not sent to
  Honcho; a person's own peer past a threshold is the inbound phase's.
  """
  use Oneiroi.System, slug: :proteus

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
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
      Jason,
      Oban,
      Req,
      Req.Response
    ],
    exports: [
      Error,
      Bridge,
      Bridges,
      Honcho,
      Honcho.Fake,
      Honcho.HTTP,
      Router,
      CardAuditWorker,
      Commands.Provision,
      Commands.AddPeer,
      Commands.RecordCard,
      Commands.RecordCardAudit,
      Commands.RecordSync,
      Commands.RecordKey,
      Events.WorkspaceProvisioned,
      Events.PeerAdded,
      Events.CardSet,
      Events.CardAudited,
      Events.CardAuditFailed,
      Events.TurnSynced,
      Events.SyncFailed,
      Events.KeyMinted,
      Store,
      Store.Bridge,
      Store.Sync
    ]

  alias Oneiroi.Proteus.Bridges

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:client, "PROTEUS_CLIENT",
       cast: &__MODULE__.cast_client/1,
       default: "honcho",
       usage:
         "which Honcho port implementation answers: honcho (its HTTP API) in every real build, fake in test (conventions §9)"},
      # The one place the host is spelled outside the port: the setting
      # the port reads it from.
      {:honcho_url, "PROTEUS_HONCHO_URL",
       cast: &__MODULE__.cast_url/1,
       required: false,
       usage:
         "where Honcho answers, on the private network (spec §6.9): a URL, or the host:port Render's blueprint hands over, read as http (proteus #16); unset until a Honcho is deployed beside this instance, and the port fails with it unset"},
      {:honcho_admin_key, "PROTEUS_HONCHO_ADMIN_KEY",
       secret: true,
       required: false,
       usage:
         "Honcho's admin JWT, which mints the workspace-scoped keys and never leaves the core (spec §6.9); when unset, minted from PROTEUS_HONCHO_JWT_SECRET"},
      {:honcho_jwt_secret, "PROTEUS_HONCHO_JWT_SECRET",
       secret: true,
       required: false,
       usage:
         "the AUTH_JWT_SECRET Honcho signs with, from which the core mints the admin JWT when PROTEUS_HONCHO_ADMIN_KEY is unset (proteus #16): the blueprint copies it from the Honcho it generated it for, so no key is typed"},
      {:request_timeout_ms, "PROTEUS_REQUEST_TIMEOUT_MS",
       cast: :integer,
       default: "10000",
       tag: :bound,
       usage:
         "how long a Honcho call waits before the bridge records it as unreachable; a bound until measured"},
      {:context_tokens, "PROTEUS_CONTEXT_TOKENS",
       cast: :integer,
       default: "800",
       tag: :bound,
       usage:
         "how much of Honcho's context on the person the brain's turn takes (spec §5); a guess at the prefix's share, not measured"},
      {:key_ttl_hours, "PROTEUS_KEY_TTL_HOURS",
       cast: :integer,
       default: "24",
       tag: :bound,
       usage:
         "how long a hands runtime's workspace-scoped Honcho key lives (spec §6.9); a bound, re-minted on wake"}
    ]
  end

  @doc false
  def cast_client("honcho"), do: {:ok, :"Elixir.Oneiroi.Proteus.Honcho.HTTP"}
  def cast_client("fake"), do: {:ok, :"Elixir.Oneiroi.Proteus.Honcho.Fake"}
  def cast_client(other), do: {:error, "is #{inspect(other)}, expected \"honcho\" or \"fake\""}

  @doc "A Honcho URL as given, or a bare host:port read as http: a private service's address on Render's network carries no scheme (proteus #16)."
  def cast_url(raw) do
    case URI.parse(raw) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, raw}

      _bare ->
        bare_url(raw)
    end
  end

  # The port is explicit: a bare host would take http's 80 by default,
  # and a private service never listens there unasked.
  defp bare_url(raw) do
    with %URI{host: host} when is_binary(host) and host != "" <- URI.parse("http://" <> raw),
         true <- Regex.match?(~r/:\d+\z/, raw) do
      {:ok, "http://" <> raw}
    else
      _other -> {:error, "is #{inspect(raw)}, expected an http(s) URL or host:port"}
    end
  end

  @impl Oneiroi.Component
  def feature_flags, do: [:proteus_honcho_off]

  @impl Oneiroi.Component
  def externals do
    [
      {:honcho,
       adapter: Oneiroi.Proteus.Honcho.HTTP,
       fake: Oneiroi.Proteus.Honcho.Fake,
       kill_switch: :proteus_honcho_off,
       classification: :personal}
    ]
  end

  @impl Oneiroi.Component
  def oban_queues do
    [{:proteus_weekly, cron: [{"0 3 * * 0", Oneiroi.Proteus.CardAuditWorker}]}]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Proteus.Events.WorkspaceProvisioned, 1},
      {Oneiroi.Proteus.Events.PeerAdded, 1},
      {Oneiroi.Proteus.Events.CardSet, 1},
      {Oneiroi.Proteus.Events.CardAudited, 1},
      {Oneiroi.Proteus.Events.CardAuditFailed, 1},
      {Oneiroi.Proteus.Events.TurnSynced, 1},
      {Oneiroi.Proteus.Events.SyncFailed, 1},
      {Oneiroi.Proteus.Events.KeyMinted, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:proteus_honcho_unreachable, "Honcho did not answer",
       remedy: "the bridge recorded it; the turn went on; check Honcho"},
      {:proteus_honcho_rejected, "Honcho refused the request",
       remedy: "the shape or the key is wrong; read the reason"},
      {:proteus_not_provisioned, "the resident has no workspace yet",
       remedy: "the first captured turn provisions it"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Proteus.Projectors.Bridge]

  @doc "Provisions the workspace and peers, once, and sets the card from git."
  @spec provision(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(provision(resident_id, actor), do: Bridges.provision(resident_id, actor))

  @doc "Sets the card at Honcho from git (source: commit, audit or provision); no event when unchanged."
  @spec set_card(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, :set | :unchanged} | {:error, term()}
  defexport(set_card(resident_id, source, actor),
    do: Bridges.set_card(resident_id, source, actor)
  )

  @doc "The card from git: the soul and identity files as lines."
  @spec card(String.t()) :: [String.t()]
  defexport(card(resident_id), do: Bridges.card(resident_id))

  @doc "The weekly card audit: pins the card back if a dream moved it; recorded either way."
  @spec audit_card(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(audit_card(resident_id, actor), do: Bridges.audit_card(resident_id, actor))

  @doc "Syncs a captured turn's messages to Honcho, once per turn; a failure is recorded and returned, never raised."
  @spec sync_turn(String.t(), String.t(), String.t(), [map()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(sync_turn(resident_id, session_key, turn_ref, messages, actor),
    do: Bridges.sync_turn(resident_id, session_key, turn_ref, messages, actor)
  )

  @doc "Honcho's context on the person in the resident's eyes, for the brain; empty when none."
  @spec context(String.t()) :: String.t()
  defexport(context(resident_id), do: Bridges.context(resident_id))

  @doc "What Honcho concluded about the person, at most `limit`, for the memory audit."
  @spec conclusions(String.t(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  defexport(conclusions(resident_id, limit), do: Bridges.conclusions(resident_id, limit))

  @doc "Deletes one conclusion from Honcho: an approved audit flag."
  @spec delete_conclusion(String.t(), String.t()) :: :ok | {:error, term()}
  defexport(delete_conclusion(resident_id, id), do: Bridges.delete_conclusion(resident_id, id))

  @doc "The bridge row, or nil before provisioning."
  @spec bridge(String.t()) :: Oneiroi.Proteus.Store.Bridge.t() | nil
  defexport(bridge(resident_id), do: Bridges.bridge(resident_id))

  @doc "The latest syncs."
  @spec syncs(String.t(), pos_integer()) :: [Oneiroi.Proteus.Store.Sync.t()]
  defexport(syncs(resident_id, limit), do: Bridges.syncs(resident_id, limit))

  @doc "A workspace-scoped, expiring key for a hands runtime; returned once."
  @spec mint_key(String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, String.t(), DateTime.t()} | {:error, term()}
  defexport(mint_key(resident_id, peer, actor), do: Bridges.mint_key(resident_id, peer, actor))
end
