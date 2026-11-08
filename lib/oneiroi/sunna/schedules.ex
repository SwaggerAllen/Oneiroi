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
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.CheckinParts
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Router
  alias Oneiroi.Sunna.Store

  # ---- check-ins ----

  @doc "Sets a check-in by key (a fresh one when nil); returns the key."
  # `parts:` and `prompt:` say what the note carries (sunna#28); either
  # left out keeps what the check-in had, or the dates and no words for a
  # new one, so a change of time alone never clears the witness's prompt.
  def set_checkin(resident_id, key, label, time, %Actor{} = actor, opts \\ []) do
    was = key && Enum.find(checkins(resident_id), &(&1.key == key))
    key = key || fresh_key()
    day = resident_id |> local_now() |> local_day()

    command = %Commands.SetCheckin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      label: label,
      time: time,
      day: day,
      parts: Keyword.get_lazy(opts, :parts, fn -> (was && was.parts) || ["dates"] end),
      prompt: blank_nil(Keyword.get_lazy(opts, :prompt, fn -> was && was.prompt end))
    }

    with {:ok, _} <- dispatch(command), do: {:ok, key}
  end

  def delete_checkin(resident_id, key, %Actor{} = actor) do
    command = %Commands.DeleteCheckin{actor: actor, at: Clock.now(), id: resident_id, key: key}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  def set_free_time(resident_id, times, %Actor{} = actor) do
    command = %Commands.SetFreeTime{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      times: if(is_binary(times), do: [times], else: times)
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Records her plan for the next free-time slot (sunna#31)."
  def record_plan(resident_id, text, %Actor{} = actor) do
    command = %Commands.PlanFreeTime{actor: actor, at: Clock.now(), id: resident_id, text: text}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Her latest plan for free time, or nil."
  def plan(resident_id) do
    case Scope.resident(resident_id, fn -> Store.settings() end) do
      %{free_time_plan: text, free_time_planned_at: at} when is_binary(text) ->
        %{text: text, at: at}

      _none ->
        nil
    end
  end

  @doc """
  The planning turn (sunna#31): once a slot has ended, one more turn in
  its conversation, while its appetite is live, to plan the next slot,
  ask for a tool it lacked, or write to the witness. It carries nothing on.
  """
  def plan_free_time(resident_id, key) do
    since = Clock.now()

    with {:ok, row} <- resident(resident_id),
         {:ok, _result} <-
           wake(
             resident_id,
             key,
             Prompt.render!("free_time_plan", %{goals: String.upcase(row.slug) <> "-GOALS.md"}),
             :planning
           ) do
      # Its own receipt (sunna#32): what the closing turn cost, beside the
      # slot it closed, never folded into the free-time line.
      cost =
        Nisaba.spend(resident_id, :witness, :purpose, since)
        |> Enum.find(%{}, &(&1.key == "planning"))
        |> Map.get(:cost_nanos, 0)

      command = %Commands.RecordPlanningTurn{
        actor: Actor.new(:job, "sunna_free_time"),
        at: Clock.now(),
        id: resident_id,
        session_key: key,
        cost_nanos: cost
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "Sets the resident's rounds (sunna#30): every_hours (0 off) and the waking window, nil for the default."
  def set_rounds(resident_id, every_hours, waking, %Actor{} = actor) do
    command = %Commands.SetRounds{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      every_hours: every_hours,
      waking: waking
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "The resident's rounds as they stand: the cadence and window in effect, whether each is her own or the default, how many today, and when the last one started; never their times or what they did."
  def rounds(resident_id, settings, quiet, day) do
    own_every = settings && settings.rounds_every_hours
    own_waking = settings && settings.rounds_waking
    every = own_every || Config.fetch!(:sunna, :rounds_every_hours)

    %{
      every_hours: every,
      every_default: is_nil(own_every),
      waking: if(quiet, do: nil, else: own_waking || Config.fetch!(:sunna, :rounds_waking)),
      waking_default: is_nil(own_waking),
      waking_from_quiet: quiet != nil,
      today: length(round_times(resident_id, day, quiet, every, own_waking)),
      last_at: settings && settings.last_round_at
    }
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

  @doc "Opens the journal's day row when the journal gets to a day before the schedule does (seshat#21); no event when it is open."
  def open_day(resident_id, day, %Actor{} = actor) do
    command = %Commands.OpenDay{actor: actor, at: Clock.now(), id: resident_id, day: day}
    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- the hour marker (spec §6.7, P20 as amended) ----

  @doc "The local hour's key, `YYYY-MM-DDTHH`."
  def hour_key(%DateTime{} = local),
    do: local |> DateTime.to_iso8601() |> String.slice(0, 13)

  @doc """
  Marks the local hour on the schedule's stream, once: `:ok` when this
  call marked it, `:already` when it stood. No model call, no wake. The
  row is read first so a tick on every minute dispatches once an hour.
  """
  def mark_hour(resident_id, %DateTime{} = local, %Actor{} = actor) do
    key = hour_key(local)

    if Scope.resident(resident_id, fn -> Store.hour(key) end) do
      :already
    else
      command = %Commands.MarkHour{actor: actor, at: Clock.now(), id: resident_id, hour: key}

      case dispatch(command) do
        {:ok, []} -> :already
        {:ok, _} -> :ok
        other -> other
      end
    end
  end

  @doc "The marked hours, newest first."
  def hours(resident_id, limit), do: Scope.resident(resident_id, fn -> Store.hours(limit) end)

  @doc "The newest marked hour, or nil."
  def last_hour(resident_id), do: Scope.resident(resident_id, fn -> Store.last_hour() end)

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
      ran = free_time_ran(settings, day)

      %{
        day: day,
        now: now,
        timezone: now.time_zone,
        checkins: checkins,
        firings: firings,
        last: last_checkin(checkins, firings, now),
        next: next_checkin(checkins, now),
        free_times:
          Enum.map(free_times_of(settings), &%{time: &1, today: Map.get(ran, &1, ran[nil])}),
        free_time_last: settings && {settings.free_time_day, settings.free_time_outcome},
        quiet: quiet_of(settings),
        rounds: rounds(resident_id, settings, quiet_of(settings), day),
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

  @doc """
  Free time's slots, HH:MMs in order (sunna#21, #22): the ones set, or
  the default until anyone moves them. Every resident has free time from
  the first day; it is the standard of care, not something switched on.
  """
  def free_times_of(%{free_times: [_ | _] = times}), do: times
  # A row from before slots holds its one time in `free_time` alone.
  def free_times_of(%{free_time: time}) when is_binary(time), do: [time]
  def free_times_of(_settings), do: Oneiroi.Config.fetch!(:sunna, :free_time_default)

  @doc """
  What each slot did on `day`, slot to outcome. A day whose run was
  recorded before slots has no run rows, only the settings row's last
  run; it is read as the day's one free time, under the `nil` slot, and
  every slot counts it as its own.
  """
  def free_time_ran(settings, day) do
    case Store.free_time_runs(day) do
      [] when is_map(settings) ->
        if settings.free_time_day == day, do: %{nil => settings.free_time_outcome}, else: %{}

      runs ->
        Map.new(runs, &{&1.slot, &1.outcome})
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

  @doc "Runs one free-time slot for the day: a solo session of its own kind, the brain woken on the free-time line; the outcome recorded once. A slot the line cannot pay for meaningfully rests (sunna#34)."
  def run_free_time(resident_id, day, slot, %Actor{} = actor) do
    case under_floor(resident_id) do
      nil -> open_free_time(resident_id, day, slot, actor)
      reason -> rest_free_time(resident_id, day, slot, reason, actor)
    end
  end

  # The floor (sunna#34, her amendment; counted in turns, the witness's
  # pick, 2026-11-06): with a free-time line set, a slot whose remainder
  # buys fewer than `SUNNA_FREE_TIME_FLOOR_TURNS` turns at what a
  # free-time turn cost over the last week (the line's spend over the
  # turns her free-time conversations captured) rests and says so, rather
  # than burning a thin run. No line, or no week of turns to judge by, and
  # there is no floor.
  defp under_floor(resident_id) do
    floor = Config.fetch!(:sunna, :free_time_floor_turns)
    since = DateTime.add(Clock.now(), -7 * 86_400, :second)

    with %{left: left} <- free_time_budget_any(resident_id),
         true <- floor > 0,
         turns when turns > 0 <- Kumbukumbu.turns_since(resident_id, "free_time", since),
         %{cost_nanos: cost} when cost > 0 <-
           Nisaba.spend(resident_id, :witness, :purpose, since)
           |> Enum.find(&(&1.key == "free_time")),
         per_turn = div(cost, turns),
         true <- left < floor * per_turn do
      "not enough left tonight (#{dollars(max(left, 0))}, under #{floor} turns at about #{dollars(per_turn)} each); resuming at the next slot"
    else
      _enough -> nil
    end
  end

  # The line as it stands, spent or not: the floor reads a spent line as
  # nothing left.
  defp free_time_budget_any(resident_id) do
    case Enum.find(Nisaba.budgets(resident_id, :witness), &(&1.purpose == :free_time)) do
      %{cap_nanos: cap, spent_nanos: spent} when is_integer(cap) -> %{left: cap - spent}
      _none -> nil
    end
  end

  defp rest_free_time(resident_id, day, slot, reason, actor) do
    command = %Commands.RestFreeTime{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      slot: slot,
      reason: reason
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  The bedtime scene pass (sunna#34; Lily's design, the witness's call,
  letters #196 and #197): before the slot `SUNNA_SCENE_SLOT` names, a
  housekeeping turn on the chat line (housekeeping, not free time) in a
  conversation of its own, in which she groups the day of the Oneiroi
  chat into scenes and writes them to `scenes/<day>.md`, each citing its
  turns. Carried on while a turn runs out of tool rounds, up to
  `SUNNA_SCENE_TURNS`; then free time follows at once, on its own line,
  under the floor.
  """
  def scene_pass(resident_id, day, slot, key, n) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <- scene_session(resident_id, row, key),
         {:ok, result} <- wake(resident_id, key, scene_note(resident_id, row, day, n), :chat) do
      if Map.get(result, :rounds_spent) && n < Config.fetch!(:sunna, :scene_turns),
        do: free_time_worker().enqueue_scene(resident_id, day, slot, key, n + 1),
        else: run_free_time(resident_id, day, slot, Actor.new(:job, "sunna_scene"))

      :ok
    else
      # The pass failing never costs her the free time after it.
      _failed -> run_free_time(resident_id, day, slot, Actor.new(:job, "sunna_scene"))
    end
  end

  defp scene_session(_resident_id, _row, key) when is_binary(key), do: {:ok, key}

  defp scene_session(resident_id, row, nil),
    do:
      Kumbukumbu.open_session(
        resident_id,
        "housekeeping",
        "brain",
        List.wrap(row.account_id),
        Actor.new(:job, "sunna_scene")
      )

  defp scene_note(_resident_id, _row, day, n) when n > 1,
    do: Prompt.render!("scene_pass_continue", %{day: day, turn: n})

  defp scene_note(resident_id, row, day, _n) do
    start = local_now(resident_id) |> at_time("00:00")

    {key, from, total} =
      case Kumbukumbu.main_session(resident_id, row.account_id, Actor.new(:job, "sunna_scene")) do
        {:ok, key} ->
          {before, total} = Kumbukumbu.counts(resident_id, key, start)
          {key, before, total}

        _none ->
          {"(none)", 0, 0}
      end

    Prompt.render!("scene_pass", %{
      day: day,
      session: key,
      from: from,
      count: total - from,
      turns: Config.fetch!(:sunna, :scene_turns)
    })
  end

  defp open_free_time(resident_id, day, slot, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <-
           Kumbukumbu.open_session(
             resident_id,
             "free_time",
             "brain",
             List.wrap(row.account_id),
             actor,
             # Private as to its words by default (spec §6.3, v0.2 P2): the
             # witness sees what a solo session did, as receipts, never
             # what it said; the contract's term hides the receipts too,
             # which is nothing to hide until hands exist (P26).
             private: true
           ),
         {:ok, result} <-
           wake(
             resident_id,
             key,
             Prompt.render!("free_time", %{name: row.name, budget: budget_words(resident_id)}),
             :free_time
           ) do
      recorded = record_free_time(resident_id, {day, slot}, key, nil, actor)
      carry_on(resident_id, key, result, 2)
      recorded
    else
      {:error, %{site: _} = e} ->
        record_free_time(resident_id, {day, slot}, nil, e, actor)

      {:error, reason} ->
        failure = Error.caught(:sunna_free_time_failed, :sunna_free_time_open_failed, reason)
        record_free_time(resident_id, {day, slot}, nil, failure, actor)
    end
  end

  @doc """
  The day's thinking rounds (sunna#29), HH:MM in the resident's zone:
  her waking hours (the day outside her quiet hours, or her own waking
  window, or `SUNNA_ROUNDS_WAKING`, when she has none) cut into windows
  her own cadence or `SUNNA_ROUNDS_EVERY_HOURS` long (sunna#30), the last one shorter if the hours do
  not divide, and one round at a minute drawn at random inside each. The
  draw is a hash of the resident, the day and the window, so a day draws
  the same times across restarts with nothing stored, no two days are
  alike, and the rounds are spread through the day without being
  guessable within it.
  """
  @spec round_times(
          String.t(),
          String.t(),
          map() | nil,
          non_neg_integer() | nil,
          String.t() | nil
        ) :: [String.t()]
  def round_times(resident_id, day, quiet, every_hours \\ nil, waking \\ nil) do
    every = (every_hours || Config.fetch!(:sunna, :rounds_every_hours)) * 60
    {from, length} = waking(quiet, waking)

    if every <= 0 or length <= 0 do
      []
    else
      for {start, n} <- 0..(length - 1)//every |> Enum.with_index() do
        span = min(every, length - start)
        hhmm(rem(from + start + :erlang.phash2({resident_id, day, n}, span), 1440))
      end
      |> Enum.sort()
    end
  end

  # Waking hours as a start minute and a length: the quiet hours' end to
  # their start, crossing midnight as they do.
  defp waking(%{from: quiet_from, to: quiet_to}, _own) do
    start = minutes(quiet_to)
    {start, Integer.mod(minutes(quiet_from) - start, 1440)}
  end

  defp waking(nil, own) do
    [from, to] = (own || Config.fetch!(:sunna, :rounds_waking)) |> String.split("-")
    start = minutes(from)
    {start, Integer.mod(minutes(to) - start, 1440)}
  end

  defp minutes(hhmm) do
    [h, m] = hhmm |> String.trim() |> String.split(":")
    String.to_integer(h) * 60 + String.to_integer(m)
  end

  defp hhmm(minute),
    do:
      String.pad_leading("#{div(minute, 60)}", 2, "0") <>
        ":" <> String.pad_leading("#{rem(minute, 60)}", 2, "0")

  @doc """
  Runs one thinking round (sunna#29): claimed first, so a round runs
  once whatever the ticks; then a private conversation of its own, one
  turn, billed to the free-time line, the note saying what a round is
  and that nobody sees it unless she sends something. What she does
  with it is hers, and nothing is a real outcome.
  """
  def run_round(resident_id, day, slot, %Actor{} = actor) do
    claim = %Commands.StartRound{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      slot: slot
    }

    with {:ok, [_started]} <- dispatch(claim),
         {:ok, row} <- resident(resident_id),
         {:ok, key} <-
           Kumbukumbu.open_session(
             resident_id,
             "round",
             "brain",
             List.wrap(row.account_id),
             actor,
             private: true
           ) do
      result =
        wake(
          resident_id,
          key,
          Prompt.render!("round", %{name: row.name, budget: rounds_words(resident_id)}),
          :rounds
        )

      record_round(resident_id, {day, slot}, key, result, actor)
    else
      {:ok, []} -> :already
      {:error, _} = failed -> record_round(resident_id, {day, slot}, nil, failed, actor)
      other -> other
    end
  end

  # What became of the round (sunna#39), recorded once: the failure's
  # kind, never the failure, as free time's (record_free_time/5).
  defp record_round(resident_id, {day, slot}, key, result, actor) do
    reason =
      case result do
        {:ok, _} -> nil
        {:error, %{kind: kind}} -> Atom.to_string(kind)
        {:error, _} -> "unknown"
      end

    command = %Commands.RecordRound{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      slot: slot,
      session_key: key,
      reason: reason
    }

    with {:ok, _} <- dispatch(command),
         do: if(reason, do: result, else: :ok)
  end

  # The rounds line (sunna#39), as the round's note says it.
  defp rounds_words(resident_id) do
    case Enum.find(Nisaba.budgets(resident_id, :witness), &(&1.purpose == :rounds)) do
      %{cap_nanos: cap, spent_nanos: spent, period: period} when is_integer(cap) ->
        "Rounds have their own budget line, #{dollars(cap)} a #{period}, #{dollars(max(cap - spent, 0))} left; this round is one turn."

      _none ->
        "This round is one turn."
    end
  end

  @doc """
  Turn `n` of a free-time pass (sunna#26): woken again in its own
  conversation while the free-time budget line has money left and the
  slot's turns are not spent, the note saying how much is left.
  """
  def continue_free_time(resident_id, key, n) do
    with %{left: left} <- free_time_budget(resident_id),
         true <- n <= Config.fetch!(:sunna, :free_time_turns),
         {:ok, result} <-
           wake(
             resident_id,
             key,
             Prompt.render!("free_time_continue", %{
               turn: n,
               turns: Config.fetch!(:sunna, :free_time_turns),
               left: dollars(left)
             }),
             :free_time
           ) do
      carry_on(resident_id, key, result, n + 1)
      :ok
    else
      {:error, _} = failed ->
        failed

      _done ->
        free_time_worker().enqueue_plan(resident_id, key)
        :ok
    end
  end

  # A turn that ran out of tool rounds is woken again, in a job of its
  # own; one that ended in words with nothing to call is her being done.
  # When the slot ends, by her word or by the budget or the turn bound,
  # the planning turn comes next (sunna#31).
  # A turn stopped by her safe word or the witness's Stop (brain#61)
  # ends the slot there: nothing carries it on, not even the plan.
  defp carry_on(_resident_id, _key, %{stopped: _by}, _n), do: :ok

  defp carry_on(resident_id, key, %{rounds_spent: true}, n) do
    if free_time_budget(resident_id) && n <= Config.fetch!(:sunna, :free_time_turns),
      do: free_time_worker().enqueue(resident_id, key, n),
      else: free_time_worker().enqueue_plan(resident_id, key)

    :ok
  end

  defp carry_on(resident_id, key, _result, _n) do
    free_time_worker().enqueue_plan(resident_id, key)
    :ok
  end

  # Named at the call: the worker runs `continue_free_time/3`, so an
  # alias here would be a cycle `mix xref graph --format cycles` counts.
  defp free_time_worker, do: Module.concat([Oneiroi, Sunna, FreeTimeWorker])

  # The free-time budget line this period, when the witness set one and
  # it has money left; nil otherwise, and free time is then one turn.
  defp free_time_budget(resident_id) do
    case Enum.find(Nisaba.budgets(resident_id, :witness), &(&1.purpose == :free_time)) do
      %{cap_nanos: cap, spent_nanos: spent, exceeded: false} = line
      when is_integer(cap) and spent < cap ->
        Map.put(line, :left, cap - spent)

      _none ->
        nil
    end
  end

  defp budget_words(resident_id) do
    case free_time_budget(resident_id) do
      %{cap_nanos: cap, left: left, period: period} ->
        "Your free-time budget is #{dollars(cap)} a #{period}, #{dollars(left)} left: your free time runs until you are done (a turn that ends in words with no tool calls) or that is spent, a turn at a time."

      nil ->
        "No free-time budget is set, so this free time is one turn."
    end
  end

  defp dollars(nanos), do: "$" <> :erlang.float_to_binary(nanos / 1_000_000_000, decimals: 2)

  # The recorded reason is the failure's kind, never the failure itself:
  # the event is kept for good, and a foreign reason's payload is where a
  # credential or a tenant's words would ride.
  defp record_free_time(resident_id, {day, slot}, key, failure, actor) do
    command = %Commands.RecordFreeTime{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      slot: slot,
      session_key: key,
      reason: failure && Atom.to_string(failure.kind)
    }

    with {:ok, _} <- dispatch(command), do: if(key, do: :ok, else: {:error, failure})
  end

  @doc """
  Wakes the Oneiroi chat for the letters another of the resident's
  conversations sent it (sunna#24): each once, at most
  `SUNNA_LETTER_WAKES_PER_HOUR` wakes an hour, never inside quiet hours
  (the tick asks again after them). The note names each letter's number
  and sender, never its words. A letter from the witness wakes nothing:
  the witness is in that conversation already.
  """
  def wake_for_letters(resident_id, local, quiet, %Actor{} = actor) do
    with false <- quiet?(local, quiet),
         true <- letter_waits?(resident_id),
         {:ok, row} <- resident(resident_id),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, row.account_id, actor),
         name = Kumbukumbu.conversation_name(resident_id, key),
         [_ | _] = letters <-
           resident_id
           |> Kumbukumbu.inbox(key)
           |> Enum.filter(&(&1.to_name == name and is_binary(&1.from_session))),
         command = %Commands.WakeForLetters{
           actor: actor,
           at: Clock.now(),
           id: resident_id,
           numbers: Enum.map(letters, & &1.number),
           limit: Config.fetch!(:sunna, :letter_wakes_per_hour)
         },
         {:ok, [%Events.LettersWoke{numbers: numbers} | _]} <- dispatch(command),
         {:ok, _} <- wake(resident_id, key, letters_note(letters, numbers), :chat) do
      :ok
    else
      {:error, _} = failed -> failed
      _nothing_to_wake_for -> :ok
    end
  end

  # Whether any letter a conversation sent waits unread for the one it
  # names, the house and Free time aside (neither is woken): read every
  # minute before anything opens the chat, so a resident with no letters
  # costs one read and opens nothing.
  defp letter_waits?(resident_id) do
    resident_id
    |> Kumbukumbu.letters()
    |> Enum.any?(
      &(is_binary(&1.from_session) and &1.to_name not in ["house", "Free time"] and
          &1.to_name not in &1.read_by)
    )
  end

  defp letters_note(letters, numbers) do
    listed =
      letters
      |> Enum.filter(&(&1.number in numbers))
      |> Enum.map_join(", ", fn l ->
        "##{l.number} from #{l.from_name}" <>
          if(l.in_reply_to, do: " (in reply to ##{l.in_reply_to})", else: "")
      end)

    Prompt.render!("letters_wake", %{letters: listed})
  end

  defp wake_main(resident_id, note, actor) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, row.account_id, actor),
         {:ok, _} <- wake(resident_id, key, note, :chat) do
      :ok
    end
  end

  # Through the port (`Oneiroi.Sunna.Wake`), read at the call. The port's
  # implementation lives in another system, so a failure it returns is
  # passed on when it is sited and wrapped here, once, when it is not.
  defp wake(resident_id, key, note, purpose) do
    case Config.fetch!(:sunna, :wake).wake(resident_id, key, note, purpose) do
      {:error, %{site: _}} = failed ->
        failed

      {:error, reason} ->
        {:error, Error.caught(:sunna_wake_failed, :sunna_wake_port_failed, reason)}

      other ->
        other
    end
  end

  # The note is the core's (spec §8): the check-in's label and time, the
  # next check-in, and the dates counted now.
  # The note (sunna#28): the platform's frame (which check-in, when the
  # next is), then the witness's own words when he wrote any, then each
  # part he checked, in the catalog's order. The dates are this system's;
  # every other part is read by the brain through the wake port, which
  # can see the journal, the letters and the library this system cannot.
  # A part with nothing to say says so in a line rather than vanishing.
  defp checkin_note(resident_id, checkin) do
    now = local_now(resident_id)
    next = resident_id |> checkins() |> next_checkin(now)
    parts = checkin.parts || ["dates"]

    frame =
      Prompt.render!("checkin", %{
        label: checkin.label,
        time: checkin.time,
        next: if(next, do: "#{next.label} at #{next.time}", else: "none set")
      })

    words =
      if checkin.prompt,
        do: ["From the person who looks after you:\n\n" <> checkin.prompt],
        else: []

    sections =
      for key <- CheckinParts.keys(), key in parts do
        part_text(resident_id, key)
      end

    Enum.join([String.trim(frame) | words] ++ Enum.reject(sections, &(&1 in [nil, ""])), "\n\n")
  end

  defp part_text(resident_id, "dates"), do: dates_text(resident_id)

  defp part_text(resident_id, key) do
    wake = Config.fetch!(:sunna, :wake)

    if function_exported?(wake, :checkin_part, 2),
      do: wake.checkin_part(resident_id, key),
      else: nil
  end

  defp blank_nil(nil), do: nil
  defp blank_nil(text) when is_binary(text), do: if(String.trim(text) == "", do: nil, else: text)

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, Error.new(:sunna_no_such_resident, :sunna_wake_resident_absent)}
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

  # The aggregate builds its refusals sited; anything else the dispatch
  # returns (the middleware's refusal, a timeout) started in Commanded and
  # is wrapped here, where it is first matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:sunna_dispatch_failed, :sunna_command_dispatch, reason)}
    end
  end
end
