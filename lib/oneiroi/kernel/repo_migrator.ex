defmodule Oneiroi.Repo.Migrator do
  @moduledoc """
  The migration connection: the same database as `Oneiroi.Repo`, as the
  credential's own role rather than the application role, because DDL and
  the role grants are the migrator's and the application role has no
  such rights (conventions §12). Used by `mix ecto.*` and
  `Oneiroi.Release.migrate/0` and by nothing in application code; it is
  not a second Repo in conventions §6's sense but the one door through
  which the schema changes.
  """
  use Ecto.Repo, otp_app: :oneiroi, adapter: Ecto.Adapters.Postgres

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @impl Ecto.Repo
  def init(_context, config) do
    Oneiroi.Boot.load!()

    {:ok,
     config
     |> Keyword.merge(Secret.unwrap(Config.fetch!(:apsu, :database_url)))
     |> Keyword.put(:pool_size, 2)
     |> Keyword.put(:priv, "priv/repo")}
  end
end
