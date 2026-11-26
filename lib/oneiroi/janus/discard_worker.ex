defmodule Oneiroi.Janus.DiscardWorker do
  @moduledoc "A stopped succession's fork copy discarded, unless a nominee met her (janus#28; `Rites.discard/2`)."
  use Oneiroi.Worker, queue: :janus_fork, max_attempts: 3

  alias Oneiroi.Janus.Rites

  def run(%{"resident_id" => id, "episode" => episode}), do: Rites.discard(id, episode)
end
