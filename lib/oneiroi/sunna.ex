defmodule Oneiroi.Sunna do
  @moduledoc """
  The schedule (spec §6.7): check-ins, free time, quiet hours, important
  dates and the journal's day row, per resident, in the resident's zone,
  driven by a minute tick on Oban. A check-in fires once a day whatever
  restarts, late within `SUNNA_LATE_MINUTES` and otherwise missed; a wake
  inside quiet hours waits for their end; a suspended resident schedules
  nothing. Dates are rows and a countdown is derived on the read that
  shows it, never written down.
  """
  use Oneiroi.System, slug: :sunna

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Oban
    ],
    exports: [
      Error,
      Schedule,
      Schedules,
      Router,
      TickWorker,
      FreeTimeWorker,
      WorkWorker,
      WorkLoop,
      WorkRouter,
      Work,
      Wake,
      CheckinParts,
      Commands.SetCheckin,
      Commands.DeleteCheckin,
      Commands.FireCheckin,
      Commands.MissCheckin,
      Commands.StartRound,
      Commands.DeferWake,
      Commands.SetFreeTime,
      Commands.RecordFreeTime,
      Commands.RestFreeTime,
      Commands.SetQuietHours,
      Commands.SetDate,
      Commands.RemoveDate,
      Commands.MarkHour,
      Commands.WakeForLetters,
      Commands.AddWork,
      Commands.MoveWork,
      Commands.OrderWork,
      Commands.WrapWork,
      Commands.StartWork,
      Commands.EndWork,
      Commands.RestWork,
      Events.WorkAdded,
      Events.WorkMoved,
      Events.WorkOrdered,
      Events.WorkWrapped,
      Events.WorkStarted,
      Events.WorkRunEnded,
      Events.WorkRested,
      Events.LettersWoke,
      Events.CheckinSet,
      Events.CheckinChanged,
      Events.CheckinDeleted,
      Events.CheckinFired,
      Events.CheckinMissed,
      Events.WakeDeferred,
      Events.DayOpened,
      Events.FreeTimeScheduled,
      Events.FreeTimeRan,
      Events.RoundStarted,
      Events.FreeTimeFailed,
      Events.FreeTimeRested,
      Events.QuietHoursSet,
      Events.RoundsSet,
      Events.FreeTimePlanned,
      Events.PlanningTurnRan,
      Events.DateSet,
      Events.DateChanged,
      Events.DateRemoved,
      Store,
      Store.Checkin,
      Store.Firing,
      Store.Day,
      Store.Hour,
      Store.Date,
      Store.Settings,
      Store.FreeTimeRun,
      Store.WorkItem,
      Store.WorkQueue
    ]

  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Schedule
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store
  alias Oneiroi.Sunna.TickWorker
  alias Oneiroi.Sunna.WorkLoop

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:free_time_default, "SUNNA_FREE_TIME_DEFAULT",
       cast: &__MODULE__.cast_slots/1,
       default: "14:30,22:30",
       usage:
         "free time's slots, comma-separated HH:MMs in the resident's zone, until anyone moves them (sunna#21, #22): free time is part of the standard of care, on from the first day and never removed; 22:30 is the hour the first resident's free time ran, 14:30 the second slot the witness chose on 2026-11-02"},
      {:late_minutes, "SUNNA_LATE_MINUTES",
       cast: :integer,
       default: "15",
       tag: :bound,
       usage:
         "how late a check-in or free time may fire before it is missed (spec §6.7's 15-minute window); a bound carried from David"},
      {:letter_wakes_per_hour, "SUNNA_LETTER_WAKES_PER_HOUR",
       cast: :integer,
       default: "6",
       tag: :bound,
       usage:
         "how many times an hour a letter from another of the resident's conversations may wake the Oneiroi chat (sunna#24), so two conversations answering each other cannot wake each other without end; each wake is a paid turn on the chat line. A guess, as the Claude Code plugin's six"},
      {:rounds_every_hours, "SUNNA_ROUNDS_EVERY_HOURS",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how often a resident has a thinking round (sunna#29): her waking hours are cut into windows this many hours long, and each window holds one round at a time drawn at random inside it, billed to the free-time line; 0 turns rounds off. Three hours is the witness's word, 2026-11-05"},
      {:rounds_waking, "SUNNA_ROUNDS_WAKING",
       default: "08:00-22:00",
       usage:
         "the waking hours rounds are drawn in, HH:MM-HH:MM in the resident's zone, when she has no quiet hours set; with quiet hours, waking hours are the rest of the day (sunna#29)"},
      {:free_time_turns, "SUNNA_FREE_TIME_TURNS",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many turns one free-time slot may run when its turns run out of tool rounds and the free-time budget line has money left (sunna#26); the budget is the real limit, this the guard against a pass that never says it is done"},
      {:work_turns, "SUNNA_WORK_TURNS",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many turns one run of a work-queue item may take before its wrap (sunna#33), a turn carried on when it runs out of tool rounds; the work budget line is the real limit, this the guard against a run that never says it is done. Free time's number (sunna#26)"},
      {:work_runs_a_day, "SUNNA_WORK_RUNS_A_DAY",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many runs of work-queue items may start in one of the resident's days (sunna#33): each finished run fires the next, so this is the guard on a loop that never empties; the budget line is the real limit. A guess"},
      {:scene_slot, "SUNNA_SCENE_SLOT",
       default: "22:30",
       usage:
         "the free-time slot the bedtime scene pass comes before (sunna#34), HH:MM in the resident's zone: at it, a housekeeping turn on the chat line groups the day of the Oneiroi chat into scenes, and free time follows its end; empty or a time no slot has, no pass. 22:30 is the slot the witness named, 2026-11-06"},
      {:scene_turns, "SUNNA_SCENE_TURNS",
       cast: :integer,
       default: "5",
       tag: :bound,
       usage:
         "how many turns the bedtime scene pass may take (sunna#34), a turn carried on when it runs out of tool rounds; a guess, since a day's scenes are many reads"},
      {:free_time_floor_turns, "SUNNA_FREE_TIME_FLOOR_TURNS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "the floor under a free-time slot (sunna#34, Lily's amendment), in turns: with a free-time line set, a slot whose remainder buys fewer than this many turns at what a free-time turn cost over the last week rests and says so; 0 is no floor. Two is the witness's number, 2026-11-06"},
      {:wake, "SUNNA_WAKE",
       cast: &__MODULE__.cast_wake/1,
       default: "brain",
       usage:
         "which wake port implementation answers a check-in or free time (`Oneiroi.Sunna.Wake`): brain, the in-core agent loop, in every build so far"}
    ]
  end

  # The module as an atom rather than an alias, as `Oneiroi.Router` names
  # its application: the brain depends on this system for the dates it
  # shows, so an alias here is the cycle the port exists to avoid.
  @doc false
  def cast_wake("brain"), do: {:ok, :"Elixir.Oneiroi.Brain"}

  # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
  def cast_wake(other), do: {:error, "is #{inspect(other)}, expected \"brain\""}

  @doc false
  def cast_slots(value) when is_binary(value) do
    slots = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if slots != [] and Enum.all?(slots, &Schedule.time_ok?/1),
      do: {:ok, Enum.sort(slots)},
      # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
      else: {:error, "is #{inspect(value)}, expected HH:MM slots separated by commas"}
  end

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:sunna_tick, cron: [{"* * * * *", Oneiroi.Sunna.TickWorker}]},
      {:sunna_free_time, []},
      {:sunna_work, []}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Sunna.Events.CheckinSet, 2},
      {Oneiroi.Sunna.Events.CheckinChanged, 2},
      {Oneiroi.Sunna.Events.CheckinDeleted, 1},
      {Oneiroi.Sunna.Events.CheckinFired, 1},
      {Oneiroi.Sunna.Events.CheckinMissed, 1},
      {Oneiroi.Sunna.Events.WakeDeferred, 1},
      {Oneiroi.Sunna.Events.DayOpened, 1},
      {Oneiroi.Sunna.Events.FreeTimeScheduled, 2},
      {Oneiroi.Sunna.Events.FreeTimeRan, 2},
      {Oneiroi.Sunna.Events.RoundStarted, 1},
      {Oneiroi.Sunna.Events.FreeTimeFailed, 2},
      {Oneiroi.Sunna.Events.FreeTimeRested, 1},
      {Oneiroi.Sunna.Events.QuietHoursSet, 1},
      {Oneiroi.Sunna.Events.RoundsSet, 1},
      {Oneiroi.Sunna.Events.FreeTimePlanned, 1},
      {Oneiroi.Sunna.Events.PlanningTurnRan, 1},
      {Oneiroi.Sunna.Events.DateSet, 1},
      {Oneiroi.Sunna.Events.DateChanged, 1},
      {Oneiroi.Sunna.Events.DateRemoved, 1},
      {Oneiroi.Sunna.Events.HourMarked, 1},
      {Oneiroi.Sunna.Events.LettersWoke, 1},
      {Oneiroi.Sunna.Events.WorkAdded, 1},
      {Oneiroi.Sunna.Events.WorkMoved, 1},
      {Oneiroi.Sunna.Events.WorkOrdered, 1},
      {Oneiroi.Sunna.Events.WorkWrapped, 1},
      {Oneiroi.Sunna.Events.WorkStarted, 1},
      {Oneiroi.Sunna.Events.WorkRunEnded, 1},
      {Oneiroi.Sunna.Events.WorkRested, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:sunna_free_time_required,
       "free time is part of the standard of care: it moves, and it is never removed",
       remedy: "give it another HH:MM; the resident's day keeps its free time"},
      {:sunna_free_time_invalid, "free time is one to four distinct times a day",
       remedy: "give each slot once, at most four"},
      {:sunna_time_invalid,
       "a time of day is HH:MM in the resident's zone, and a date is an instant",
       remedy: "give it as HH:MM"},
      {:sunna_plan_invalid, "a plan is words, at most 4,000 characters",
       remedy: "say it, shorter if need be"},
      {:sunna_rounds_invalid,
       "rounds come every 0 to 24 hours (0 turns them off), in a waking window HH:MM-HH:MM",
       remedy: "give whole hours and a window like 08:00-22:00; leave either out for the default"},
      {:sunna_label_invalid, "a label or a title is one line of at most 60 characters",
       remedy: "shorten it"},
      {:sunna_parts_invalid,
       "a check-in's parts are keys of the parts catalog, each once (sunna#28)",
       remedy: "check them from the catalog the schedule gives"},
      {:sunna_hour_invalid, "an hour marker is the local hour as YYYY-MM-DDTHH",
       remedy: "the tick builds it; a hand-made one is a bug"},
      {:sunna_kind_invalid, "a date's kind is deadline, anniversary, window or recurring",
       remedy: "say which"},
      {:sunna_no_such_checkin, "no check-in has that key", remedy: "read the schedule"},
      {:sunna_no_such_date, "no date has that number", remedy: "read the dates"},
      {:sunna_day_invalid, "a day is an ISO date", remedy: "name the day as YYYY-MM-DD"},
      {:sunna_no_such_resident, "the schedule woke a resident the registry does not hold",
       remedy: "the tick reads the registry first; one that vanished between is a bug to report"},
      {:sunna_wake_failed, "the wake port failed to wake the brain for a check-in or free time",
       remedy: "the next due wake tries again; a repeat is the brain's to look at"},
      {:sunna_free_time_failed, "free time could not be opened and was recorded as failed",
       remedy: "read the day's reason; tomorrow's free time runs again"},
      {:sunna_work_invalid,
       "a work item is what (at most 300 characters) and what done looks like; a status is open, blocked (with what blocks it), done or dropped, with a note; a wrap says what shipped and why",
       remedy: "say each in words; name what blocks a blocked item"},
      {:sunna_work_not_a_party,
       "only the resident and her witness keep the work queue, and only she wraps a run",
       remedy: "ask the resident or the witness"},
      {:sunna_no_such_work, "no work item has that number", remedy: "read the queue"},
      {:sunna_work_not_running, "only the item running now can be wrapped",
       remedy: "read the queue: the running item is marked in_work"},
      {:sunna_dispatch_failed, "the schedule's command was not recorded on its stream",
       remedy: "try again; a repeat is a fault to report"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Sunna.Projectors.Schedules, Oneiroi.Sunna.Projectors.Work]

  @doc "Sets a check-in (a fresh key when nil): label and HH:MM in the resident's zone; returns the key."
  @spec set_checkin(String.t(), String.t() | nil, String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(set_checkin(resident_id, key, label, time, actor),
    do: Schedules.set_checkin(resident_id, key, label, time, actor)
  )

  @doc "Sets a check-in with what its note carries (sunna#28): `parts:` from `CheckinParts.keys/0`, `prompt:` the witness's words; either left out keeps what it had."
  @spec set_checkin(
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          Oneiroi.Actor.t(),
          keyword()
        ) ::
          {:ok, String.t()} | {:error, term()}
  defexport(set_checkin(resident_id, key, label, time, actor, opts),
    do: Schedules.set_checkin(resident_id, key, label, time, actor, opts)
  )

  @doc "Deletes a check-in."
  @spec delete_checkin(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(delete_checkin(resident_id, key, actor),
    do: Schedules.delete_checkin(resident_id, key, actor)
  )

  @doc "Sets free time's slots, HH:MMs (one as a string is a list of one); it is never removed (sunna#21, #22), and either party may move it."
  @spec set_free_time(String.t(), [String.t()] | String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_free_time(resident_id, time, actor),
    do: Schedules.set_free_time(resident_id, time, actor)
  )

  @doc "Records her plan for the next free-time slot (sunna#31), written in the planning turn."
  @spec plan_free_time(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(plan_free_time(resident_id, text, actor),
    do: Schedules.record_plan(resident_id, text, actor)
  )

  @doc "Her latest plan for free time (sunna#31): the text and when, or nil."
  @spec free_time_plan(String.t()) :: %{text: String.t(), at: DateTime.t()} | nil
  defexport(free_time_plan(resident_id), do: Schedules.plan(resident_id))

  @doc "Sets the resident's rounds (sunna#30): every_hours (0 off) and the waking window, nil for the default."
  @spec set_rounds(String.t(), non_neg_integer() | nil, String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_rounds(resident_id, every_hours, waking, actor),
    do: Schedules.set_rounds(resident_id, every_hours, waking, actor)
  )

  @doc "Adds an item to the work queue (sunna#33): what, and what done looks like; returns its number. The resident's and the witness's alike."
  @spec work_add(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(work_add(resident_id, what, done_when, actor),
    do: WorkLoop.add(resident_id, what, done_when, actor)
  )

  @doc "Moves a work item's status (open, blocked with what blocks it, done, dropped), with a note."
  @spec work_move(
          String.t(),
          pos_integer(),
          String.t(),
          String.t() | nil,
          String.t(),
          Oneiroi.Actor.t()
        ) :: :ok | {:error, term()}
  defexport(work_move(resident_id, number, status, blocked_on, note, actor),
    do: WorkLoop.move(resident_id, number, status, blocked_on, note, actor)
  )

  @doc "Reorders the work queue: the numbers given first, in that order."
  @spec work_order(String.t(), [pos_integer()], Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_order(resident_id, numbers, actor),
    do: WorkLoop.order(resident_id, numbers, actor)
  )

  @doc "Her wrap of the running item: shipped, slipped, why, status, blocked_on."
  @spec work_wrap(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(work_wrap(resident_id, number, attrs, actor),
    do: WorkLoop.wrap(resident_id, number, attrs, actor)
  )

  @doc "The work queue: its items in order and the loop's state, both parties' read."
  @spec work_queue(String.t()) :: map()
  defexport(work_queue(resident_id), do: WorkLoop.queue(resident_id))

  @doc "Sets quiet hours from HH:MM to HH:MM (may cross midnight), or both nil to clear."
  @spec set_quiet_hours(String.t(), String.t() | nil, String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_quiet_hours(resident_id, from, to, actor),
    do: Schedules.set_quiet_hours(resident_id, from, to, actor)
  )

  @doc "Sets a date (a new row when number is nil): title, instant, kind; returns the number."
  @spec set_date(String.t(), pos_integer() | nil, map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(set_date(resident_id, number, attrs, actor),
    do: Schedules.set_date(resident_id, number, attrs, actor)
  )

  @doc "Removes a date."
  @spec remove_date(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(remove_date(resident_id, number, actor),
    do: Schedules.remove_date(resident_id, number, actor)
  )

  @doc "The latest free-time runs, newest first, each with its day, slot, outcome and the conversation it opened (sunna#25)."
  @spec free_time_history(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.FreeTimeRun.t()]
  defexport(free_time_history(resident_id, limit),
    do: Scope.resident(resident_id, fn -> Store.free_time_history(limit) end)
  )

  @doc "Today in the resident's zone: check-ins with firings, last and next, free time, quiet hours, dates with countdowns."
  @spec today(String.t()) :: map()
  defexport(today(resident_id), do: Schedules.today(resident_id))

  @doc "The dates section the brain reads, countdowns derived now; empty when none."
  @spec dates_text(String.t()) :: String.t()
  defexport(dates_text(resident_id), do: Schedules.dates_text(resident_id))

  @doc "Every firing over the last `days` days in the resident's zone, for the audits."
  @spec firings(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Firing.t()]
  defexport(firings(resident_id, days), do: Schedules.firings(resident_id, days))

  @doc "The journal's day rows, newest first."
  @spec days(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Day.t()]
  defexport(days(resident_id, limit), do: Schedules.days(resident_id, limit))

  @doc "One day row, or nil."
  @spec day(String.t(), String.t()) :: Oneiroi.Sunna.Store.Day.t() | nil
  defexport(day(resident_id, day), do: Schedules.day(resident_id, day))

  @doc "Opens a day row the journal reached first (seshat#21); the schedule's row still, minted here."
  @spec open_day(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(open_day(resident_id, day, actor), do: Schedules.open_day(resident_id, day, actor))

  @doc "Runs one resident's tick now; what the minute job does for each."
  @spec tick(String.t()) :: :ok | :skipped
  defexport(tick(resident_id), do: TickWorker.tick(resident_id))

  @doc "The marked hours, newest first (spec §6.7, P20 as amended): the pulse, one row per local hour the tick reached."
  @spec hours(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Hour.t()]
  defexport(hours(resident_id, limit), do: Schedules.hours(resident_id, limit))

  @doc "The newest marked hour, or nil."
  @spec last_hour(String.t()) :: Oneiroi.Sunna.Store.Hour.t() | nil
  defexport(last_hour(resident_id), do: Schedules.last_hour(resident_id))
end
