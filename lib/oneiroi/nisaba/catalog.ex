defmodule Oneiroi.Nisaba.Catalog do
  @moduledoc """
  The model catalog (nisaba#24): what the provider lists, priced, kept
  in a platform table and fetched again each night, so the Regression
  page and a succession's pool read prices without a call out. A cache
  of the provider's own list, not a record of anyone's: written here,
  never by an event, and replaced whole on each fetch.

  And her pace (nisaba#25): the tokens a day she spends on average over
  the last 90 days, the figure a succession's monthly estimates multiply.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Provider.Model
  alias Oneiroi.Nisaba.Purpose
  alias Oneiroi.Nisaba.Store.Usage
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  defmodule Row do
    @moduledoc "One listed model, as last fetched."
    use Ecto.Schema
    @primary_key false
    schema "nisaba_model" do
      field(:model_id, :string, primary_key: true)
      field(:name, :string)
      field(:description, :string)
      field(:input_nanos, :integer)
      field(:output_nanos, :integer)
      field(:context, :integer)
      field(:tools, :boolean, default: false)
      field(:fetched_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @window_days 90

  @doc "Fetches the provider's list and replaces the catalog with it; `{:ok, count}` or the provider's failure, the old list kept."
  @spec refresh() :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh do
    with {:ok, models} <- Config.fetch!(:nisaba, :provider).models() do
      at = Clock.now()
      rows = Enum.map(models, &row(&1, at))

      Scope.platform(fn ->
        Repo.delete_all(Row)
        rows |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(Row, &1))
      end)

      {:ok, length(rows)}
    end
  end

  @doc "Every listed model, by slug."
  @spec all() :: [Row.t()]
  def all, do: Scope.platform(fn -> Repo.all(from(m in Row, order_by: m.model_id)) end)

  @doc "One listed model, or nil."
  @spec get(String.t()) :: Row.t() | nil
  def get(model_id) when is_binary(model_id),
    do: Scope.platform(fn -> Repo.get_by(Row, model_id: model_id) end)

  @doc """
  Her tokens a day, input and output, averaged over the last 90 days
  or over the days since her first call when she is younger than that,
  never fewer than one; the witness's own spending on her (drafting,
  regression) and a succession's runs are not hers and are left out.
  `cost` is what those calls cost a day on average, in nano-dollars, as
  the ledger recorded it (nisaba#27): her spending now, beside the
  estimates at list prices.
  """
  @spec pace(String.t()) :: %{
          input: non_neg_integer(),
          output: non_neg_integer(),
          cost: non_neg_integer(),
          days: pos_integer()
        }
  def pace(resident_id) do
    now = Clock.now()
    since = DateTime.add(now, -@window_days * 86_400, :second)
    # A succession's runs are the process's, not her pace (janus#12).
    hers = Enum.map(Purpose.all() -- [:succession | Purpose.witness_only()], &to_string/1)

    {input, output, cost, first} =
      Scope.resident(resident_id, fn ->
        Repo.one(
          from(u in Usage,
            where: u.at >= ^since and u.purpose in ^hers,
            select:
              {coalesce(sum(u.prompt_tokens), 0), coalesce(sum(u.completion_tokens), 0),
               coalesce(sum(u.cost_nanos), 0), min(u.at)}
          )
        )
      end)

    days =
      case first do
        nil -> 1
        at -> now |> DateTime.diff(at, :second) |> div(86_400) |> Kernel.+(1) |> min(@window_days)
      end

    %{
      input: div(to_int(input), days),
      output: div(to_int(output), days),
      cost: div(to_int(cost), days),
      days: days
    }
  end

  @doc "A month at `pace` and a model's prices, in nano-dollars: the day's average × 30."
  @spec monthly(map(), map()) :: non_neg_integer()
  def monthly(%{input: i, output: o}, %{input_nanos: pi, output_nanos: po}),
    do: (i * pi + o * po) * 30

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  defp row(%Model{} = m, at),
    do: %{
      model_id: m.id,
      name: m.name,
      description: m.description,
      input_nanos: m.input_nanos,
      output_nanos: m.output_nanos,
      context: m.context,
      tools: m.tools? == true,
      fetched_at: at
    }
end
