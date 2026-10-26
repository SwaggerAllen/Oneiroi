defmodule Oneiroi.Release do
  @moduledoc """
  Release tasks, run via `bin/oneiroi eval`: no Mix inside a release.
  `migrate/0` runs in the container's own start command ahead of `start`
  (the Dockerfile), through the migrator connection, so the application
  role never needs DDL rights.
  """

  @app :oneiroi

  def migrate do
    Application.load(@app)
    Oneiroi.Boot.load!()
    path = Application.app_dir(@app, "priv/repo/migrations")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(
        Oneiroi.Repo.Migrator,
        &Ecto.Migrator.run(&1, path, :up, all: true),
        pool_size: 2
      )

    :ok
  end
end
