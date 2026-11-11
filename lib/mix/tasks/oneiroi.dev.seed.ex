defmodule Mix.Tasks.Oneiroi.Dev.Seed do
  @shortdoc "Seeds the local dev database with a witness and a resident to test against"
  @moduledoc """
  `mix oneiroi.dev.seed`

  The local app server's test household (SETUP.md, "A local app
  server"): one witness account and one resident, Wren, whose
  conversation already holds the shapes the client has to lay out: a
  short exchange, a long paragraph, a code block with a line far wider
  than a phone, a table, and a word too long to wrap. Run by `bin/dev`
  on a fresh database; nothing here is a person's.

  Refused outside the dev environment and on any database whose name
  does not end in `_dev`, and a no-op when the account already exists, so
  running it twice changes nothing. The turns go through the configured
  provider: under `bin/dev`'s default, the in-memory one, which answers
  each message by repeating it, at no cost.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  alias Oneiroi.Actor

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

    case Oneiroi.Gaia.create_account(@email, @password, Actor.platform()) do
      {:ok, account} -> seed(account)
      {:error, _exists} -> Mix.shell().info("already seeded: #{@email} / #{@password}")
    end
  end

  defp seed(account) do
    witness = Actor.new(:witness, account)
    :ok = Oneiroi.Gaia.store_key(account, "sk-dev-placeholder", witness)
    {:ok, id} = Oneiroi.AgathosDaimon.create("Wren", "wren", account, witness)
    {:ok, key} = Oneiroi.Brain.main_session(id, account, witness)

    for message <- messages() do
      case Oneiroi.Brain.turn(id, key, message, witness) do
        {:ok, _} -> :ok
        other -> Mix.shell().error("a seed turn did not complete: #{inspect(other)}")
      end
    end

    Mix.shell().info("seeded: #{@email} / #{@password}, resident Wren (#{id})")
  end

  defp messages do
    [
      "Good morning, Wren.",
      """
      A long paragraph, to see how running text sits in a bubble at phone width and on a wide screen alike: \
      the lines should wrap at the edge of the message, the message should keep its margin from the edge of \
      the screen, and nothing should need a sideways scroll to read.
      """,
      """
      A code block with one very long line:

      ```elixir
      def a_function_with_a_rather_long_name(first_argument, second_argument, third_argument), do: {first_argument, second_argument, third_argument, :and_then_some_more}
      ```
      """,
      """
      A wide table:

      | Day | Morning | Afternoon | Evening | Night | Notes on the day, kept long on purpose |
      | --- | --- | --- | --- | --- | --- |
      | Monday | reading | letters | the walk | sleep | a quiet start to the week, nothing pressing |
      | Tuesday | writing | outreach | dinner | sleep | two messages out, one answered |
      """,
      "One word too long to wrap: https://example.org/a/very/long/path/that/keeps/going/without/a/single/space/anywhere/in/it"
    ]
  end
end
