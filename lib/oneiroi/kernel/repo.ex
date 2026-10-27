defmodule Oneiroi.Repo do
  @moduledoc """
  The one Repo (conventions §6), owned by Apsu. Stores own
  schemas and queries, never connections.

  Two things happen on every connection and every query, and both are
  tenancy (conventions §12). On connect, `SET ROLE oneiroi_app`: the
  application role owns nothing, cannot bypass row-level security and
  cannot run DDL, so the credential the deployment supplies is the
  migrator's and the application never acts as it. On every query,
  `prepare_query/3` refuses a read from a process with no
  `Oneiroi.Scope` set, so an unscoped read fails here with a named
  error rather than at the database with an empty result.

  Connection settings are assembled from the platform's declared
  settings in `init/2`, never re-declared in config.
  """
  use Ecto.Repo, otp_app: :oneiroi, adapter: Ecto.Adapters.Postgres

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  defmodule UnscopedError do
    @moduledoc "Raised by a query from a process that holds no scope."
    defexception [:message]
  end

  @impl Ecto.Repo
  def init(_context, config) do
    Oneiroi.Boot.load!()

    {:ok,
     config
     |> Keyword.merge(Secret.unwrap(Config.fetch!(:apsu, :database_url)))
     |> Keyword.put(:pool_size, Config.fetch!(:apsu, :pool_size))
     |> Keyword.put(:after_connect, {__MODULE__, :set_role, []})
     |> Keyword.put(:telemetry_prefix, [:oneiroi, :apsu, :repo])}
  end

  @doc "Takes the application role on a fresh connection (conventions §12)."
  @spec set_role(pid()) :: :ok
  def set_role(conn) do
    Postgrex.query!(conn, "SET ROLE #{app_role()}", [])
    :ok
  end

  @doc "The application role's name, one literal in one place."
  @spec app_role() :: String.t()
  def app_role, do: "oneiroi_app"

  # The process key `Oneiroi.Scope` writes, read here by name rather than
  # through `Oneiroi.Scope.current/0`: the scope runs its transactions on
  # this repo, so the repo naming the scope back is a cycle. The spine
  # test asserts the two agree (a scoped query passes, an unscoped one
  # raises), which is what holds the literal in both places together.
  @scope_key :oneiroi_scope

  @impl Ecto.Repo
  def prepare_query(_operation, query, opts) do
    if Process.get(@scope_key) == nil and not Keyword.get(opts, :oneiroi_unscoped, false) do
      raise UnscopedError,
        message:
          "a query ran with no Oneiroi.Scope set (wrap it in Oneiroi.Scope.resident/2, " <>
            "account/2 or platform/1; conventions §12)"
    end

    {query, opts}
  end
end
