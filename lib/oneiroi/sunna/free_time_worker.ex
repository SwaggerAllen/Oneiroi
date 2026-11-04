defmodule Oneiroi.Sunna.FreeTimeWorker do
  @moduledoc """
  Free time carried on (sunna#26): a free-time pass that ran out of
  tool rounds is woken again in its own conversation, one turn a job, so
  a long pass never holds the minute tick that fires everyone's
  check-ins. It goes on while the witness's free-time budget line has
  money left this period, up to `SUNNA_FREE_TIME_TURNS` turns a slot,
  and stops when a turn ends in words with nothing left to call: her
  saying she is done.
  """
  use Oneiroi.Worker, queue: :sunna_free_time, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Sunna.Schedules

  def run(%{"resident_id" => resident_id, "session_key" => key, "turn" => n}),
    do: Schedules.continue_free_time(resident_id, key, n)

  @doc "Enqueues turn `n` of the free-time pass in `key`."
  def enqueue(resident_id, key, n) do
    Jobs.enqueue(__MODULE__, %{"resident_id" => resident_id, "session_key" => key, "turn" => n},
      unique: [period: :infinity, keys: [:session_key, :turn]]
    )
  end
end
