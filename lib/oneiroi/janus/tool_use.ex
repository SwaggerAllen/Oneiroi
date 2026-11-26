defmodule Oneiroi.Janus.ToolUse do
  @moduledoc """
  Tool calls on Oneiroi by model (janus#11): each night, the day before's
  calls across every resident, counted by the model that made them and
  how many the brain could not run (arguments that were not a JSON
  object, a tool that does not exist), kept a day to a row so the totals
  run on. Independent of anyone's judgment of her: what the catalog and
  the pool show beside a model's price.

  Only counts cross from memory (`Kumbukumbu.tool_call_counts/4`): no
  words of any call leave the database.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Janus.Store
  alias Oneiroi.Janus.Store.ToolUse, as: Row
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  # The brain's own answers to a call it could not run
  # (`Oneiroi.Brain.Tools`); a test holds these to the brain's words.
  @failures [
    "Not done: the arguments were not a JSON object",
    "Not done: there is no tool named"
  ]

  @doc "The answers that mark a call the brain could not run."
  @spec failures() :: [String.t()]
  def failures, do: @failures

  @doc "Counts `day`'s calls (a UTC date) and replaces that day's rows; `{:ok, models}`."
  @spec count(Date.t()) :: {:ok, non_neg_integer()}
  def count(%Date{} = day) do
    from_at = DateTime.new!(day, ~T[00:00:00.000000], "Etc/UTC")
    to_at = DateTime.add(from_at, 86_400, :second)

    totals =
      AgathosDaimon.residents()
      |> Enum.flat_map(&Kumbukumbu.tool_call_counts(&1.id, from_at, to_at, @failures))
      |> Enum.group_by(& &1.model)
      |> Enum.map(fn {model, rows} ->
        %{
          model: model,
          day: day,
          calls: rows |> Enum.map(& &1.calls) |> Enum.sum(),
          failed: rows |> Enum.map(& &1.failed) |> Enum.sum()
        }
      end)

    Scope.platform(fn ->
      Repo.delete_all(from(t in Row, where: t.day == ^day))
      Repo.insert_all(Row, totals)
    end)

    {:ok, length(totals)}
  end

  @doc "The running totals: `%{model => {calls, failed}}`."
  @spec totals() :: %{String.t() => {non_neg_integer(), non_neg_integer()}}
  def totals, do: Scope.platform(&Store.tool_use/0)
end
