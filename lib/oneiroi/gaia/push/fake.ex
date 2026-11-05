defmodule Oneiroi.Gaia.Push.Fake do
  @moduledoc """
  The in-memory push service (conventions §9): every delivery is kept,
  and an endpoint marked gone answers as a push service does for a
  device that is no more.
  """
  @behaviour Oneiroi.Gaia.Push

  @key {__MODULE__, :sent}
  @gone {__MODULE__, :gone}

  @impl true
  def deliver(endpoint) do
    :persistent_term.put(@key, sent() ++ [endpoint])
    if endpoint in :persistent_term.get(@gone, []), do: :gone, else: :ok
  end

  @doc "Every endpoint pushed to, in order."
  def sent, do: :persistent_term.get(@key, [])

  @doc "Marks an endpoint as a device that is gone."
  def gone(endpoint),
    do: :persistent_term.put(@gone, [endpoint | :persistent_term.get(@gone, [])])

  @doc "Forgets every delivery and every gone device."
  def clear do
    :persistent_term.erase(@key)
    :persistent_term.erase(@gone)
    :ok
  end
end
