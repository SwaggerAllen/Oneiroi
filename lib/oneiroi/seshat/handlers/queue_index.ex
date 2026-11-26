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
  use Oneiroi.Handler,
    application: Oneiroi.Commanded,
    name: "seshat_queue_index",
    consistency: :eventual

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Seshat.QueueIndexWorker
  alias Oneiroi.Seshat.ReviewThreadWorker

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  # A review's decision goes into its document's thread too (seshat#110).
  @impl Commanded.Event.Handler
  def handle(%Oneiroi.Sunna.Events.Queue.ReviewDecided{} = e, metadata) do
    Jobs.enqueue(ReviewThreadWorker, %{
      "household_id" => e.id,
      "task" => e.task,
      "act" => e.act,
      "outcome" => e.outcome,
      "pin" => e.pin,
      "note" => e.note,
      "actor_kind" => to_string(field(e.actor, :kind)),
      "actor_id" => field(e.actor, :id)
    })

    index(e, metadata)
  end

  def handle(event, metadata), do: index(event, metadata)

  defp index(%{__struct__: module, id: household_id} = event, _metadata) do
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

  defp index(_event, _metadata), do: :ok

  defp field(nil, _key), do: nil
  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp queue_event?(module),
    do: match?(["Oneiroi", "Sunna", "Events", "Queue", _], Module.split(module))

  defp task_of(event), do: Map.get(event, :task) || Map.get(event, :number)
end
