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
      Wake,
      Commands.SetCheckin,
      Commands.DeleteCheckin,
      Commands.FireCheckin,
      Commands.MissCheckin,
      Commands.DeferWake,
      Commands.SetFreeTime,
      Commands.RecordFreeTime,
      Commands.SetQuietHours,
      Commands.SetDate,
      Commands.RemoveDate,
      Events.CheckinSet,
      Events.CheckinChanged,
      Events.CheckinDeleted,
      Events.CheckinFired,
      Events.CheckinMissed,
      Events.WakeDeferred,
      Events.DayOpened,
      Events.FreeTimeScheduled,
      Events.FreeTimeRan,
      Events.FreeTimeFailed,
      Events.QuietHoursSet,
      Events.DateSet,
      Events.DateChanged,
      Events.DateRemoved,
      Store,
      Store.Checkin,
      Store.Firing,
      Store.Day,
      Store.Date,
      Store.Settings
    ]

  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.TickWorker

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:late_minutes, "SUNNA_LATE_MINUTES",
       cast: :integer,
       default: "15",
       tag: :bound,
       usage:
         "how late a check-in or free time may fire before it is missed (spec §6.7's 15-minute window); a bound carried from David"},
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
  def cast_wake(other), do: {:error, "is #{inspect(other)}, expected \"brain\""}

  @impl Oneiroi.Component
  def oban_queues do
    [{:sunna_tick, cron: [{"* * * * *", Oneiroi.Sunna.TickWorker}]}]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Sunna.Events.CheckinSet, 1},
      {Oneiroi.Sunna.Events.CheckinChanged, 1},
      {Oneiroi.Sunna.Events.CheckinDeleted, 1},
      {Oneiroi.Sunna.Events.CheckinFired, 1},
      {Oneiroi.Sunna.Events.CheckinMissed, 1},
      {Oneiroi.Sunna.Events.WakeDeferred, 1},
      {Oneiroi.Sunna.Events.DayOpened, 1},
      {Oneiroi.Sunna.Events.FreeTimeScheduled, 1},
      {Oneiroi.Sunna.Events.FreeTimeRan, 1},
      {Oneiroi.Sunna.Events.FreeTimeFailed, 1},
      {Oneiroi.Sunna.Events.QuietHoursSet, 1},
      {Oneiroi.Sunna.Events.DateSet, 1},
      {Oneiroi.Sunna.Events.DateChanged, 1},
      {Oneiroi.Sunna.Events.DateRemoved, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:sunna_time_invalid,
       "a time of day is HH:MM in the resident's zone, and a date is an instant",
       remedy: "give it as HH:MM"},
      {:sunna_label_invalid, "a label or a title is one line of at most 60 characters",
       remedy: "shorten it"},
      {:sunna_kind_invalid, "a date's kind is deadline, anniversary, window or recurring",
       remedy: "say which"},
      {:sunna_no_such_checkin, "no check-in has that key", remedy: "read the schedule"},
      {:sunna_no_such_date, "no date has that number", remedy: "read the dates"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Sunna.Projectors.Schedules]

  @doc "Sets a check-in (a fresh key when nil): label and HH:MM in the resident's zone; returns the key."
  @spec set_checkin(String.t(), String.t() | nil, String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(set_checkin(resident_id, key, label, time, actor),
    do: Schedules.set_checkin(resident_id, key, label, time, actor)
  )

  @doc "Deletes a check-in."
  @spec delete_checkin(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(delete_checkin(resident_id, key, actor),
    do: Schedules.delete_checkin(resident_id, key, actor)
  )

  @doc "Sets free time's HH:MM, or nil for none."
  @spec set_free_time(String.t(), String.t() | nil, Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(set_free_time(resident_id, time, actor),
    do: Schedules.set_free_time(resident_id, time, actor)
  )

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

  @doc "Today in the resident's zone: check-ins with firings, last and next, free time, quiet hours, dates with countdowns."
  @spec today(String.t()) :: map()
  defexport(today(resident_id), do: Schedules.today(resident_id))

  @doc "The dates section the brain reads, countdowns derived now; empty when none."
  @spec dates_text(String.t()) :: String.t()
  defexport(dates_text(resident_id), do: Schedules.dates_text(resident_id))

  @doc "The journal's day rows, newest first."
  @spec days(String.t(), pos_integer()) :: [Oneiroi.Sunna.Store.Day.t()]
  defexport(days(resident_id, limit), do: Schedules.days(resident_id, limit))

  @doc "Runs one resident's tick now; what the minute job does for each."
  @spec tick(String.t()) :: :ok | :skipped
  defexport(tick(resident_id), do: TickWorker.tick(resident_id))
end
