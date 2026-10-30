defmodule Oneiroi.Sunna.Schedules do
  @moduledoc """
  The schedule's service functions (spec §6.7): the command edge for
  check-ins, free time, quiet hours and dates; the reads the Schedule
  screen takes; the local-time arithmetic the tick and the screen share;
  and the wake itself, a core-controlled note the brain answers.

  Times are the resident's own: every instant is shifted into the zone
  on the resident's row, so a check-in at 06:00 is 06:00 where the
  resident lives, and a date's countdown is counted in that zone's days.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Router
  alias Oneiroi.Sunna.Schedule
  alias Oneiroi.Sunna.Store

  # ---- check-ins ----

  @doc "Sets a check-in by key (a fresh one when nil); returns the key."
  def set_checkin(resident_id, key, label, time, %Actor{} = actor) do
    key = key || fresh_key()
    day = resident_id |> local_now() |> local_day()

    command = %Commands.SetCheckin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      label: label,
      time: time,
      day: day
    }

    with {:ok, _} <- dispatch(command), do: {:ok, key}
  end

  def delete_checkin(resident_id, key, %Actor{} = actor) do
    command = %Commands.DeleteCheckin{actor: actor, at: Clock.now(), id: resident_id, key: key}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  def set_free_time(resident_id, time, %Actor{} = actor) do
    command = %Commands.SetFreeTime{actor: actor, at: Clock.now(), id: resident_id, time: time}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  def set_quiet_hours(resident_id, from, to, %Actor{} = actor) do
    command = %Commands.SetQuietHours{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      from: from,
      to: to
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- dates ----

  @doc "Sets a date: a new row (number minted) when `number` is nil; returns the number."
  def set_date(resident_id, number, %{title: title, on: on, kind: kind}, %Actor{} = actor) do
    with {:ok, number} <- date_number(resident_id, number, actor) do
      command = %Commands.SetDate{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        title: title,
        on: on,
        kind: kind
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  defp date_number(resident_id, nil, actor), do: AgathosDaimon.mint_id(resident_id, "date", actor)
  defp date_number(_resident_id, number, _actor), do: {:ok, number}

  def remove_date(resident_id, number, %Actor{} = actor) do
    command = %Commands.RemoveDate{actor: actor, at: Clock.now(), id: resident_id, number: number}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- the day row ----

  @doc "Opens the journal's day row when the journal gets to a day before the schedule does (seshat #21); no event when it is open."
  def open_day(resident_id, day, %Actor{} = actor) do
    command = %Commands.OpenDay{actor: actor, at: Clock.now(), id: resident_id, day: day}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "One day row, or nil."
  def day(resident_id, day), do: Scope.resident(resident_id, fn -> Store.day(day) end)

  # ---- reads ----

  def checkins(resident_id), do: Scope.resident(resident_id, fn -> Store.checkins() end)
  def dates(resident_id), do: Scope.resident(resident_id, fn -> Store.dates() end)
  def days(resident_id, limit), do: Scope.resident(resident_id, fn -> Store.days(limit) end)
  def settings(resident_id), do: Scope.resident(resident_id, fn -> Store.settings() end)

  @doc """
  Today in the resident's zone: the day, the local instant, the last and
  next check-in with their times, today's firings, free time and quiet
  hours, and the dates with their countdowns derived now.
  """
  def today(resident_id) do
    now = local_now(resident_id)
    day = local_day(now)

    Scope.resident(resident_id, fn ->
      checkins = Store.checkins()
      firings = Store.firings(day)
      settings = Store.settings()

      %{
        day: day,
        now: now,
        timezone: now.time_zone,
        checkins: checkins,
        firings: firings,
        last: last_checkin(checkins, firings, now),
        next: next_checkin(checkins, now),
        free_time: settings && settings.free_time,
        free_time_last: settings && {settings.free_time_day, settings.free_time_outcome},
        quiet: quiet_of(settings),
        dates: Enum.map(Store.dates(), &date_with_countdown(&1, now))
      }
    end)
  end

  @doc "Every firing over the last `days` days in the resident's zone, today included."
  def firings(resident_id, days) do
    today = resident_id |> local_now() |> DateTime.to_date()
    from = today |> Date.add(-(days - 1)) |> Date.to_iso8601()
    Scope.resident(resident_id, fn -> Store.firings_between(from, Date.to_iso8601(today)) end)
  end

  @doc "The dates section the brain is shown, with every countdown derived on this read; empty when there are none."
  @spec dates_text(String.t()) :: String.t()
  def dates_text(resident_id) do
    now = local_now(resident_id)

    case Scope.resident(resident_id, fn -> Store.dates() end) do
      [] ->
        ""

      dates ->
        lines = Enum.map(dates, fn d -> "- " <> countdown_line(date_with_countdown(d, now)) end)
        Enum.join(["# Dates\n\nCounted today, never written down." | lines], "\n")
    end
  end

  @doc "A date with `days_to` derived from the resident's local day: negative once past."
  def date_with_countdown(date, %DateTime{} = now) do
    local = DateTime.shift_zone!(date.on, now.time_zone)
    days = Date.diff(DateTime.to_date(local), DateTime.to_date(now))

    %{
      number: date.number,
      title: date.title,
      on: date.on,
      kind: date.kind,
      days_to: days,
      local: local
    }
  end

  defp countdown_line(%{days_to: 0} = d), do: "today: #{d.title} (#{d.kind}, date/#{d.number})"

  defp countdown_line(%{days_to: n} = d) when n > 0,
    do:
      "#{n} days to #{d.title} (#{d.kind}, #{Date.to_iso8601(DateTime.to_date(d.local))}, date/#{d.number})"

  defp countdown_line(%{days_to: n} = d),
    do: "#{-n} days since #{d.title} (#{d.kind}, date/#{d.number})"

  # ---- the tick's arithmetic ----

  @doc "Now in the resident's zone (UTC until the witness sets one)."
  def local_now(resident_id) do
    zone =
      case AgathosDaimon.fetch(resident_id) do
        {:ok, %{timezone: tz}} when is_binary(tz) -> tz
        _other -> "Etc/UTC"
      end

    DateTime.shift_zone!(Clock.now(), zone)
  end

  @doc "The ISO date of a local instant."
  def local_day(%DateTime{} = local), do: local |> DateTime.to_date() |> Date.to_iso8601()

  @doc "The instant a `HH:MM` falls on `day` in the local zone."
  def at_time(%DateTime{} = local, "" <> time) do
    [h, m] = time |> String.split(":") |> Enum.map(&String.to_integer/1)
    {:ok, naive} = NaiveDateTime.new(DateTime.to_date(local), Time.new!(h, m, 0))

    case DateTime.from_naive(naive, local.time_zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, after_gap} -> after_gap
    end
  end

  @doc "Whether a local instant falls inside quiet hours, which may cross midnight."
  def quiet?(_local, nil), do: false

  def quiet?(%DateTime{} = local, %{from: from, to: to}) do
    t = Time.to_string(DateTime.to_time(local)) |> String.slice(0, 5)
    if from <= to, do: t >= from and t < to, else: t >= from or t < to
  end

  @doc "When quiet hours end, from a local instant inside them."
  def quiet_end(%DateTime{} = local, %{from: from, to: to}) do
    today_end = at_time(local, to)

    if from <= to or DateTime.compare(local, today_end) == :lt,
      do: today_end,
      else: local |> DateTime.add(1, :day) |> at_time(to)
  end

  @doc "What the tick does with a check-in now: :fire, :miss, {:defer, until}, or :wait."
  def due(checkin, %DateTime{} = local, quiet, outcome) do
    case outcome do
      nil -> due_now(checkin, local, quiet)
      {:deferred, until} -> if DateTime.compare(local, until) != :lt, do: :fire, else: :wait
      _final -> :wait
    end
  end

  defp due_now(checkin, local, quiet) do
    day = local_day(local)
    scheduled = at_time(local, checkin.time)
    late = Config.fetch!(:sunna, :late_minutes) * 60

    cond do
      checkin.changed_day == day and DateTime.compare(checkin.set_at, scheduled) == :gt ->
        :wait

      DateTime.compare(local, scheduled) == :lt ->
        :wait

      DateTime.diff(local, scheduled, :second) > late ->
        :miss

      quiet?(local, quiet) ->
        {:defer, quiet_end(local, quiet)}

      true ->
        :fire
    end
  end

  # ---- firing ----

  @doc "Fires a check-in: the firing row first, then the wake in the main session with the core's note."
  def fire_checkin(resident_id, checkin, day, %Actor{} = actor) do
    command = %Commands.FireCheckin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: checkin.key,
      day: day
    }

    case dispatch(command) do
      {:ok, []} -> :already
      {:ok, _} -> wake_main(resident_id, checkin_note(resident_id, checkin), actor)
      other -> other
    end
  end

  def miss_checkin(resident_id, key, day, %Actor{} = actor) do
    command = %Commands.MissCheckin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      day: day
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def defer_wake(resident_id, key, day, until, %Actor{} = actor) do
    command = %Commands.DeferWake{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      day: day,
      until: until
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Runs free time for the day: a solo session of its own kind, the brain woken on the free-time line; the outcome recorded once."
  def run_free_time(resident_id, day, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <-
           Kumbukumbu.open_session(
             resident_id,
             "free_time",
             "brain",
             List.wrap(row.account_id),
             actor,
             private: AgathosDaimon.contract(resident_id).solo_sessions_private
           ),
         {:ok, _} <-
           wake(resident_id, key, Prompt.render!("free_time", %{name: row.name}), :free_time) do
      record_free_time(resident_id, day, key, nil, actor)
    else
      {:error, reason} -> record_free_time(resident_id, day, nil, reason_text(reason), actor)
    end
  end

  defp record_free_time(resident_id, day, key, reason, actor) do
    command = %Commands.RecordFreeTime{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      session_key: key,
      reason: reason
    }

    with {:ok, _} <- dispatch(command), do: if(key, do: :ok, else: {:error, reason})
  end

  defp wake_main(resident_id, note, actor) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, row.account_id, actor),
         {:ok, _} <- wake(resident_id, key, note, :chat) do
      :ok
    end
  end

  # Through the port (`Oneiroi.Sunna.Wake`), read at the call.
  defp wake(resident_id, key, note, purpose),
    do: Config.fetch!(:sunna, :wake).wake(resident_id, key, note, purpose)

  # The note is the core's (spec §8): the check-in's label and time, the
  # next check-in, and the dates counted now.
  defp checkin_note(resident_id, checkin) do
    now = local_now(resident_id)
    next = resident_id |> checkins() |> next_checkin(now)

    Prompt.render!("checkin", %{
      label: checkin.label,
      time: checkin.time,
      next: if(next, do: "#{next.label} at #{next.time}", else: "none set"),
      dates: dates_text(resident_id)
    })
  end

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, :no_such_resident}
    end
  end

  defp last_checkin(checkins, firings, now) do
    fired = Enum.filter(firings, &(&1.outcome == "fired"))

    case List.last(fired) do
      nil ->
        nil

      f ->
        Enum.find(checkins, &(&1.key == f.key))
        |> then(
          &(&1 && %{label: &1.label, time: &1.time, at: DateTime.shift_zone!(f.at, now.time_zone)})
        )
    end
  end

  defp next_checkin(checkins, now) do
    t = now |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)

    case Enum.find(checkins, &(&1.time > t)) do
      nil ->
        List.first(checkins) &&
          %{label: hd(checkins).label, time: hd(checkins).time, tomorrow: true}

      c ->
        %{label: c.label, time: c.time, tomorrow: false}
    end
  end

  defp quiet_of(%{quiet_from: from, quiet_to: to}) when is_binary(from) and is_binary(to),
    do: %{from: from, to: to}

  defp quiet_of(_), do: nil

  defp fresh_key, do: 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp reason_text(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp reason_text(other), do: other |> inspect() |> String.slice(0, 200)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :time_invalid} ->
        {:error, Error.new(:sunna_time_invalid)}

      {:error, :label_invalid} ->
        {:error, Error.new(:sunna_label_invalid)}

      {:error, :kind_invalid} ->
        {:error, Error.new(:sunna_kind_invalid, kinds: Schedule.date_kinds())}

      {:error, :no_such_checkin} ->
        {:error, Error.new(:sunna_no_such_checkin, key: command.key)}

      {:error, :day_invalid} ->
        {:error, Error.new(:sunna_day_invalid, day: inspect(command.day))}

      {:error, :no_such_date} ->
        {:error, Error.new(:sunna_no_such_date, number: command.number)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
