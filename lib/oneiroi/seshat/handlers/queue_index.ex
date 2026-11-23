defmodule Oneiroi.Seshat.Handlers.QueueIndex do
  @moduledoc """
  Every house queue task has its index document in the household
  repository (sunna#80, lily:design/queue-ia §4; spec §6.10, repo first):
  `tasks/<project>/<slug>.md`, rendered from the rows after every event
  that touches the task. Eventual (conventions §7): each such event asks
  `Oneiroi.Seshat.QueueIndexWorker` for a render a moment later, by
  which time the projection has the change; a burst of moves on one task
  is one render.
  """
  use Commanded.Event.Handler,
    application: Oneiroi.Commanded,
    name: "seshat_queue_index",
    consistency: :eventual

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Seshat.QueueIndexWorker

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  @impl Commanded.Event.Handler
  def handle(%{__struct__: module, id: household_id} = event, _metadata) do
    case {queue_event?(module), task_of(event)} do
      {true, n} when is_integer(n) ->
        Jobs.enqueue(
          QueueIndexWorker,
          %{"household_id" => household_id, "task" => n},
          schedule_in: 2,
          unique: [period: 60, keys: [:household_id, :task], states: [:available, :scheduled]]
        )

        :ok

      _other ->
        :ok
    end
  end

  def handle(_event, _metadata), do: :ok

  defp queue_event?(module),
    do: match?(["Oneiroi", "Sunna", "Events", "Queue", _], Module.split(module))

  defp task_of(event), do: Map.get(event, :task) || Map.get(event, :number)
end
