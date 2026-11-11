defmodule Mix.Tasks.Oneiroi.Dev.Seed do
  @shortdoc "Seeds the local dev database with a witness and a resident to test against"
  @moduledoc """
  `mix oneiroi.dev.seed`

  The local app server's household (SETUP.md §7, brain#81): writes
  `Oneiroi.Brain.DevSeed` into a fresh dev database. Refused outside the
  dev environment and on any database whose name does not end in
  `_dev`; a second run finds the account and changes nothing. The turns
  go through the configured provider: under `bin/dev`'s default, the
  in-memory one, which answers each message by repeating it, at no cost.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  alias Oneiroi.Brain.DevSeed

  @email "dev@oneiroi.local"
  @password "oneiroi-dev-password"

  @impl Mix.Task
  def run(_args) do
    if Mix.env() != :dev, do: Mix.raise("dev.seed runs only in the dev environment")
    # The seed runs beside a server that may already hold the port.
    Application.put_env(:oneiroi, :serve, false)
    Mix.Task.run("app.start")
    # The projectors log every event at debug; the seed says only its result.
    Logger.configure(level: :warning)
    database = Oneiroi.Repo.config()[:database] || ""

    unless String.ends_with?(database, "_dev"),
      do: Mix.raise("dev.seed refuses the database #{inspect(database)}: only a *_dev one")

    case DevSeed.run(@email, @password) do
      {:ok, id} -> Mix.shell().info("seeded: #{@email} / #{@password}, resident Wren (#{id})")
      :exists -> Mix.shell().info("already seeded: #{@email} / #{@password}")
    end
  end
end
