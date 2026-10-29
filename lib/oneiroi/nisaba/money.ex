defmodule Oneiroi.Nisaba.Money do
  @moduledoc """
  Nano-dollars in, dollars out. A cost is an integer count of 10^-9 USD:
  OpenRouter reports costs like 0.0000195, which a cent cannot hold and a
  float should not, since an event replays on another machine. The API
  speaks dollars as decimal strings and never floats.
  """

  @nanos_per_dollar 1_000_000_000

  @doc "Nano-dollars from a provider's USD figure, a float or a decimal string, rounded half up."
  @spec from_usd(number() | String.t() | Decimal.t()) :: non_neg_integer()
  def from_usd(usd) do
    usd
    |> to_decimal()
    |> Decimal.mult(@nanos_per_dollar)
    |> Decimal.round(0, :half_up)
    |> Decimal.to_integer()
  end

  @doc "A decimal string of dollars from nano-dollars, with the places that matter."
  @spec to_usd(non_neg_integer()) :: String.t()
  def to_usd(nanos) when is_integer(nanos) do
    nanos
    |> Decimal.new()
    |> Decimal.div(@nanos_per_dollar)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @doc "Nano-dollars from a user-typed dollar string, or nil when it is not a number."
  @spec parse_usd(term()) :: non_neg_integer() | nil
  def parse_usd(string) when is_binary(string) do
    case Decimal.parse(String.trim(string)) do
      {decimal, ""} -> if Decimal.negative?(decimal), do: nil, else: from_usd(decimal)
      _other -> nil
    end
  end

  def parse_usd(number) when is_number(number) and number >= 0, do: from_usd(number)
  def parse_usd(_other), do: nil

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)
  defp to_decimal(i) when is_integer(i), do: Decimal.new(i)
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)
end
