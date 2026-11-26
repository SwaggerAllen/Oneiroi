defmodule Oneiroi.Janus.CutoverWorker do
  @moduledoc """
  The roll-forward's job (janus#26): one attempt, never retried on its
  own, because a cutover that stopped partway is a thing a person reads
  before anything runs again (`RollForward.run/1`).
  """
  use Oneiroi.Worker, queue: :janus_fork, max_attempts: 1

  alias Oneiroi.Janus.RollForward

  def run(%{"resident_id" => id}), do: RollForward.run(id)
end
