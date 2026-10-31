defmodule Mix.Tasks.Oneiroi.Fixture.Run do
  @shortdoc "A full run on a fixture resident against the configured provider (brain #37)"
  @moduledoc """
  `mix oneiroi.fixture.run --chat-model SLUG --judge-model SLUG [--turns N] [--report FILE] [--archive DIR] [--asks DIR]`

  Creates a witness and a fixture (spec §12, P40) on the store, runs the
  fixture script's turns with the judge reading each reply for an ask to
  continue (P57), then the nightly pass, the wash and the audits, and
  prints the report (`Oneiroi.Brain.FixtureRun`). With `--archive`, the
  fixture's export is written under `DIR`: a fixture that accretes
  memory is archived, never deleted, and the workflow commits that
  directory to the archive branch. With `--asks`, any ask is written
  under `DIR` for the workflow to tell the author: `asks.md` for every
  ask, and `precedent.md` when one ended the run.

  The OpenRouter key is read from `OPENROUTER_API_KEY`, the one name the
  workflow's secret is passed under, and printed nowhere; with the
  in-memory provider a placeholder stands in. Refused, before anything is
  written, on a store that holds any resident who is not a fixture: a
  run lands only where nobody lives. Exit 0 when every turn and step ran,
  1 otherwise, 2 on a refusal.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  alias Oneiroi.Actor
  alias Oneiroi.Brain.FixtureRun
  alias Oneiroi.SimaQian.Export

  @switches [
    chat_model: :string,
    judge_model: :string,
    turns: :integer,
    report: :string,
    archive: :string,
    asks: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)
    chat = Keyword.get(opts, :chat_model) || Mix.raise("--chat-model is required")
    judge = Keyword.get(opts, :judge_model) || Mix.raise("--judge-model is required")
    turns = Keyword.get(opts, :turns, length(FixtureRun.script()))
    Mix.Task.run("app.start")

    provider = Oneiroi.Config.fetch!(:nisaba, :provider)

    case refusal(provider, Oneiroi.AgathosDaimon.residents(), key()) do
      nil -> :ok
      reason -> refuse(reason)
    end

    {:ok, account} = account(key())
    outcome = FixtureRun.run(account, %{chat_model: chat, judge_model: judge, turns: turns})
    text = FixtureRun.markdown(outcome)
    Mix.shell().info(text)
    if path = Keyword.get(opts, :report), do: File.write!(path, text)
    if dir = Keyword.get(opts, :archive), do: archive(outcome, dir)
    if dir = Keyword.get(opts, :asks), do: asks(outcome, dir)
    if elem(outcome, 0) != :ok, do: exit({:shutdown, 1})
  end

  @doc "Why the run may not happen with `provider` on a store holding `residents`, with `key`, or nil."
  @spec refusal(module(), [map()], String.t() | nil) :: String.t() | nil
  def refusal(provider, residents, key) do
    fake? = provider == Oneiroi.Nisaba.Provider.Fake

    cond do
      Enum.any?(residents, &(&1.kind != "fixture")) ->
        "this store holds a resident who is not a fixture: a fixture run happens only where nobody lives"

      not fake? and key in [nil, ""] ->
        "OPENROUTER_API_KEY is not set and the provider is a real one"

      true ->
        nil
    end
  end

  @doc "Writes a run's asks to continue under `dir` (P57): `asks.md` when any, `precedent.md` when one ended the run."
  # The directory is the task's own argument, named by the workflow.
  # sobelow_skip ["Traversal.FileModule"]
  @spec asks({atom(), map()}, Path.t()) :: :ok
  def asks({_outcome, report}, dir) do
    File.mkdir_p!(dir)

    with text when is_binary(text) <- FixtureRun.asks_markdown(report),
         do: File.write!(Path.join(dir, "asks.md"), text)

    with text when is_binary(text) <- FixtureRun.asks_markdown(report, ["continue"]),
         do: File.write!(Path.join(dir, "precedent.md"), text)

    :ok
  end

  # The secret's one name; a placeholder for the in-memory provider.
  defp key, do: System.get_env("OPENROUTER_API_KEY")

  defp refuse(reason) do
    Mix.shell().error("FIXTURE RUN: REFUSED, " <> reason)
    exit({:shutdown, 2})
  end

  defp account(key) do
    password = 24 |> :crypto.strong_rand_bytes() |> Base.encode64()

    with {:ok, id} <-
           Oneiroi.Gaia.create_account("fixture@oneiroi.invalid", password, Actor.platform()),
         :ok <-
           Oneiroi.Gaia.store_key(id, key || "sk-fixture-placeholder", Actor.new(:witness, id)),
         do: {:ok, id}
  end

  defp archive({_outcome, %{resident_id: id}}, dir) do
    File.mkdir_p!(dir)
    {:ok, _} = Export.write(id, dir)
    :ok
  end

  defp archive(_setup_failed, _dir), do: :ok
end
