defmodule Oneiroi.Sunna.Projectors.Schedules do
  @moduledoc "Folds the schedule streams into check-ins, firings, days, dates and the settings row."
  use Oneiroi.Projection, name: "sunna_schedules"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Store.{Checkin, Date, Day, Firing, Settings}

  fold(%Events.CheckinSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :checkin,
      %Checkin{
        resident_id: e.id,
        key: e.key,
        label: e.label,
        time: e.time,
        changed_day: e.day,
        set_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key]
    )
  end)

  fold(%Events.CheckinChanged{} = e, _metadata, fn multi ->
    set_checkin(multi, e.key, label: e.label, time: e.time, changed_day: e.day, set_at: e.at)
  end)

  fold(%Events.CheckinDeleted{} = e, _metadata, fn multi ->
    Multi.delete_all(multi, :checkin, from(c in Checkin, where: c.key == ^e.key))
  end)

  fold(%Events.CheckinFired{} = e, _metadata, fn multi -> firing(multi, e, "fired", nil) end)
  fold(%Events.CheckinMissed{} = e, _metadata, fn multi -> firing(multi, e, "missed", nil) end)

  fold(%Events.WakeDeferred{} = e, _metadata, fn multi ->
    firing(multi, e, "deferred", e.until)
  end)

  fold(%Events.DayOpened{} = e, _metadata, fn multi ->
    Multi.insert(multi, :day, %Day{resident_id: e.id, day: e.day, opened_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :day]
    )
  end)

  fold(%Events.FreeTimeScheduled{} = e, _metadata, fn multi ->
    settings(multi, e.id, free_time: e.time)
  end)

  fold(%Events.FreeTimeRan{} = e, _metadata, fn multi ->
    settings(multi, e.id,
      free_time_day: e.day,
      free_time_outcome: "ran",
      free_time_session_key: e.session_key
    )
  end)

  fold(%Events.FreeTimeFailed{} = e, _metadata, fn multi ->
    settings(multi, e.id,
      free_time_day: e.day,
      free_time_outcome: "failed: " <> e.reason,
      free_time_session_key: nil
    )
  end)

  fold(%Events.QuietHoursSet{} = e, _metadata, fn multi ->
    settings(multi, e.id, quiet_from: e.from, quiet_to: e.to)
  end)

  fold(%Events.DateSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :date,
      %Date{
        resident_id: e.id,
        number: e.number,
        title: e.title,
        on: e.on,
        kind: e.kind,
        set_by_kind: actor_kind(e.actor),
        set_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.DateChanged{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :date, from(d in Date, where: d.number == ^e.number),
      set: [title: e.title, on: e.on, kind: e.kind, set_at: e.at]
    )
  end)

  fold(%Events.DateRemoved{} = e, _metadata, fn multi ->
    Multi.delete_all(multi, :date, from(d in Date, where: d.number == ^e.number))
  end)

  defp firing(multi, e, outcome, until) do
    multi
    |> Multi.insert(
      :firing,
      %Firing{
        resident_id: e.id,
        key: e.key,
        day: e.day,
        outcome: outcome,
        at: e.at,
        until: until
      },
      on_conflict: [set: [outcome: outcome, at: e.at, until: until]],
      conflict_target: [:resident_id, :key, :day]
    )
    |> set_checkin(e.key, last_day: e.day, last_outcome: outcome, last_at: e.at)
  end

  defp set_checkin(multi, key, set),
    do:
      Multi.update_all(
        multi,
        {:checkin, key, Keyword.keys(set)},
        from(c in Checkin, where: c.key == ^key),
        set: set
      )

  # One settings row per resident, made on first use.
  defp settings(multi, id, set) do
    Multi.insert(
      multi,
      {:settings, Keyword.keys(set)},
      struct!(Settings, [resident_id: id] ++ set),
      on_conflict: [set: set],
      conflict_target: [:resident_id]
    )
  end

  defp actor_kind(%{} = actor), do: to_string(Map.get(actor, :kind) || Map.get(actor, "kind"))
  defp actor_kind(_other), do: nil
end
