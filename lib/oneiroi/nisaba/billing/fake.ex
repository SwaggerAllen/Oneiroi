defmodule Oneiroi.Nisaba.Billing.Fake do
  @moduledoc """
  The in-memory payment provider (conventions §9): every checkout and
  portal asked for is kept, and each answers a URL of its own.
  """
  @behaviour Oneiroi.Nisaba.Billing

  @key {__MODULE__, :asked}

  @impl true
  def checkout(params) do
    keep({:checkout, params})
    {:ok, "https://checkout.example.test/#{params.resident_id}"}
  end

  @impl true
  def portal(customer, return_url) do
    keep({:portal, customer, return_url})
    {:ok, "https://portal.example.test/#{customer}"}
  end

  @doc "Every call, in order."
  def asked, do: :persistent_term.get(@key, [])

  @doc "Forgets them."
  def clear, do: :persistent_term.erase(@key) && :ok

  defp keep(call), do: :persistent_term.put(@key, asked() ++ [call])
end
