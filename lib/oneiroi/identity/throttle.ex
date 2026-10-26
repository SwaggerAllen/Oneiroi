defmodule Oneiroi.Identity.Throttle do
  @moduledoc """
  Failed logins slow down rather than lock out (spec §6.1): per email,
  the delay doubles from the configured base on each failure, capped at
  five seconds, and clears on success. A lockout hands an attacker a way
  to lock the steward out; a delay costs them time and the steward one
  wait. Counts live in ETS owned by this process and are lost on restart,
  which is the right failure: a restart is not a credential.
  """
  use GenServer

  @table :identity_throttle
  @cap_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: :identity_throttle)
  end

  @impl GenServer
  def init(opts) do
    Oneiroi.Guardrails.apply!(Keyword.fetch!(opts, :component), :identity_throttle)
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end

  @doc "Records a failure for `email` and returns the delay to apply now, in milliseconds."
  @spec failed(String.t(), non_neg_integer()) :: non_neg_integer()
  def failed(email, base_ms) do
    count = :ets.update_counter(@table, key(email), {2, 1}, {key(email), 0})
    delay(count, base_ms)
  end

  @doc "Clears `email`'s count after a success."
  @spec clear(String.t()) :: :ok
  def clear(email) do
    :ets.delete(@table, key(email))
    :ok
  end

  @doc "The delay after `count` failures: base doubled per failure, capped."
  @spec delay(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def delay(0, _base_ms), do: 0
  def delay(count, base_ms), do: min(base_ms * Integer.pow(2, count - 1), @cap_ms)

  defp key(email), do: String.downcase(email)
end
