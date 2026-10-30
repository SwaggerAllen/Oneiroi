defmodule Oneiroi.Sunna.Schedule do
  @moduledoc """
  The schedule aggregate on `schedule-<resident_id>` (spec §6.7). Pure:
  the day, the instant and the number arrive on the command; the tick
  decides what is due and this aggregate decides what has already
  happened, so a check-in fires once a day whatever restarts.
  """

  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Events

  defstruct [
    :id,
    checkins: %{},
    free_time: nil,
    free_time_days: %{},
    quiet: nil,
    dates: %{},
    days: MapSet.new(),
    hours: MapSet.new()
  ]

  @hour ~r/\A\d{4}-\d{2}-\d{2}T([01]\d|2[0-3])\z/

  @time ~r/\A([01]\d|2[0-3]):[0-5]\d\z/
  @date_kinds ~w(deadline anniversary window recurring)
  @label_limit 60

  @doc "The kinds a date takes (spec §6.7)."
  @spec date_kinds() :: [String.t()]
  def date_kinds, do: @date_kinds

  @doc "Whether a time of day is well formed: `HH:MM`."
  @spec time_ok?(term()) :: boolean()
  def time_ok?(time), do: is_binary(time) and Regex.match?(@time, time)

  # ---- check-ins ----

  def execute(%__MODULE__{checkins: checkins}, %Commands.SetCheckin{} = c) do
    cond do
      not time_ok?(c.time) ->
        {:error, :time_invalid}

      not label_ok?(c.label) ->
        {:error, :label_invalid}

      not Map.has_key?(checkins, c.key) ->
        %Events.CheckinSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          label: c.label,
          time: c.time,
          day: c.day
        }

      same_checkin?(checkins[c.key], c) ->
        []

      true ->
        %Events.CheckinChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          label: c.label,
          time: c.time,
          day: c.day
        }
    end
  end

  def execute(%__MODULE__{checkins: checkins}, %Commands.DeleteCheckin{} = c) do
    if Map.has_key?(checkins, c.key),
      do: %Events.CheckinDeleted{actor: c.actor, at: c.at, id: c.id, key: c.key},
      else: {:error, :no_such_checkin}
  end

  # Once a day: a second fire or a miss after a fire is no event, a
  # deferred wake fires at its end, and the first firing of a day opens
  # the day (the journal's row). The first version returned no event for
  # every recorded outcome, deferral included, so a check-in inside quiet
  # hours was deferred and then never woke; the test for quiet hours
  # found it.
  def execute(%__MODULE__{} = s, %Commands.FireCheckin{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin -> {:error, :no_such_checkin}
      nil -> fire(s, c)
      {:deferred, _until} -> fire(s, c)
      _already -> []
    end
  end

  def execute(%__MODULE__{} = s, %Commands.MissCheckin{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin -> {:error, :no_such_checkin}
      nil -> %Events.CheckinMissed{actor: c.actor, at: c.at, id: c.id, key: c.key, day: c.day}
      _already -> []
    end
  end

  def execute(%__MODULE__{} = s, %Commands.DeferWake{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin ->
        {:error, :no_such_checkin}

      nil ->
        %Events.WakeDeferred{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          day: c.day,
          until: c.until
        }

      {:deferred, _} ->
        []

      _already ->
        []
    end
  end

  # ---- the day row ----

  # The hour marker (P20 as amended): once per local hour, and never a
  # wake.
  def execute(%__MODULE__{hours: hours}, %Commands.MarkHour{} = c) do
    cond do
      not (is_binary(c.hour) and Regex.match?(@hour, c.hour)) -> {:error, :hour_invalid}
      MapSet.member?(hours, c.hour) -> []
      true -> %Events.HourMarked{actor: c.actor, at: c.at, id: c.id, hour: c.hour}
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.OpenDay{} = c) do
    cond do
      not day_ok?(c.day) -> {:error, :day_invalid}
      MapSet.member?(days, c.day) -> []
      true -> %Events.DayOpened{actor: c.actor, at: c.at, id: c.id, day: c.day}
    end
  end

  # ---- free time ----

  def execute(%__MODULE__{free_time: current}, %Commands.SetFreeTime{} = c) do
    cond do
      not (is_nil(c.time) or time_ok?(c.time)) -> {:error, :time_invalid}
      current == c.time -> []
      true -> %Events.FreeTimeScheduled{actor: c.actor, at: c.at, id: c.id, time: c.time}
    end
  end

  def execute(%__MODULE__{free_time_days: days}, %Commands.RecordFreeTime{} = c) do
    cond do
      Map.has_key?(days, c.day) ->
        []

      is_binary(c.session_key) ->
        %Events.FreeTimeRan{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          session_key: c.session_key
        }

      true ->
        %Events.FreeTimeFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          reason: c.reason || "unknown"
        }
    end
  end

  # ---- quiet hours, dates ----

  def execute(%__MODULE__{quiet: quiet}, %Commands.SetQuietHours{} = c) do
    cond do
      not ((is_nil(c.from) and is_nil(c.to)) or (time_ok?(c.from) and time_ok?(c.to))) ->
        {:error, :time_invalid}

      quiet == quiet_of(c) ->
        []

      true ->
        %Events.QuietHoursSet{actor: c.actor, at: c.at, id: c.id, from: c.from, to: c.to}
    end
  end

  def execute(%__MODULE__{dates: dates}, %Commands.SetDate{} = c) do
    cond do
      not label_ok?(c.title) ->
        {:error, :label_invalid}

      c.kind not in @date_kinds ->
        {:error, :kind_invalid}

      not match?(%DateTime{}, c.on) ->
        {:error, :time_invalid}

      not Map.has_key?(dates, c.number) ->
        %Events.DateSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          title: c.title,
          on: c.on,
          kind: c.kind
        }

      dates[c.number] == date_of(c) ->
        []

      true ->
        %Events.DateChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          title: c.title,
          on: c.on,
          kind: c.kind
        }
    end
  end

  def execute(%__MODULE__{dates: dates}, %Commands.RemoveDate{} = c) do
    if Map.has_key?(dates, c.number),
      do: %Events.DateRemoved{actor: c.actor, at: c.at, id: c.id, number: c.number},
      else: {:error, :no_such_date}
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.CheckinSet{} = e),
    do: %{
      s
      | id: e.id,
        checkins:
          Map.put(s.checkins, e.key, %{
            label: e.label,
            time: e.time,
            changed_day: e.day,
            outcomes: %{}
          })
    }

  def apply(%__MODULE__{} = s, %Events.CheckinChanged{} = e) do
    update_in(s.checkins[e.key], &%{&1 | label: e.label, time: e.time, changed_day: e.day})
  end

  def apply(%__MODULE__{} = s, %Events.CheckinDeleted{} = e),
    do: %{s | checkins: Map.delete(s.checkins, e.key)}

  def apply(%__MODULE__{} = s, %Events.CheckinFired{} = e),
    do: put_outcome(s, e.key, e.day, :fired)

  def apply(%__MODULE__{} = s, %Events.CheckinMissed{} = e),
    do: put_outcome(s, e.key, e.day, :missed)

  def apply(%__MODULE__{} = s, %Events.WakeDeferred{} = e),
    do: put_outcome(s, e.key, e.day, {:deferred, e.until})

  def apply(%__MODULE__{} = s, %Events.DayOpened{} = e),
    do: %{s | id: e.id, days: MapSet.put(s.days, e.day)}

  def apply(%__MODULE__{} = s, %Events.HourMarked{} = e),
    do: %{s | id: e.id, hours: MapSet.put(s.hours, e.hour)}

  def apply(%__MODULE__{} = s, %Events.FreeTimeScheduled{} = e),
    do: %{s | id: e.id, free_time: e.time}

  def apply(%__MODULE__{} = s, %Events.FreeTimeRan{} = e),
    do: %{s | free_time_days: Map.put(s.free_time_days, e.day, :ran)}

  def apply(%__MODULE__{} = s, %Events.FreeTimeFailed{} = e),
    do: %{s | free_time_days: Map.put(s.free_time_days, e.day, :failed)}

  def apply(%__MODULE__{} = s, %Events.QuietHoursSet{} = e),
    do: %{s | id: e.id, quiet: quiet_of(e)}

  def apply(%__MODULE__{} = s, %Events.DateSet{} = e),
    do: %{s | id: e.id, dates: Map.put(s.dates, e.number, date_of(e))}

  def apply(%__MODULE__{} = s, %Events.DateChanged{} = e),
    do: %{s | dates: Map.put(s.dates, e.number, date_of(e))}

  def apply(%__MODULE__{} = s, %Events.DateRemoved{} = e),
    do: %{s | dates: Map.delete(s.dates, e.number)}

  # ---- helpers ----

  defp fire(%__MODULE__{days: days}, c) do
    fired = %Events.CheckinFired{actor: c.actor, at: c.at, id: c.id, key: c.key, day: c.day}

    if MapSet.member?(days, c.day),
      do: fired,
      else: [%Events.DayOpened{actor: c.actor, at: c.at, id: c.id, day: c.day}, fired]
  end

  @doc "The outcome of a check-in on a day: nil, :fired, :missed, {:deferred, until}, or :no_such_checkin."
  def outcome(%__MODULE__{checkins: checkins}, key, day) do
    case Map.get(checkins, key) do
      nil -> :no_such_checkin
      %{outcomes: outcomes} -> Map.get(outcomes, day)
    end
  end

  defp put_outcome(s, key, day, outcome) do
    case Map.get(s.checkins, key) do
      nil -> s
      _ -> update_in(s.checkins[key].outcomes, &Map.put(&1, day, outcome))
    end
  end

  defp same_checkin?(%{label: label, time: time}, c), do: label == c.label and time == c.time

  defp day_ok?(day), do: is_binary(day) and match?({:ok, _}, Date.from_iso8601(day))

  defp label_ok?(label),
    do: is_binary(label) and String.trim(label) != "" and String.length(label) <= @label_limit

  defp quiet_of(%{from: nil, to: nil}), do: nil
  defp quiet_of(%{from: from, to: to}), do: %{from: from, to: to}

  defp date_of(c), do: %{title: c.title, on: c.on, kind: c.kind}
end
