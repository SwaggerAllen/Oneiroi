defmodule Oneiroi.Nisaba.Halt do
  @moduledoc """
  The halt flag (nisaba#22): set by a stream's sink in the streaming
  process, read by the provider's collector between chunks, cleared at
  each call's start. A leaf, so the ledger and the providers both read it
  without depending on each other.
  """

  @key :oneiroi_nisaba_halt

  @doc "Asks the stream in this process to end at the next chunk."
  @spec halt() :: :ok
  def halt do
    Process.put(@key, true)
    :ok
  end

  @doc "Whether this process's stream was asked to end."
  @spec halted?() :: boolean()
  def halted?, do: Process.get(@key, false)

  @doc "Clears the flag, at a call's start."
  @spec clear() :: :ok
  def clear do
    Process.delete(@key)
    :ok
  end
end
