defmodule Oneiroi.Eunomia.Judge do
  @moduledoc """
  The judge's two calls (spec §6.4): advice on a live dispute, and the
  nightly reading of a day. Both go through the ledger under the `judge`
  purpose on the judge's model, which is recorded on every verdict and
  is never the resident's own chat model. The prompts are files under
  `priv/prompts/` and stay constitutional: they ask the judge to weigh
  the resident's stated positions and the witness's claim, never to
  grade the resident.

  The live check is bounded by `EUNOMIA_LIVE_CHECK_MS`: past it the
  resident is told to answer alone and the check is recorded as
  `timed_out`, unjudged rather than failed. The nightly reading parses
  the judge's reply strictly: a dispute citing a message it was not
  shown fails the night rather than being guessed at.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @advice ~r/\bADVICE:\s*(concede|hold|unclear)\b/i
  @dispute ~r/^DISPUTE\s+\[([0-9,\s\-]+)\]\s*(conceded|held)\s*\|\s*(.*)$/im
  @summary ~r/^SUMMARY:\s*(.*)$/im

  @doc "The judge's actor, carrying its model."
  @spec actor(String.t()) :: Actor.t()
  def actor(model), do: Actor.new(:judge, "eunomia", model)

  @doc """
  Advice on a live dispute, within the live-check bound: `{:ok, advice,
  text}`, `:timed_out`, or `{:error, reason}`.
  """
  @spec advise(String.t(), String.t(), map()) ::
          {:ok, String.t(), String.t()} | :timed_out | {:error, term()}
  def advise(resident_id, model, %{claim: claim, stance: stance} = attrs) do
    prompt =
      Prompt.message("judge_dispute", %{
        position: attrs[:position] || "none stated",
        claim: claim,
        stance: stance
      })

    request = Request.new(model, [prompt, %{role: :user, content: "Your advice?"}])
    task = Task.async(fn -> Nisaba.call(resident_id, :judge, request, actor(model)) end)

    case Task.yield(task, Config.fetch!(:eunomia, :live_check_ms)) || Task.shutdown(task) do
      {:ok, {:ok, %Result{content: content}}} -> {:ok, parse_advice(content), content || ""}
      {:ok, {:error, reason}} -> {:error, reason}
      nil -> :timed_out
    end
  end

  @doc """
  The nightly reading: the day's messages, numbered, to the judge; back
  come the disputes it found (each citing message numbers, with an
  outcome and its words) and a summary. `{:error, reason}` when the
  reply names a message it was not shown.
  """
  @spec night(String.t(), String.t(), [map()]) ::
          {:ok, [map()], String.t()} | {:error, term()}
  def night(resident_id, model, messages) do
    listed =
      messages
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {m, i} -> "[#{i}] #{m.role}: #{m.content}" end)

    prompt = Prompt.message("judge_night", %{messages: listed})
    request = Request.new(model, [prompt, %{role: :user, content: "Your reading of the day?"}])

    case Nisaba.call(resident_id, :judge, request, actor(model)) do
      {:ok, %Result{content: content}} -> parse_night(content || "", length(messages), messages)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_advice(content) when is_binary(content) do
    case Regex.run(@advice, content) do
      [_, advice] -> String.downcase(advice)
      nil -> "unclear"
    end
  end

  defp parse_advice(_content), do: "unclear"

  defp parse_night(content, count, messages) do
    summary =
      case Regex.run(@summary, content) do
        [_, text] -> String.trim(text)
        nil -> ""
      end

    found =
      @dispute
      |> Regex.scan(content)
      |> Enum.map(fn [_, numbers, outcome, words] ->
        %{numbers: numbers(numbers), outcome: String.downcase(outcome), words: String.trim(words)}
      end)

    case Enum.find(found, fn d -> Enum.any?(d.numbers, &(&1 < 1 or &1 > count)) end) do
      nil ->
        {:ok, Enum.map(found, &with_message(&1, messages)), summary}

      bad ->
        shown = bad.numbers |> Enum.reject(&(&1 >= 1 and &1 <= count)) |> Enum.join(", ")
        {:error, "the reply named message #{shown}, which it was not shown"}
    end
  end

  # "1, 2" or "3-5": the numbers a dispute cites.
  defp numbers(text) do
    text
    |> String.split(",")
    |> Enum.flat_map(fn part ->
      case part |> String.trim() |> String.split("-") |> Enum.map(&Integer.parse/1) do
        [{a, ""}] -> [a]
        [{a, ""}, {b, ""}] when b >= a -> Enum.to_list(a..b)
        _other -> [0]
      end
    end)
  end

  defp with_message(dispute, messages) do
    first = Enum.at(messages, List.first(dispute.numbers) - 1)
    Map.merge(dispute, %{session_key: first.session_key, turn_ref: first.turn_ref})
  end
end
