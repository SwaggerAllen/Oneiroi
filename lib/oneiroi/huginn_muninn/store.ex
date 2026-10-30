defmodule Oneiroi.HuginnMuninn.Store do
  @moduledoc "The audits projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Counter do
    @moduledoc "A figure of kind counter: its value is the fold of its increments."
    use Ecto.Schema
    @primary_key false
    schema "huginn_muninn_counter" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:label, :string)
      field(:value, :integer, default: 0)
      field(:increments, :integer, default: 0)
      field(:defined_at, :utc_datetime_usec)
      field(:last_at, :utc_datetime_usec)
      field(:last_by_kind, :string)
      field(:retired_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Increment do
    @moduledoc "One increment, with its actor: the concession-count pattern."
    use Ecto.Schema
    @primary_key false
    schema "huginn_muninn_increment" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:sequence, :integer, primary_key: true)
      field(:at, :utc_datetime_usec)
      field(:by, :integer)
      field(:note, :string)
      field(:actor_kind, :string)
      field(:actor_id, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Audit do
    @moduledoc "A witness's audit: a rule over a figure, and its last result."
    use Ecto.Schema
    @primary_key false
    schema "huginn_muninn_audit" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:label, :string)
      field(:figure, :string)
      field(:op, :string)
      field(:value, :integer)
      field(:tone, :string)
      field(:counts, :boolean, default: true)
      field(:defined_at, :utc_datetime_usec)
      field(:retired_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Run do
    @moduledoc "One run of one audit: the tone, the value, the finding."
    use Ecto.Schema
    @primary_key false
    schema "huginn_muninn_run" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:sequence, :integer, primary_key: true)
      field(:at, :utc_datetime_usec)
      field(:builtin, :boolean, default: false)
      field(:tone, :string)
      field(:value, :integer)
      field(:finding, :string)
    end

    @type t :: %__MODULE__{}
  end

  @spec counters() :: [Counter.t()]
  def counters, do: Repo.all(from(c in Counter, where: is_nil(c.retired_at), order_by: c.key))

  @spec counter(String.t()) :: Counter.t() | nil
  def counter(key),
    do: Repo.one(from(c in Counter, where: c.key == ^key and is_nil(c.retired_at)))

  @spec increments(String.t(), pos_integer()) :: [Increment.t()]
  def increments(key, limit),
    do:
      Repo.all(
        from(i in Increment, where: i.key == ^key, order_by: [desc: i.sequence], limit: ^limit)
      )

  @spec audits() :: [Audit.t()]
  def audits, do: Repo.all(from(a in Audit, where: is_nil(a.retired_at), order_by: a.key))

  @doc "The latest run of every audit key."
  @spec latest_runs() :: [Run.t()]
  def latest_runs do
    from(r in Run, distinct: r.key, order_by: [asc: r.key, desc: r.sequence]) |> Repo.all()
  end

  @spec runs(String.t(), pos_integer()) :: [Run.t()]
  def runs(key, limit),
    do:
      Repo.all(from(r in Run, where: r.key == ^key, order_by: [desc: r.sequence], limit: ^limit))
end
