defmodule Oneiroi.Sunna.Store do
  @moduledoc "The schedule projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Checkin do
    @moduledoc "A check-in: its label, its time of day in the resident's zone, and its last outcome."
    use Ecto.Schema
    @primary_key false
    schema "sunna_checkin" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:label, :string)
      field(:time, :string)
      field(:parts, {:array, :string}, default: ["dates"])
      field(:prompt, :string)
      field(:changed_day, :string)
      field(:last_day, :string)
      field(:last_outcome, :string)
      field(:last_at, :utc_datetime_usec)
      field(:set_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Firing do
    @moduledoc "One day's outcome for a check-in: fired, missed, or deferred until an instant."
    use Ecto.Schema
    @primary_key false
    schema "sunna_firing" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:outcome, :string)
      field(:at, :utc_datetime_usec)
      field(:until, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Day do
    @moduledoc "The journal's day row (spec §6.5), opened at the day's first check-in."
    use Ecto.Schema
    @primary_key false
    schema "sunna_day" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:opened_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Hour do
    @moduledoc "One marked local hour (spec §6.7, P20 as amended): the pulse."
    use Ecto.Schema
    @primary_key false
    schema "sunna_hour" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:hour, :string, primary_key: true)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Date do
    @moduledoc "An important date as a row (spec §6.7, F56); the countdown is derived when read, never stored."
    use Ecto.Schema
    @primary_key false
    schema "sunna_date" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:title, :string)
      field(:on, :utc_datetime_usec)
      field(:kind, :string)
      field(:set_by_kind, :string)
      field(:set_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule FreeTimeRun do
    @moduledoc "One free-time slot's run on a day (sunna#22): ran, or failed with its reason; `slot` is nil for a day recorded before slots."
    use Ecto.Schema
    @primary_key false
    schema "sunna_free_time_run" do
      field(:resident_id, :binary_id)
      field(:day, :string)
      field(:slot, :string)
      field(:outcome, :string)
      field(:session_key, :string)
      field(:at, :utc_datetime_usec)
      field(:planning_nanos, :integer)
    end

    @type t :: %__MODULE__{}
  end

  defmodule FreeTimeOnce do
    @moduledoc "A one-off free-time slot (sunna#45): a day and a time in her zone, and who added it."
    use Ecto.Schema
    @primary_key false
    schema "sunna_free_time_once" do
      field(:resident_id, :binary_id)
      field(:day, :string)
      field(:time, :string)
      field(:added_by, :string)
      field(:added_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Round do
    @moduledoc "One thinking round (sunna#39): claimed at its drawn slot, then ran in a conversation or failed with its kind."
    use Ecto.Schema
    @primary_key false
    schema "sunna_round" do
      field(:resident_id, :binary_id)
      field(:day, :string)
      field(:slot, :string)
      field(:outcome, :string)
      field(:session_key, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule WorkItem do
    @moduledoc "An item of the work queue (sunna#33): what, done when, its place and status, and its last wrap."
    use Ecto.Schema
    @primary_key false
    schema "sunna_work_item" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:what, :string)
      field(:done_when, :string)
      field(:status, :string)
      field(:blocked_on, :string)
      # Held for the witness (sunna#54): the ask, who held it, when.
      field(:held_ask, :string)
      field(:held_by, :string)
      field(:held_at, :utc_datetime_usec)
      field(:position, :integer)
      field(:added_by, :string)
      field(:added_at, :utc_datetime_usec)
      field(:note, :string)
      field(:moved_by, :string)
      field(:moved_at, :utc_datetime_usec)
      field(:shipped, :string)
      field(:slipped, :string)
      field(:why, :string)
      field(:wrapped_at, :utc_datetime_usec)
      field(:runs, :integer, default: 0)
      field(:session_key, :string)
      # How long it has been in work (sunna#58): its first run's start, and
      # the seconds its ended runs took.
      field(:first_started_at, :utc_datetime_usec)
      field(:worked_seconds, :integer, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule WorkQueue do
    @moduledoc "The work loop's state (sunna#33): the item running and since when, the rest and its reason, and the day's runs."
    use Ecto.Schema
    @primary_key false
    schema "sunna_work_queue" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:running, :integer)
      field(:running_key, :string)
      field(:running_since, :utc_datetime_usec)
      field(:rested_reason, :string)
      field(:rested_at, :utc_datetime_usec)
      field(:run_day, :string)
      field(:runs_on_day, :integer, default: 0)
      field(:armed, :boolean, default: false)
      field(:armed_at, :utc_datetime_usec)
      field(:armed_by, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Settings do
    @moduledoc "The resident's one schedule row: free time, quiet hours, the last free-time run."
    use Ecto.Schema
    @primary_key false
    schema "sunna_schedule" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:free_time, :string)
      field(:free_times, {:array, :string})
      field(:quiet_from, :string)
      field(:quiet_to, :string)
      field(:free_time_day, :string)
      field(:free_time_outcome, :string)
      field(:free_time_session_key, :string)
      field(:rounds_every_hours, :integer)
      field(:rounds_waking, :string)
      field(:last_round_at, :utc_datetime_usec)
      field(:free_time_plan, :string)
      field(:free_time_planned_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec checkins() :: [Checkin.t()]
  def checkins, do: Repo.all(from(c in Checkin, order_by: c.time))

  @spec firings(String.t()) :: [Firing.t()]
  def firings(day), do: Repo.all(from(f in Firing, where: f.day == ^day, order_by: f.at))

  @doc "Every firing on a day in [from, to], by day then time."
  @spec firings_between(String.t(), String.t()) :: [Firing.t()]
  def firings_between(from, to),
    do:
      Repo.all(from(f in Firing, where: f.day >= ^from and f.day <= ^to, order_by: [f.day, f.at]))

  @spec hour(String.t()) :: Hour.t() | nil
  def hour(key), do: Repo.one(from(h in Hour, where: h.hour == ^key))

  @spec hours(pos_integer()) :: [Hour.t()]
  def hours(limit), do: Repo.all(from(h in Hour, order_by: [desc: h.hour], limit: ^limit))

  @spec last_hour() :: Hour.t() | nil
  def last_hour, do: Repo.one(from(h in Hour, order_by: [desc: h.hour], limit: 1))

  @spec days(pos_integer()) :: [Day.t()]
  def days(limit), do: Repo.all(from(d in Day, order_by: [desc: d.day], limit: ^limit))

  @spec day(String.t()) :: Day.t() | nil
  def day(day), do: Repo.one(from(d in Day, where: d.day == ^day))

  @spec dates() :: [Date.t()]
  def dates, do: Repo.all(from(d in Date, order_by: d.on))

  @doc "The free-time runs recorded on a day, any slot."
  @spec free_time_runs(String.t()) :: [FreeTimeRun.t()]
  def free_time_runs(day),
    do: Repo.all(from(r in FreeTimeRun, where: r.day == ^day, order_by: r.at))

  @doc "The latest free-time runs, any day, newest first (sunna#25)."
  @spec free_time_history(pos_integer()) :: [FreeTimeRun.t()]
  def free_time_history(limit),
    do: Repo.all(from(r in FreeTimeRun, order_by: [desc: r.at], limit: ^limit))

  @doc "The one-off free-time slots from `day` on, in order (sunna#45)."
  @spec free_time_once_from(String.t()) :: [FreeTimeOnce.t()]
  def free_time_once_from(day),
    do: Repo.all(from(o in FreeTimeOnce, where: o.day >= ^day, order_by: [o.day, o.time]))

  @doc "The latest rounds, any day, newest first (sunna#39)."
  @spec rounds(pos_integer()) :: [Round.t()]
  def rounds(limit), do: Repo.all(from(r in Round, order_by: [desc: r.at], limit: ^limit))

  @doc "The rounds claimed since `since`, oldest first (sunna#39)."
  @spec rounds_since(DateTime.t()) :: [Round.t()]
  def rounds_since(since),
    do: Repo.all(from(r in Round, where: r.at >= ^since, order_by: r.at))

  @doc "Whether a session is one a free-time run opened or resumed (sunna#44)."
  @spec free_time_session?(String.t()) :: boolean()
  def free_time_session?(key),
    do: Repo.exists?(from(r in FreeTimeRun, where: r.session_key == ^key))

  @doc "The work queue's items in priority order (sunna#33)."
  @spec work_items() :: [WorkItem.t()]
  def work_items, do: Repo.all(from(w in WorkItem, order_by: [w.position, w.number]))

  @doc "The work loop's state, or nil before anything was queued."
  @spec work_queue() :: WorkQueue.t() | nil
  def work_queue, do: Repo.one(from(q in WorkQueue, limit: 1))

  @doc "Whether a free-time pass is underway: a slot ran since `since` and its planning turn has not closed it (sunna#33's care rule)."
  @spec free_time_underway?(DateTime.t()) :: boolean()
  def free_time_underway?(since),
    do:
      Repo.exists?(
        from(r in FreeTimeRun,
          where: r.outcome == "ran" and r.at >= ^since and is_nil(r.planning_nanos)
        )
      )

  @doc "Every resident with work open or running, for the tick: a cross-tenant read under the platform scope."
  @spec working_residents() :: [String.t()]
  def working_residents,
    do:
      Repo.all(
        from(w in WorkItem,
          where: w.status in ["open", "in_work"],
          distinct: true,
          select: w.resident_id
        )
      )

  @spec settings() :: Settings.t() | nil
  def settings, do: Repo.one(from(s in Settings, limit: 1))

  @doc "Every resident with something scheduled, for the tick: a cross-tenant read under the platform scope, named in the system doc."
  @spec scheduled_residents() :: [String.t()]
  def scheduled_residents do
    checkins = from(c in Checkin, select: c.resident_id)
    free = from(s in Settings, where: not is_nil(s.free_time), select: s.resident_id)
    Repo.all(checkins) |> Kernel.++(Repo.all(free)) |> Enum.uniq()
  end
end
