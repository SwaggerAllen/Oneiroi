defmodule Oneiroi.Eunomia.Imports do
  @moduledoc """
  Judgement history carried from another platform by an import (eunomia
  #29): positions with their chains, disputes live and nightly with how
  each was settled, predictions, and the nights the other platform
  judged. Each goes through the aggregate as a live record would, under
  the actor the source names, so the Judgement and Predictions screens,
  the concession ratio and the brain's tools read it as they read their
  own.

  Three things differ from a live record, each because the words or the
  facts are what they were: a statement is held to its shape and not to
  the thousand-character limit; a prediction may have no due date; and
  a night recorded here is a day the nightly pass then never judges
  again, which is the point, since the other platform already did.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Judge
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands
  alias Oneiroi.Eunomia.JudgementRouter, as: Router

  @type parties :: %{resident: Actor.t(), witness: Actor.t()}

  @doc """
  Replays `history`, a map of lists under `:positions`, `:disputes`,
  `:predictions` and `:nights` (each record's shape below), in that
  order, since a dispute names a position. `parties` gives the
  resident's and the witness's actors; a judge's is made from the model
  the record names. Returns how many of each were recorded and the
  source's position ids mapped to the numbers minted here.

  - a position: `source_id`, `statement`, `replaces` (a source id or
    nil), `session_key`, `turn_ref`
  - a dispute: `source` (`live` or `night`), `position` (a source id or
    nil), `claim`, `stance`, `session_key`, `turn_ref`, `advice`,
    `advice_text`, `judge_model`, `settled` (nil or `%{outcome, note}`)
  - a prediction: `statement`, `due` (a DateTime or nil), `by`
    (`:resident` or `:witness`), `session_key`, `turn_ref`, `resolved`
    (nil or `%{outcome, note}`)
  - a night: `day`, `messages`, `found`, `judge_model`, `summary`,
    `failed` (nil or the reason)
  """
  @spec replay(String.t(), map(), parties()) :: {:ok, map()} | {:error, term()}
  def replay(resident_id, history, %{resident: %Actor{}, witness: %Actor{}} = parties) do
    with {:ok, numbers} <- positions(resident_id, Map.get(history, :positions, []), parties),
         {:ok, disputes} <-
           each(Map.get(history, :disputes, []), &dispute(resident_id, &1, numbers, parties)),
         {:ok, predictions} <-
           each(Map.get(history, :predictions, []), &prediction(resident_id, &1, parties)),
         {:ok, nights} <- each(Map.get(history, :nights, []), &night(resident_id, &1)) do
      {:ok,
       %{
         positions: map_size(numbers),
         disputes: disputes,
         predictions: predictions,
         nights: nights,
         position_numbers: numbers
       }}
    end
  end

  # ---- positions ----

  # In the source's order, so a replacement meets the position it
  # replaces already recorded. A replacement of a position something
  # else already replaced cannot be a link in a chain here (a chain has
  # one head); it is taken as a position of its own rather than lost.
  defp positions(resident_id, records, parties) do
    Enum.reduce_while(records, {:ok, %{}}, fn r, {:ok, numbers} ->
      case position(resident_id, r, Map.get(numbers, r.replaces), parties.resident) do
        {:ok, number} -> {:cont, {:ok, Map.put(numbers, r.source_id, number)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp position(resident_id, r, replaces, actor) do
    with {:ok, number} <- AgathosDaimon.mint_id(resident_id, "position", actor) do
      take = %Commands.TakePosition{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        statement: r.statement,
        session_key: r.session_key,
        turn_ref: r.turn_ref,
        imported: true
      }

      case take |> chained(replaces) |> dispatch() do
        {:ok, _} -> {:ok, number}
        {:error, %{kind: :eunomia_position_replaced}} -> taken(dispatch(take), number)
        other -> other
      end
    end
  end

  defp chained(take, nil), do: take

  defp chained(take, replaces),
    do:
      struct!(Commands.ReplacePosition, take |> Map.from_struct() |> Map.put(:replaces, replaces))

  defp taken({:ok, _}, number), do: {:ok, number}
  defp taken(error, _number), do: error

  # ---- disputes ----

  defp dispute(resident_id, r, numbers, parties) do
    actor = if r.source == "night", do: Judge.actor(r.judge_model), else: parties.resident
    ref = 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    check = %Commands.CheckDispute{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      source: r.source,
      position_number: r.position && Map.get(numbers, r.position),
      claim: r.claim,
      stance: r.stance,
      session_key: r.session_key,
      turn_ref: r.turn_ref,
      outcome: "advised",
      advice: r.advice,
      advice_text: r.advice_text,
      judge_model: r.judge_model
    }

    with {:ok, _} <- dispatch(check) do
      settle(resident_id, ref, r.settled, actor)
    end
  end

  defp settle(_resident_id, _ref, nil, _actor), do: :ok

  defp settle(resident_id, ref, %{outcome: outcome, note: note}, actor) do
    command = %Commands.SettleDispute{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: resident_id,
      ref: ref,
      outcome: outcome
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- predictions ----

  defp prediction(resident_id, r, parties) do
    actor = Map.fetch!(parties, r.by)

    with {:ok, number} <- AgathosDaimon.mint_id(resident_id, "prediction", actor),
         {:ok, _} <-
           dispatch(%Commands.LogPrediction{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             statement: r.statement,
             due: r.due,
             session_key: r.session_key,
             turn_ref: r.turn_ref,
             imported: true
           }) do
      resolve(resident_id, number, r.resolved, parties.witness)
    end
  end

  # Resolved by the witness only (F17), here as live.
  defp resolve(_resident_id, _number, nil, _witness), do: :ok

  defp resolve(resident_id, number, %{outcome: outcome, note: note}, witness) do
    command = %Commands.ResolvePrediction{
      actor: witness,
      at: Clock.now(),
      note: note,
      id: resident_id,
      number: number,
      outcome: outcome
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- nights ----

  defp night(resident_id, %{failed: reason} = r) when is_binary(reason) do
    command = %Commands.FailNight{
      actor: Judge.actor(r.judge_model),
      at: Clock.now(),
      id: resident_id,
      day: r.day,
      reason: reason
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  defp night(resident_id, r) do
    command = %Commands.RecordNight{
      actor: Judge.actor(r.judge_model),
      at: Clock.now(),
      id: resident_id,
      day: r.day,
      messages: r.messages,
      chars: nil,
      found: r.found,
      judge_model: r.judge_model,
      summary: r.summary,
      criteria: nil,
      movements: []
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- helpers ----

  defp each(records, fun) do
    Enum.reduce_while(records, {:ok, 0}, fn r, {:ok, n} ->
      case fun.(r) do
        :ok -> {:cont, {:ok, n + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} -> {:ok, events}
      {:error, reason} when is_atom(reason) -> {:error, translate(reason)}
      {:error, other} -> {:error, other}
    end
  end

  # The aggregate's reasons in the boundary's vocabulary, as Judgements
  # names them.
  defp translate(:statement_invalid), do: Error.new(:eunomia_statement_invalid)
  defp translate(:no_such_position), do: Error.new(:eunomia_no_such_position)
  defp translate(:position_replaced), do: Error.new(:eunomia_position_replaced)
  defp translate(:dispute_invalid), do: Error.new(:eunomia_dispute_invalid)
  defp translate(:no_such_dispute), do: Error.new(:eunomia_no_such_dispute)
  defp translate(:no_such_prediction), do: Error.new(:eunomia_no_such_prediction)
  defp translate(:due_invalid), do: Error.new(:eunomia_due_invalid)
  defp translate(other), do: other
end
