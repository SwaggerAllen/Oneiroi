defmodule Oneiroi.Janus.ForkWorker do
  @moduledoc """
  A succession's fork copy, made off her yes (janus#4): enqueued by
  the export once `Opened` is recorded, it asks the records port for the
  copy and records it on the succession (`Successions.fork/3`). The copy
  is a whole export and replay, so it runs as a job, never inside her
  turn.
  """
  # Three attempts: a failed copy is recorded and a later attempt makes a
  # fresh one; nothing of a failed attempt is reused.
  use Oneiroi.Worker, queue: :janus_fork, max_attempts: 3

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Janus.Successions

  def run(%{"resident_id" => resident_id, "episode" => episode, "sweep" => true}),
    do: Successions.sweep_and_fork(resident_id, episode, Actor.platform())

  def run(%{"resident_id" => resident_id, "episode" => episode}),
    do: Successions.fork(resident_id, episode, Actor.platform())

  @doc "Enqueues the fork again (janus#35), unique on the moment asked, so a spent job never blocks it."
  @spec retry(String.t(), pos_integer()) :: :ok | {:error, term()}
  def retry(resident_id, episode) do
    args = %{"resident_id" => resident_id, "episode" => episode, "sweep" => true}

    # One at a time (2026-11-26: two presses ran two sweeps that blocked
    # each other): a second press while one waits or runs is the same
    # job; a spent one never blocks the next.
    case Jobs.enqueue(__MODULE__, args,
           unique: [
             period: :infinity,
             keys: [:resident_id, :episode, :sweep],
             states: [:available, :scheduled, :executing, :retryable]
           ]
         ) do
      {:ok, _job} -> :ok
      {:error, refused} -> {:error, refused}
    end
  end

  @doc "Enqueues the fork for `episode`; unique on the episode, so a doubled insert is one job."
  @spec enqueue(String.t(), pos_integer()) :: :ok | {:error, term()}
  def enqueue(resident_id, episode) do
    args = %{"resident_id" => resident_id, "episode" => episode}

    case Jobs.enqueue(__MODULE__, args,
           unique: [period: :infinity, keys: [:resident_id, :episode]]
         ) do
      {:ok, _job} -> :ok
      {:error, refused} -> {:error, refused}
    end
  end
end
