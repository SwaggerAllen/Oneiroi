defmodule Oneiroi.Janus.ToolUseWorker do
  @moduledoc "The nightly count of the day before's tool calls by model (janus#11)."
  use Oneiroi.Worker, queue: :janus_nightly

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Janus.ToolUse

  def run(_args) do
    day = Clock.now() |> DateTime.to_date() |> Date.add(-1)
    with {:ok, _models} <- ToolUse.count(day), do: :ok
  end
end
