defmodule Mix.Tasks.Oneiroi.Setup do
  @shortdoc "Creates the one account a self-hosted instance starts with"
  @moduledoc """
  `mix oneiroi.setup --email you@example.org --password '...'`

  The self-hosted instance's one account (spec §6.1): the same code the
  hosted sign-up will use at the threshold (P1), run once from the shell.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [email: :string, password: :string])

    email = Keyword.get(opts, :email) || Mix.raise("--email is required")
    password = Keyword.get(opts, :password) || Mix.raise("--password is required")
    Mix.Task.run("app.start")

    case Oneiroi.Identity.create_account(email, password, Oneiroi.Actor.platform()) do
      {:ok, id} -> Mix.shell().info("account #{id} created for #{email}")
      {:error, reason} -> Mix.raise("account not created: #{inspect(reason)}")
    end
  end
end
