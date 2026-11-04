defmodule Oneiroi.Sunna.Schedule do
  @moduledoc """
  The schedule aggregate on `schedule-<resident_id>` (spec §6.7). Pure:
  the day, the instant and the number arrive on the command; the tick
  decides what is due and this aggregate decides what has already
  happened, so a check-in fires once a day whatever restarts.
  """

  alias Oneiroi.Sunna.CheckinParts
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events

  defstruct [
    :id,
    checkins: %{},
    free_times: nil,
    free_time_days: %{},
    quiet: nil,
    dates: %{},
    days: MapSet.new(),
    hours: MapSet.new(),
    letters_woken: MapSet.new(),
    letter_wakes: []
  ]

  @hour ~r/\A\d{4}-\d{2}-\d{2}T([01]\d|2[0-3])\z/

  @time ~r/\A([01]\d|2[0-3]):[0-5]\d\z/
  @date_kinds ~w(deadline anniversary window recurring)
  @label_limit 60
  # A bound (sunna#22): free time is one to this many slots a day, so a
  # list cannot grow into a resident who is never not on her own time.
  @free_time_slots 4

  @doc "The kinds a date takes (spec §6.7)."
  @spec date_kinds() :: [String.t()]
  def date_kinds, do: @date_kinds

  @doc "Whether a time of day is well formed: `HH:MM`."
  @spec time_ok?(term()) :: boolean()
  def time_ok?(time), do: is_binary(time) and Regex.match?(@time, time)

  # ---- check-ins ----

  def execute(%__MODULE__{checkins: checkins}, %Commands.SetCheckin{} = c) do
    # A command that says nothing of its parts carries the dates, the
    # note every check-in had before sunna#28.
    c = %{c | parts: c.parts || ["dates"]}

    cond do
      not time_ok?(c.time) ->
        {:error, Error.new(:sunna_time_invalid, :sunna_checkin_time_invalid)}

      not label_ok?(c.label) ->
        {:error, Error.new(:sunna_label_invalid, :sunna_checkin_label_invalid)}

      not parts_ok?(c.parts) ->
        {:error,
         Error.new(:sunna_parts_invalid, :sunna_checkin_parts_invalid, parts: CheckinParts.keys())}

      not Map.has_key?(checkins, c.key) ->
        %Events.CheckinSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          key: c.key,
          label: c.label,
          time: c.time,
          day: c.day,
          parts: c.parts,
          prompt: c.prompt
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
          day: c.day,
          parts: c.parts,
          prompt: c.prompt
        }
    end
  end

  def execute(%__MODULE__{checkins: checkins}, %Commands.DeleteCheckin{} = c) do
    if Map.has_key?(checkins, c.key),
      do: %Events.CheckinDeleted{actor: c.actor, at: c.at, id: c.id, key: c.key},
      else: {:error, Error.new(:sunna_no_such_checkin, :sunna_checkin_delete_absent, key: c.key)}
  end

  # Once a day: a second fire or a miss after a fire is no event, a
  # deferred wake fires at its end, and the first firing of a day opens
  # the day (the journal's row). The first version returned no event for
  # every recorded outcome, deferral included, so a check-in inside quiet
  # hours was deferred and then never woke; the test for quiet hours
  # found it.
  def execute(%__MODULE__{} = s, %Commands.FireCheckin{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin ->
        {:error, Error.new(:sunna_no_such_checkin, :sunna_checkin_fire_absent, key: c.key)}

      nil ->
        fire(s, c)

      {:deferred, _until} ->
        fire(s, c)

      _already ->
        []
    end
  end

  def execute(%__MODULE__{} = s, %Commands.MissCheckin{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin ->
        {:error, Error.new(:sunna_no_such_checkin, :sunna_checkin_miss_absent, key: c.key)}

      nil ->
        %Events.CheckinMissed{actor: c.actor, at: c.at, id: c.id, key: c.key, day: c.day}

      _already ->
        []
    end
  end

  def execute(%__MODULE__{} = s, %Commands.DeferWake{} = c) do
    case outcome(s, c.key, c.day) do
      :no_such_checkin ->
        {:error, Error.new(:sunna_no_such_checkin, :sunna_checkin_defer_absent, key: c.key)}

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
      not (is_binary(c.hour) and Regex.match?(@hour, c.hour)) ->
        {:error, Error.new(:sunna_hour_invalid, :sunna_hour_marker_invalid)}

      MapSet.member?(hours, c.hour) ->
        []

      true ->
        %Events.HourMarked{actor: c.actor, at: c.at, id: c.id, hour: c.hour}
    end
  end

  # A letter's wake (sunna#24): each letter wakes the chat once, and at
  # most `limit` wakes in the hour before the command's instant; a letter
  # held back by the bound is taken by a later tick.
  def execute(%__MODULE__{} = s, %Commands.WakeForLetters{} = c) do
    fresh = c.numbers |> Enum.reject(&MapSet.member?(s.letters_woken, &1)) |> Enum.sort()
    hour_ago = DateTime.add(c.at, -3600, :second)
    recent = Enum.count(s.letter_wakes, &(DateTime.compare(&1, hour_ago) == :gt))

    cond do
      fresh == [] -> []
      recent >= c.limit -> []
      true -> %Events.LettersWoke{actor: c.actor, at: c.at, id: c.id, numbers: fresh}
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.OpenDay{} = c) do
    cond do
      not day_ok?(c.day) ->
        {:error, Error.new(:sunna_day_invalid, :sunna_day_open_invalid, day: inspect(c.day))}

      MapSet.member?(days, c.day) ->
        []

      true ->
        %Events.DayOpened{actor: c.actor, at: c.at, id: c.id, day: c.day}
    end
  end

  # ---- free time ----

  def execute(%__MODULE__{free_times: current}, %Commands.SetFreeTime{} = c) do
    times = List.wrap(c.times)

    cond do
      # Free time moves and is never removed (sunna#21): at least one slot.
      times == [] ->
        {:error, Error.new(:sunna_free_time_required, :sunna_free_time_removed)}

      not Enum.all?(times, &time_ok?/1) ->
        {:error, Error.new(:sunna_time_invalid, :sunna_free_time_time_invalid)}

      length(times) > @free_time_slots or length(Enum.uniq(times)) != length(times) ->
        {:error,
         Error.new(:sunna_free_time_invalid, :sunna_free_time_slots_invalid,
           slots: length(times),
           bound: @free_time_slots
         )}

      current == Enum.sort(times) ->
        []

      true ->
        %Events.FreeTimeScheduled{actor: c.actor, at: c.at, id: c.id, times: Enum.sort(times)}
    end
  end

  def execute(%__MODULE__{free_time_days: days}, %Commands.RecordFreeTime{} = c) do
    cond do
      # A day recorded before slots (a version 1 event, `:all`) had its
      # one free time, and runs no other. Otherwise the tick decides
      # whether a slot has run, by its instant (sunna#27); a run whose day
      # and slot an earlier run carries, after a change of zone, is
      # another slot and is recorded.
      # The same record again, at the same instant, is the same run.
      Map.has_key?(days, {c.day, :all}) or Map.get(days, {c.day, c.slot}) == c.at ->
        []

      is_binary(c.session_key) ->
        %Events.FreeTimeRan{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          slot: c.slot,
          session_key: c.session_key
        }

      true ->
        %Events.FreeTimeFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          slot: c.slot,
          reason: c.reason || "unknown"
        }
    end
  end

  # ---- quiet hours, dates ----

  def execute(%__MODULE__{quiet: quiet}, %Commands.SetQuietHours{} = c) do
    cond do
      not ((is_nil(c.from) and is_nil(c.to)) or (time_ok?(c.from) and time_ok?(c.to))) ->
        {:error, Error.new(:sunna_time_invalid, :sunna_quiet_hours_time_invalid)}

      quiet == quiet_of(c) ->
        []

      true ->
        %Events.QuietHoursSet{actor: c.actor, at: c.at, id: c.id, from: c.from, to: c.to}
    end
  end

  def execute(%__MODULE__{dates: dates}, %Commands.SetDate{} = c) do
    cond do
      not label_ok?(c.title) ->
        {:error, Error.new(:sunna_label_invalid, :sunna_date_title_invalid)}

      c.kind not in @date_kinds ->
        {:error, Error.new(:sunna_kind_invalid, :sunna_date_kind_invalid, kinds: @date_kinds)}

      not match?(%DateTime{}, c.on) ->
        {:error, Error.new(:sunna_time_invalid, :sunna_date_on_invalid)}

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
      else: {:error, Error.new(:sunna_no_such_date, :sunna_date_remove_absent, number: c.number)}
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
            parts: e.parts,
            prompt: e.prompt,
            changed_day: e.day,
            outcomes: %{}
          })
    }

  def apply(%__MODULE__{} = s, %Events.CheckinChanged{} = e) do
    update_in(
      s.checkins[e.key],
      &Map.merge(&1, %{
        label: e.label,
        time: e.time,
        parts: e.parts,
        prompt: e.prompt,
        changed_day: e.day
      })
    )
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

  def apply(%__MODULE__{} = s, %Events.LettersWoke{} = e) do
    hour_ago = DateTime.add(e.at, -3600, :second)

    %{
      s
      | id: e.id,
        letters_woken: MapSet.union(s.letters_woken, MapSet.new(e.numbers)),
        letter_wakes: [
          e.at | Enum.filter(s.letter_wakes, &(DateTime.compare(&1, hour_ago) == :gt))
        ]
    }
  end

  def apply(%__MODULE__{} = s, %Events.FreeTimeScheduled{} = e),
    do: %{s | id: e.id, free_times: e.times || List.wrap(e.time)}

  def apply(%__MODULE__{} = s, %Events.FreeTimeRan{} = e),
    do: %{s | free_time_days: Map.put(s.free_time_days, {e.day, e.slot || :all}, e.at)}

  def apply(%__MODULE__{} = s, %Events.FreeTimeFailed{} = e),
    do: %{s | free_time_days: Map.put(s.free_time_days, {e.day, e.slot || :all}, e.at)}

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

  defp same_checkin?(was, c),
    do:
      was.label == c.label and was.time == c.time and Map.get(was, :parts) == c.parts and
        Map.get(was, :prompt) == c.prompt

  # The parts a note carries are the catalog's keys, each once.
  defp parts_ok?(parts),
    do:
      is_list(parts) and parts == Enum.uniq(parts) and
        Enum.all?(parts, &(&1 in CheckinParts.keys()))

  defp day_ok?(day), do: is_binary(day) and match?({:ok, _}, Date.from_iso8601(day))

  defp label_ok?(label),
    do: is_binary(label) and String.trim(label) != "" and String.length(label) <= @label_limit

  defp quiet_of(%{from: nil, to: nil}), do: nil
  defp quiet_of(%{from: from, to: to}), do: %{from: from, to: to}

  defp date_of(c), do: %{title: c.title, on: c.on, kind: c.kind}
end
