defmodule Oneiroi.Sunna.Calendar do
  @moduledoc """
  The calendar's ranges (sunna#48): a range of the resident's local days,
  held to `SUNNA_DAYS_SPAN`, and, for today and every day after it, the
  schedule the rules as they stand would run on that day, computed on the
  read and never written down, as a date's countdown is (sunna#8).

  Each entry of a day's schedule is one occurrence: its kind, its key, the
  HH:MM it is set for in her zone, the instant it would run (a check-in
  inside quiet hours at their end, as the tick defers it), its `rule` and
  its `status`. Today every standing item repeats daily (`%{freq:
  "daily"}`) and a one-off or a date has no rule (`nil`); every status is
  `scheduled`. Recurrence (`design/scheduling-notes.md`) fills `rule` with
  its fields and adds `skipped` and `paused`, so the shape stays.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store

  @daily %{freq: "daily"}

  @doc """
  A range of her local days from `from` through `to` (ISO dates, both
  included, both required): `{:ok, %{from, to, today, zone, days}}`,
  `days` every ISO date of the range in order; `sunna_day_invalid` for a
  bound that is no date, `sunna_range_invalid` for one missing, a range
  that runs backwards, or one longer than `SUNNA_DAYS_SPAN`.
  """
  @spec range(String.t(), term(), term()) :: {:ok, map()} | {:error, Error.t()}
  def range(resident_id, from, to) do
    with {:ok, first} <- date(from, :from),
         {:ok, last} <- date(to, :to),
         :ok <- span(first, last) do
      local = local_now(resident_id)

      {:ok,
       %{
         from: Date.to_iso8601(first),
         to: Date.to_iso8601(last),
         today: Schedules.local_day(local),
         zone: local.time_zone,
         days: Enum.map(Date.range(first, last), &Date.to_iso8601/1)
       }}
    end
  end

  defp date(text, side) when is_binary(text) and text != "" do
    case Date.from_iso8601(text) do
      {:ok, date} ->
        {:ok, date}

      _other ->
        {:error,
         Error.new(:sunna_day_invalid, :sunna_calendar_day_invalid, day: text, side: side)}
    end
  end

  defp date(_missing, side),
    do: {:error, Error.new(:sunna_range_invalid, :sunna_calendar_bound_missing, side: side)}

  defp span(first, last) do
    days = Date.diff(last, first) + 1
    max = Config.fetch!(:sunna, :days_span)

    if days in 1..max//1,
      do: :ok,
      else:
        {:error,
         Error.new(:sunna_range_invalid, :sunna_calendar_span_invalid,
           from: Date.to_iso8601(first),
           to: Date.to_iso8601(last),
           max: max
         )}
  end

  @doc """
  The schedule of each of `days` (ISO dates) that is today or later in her
  zone, day to `%{quiet, rounds, entries}`; past days are left out. A
  resident who is not active schedules nothing (spec §6.7), so her days
  hold no entries and no rounds.
  """
  @spec schedules(String.t(), [String.t()]) :: %{String.t() => map()}
  def schedules(resident_id, days) do
    local = local_now(resident_id)
    today = Schedules.local_day(local)
    ahead = Enum.filter(days, &(&1 >= today))

    if ahead == [] do
      %{}
    else
      active = active?(resident_id)

      {checkins, settings, once, dates} =
        Scope.resident(resident_id, fn ->
          {Store.checkins(), Store.settings(), Store.free_time_once_from(hd(ahead)),
           Store.dates()}
        end)

      quiet = quiet_of(settings)
      rules = %{checkins: checkins, settings: settings, once: once, dates: dates, quiet: quiet}

      Map.new(ahead, fn day ->
        {day, day_schedule(resident_id, day, local.time_zone, rules, active)}
      end)
    end
  end

  defp day_schedule(_resident_id, _day, _zone, %{quiet: quiet}, false),
    do: %{quiet: quiet, rounds: 0, entries: []}

  defp day_schedule(resident_id, day, zone, rules, true) do
    noon = noon(day, zone)
    settings = rules.settings
    every = settings && settings.rounds_every_hours
    waking = settings && settings.rounds_waking

    entries =
      Enum.map(rules.checkins, &checkin(&1, noon, rules.quiet)) ++
        Enum.map(Schedules.free_times_of(settings), &free_time(&1, noon)) ++
        for(o <- rules.once, o.day == day, do: once(o, noon)) ++
        for(d <- rules.dates, local_day(d.on, zone) == day, do: date_entry(d, zone))

    %{
      quiet: rules.quiet,
      # How many, never when: a round's time is hers (sunna#29, #39).
      rounds: length(Schedules.round_times(resident_id, day, rules.quiet, every, waking)),
      entries: Enum.sort_by(entries, &{DateTime.to_unix(&1.at, :microsecond), &1.kind, &1.key})
    }
  end

  # A check-in whose time falls inside quiet hours waits for their end,
  # as the tick's `due/4` defers it.
  defp checkin(c, noon, quiet) do
    set = Schedules.at_time(noon, c.time)

    at =
      if Schedules.quiet?(set, quiet), do: Schedules.quiet_end(set, quiet), else: set

    entry("checkin", c.key, c.label, c.time, at, @daily)
    |> Map.put(:deferred, DateTime.compare(at, set) != :eq)
  end

  defp free_time(time, noon),
    do: entry("free_time", time, nil, time, Schedules.at_time(noon, time), @daily)

  defp once(o, noon) do
    "free_time"
    |> entry(Schedules.once_label(o.time), nil, o.time, Schedules.at_time(noon, o.time), nil)
    |> Map.put(:added_by, o.added_by)
  end

  defp date_entry(d, zone) do
    local = DateTime.shift_zone!(d.on, zone)
    time = local |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)

    "date"
    |> entry(Integer.to_string(d.number), d.title, time, d.on, nil)
    |> Map.put(:date_kind, d.kind)
  end

  defp entry(kind, key, label, time, at, rule),
    do: %{
      kind: kind,
      key: key,
      label: label,
      time: time,
      at: utc(at),
      rule: rule,
      status: "scheduled"
    }

  # In UTC at microsecond precision, as every other instant the API gives.
  defp utc(%DateTime{} = at) do
    {us, _precision} = at.microsecond
    at |> DateTime.shift_zone!("Etc/UTC") |> Map.put(:microsecond, {us, 6})
  end

  defp noon(day, zone) do
    {:ok, at} = DateTime.new(Date.from_iso8601!(day), ~T[12:00:00], zone)
    at
  end

  defp local_day(%DateTime{} = at, zone),
    do: at |> DateTime.shift_zone!(zone) |> DateTime.to_date() |> Date.to_iso8601()

  defp active?(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{state: "active"}} -> true
      _other -> false
    end
  end

  # One reading of now for the whole read, in her zone.
  defp local_now(resident_id), do: Schedules.local_now(resident_id)

  defp quiet_of(%{quiet_from: from, quiet_to: to}) when is_binary(from) and is_binary(to),
    do: %{from: from, to: to}

  defp quiet_of(_none), do: nil
end
