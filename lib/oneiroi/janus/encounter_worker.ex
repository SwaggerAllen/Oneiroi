defmodule Oneiroi.Janus.EncounterWorker do
  @moduledoc "One step of the encounter's relay (janus#19): one side woken with what the other said (`Rites.encounter_step/6`), in each side's own thread."
  use Oneiroi.Worker, queue: :janus_screening, max_attempts: 1

  alias Oneiroi.Janus.Rites

  def run(
        %{
          "resident_id" => id,
          "episode" => episode,
          "attempt" => attempt,
          "side" => side,
          "note" => note
        } = args
      ),
      do: Rites.encounter_step(id, episode, attempt, side, note, Map.get(args, "sessions", %{}))
end
