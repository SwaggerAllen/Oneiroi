defmodule Oneiroi.Brain.OracleWorker do
  @moduledoc """
  One oracle question, run in the background (brain #49): each question
  of a dispatch is its own job, so a batch reads in parallel on the
  `brain_oracle` queue. Replay-safe: a question already answered or
  failed is left as it is (`Oracle.run/2` reads its status first), and
  the unique key keeps two jobs for one question rare.
  """
  use Oneiroi.Worker, queue: :brain_oracle, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Brain.Oracle

  def run(%{"resident_id" => resident_id, "number" => number}) do
    Oracle.run(resident_id, number)
  end

  @doc "Enqueues question `number` of `resident_id`."
  def enqueue(resident_id, number) do
    Jobs.enqueue(__MODULE__, %{"resident_id" => resident_id, "number" => number},
      unique: [period: :infinity, keys: [:resident_id, :number]]
    )
  end
end
