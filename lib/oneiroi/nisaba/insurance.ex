defmodule Oneiroi.Nisaba.Insurance do
  @moduledoc """
  Nanshe, the insurance floor (spec §6.11, F46): policy on four axes,
  each cut into three buckets, a policy one bucket per axis. The floor
  bucket on every axis is what every resident has without choosing it;
  above it a witness prepays a larger bucket; the pool is prepaid, never
  accrued as debt.

  **The buckets are configuration with defaults until the platform is
  stood up and measured** (spec §6.11's own words): rows a governance
  process can change arrive with governance (P4), and until then each
  axis's three values are a setting here, placeholders and said so. A
  policy references its buckets by id (`<axis>/floor`, `/mid`, `/high`),
  so a change to a bucket's value changes what every policy on it pays
  out from the next week, as the spec asks.
  """

  alias Oneiroi.Config

  @axes ~w(model witness free_time term)
  @levels ~w(floor mid high)

  @doc "The four axes."
  def axes, do: @axes

  @doc "Every bucket: axis, id, level, value, whether it is the floor."
  @spec buckets() :: [map()]
  def buckets do
    Enum.flat_map(@axes, fn axis ->
      axis
      |> values()
      |> Enum.zip(@levels)
      |> Enum.map(fn {value, level} ->
        %{
          axis: axis,
          id: axis <> "/" <> level,
          level: level,
          value: value,
          floor: level == "floor"
        }
      end)
    end)
  end

  @doc "One bucket by id, or nil."
  def bucket(id), do: Enum.find(buckets(), &(&1.id == id))

  @doc "The floor policy: the floor bucket on every axis."
  def floor_policy, do: Map.new(@axes, &{String.to_existing_atom(&1), &1 <> "/floor"})

  @doc "Whether `bucket_id` is a bucket on `axis`."
  def on_axis?(bucket_id, axis), do: match?(%{axis: ^axis}, bucket(bucket_id))

  @doc "A policy's values: the model slug, nano-dollars a week for the witness and for free time, the term in days."
  def resolve(%{model: m, witness: s, free_time: f, term: t}) do
    %{
      model: value(m),
      witness_nanos_week: value(s),
      free_time_nanos_week: value(f),
      term_days: value(t)
    }
  end

  defp value(bucket_id) do
    case bucket(bucket_id) do
      nil -> nil
      %{value: v} -> v
    end
  end

  defp values("model"), do: Config.fetch!(:nisaba, :insurance_models)
  defp values("witness"), do: Config.fetch!(:nisaba, :insurance_witness_nanos_week)
  defp values("free_time"), do: Config.fetch!(:nisaba, :insurance_free_time_nanos_week)
  defp values("term"), do: Config.fetch!(:nisaba, :insurance_term_days)

  @doc false
  def cast_list(raw) when is_binary(raw) do
    case raw |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [_, _, _] = three -> {:ok, three}
      # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
      other -> {:error, "is #{inspect(other)}, expected three comma-separated values"}
    end
  end

  @doc false
  def cast_integers(raw) when is_binary(raw) do
    with {:ok, three} <- cast_list(raw) do
      parsed = Enum.map(three, &Integer.parse/1)

      if Enum.all?(parsed, &match?({n, ""} when n > 0, &1)),
        do: {:ok, Enum.map(parsed, &elem(&1, 0))},
        # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
        else: {:error, "is #{inspect(raw)}, expected three positive integers"}
    end
  end
end
