defmodule Oneiroi.Janus.WakeWorker do
  @moduledoc """
  A succession's wake of one resident (janus#13): her runs to judge, the
  deliberation's rounds, the farewell's wakes, each a turn in her main
  conversation through the brain port (`succession_wake/2`).
  """
  use Oneiroi.Worker, queue: :janus_screening, max_attempts: 3

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config

  # A wake in a session named (her sealed packet thread, janus#44), or
  # in her main conversation.
  def run(%{"resident_id" => resident_id, "note" => note, "session" => key})
      when is_binary(key) do
    case Config.fetch!(:janus, :brain).succession_wake(resident_id, note, key) do
      {:ok, _answer} -> :ok
      {:error, _} = failed -> failed
    end
  end

  def run(%{"resident_id" => resident_id, "note" => note}) do
    case Config.fetch!(:janus, :brain).succession_wake(resident_id, note) do
      {:ok, _answer} -> :ok
      {:error, _} = failed -> failed
    end
  end

  @doc "Enqueues a wake of `resident_id` with `note`, now or at `at`."
  @spec enqueue(String.t(), String.t(), DateTime.t() | nil) :: :ok | {:error, term()}
  def enqueue(resident_id, note, at \\ nil) do
    args = %{"resident_id" => resident_id, "note" => note}
    opts = if at, do: [scheduled_at: at], else: []

    case Jobs.enqueue(__MODULE__, args, opts) do
      {:ok, _job} -> :ok
      {:error, refused} -> {:error, refused}
    end
  end
end
