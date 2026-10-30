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

  defmodule Settings do
    @moduledoc "The resident's one schedule row: free time, quiet hours, the last free-time run."
    use Ecto.Schema
    @primary_key false
    schema "sunna_schedule" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:free_time, :string)
      field(:quiet_from, :string)
      field(:quiet_to, :string)
      field(:free_time_day, :string)
      field(:free_time_outcome, :string)
      field(:free_time_session_key, :string)
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
