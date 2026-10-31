defmodule Mix.Tasks.Oneiroi.Import.DryRun do
  @shortdoc "Rehearses an import on a throwaway store: no turn, no model call (sima-qian #18)"
  @moduledoc """
  `mix oneiroi.import.dry_run --source DIR --name NAME --slug SLUG [--report FILE]`

  Imports the repository checked out at `DIR` exactly as production's
  import does, backs it up once to a local bare remote, and prints a
  report of names and counts, never contents (`Oneiroi.SimaQian.DryRun`).
  The report is written to `FILE` too when given, which is how the
  workflow puts it in the job summary.

  Two refusals, before anything is written: the provider must be the
  in-memory one (`NISABA_PROVIDER=fake`), so no model is called and no
  key is needed; and the store must hold no resident, so the rehearsal
  can never land in a store someone lives in. The exit code is 0 when
  the import and the backup ran, 1 when either failed, 2 on a refusal.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  alias Oneiroi.Actor
  alias Oneiroi.SimaQian.DryRun

  @switches [source: :string, name: :string, slug: :string, report: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)
    source = Keyword.get(opts, :source) || Mix.raise("--source is required")
    name = Keyword.get(opts, :name) || Mix.raise("--name is required")
    slug = Keyword.get(opts, :slug) || Mix.raise("--slug is required")
    Mix.Task.run("app.start")

    case refusal(Oneiroi.Config.fetch!(:nisaba, :provider), Oneiroi.AgathosDaimon.residents()) do
      nil -> :ok
      reason -> refuse(reason)
    end

    {:ok, account} = account()
    witness = Actor.new(:witness, account)
    outcome = DryRun.run(source, %{name: name, slug: slug}, account, witness)
    text = DryRun.markdown(outcome)
    Mix.shell().info(text)
    if path = Keyword.get(opts, :report), do: File.write!(path, text)
    if elem(outcome, 0) != :ok, do: exit({:shutdown, 1})
  end

  @doc "Why the rehearsal may not run with `provider` on a store holding `residents`, or nil."
  @spec refusal(module(), [map()]) :: String.t() | nil
  def refusal(provider, residents) do
    cond do
      provider != Oneiroi.Nisaba.Provider.Fake ->
        "NISABA_PROVIDER must be fake: a dry run makes no model call"

      residents != [] ->
        "this store already holds a resident: a dry run runs on a throwaway store only"

      true ->
        nil
    end
  end

  defp refuse(reason) do
    Mix.shell().error("IMPORT DRY RUN: REFUSED, " <> reason)
    exit({:shutdown, 2})
  end

  # The throwaway witness, with a placeholder key the in-memory provider
  # accepts; the password is random and printed nowhere.
  defp account do
    password = 24 |> :crypto.strong_rand_bytes() |> Base.encode64()
    platform = Actor.platform()

    with {:ok, id} <- Oneiroi.Gaia.create_account("dry-run@oneiroi.invalid", password, platform),
         :ok <- Oneiroi.Gaia.store_key(id, "sk-dry-run", Actor.new(:witness, id)),
         do: {:ok, id}
  end
end
