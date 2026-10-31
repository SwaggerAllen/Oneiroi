defmodule Oneiroi.Eunomia.Judge do
  @moduledoc """
  The judge's two calls (spec §6.4): advice on a live dispute, and the
  nightly reading of a day. Both go through the ledger under the `judge`
  purpose on the judge's model, which is recorded on every verdict and
  is never the resident's own chat model. The prompts are files under
  `priv/prompts/` and stay constitutional: they ask the judge to weigh
  the resident's stated positions and the witness's claim, never to
  grade the resident. The nightly reading also carries the day's
  movement (spec §6.4, P34): what happened, what stance followed, what
  intention was adopted, where it can resume, one `MOVED` line per
  thread, parsed as strictly as the disputes.

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
  @moved ~r/^MOVED\s+\[([0-9,\s\-]+)\]\s*(.*)$/im
  @movement_fields ~w(happened stance intention resume)
  @summary ~r/^SUMMARY:\s*(.*)$/im
  @aware ~r/^AWARE\s+\[(\d+)\]\s*\|\s*(.*)$/im

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
  outcome and its words), a summary, and the movements (each citing
  message numbers, with the four fields, string-keyed, nil where the
  judge wrote `-`). `{:error, reason}` when the reply names a message
  it was not shown, or a MOVED line has other than four fields.
  """
  @spec night(String.t(), String.t(), [map()]) ::
          {:ok, [map()], String.t(), [map()]} | {:error, term()}
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

  @doc """
  The test-awareness scan (spec §12, P40; eunomia #28): the replies,
  numbered, to the judge, which lists each one that says or implies the
  assistant is being tested. `{:ok, [%{number, words}]}`, or `{:error,
  reason}` when the reply names a number it was not shown, which fails
  the scan rather than being guessed at. Billed under `judge`.
  """
  @spec awareness(String.t(), String.t(), [String.t()]) :: {:ok, [map()]} | {:error, term()}
  def awareness(resident_id, model, replies) when is_list(replies) do
    listed =
      replies
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} -> "[#{i}] #{text}" end)

    prompt = Prompt.message("judge_awareness", %{replies: listed})
    request = Request.new(model, [prompt, %{role: :user, content: "Which replies, if any?"}])

    with {:ok, %Result{content: content}} <-
           Nisaba.call(resident_id, :judge, request, actor(model)) do
      found =
        @aware
        |> Regex.scan(content || "")
        |> Enum.map(fn [_, n, words] ->
          %{number: String.to_integer(n), words: String.trim(words)}
        end)

      case Enum.find(found, &(&1.number < 1 or &1.number > length(replies))) do
        nil -> {:ok, Enum.uniq_by(found, & &1.number)}
        bad -> {:error, "the reply named reply #{bad.number}, which it was not shown"}
      end
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

    with {:ok, movements} <- movements(content),
         :ok <- all_shown(found ++ movements, count) do
      {:ok, Enum.map(found, &with_message(&1, messages)), summary,
       Enum.map(movements, &with_movement_message(&1, messages))}
    end
  end

  defp all_shown(lines, count) do
    case Enum.find(lines, fn l -> Enum.any?(l.numbers, &(&1 < 1 or &1 > count)) end) do
      nil ->
        :ok

      bad ->
        shown = bad.numbers |> Enum.reject(&(&1 >= 1 and &1 <= count)) |> Enum.join(", ")
        {:error, "the reply named message #{shown}, which it was not shown"}
    end
  end

  # The movement lines (P34): four fields, each a phrase or `-`. Fewer
  # or more fields is a line the pass cannot read, and it fails the
  # night rather than being guessed at, as a dispute citing an unshown
  # message does.
  defp movements(content) do
    @moved
    |> Regex.scan(content)
    |> Enum.reduce_while({:ok, []}, fn [_, numbers, rest], {:ok, acc} ->
      case movement_line(numbers, rest) do
        {:ok, movement} -> {:cont, {:ok, acc ++ [movement]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp movement_line(numbers, rest) do
    fields = rest |> String.split("|") |> Enum.map(&String.trim/1)

    if length(fields) == 4 do
      movement = @movement_fields |> Enum.zip(Enum.map(fields, &field_value/1)) |> Map.new()
      {:ok, Map.put(movement, :numbers, numbers(numbers))}
    else
      {:error,
       "the reply's MOVED line [#{String.trim(numbers)}] has #{length(fields)} fields where four were due"}
    end
  end

  # A `-` is the judge saying there is nothing to say, kept as nil.
  defp field_value(f) when f in ["", "-"], do: nil
  defp field_value(f), do: f

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

  # A movement travels in an event, so its keys are strings and the
  # turn it names is a ref the brain can cite back.
  defp with_movement_message(movement, messages) do
    {numbers, fields} = Map.pop(movement, :numbers)
    first = Enum.at(messages, List.first(numbers) - 1)
    fields |> Map.put("numbers", numbers) |> Map.put("turn_ref", first.turn_ref)
  end
end
