defmodule Oneiroi.Sunna.Projectors.Work do
  @moduledoc "Folds the work streams (sunna#33) into one row an item and one row of the loop's state."
  use Oneiroi.Projection, name: "sunna_work"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Store.{WorkItem, WorkQueue}
  alias Oneiroi.Sunna.Work

  # A held mark never outlives its ask (sunna#55): every move, wrap or
  # start of the item clears it.
  @unheld [held_ask: nil, held_by: nil, held_at: nil]

  fold(%Events.WorkAdded{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :work,
      %WorkItem{
        resident_id: e.id,
        number: e.number,
        what: e.what,
        done_when: e.done_when,
        status: "open",
        position: e.number,
        added_by: Atom.to_string(e.actor.kind),
        added_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
    |> queue(e.id, rested_reason: nil, rested_at: nil)
  end)

  fold(%Events.WorkMoved{} = e, _metadata, fn multi ->
    multi
    |> item(
      e.id,
      e.number,
      [
        status: e.status,
        blocked_on: e.blocked_on,
        note: e.note,
        moved_by: Atom.to_string(e.actor.kind),
        moved_at: e.at
      ] ++ @unheld
    )
    |> queue(e.id, rested_reason: nil, rested_at: nil)
  end)

  # Held for the witness (sunna#54): the ask stands on the item until a
  # move or a start takes it out (sunna#55).
  fold(%Events.WorkHeld{} = e, _metadata, fn multi ->
    multi
    |> item(e.id, e.number,
      status: "held",
      blocked_on: nil,
      held_ask: e.ask,
      held_by: Atom.to_string(e.actor.kind),
      held_at: e.at,
      note: e.note,
      moved_by: Atom.to_string(e.actor.kind),
      moved_at: e.at
    )
    |> queue(e.id, rested_reason: nil, rested_at: nil)
  end)

  fold(%Events.WorkOrdered{} = e, _metadata, fn multi ->
    e.order
    |> Enum.with_index(1)
    |> Enum.reduce(multi, fn {number, position}, m ->
      Multi.update_all(
        m,
        {:position, number},
        from(w in WorkItem, where: w.resident_id == ^e.id and w.number == ^number),
        set: [position: position]
      )
    end)
    |> queue(e.id, rested_reason: nil, rested_at: nil)
  end)

  fold(%Events.WorkWrapped{} = e, _metadata, fn multi ->
    # A wrap held (sunna#56) is followed by its `WorkHeld`, which sets the
    # ask again; any other wrap leaves nothing held.
    item(
      multi,
      e.id,
      e.number,
      [
        status: e.status,
        blocked_on: e.blocked_on,
        shipped: e.shipped,
        slipped: e.slipped,
        why: e.why,
        wrapped_at: e.at
      ] ++ @unheld
    )
  end)

  fold(%Events.WorkStarted{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :started,
      from(w in WorkItem, where: w.resident_id == ^e.id and w.number == ^e.number),
      set: [status: "in_work", blocked_on: nil, session_key: e.session_key] ++ @unheld,
      inc: [runs: 1]
    )
    |> Multi.run(:day_runs, fn repo, _ ->
      row = repo.one(from(q in WorkQueue, where: q.resident_id == ^e.id))
      {:ok, if(row && row.run_day == e.day, do: row.runs_on_day + 1, else: 1)}
    end)
    |> Multi.run(:queue, fn repo, %{day_runs: runs} ->
      upsert(repo, e.id,
        running: e.number,
        running_key: e.session_key,
        running_since: e.at,
        rested_reason: nil,
        rested_at: nil,
        run_day: e.day,
        runs_on_day: runs
      )
    end)
  end)

  fold(%Events.WorkRunEnded{} = e, _metadata, fn multi ->
    multi
    |> item(e.id, e.number, status: e.status)
    |> queue(
      e.id,
      [running: nil, running_key: nil, running_since: nil] ++
        if(e.stopped,
          do: [rested_reason: Work.stopped_rest(), rested_at: e.at],
          else: []
        )
    )
  end)

  fold(%Events.WorkArmed{} = e, _metadata, fn multi ->
    queue(multi, e.id,
      armed: true,
      armed_at: e.at,
      armed_by: actor_kind(e.actor),
      rested_reason: nil,
      rested_at: nil
    )
  end)

  fold(%Events.WorkDisarmed{} = e, _metadata, fn multi ->
    queue(multi, e.id, armed: false, armed_at: nil, armed_by: nil)
  end)

  fold(%Events.WorkRunsReset{} = e, _metadata, fn multi ->
    queue(multi, e.id, runs_on_day: 0, rested_reason: nil, rested_at: nil)
  end)

  fold(%Events.WorkRested{} = e, _metadata, fn multi ->
    queue(multi, e.id, rested_reason: e.reason, rested_at: e.at)
  end)

  defp item(multi, resident_id, number, set),
    do:
      Multi.update_all(
        multi,
        {:item, number},
        from(w in WorkItem, where: w.resident_id == ^resident_id and w.number == ^number),
        set: set
      )

  defp queue(multi, resident_id, set),
    do: Multi.run(multi, :queue, fn repo, _ -> upsert(repo, resident_id, set) end)

  defp upsert(repo, resident_id, set) do
    repo.insert(struct(WorkQueue, [resident_id: resident_id] ++ set),
      on_conflict: [set: set],
      conflict_target: [:resident_id]
    )
  end

  # Who armed the line (sunna#43): the resident or the witness, by kind.
  defp actor_kind(%{kind: kind}), do: to_string(kind)
  defp actor_kind(%{"kind" => kind}), do: to_string(kind)
  defp actor_kind(_none), do: nil
end
