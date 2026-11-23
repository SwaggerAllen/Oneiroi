defmodule Oneiroi.Seshat.QueueIndexWorker do
  @moduledoc "Renders one house queue task's index document into the household repository (`Oneiroi.Seshat.QueueIndex`)."
  use Oneiroi.Worker, queue: :seshat_household

  alias Oneiroi.Seshat.QueueIndex

  def run(%{"household_id" => h, "task" => n}), do: QueueIndex.render(h, n)
end
