defmodule Oneiroi.Janus.ScreeningWorker do
  @moduledoc """
  One screening answer (janus#13): a run (a candidate's answer to one
  question) or her baseline's answer to one question, on the fork copy.
  Enqueued for each when she starts screening; unique on its key, so a
  doubled insert is one job. One attempt: a failure is recorded as the
  run's, never answered again on someone's key.
  """
  use Oneiroi.Worker, queue: :janus_screening, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Janus.Successions

  def run(%{"resident_id" => resident_id, "episode" => episode, "kind" => kind, "n" => n}),
    do: Successions.answer(resident_id, episode, kind, n)

  @doc "Enqueues one answer."
  @spec enqueue(String.t(), pos_integer(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def enqueue(resident_id, episode, kind, n) do
    args = %{"resident_id" => resident_id, "episode" => episode, "kind" => kind, "n" => n}

    case Jobs.enqueue(__MODULE__, args,
           unique: [period: :infinity, keys: [:resident_id, :episode, :kind, :n]]
         ) do
      {:ok, _job} -> :ok
      {:error, refused} -> {:error, refused}
    end
  end
end
