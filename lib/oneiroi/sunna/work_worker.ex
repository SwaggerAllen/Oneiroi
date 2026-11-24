defmodule Oneiroi.Sunna.WorkWorker do
  @moduledoc """
  The work line's jobs (sunna#33, #86), on the `sunna_work` queue, one
  turn a job so a long run never holds the minute tick: the check that
  starts the next activity, each turn of a run, and the run's closing
  turn. A turn put off for care is snoozed and tried again.
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

  # A house queue activity's run (sunna#86).
  def run(%{"resident_id" => id, "session_key" => key, "act" => act, "turn" => "wrap"} = a),
    do: WorkLoop.activity_wrap(id, key, a["household"], a["task"], act)

  def run(%{"resident_id" => id, "session_key" => key, "act" => act, "turn" => n} = a),
    do: WorkLoop.activity_turn(id, key, a["household"], a["task"], act, n)

  # An old item run's job (retired, sunna#102): nothing to do.
  def run(%{"number" => _number}), do: :ok

  @doc "Asks for a queue check, at most one waiting a resident."
  def enqueue_check(resident_id),
    do:
      Jobs.enqueue(__MODULE__, %{"resident_id" => resident_id, "turn" => "check"},
        unique: [period: 60, keys: [:resident_id, :turn], states: [:available, :scheduled]]
      )

  @doc "Enqueues the queue check `seconds` from now: after a run that failed (sunna#52)."
  def enqueue_check(resident_id, seconds),
    do:
      Jobs.enqueue(__MODULE__, %{"resident_id" => resident_id, "turn" => "check"},
        schedule_in: seconds,
        unique: [period: 60, keys: [:resident_id, :turn], states: [:available, :scheduled]]
      )

  @doc "Enqueues turn `n` of a house queue activity's run (sunna#86)."
  def enqueue_activity(resident_id, key, %{household: h, task: task, act: act}, n),
    do: activity_job(resident_id, key, h, task, act, n)

  @doc "Enqueues an activity run's closing turn."
  def enqueue_activity_wrap(resident_id, key, h, task, act),
    do: activity_job(resident_id, key, h, task, act, "wrap")

  defp activity_job(resident_id, key, h, task, act, turn) do
    Jobs.enqueue(
      __MODULE__,
      %{
        "resident_id" => resident_id,
        "session_key" => key,
        "household" => h,
        "task" => task,
        "act" => act,
        "turn" => turn
      },
      unique: [period: :infinity, keys: [:session_key, :turn]]
    )
  end
end
