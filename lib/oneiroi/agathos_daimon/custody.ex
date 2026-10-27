defmodule Oneiroi.AgathosDaimon.Custody do
  @moduledoc "The wire form of a custodian: `{:account, id}` is `account:<id>`, `:community` is `community`."

  @type t :: {:account, String.t()} | :community

  @spec to_wire(t()) :: String.t()
  def to_wire({:account, id}), do: "account:" <> id
  def to_wire(:community), do: "community"

  @spec from_wire(String.t() | t()) :: t()
  def from_wire("account:" <> id), do: {:account, id}
  def from_wire("community"), do: :community
  def from_wire({:account, _} = c), do: c
  def from_wire(:community), do: :community
end
