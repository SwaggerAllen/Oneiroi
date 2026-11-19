defmodule Oneiroi.Gaia.Projectors.Rounds do
  @moduledoc "Folds a household's round-robin threads (gaia#53) into a row a thread and a row a turn."
  use Oneiroi.Projection, name: "gaia_rounds"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.{RoundThread, RoundTurn}

  fold(%Events.RoundStarted{} = e, _metadata, fn multi ->
    thread(multi, e, round: e.round, order: e.order, stopped: false, live_turn: nil)
  end)

  fold(%Events.RoundTurnIssued{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :turn,
      %RoundTurn{
        household_id: e.id,
        turn_id: e.turn_id,
        thread: e.thread,
        round: e.round,
        resident_id: e.resident_id,
        issued_at: e.at,
        expires_at: e.expires_at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :turn_id]
    )
    |> thread(e, live_turn: e.turn_id)
  end)

  fold(%Events.RoundTurnSpent{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :spent,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a thread or turn is within it
      from(t in RoundTurn, where: t.household_id == ^e.id and t.turn_id == ^e.turn_id),
      set: [outcome: e.outcome, spent_at: e.at]
    )
    |> Multi.update_all(
      :unlive,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a thread or turn is within it
      from(t in RoundThread,
        where: t.household_id == ^e.id and t.thread == ^e.thread and t.live_turn == ^e.turn_id
      ),
      set: [live_turn: nil, changed_at: e.at]
    )
  end)

  fold(%Events.RoundsStopped{} = e, _metadata, fn multi ->
    thread(multi, e, stopped: true, live_turn: nil)
  end)

  fold(%Events.RoundsOptedOut{} = e, _metadata, fn multi ->
    multi
    |> thread(e, [])
    |> Multi.update_all(
      :optout,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a thread or turn is within it
      from(t in RoundThread,
        where: t.household_id == ^e.id and t.thread == ^e.thread,
        update: [
          set: [
            optout: fragment("array_append(?, ?)", t.optout, type(^e.resident_id, :binary_id))
          ]
        ]
      ),
      []
    )
  end)

  fold(%Events.RoundsOptedIn{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :optin,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a thread or turn is within it
      from(t in RoundThread,
        where: t.household_id == ^e.id and t.thread == ^e.thread,
        update: [
          set: [
            optout: fragment("array_remove(?, ?)", t.optout, type(^e.resident_id, :binary_id))
          ]
        ]
      ),
      []
    )
  end)

  # The thread's row, made on its first event, the given fields set.
  defp thread(multi, e, set) do
    Multi.insert(
      multi,
      {:thread, System.unique_integer()},
      struct(
        RoundThread,
        [
          household_id: e.id,
          thread: e.thread,
          round: 0,
          order: [],
          optout: [],
          stopped: false,
          changed_at: e.at
        ] ++
          set
      ),
      on_conflict: [set: Keyword.put(set, :changed_at, e.at)],
      conflict_target: [:household_id, :thread]
    )
  end
end
