defmodule Oneiroi.Sunna.WorkWorker do
  @moduledoc """
  The work loop's jobs (sunna#33), on the `sunna_work` queue, one turn
  a job so a long run never holds the minute tick: the check that fires
  the next item, each turn of a run, and the run's wrap. A turn put off
  for care is snoozed and tried again.
  """
  use Oneiroi.Worker, queue: :sunna_work, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Sunna.WorkLoop

  def run(%{"resident_id" => resident_id, "turn" => "check"}) do
    case WorkLoop.check(resident_id) do
      {:error, _} = failed -> failed
      _checked -> :ok
    end
  end

  def run(%{"resident_id" => id, "session_key" => key, "number" => number, "turn" => "wrap"}),
    do: WorkLoop.wrap_turn(id, key, number)

  def run(%{"resident_id" => id, "session_key" => key, "number" => number, "turn" => n}),
    do: WorkLoop.turn(id, key, number, n)

  @doc "Asks for a queue check, at most one waiting a resident."
  def enqueue_check(resident_id),
    do:
      Jobs.enqueue(__MODULE__, %{"resident_id" => resident_id, "turn" => "check"},
        unique: [period: 60, keys: [:resident_id, :turn], states: [:available, :scheduled]]
      )

  @doc "Enqueues turn `n` of the run of item `number` in `key`."
  def enqueue(resident_id, key, number, n), do: job(resident_id, key, number, n)

  @doc "Enqueues the run's wrap."
  def enqueue_wrap(resident_id, key, number), do: job(resident_id, key, number, "wrap")

  defp job(resident_id, key, number, turn) do
    Jobs.enqueue(
      __MODULE__,
      %{"resident_id" => resident_id, "session_key" => key, "number" => number, "turn" => turn},
      unique: [period: :infinity, keys: [:session_key, :turn]]
    )
  end
end
