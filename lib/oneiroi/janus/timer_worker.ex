defmodule Oneiroi.Janus.TimerWorker do
  @moduledoc """
  A succession's timers (janus#16, #20): ten minutes of silence in the
  room, her asks at fifty minutes and hourly after, the close ten
  minutes after she calls it, the farewell's wakes at her cadence and
  its last wake. Each checks, when it fires, that the state it was set
  for still holds (`Rites.timer/4`).
  """
  use Oneiroi.Worker, queue: :janus_screening, max_attempts: 3

  alias Oneiroi.Janus.Rites

  def run(%{"resident_id" => id, "episode" => episode, "kind" => kind, "attempt" => attempt}),
    do: Rites.timer(id, episode, kind, attempt)
end
