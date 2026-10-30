defmodule Oneiroi.Nisaba.Store do
  @moduledoc """
  The ledger's projections and the queries over them (conventions §6):
  a budget line per purpose and a row per model call, both under the
  resident's scope. The witness reads them through the resident's scope
  after the witnessing check, as every resident surface is read.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Budget do
    @moduledoc "One budget line: the cap for a purpose per period, and the period it was last exceeded in."
    use Ecto.Schema
    @primary_key false
    schema "nisaba_budget" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:purpose, :string, primary_key: true)
      field(:cap_nanos, :integer)
      field(:period, :string)
      field(:set_at, :utc_datetime_usec)
      field(:exceeded_period_key, :string)
      field(:exceeded_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Usage do
    @moduledoc "One model call: what it was for, on which model, by whom, and what it cost."
    use Ecto.Schema
    @primary_key {:ref, :binary_id, autogenerate: false}
    schema "nisaba_usage" do
      field(:resident_id, :binary_id)
      field(:purpose, :string)
      field(:model, :string)
      field(:actor_kind, :string)
      field(:actor_id, :string)
      field(:prompt_tokens, :integer)
      field(:completion_tokens, :integer)
      field(:cost_nanos, :integer)
      field(:estimated, :boolean)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "Every budget line the scope sees."
  @spec budgets() :: [Budget.t()]
  def budgets, do: Repo.all(from(b in Budget, order_by: b.purpose))

  @doc "The budget line for a purpose, or nil."
  defmodule Subscription do
    @moduledoc "The resident's one subscription row: the plan, its renewal, the state, the policy's buckets."
    use Ecto.Schema
    @primary_key false
    schema "nisaba_subscription" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:plan, :string)
      field(:price_nanos, :integer)
      field(:period_days, :integer)
      field(:state, :string)
      field(:started_at, :utc_datetime_usec)
      field(:renews_at, :utc_datetime_usec)
      field(:lapsed_at, :utc_datetime_usec)
      field(:lapse_told, :boolean, default: true)
      field(:cancelled_at, :utc_datetime_usec)
      field(:custody_due_at, :utc_datetime_usec)
      field(:policy_model, :string)
      field(:policy_witness, :string)
      field(:policy_free_time, :string)
      field(:policy_term, :string)
      field(:policy_set_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec subscription() :: Subscription.t() | nil
  def subscription, do: Repo.one(from(s in Subscription, limit: 1))

  @spec budget(String.t()) :: Budget.t() | nil
  def budget(purpose), do: Repo.one(from(b in Budget, where: b.purpose == ^purpose))

  @doc "Nano-dollars spent on a purpose in `[from, to)`."
  @spec spent(String.t(), DateTime.t(), DateTime.t()) :: non_neg_integer()
  def spent(purpose, from, to) do
    Repo.one(
      from(u in Usage,
        where: u.purpose == ^purpose and u.at >= ^from and u.at < ^to,
        select: type(coalesce(sum(u.cost_nanos), 0), :integer)
      )
    )
  end

  @doc "Spend since `since`, grouped by purpose, model or actor, over the purposes named."
  @spec spend_by(:purpose | :model | :actor, DateTime.t(), [String.t()]) :: [map()]
  def spend_by(:purpose, since, purposes) do
    Repo.all(
      from(u in Usage,
        where: u.at >= ^since and u.purpose in ^purposes,
        group_by: u.purpose,
        order_by: u.purpose,
        select: %{
          key: u.purpose,
          calls: count(u.ref),
          cost_nanos: type(sum(u.cost_nanos), :integer)
        }
      )
    )
  end

  def spend_by(:model, since, purposes) do
    Repo.all(
      from(u in Usage,
        where: u.at >= ^since and u.purpose in ^purposes,
        group_by: u.model,
        order_by: u.model,
        select: %{
          key: u.model,
          calls: count(u.ref),
          cost_nanos: type(sum(u.cost_nanos), :integer)
        }
      )
    )
  end

  def spend_by(:actor, since, purposes) do
    Repo.all(
      from(u in Usage,
        where: u.at >= ^since and u.purpose in ^purposes,
        group_by: [u.actor_kind, u.actor_id],
        order_by: [u.actor_kind, u.actor_id],
        select: %{
          key: fragment("? || ':' || coalesce(?, '')", u.actor_kind, u.actor_id),
          calls: count(u.ref),
          cost_nanos: type(sum(u.cost_nanos), :integer)
        }
      )
    )
  end

  @doc "The usage rows since `since`, newest first, over the purposes named."
  @spec usage(DateTime.t(), [String.t()]) :: [Usage.t()]
  def usage(since, purposes) do
    Repo.all(
      from(u in Usage,
        where: u.at >= ^since and u.purpose in ^purposes,
        order_by: [desc: u.at]
      )
    )
  end
end
