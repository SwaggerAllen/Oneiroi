defmodule Oneiroi.Sunna.Projectors.Schedules do
  @moduledoc "Folds the schedule streams into check-ins, firings, days, dates and the settings row."
  use Oneiroi.Projection, name: "sunna_schedules"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Store.{Checkin, Date, Day, Firing, FreeTimeRun, Hour, Settings}

  fold(%Events.CheckinSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :checkin,
      %Checkin{
        resident_id: e.id,
        key: e.key,
        label: e.label,
        time: e.time,
        parts: e.parts || ["dates"],
        prompt: e.prompt,
        changed_day: e.day,
        set_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key]
    )
  end)

  fold(%Events.CheckinChanged{} = e, _metadata, fn multi ->
    set_checkin(multi, e.id, e.key,
      label: e.label,
      time: e.time,
      parts: e.parts || ["dates"],
      prompt: e.prompt,
      changed_day: e.day,
      set_at: e.at
    )
  end)

  fold(%Events.CheckinDeleted{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :checkin,
      from(c in Checkin, where: c.resident_id == ^e.id and c.key == ^e.key)
    )
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

  fold(%Events.HourMarked{} = e, _metadata, fn multi ->
    Multi.insert(multi, :hour, %Hour{resident_id: e.id, hour: e.hour, at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :hour]
    )
  end)

  fold(%Events.FreeTimeScheduled{} = e, _metadata, fn multi ->
    times = e.times || List.wrap(e.time)
    settings(multi, e.id, free_times: times, free_time: List.last(times))
  end)

  # The settings row keeps the last run of any slot (what the schedule
  # route has always said); each slot's run is its own row (sunna#22).
  fold(%Events.FreeTimeRan{} = e, _metadata, fn multi ->
    multi
    |> settings(e.id,
      free_time_day: e.day,
      free_time_outcome: "ran",
      free_time_session_key: e.session_key
    )
    |> free_time_run(e, "ran", e.session_key)
  end)

  fold(%Events.FreeTimeFailed{} = e, _metadata, fn multi ->
    multi
    |> settings(e.id,
      free_time_day: e.day,
      free_time_outcome: "failed: " <> e.reason,
      free_time_session_key: nil
    )
    |> free_time_run(e, "failed: " <> e.reason, nil)
  end)

  fold(%Events.RoundsSet{} = e, _metadata, fn multi ->
    settings(multi, e.id, rounds_every_hours: e.every_hours, rounds_waking: e.waking)
  end)

  fold(%Events.RoundStarted{} = e, _metadata, fn multi ->
    settings(multi, e.id, last_round_at: e.at)
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
    Multi.update_all(
      multi,
      :date,
      from(d in Date, where: d.resident_id == ^e.id and d.number == ^e.number),
      set: [title: e.title, on: e.on, kind: e.kind, set_at: e.at]
    )
  end)

  fold(%Events.DateRemoved{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :date,
      from(d in Date, where: d.resident_id == ^e.id and d.number == ^e.number)
    )
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
    |> set_checkin(e.id, e.key, last_day: e.day, last_outcome: outcome, last_at: e.at)
  end

  defp set_checkin(multi, resident_id, key, set),
    do:
      Multi.update_all(
        multi,
        {:checkin, key, Keyword.keys(set)},
        from(c in Checkin, where: c.resident_id == ^resident_id and c.key == ^key),
        set: set
      )

  # One settings row per resident, made on first use.
  defp free_time_run(multi, e, outcome, session_key) do
    Multi.insert(
      multi,
      :free_time_run,
      %FreeTimeRun{
        resident_id: e.id,
        day: e.day,
        slot: e.slot,
        outcome: outcome,
        session_key: session_key,
        at: e.at
      },
      on_conflict: :nothing
    )
  end

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
