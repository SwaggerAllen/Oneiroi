defmodule Oneiroi.Sunna.QueueGraph do
  @moduledoc """
  The house queue's rules, pure (lily:design/queue-ia revision 5, §1,
  §6.1): no storage, no clock, so every rule is tested on its own and the
  aggregate only asks.

  A **task** is `%{number, status, layers}`: `status` is "open" or
  "dropped", and `layers` is an array of arrays of activity ids. Each
  layer's activities may run in parallel, and a layer opens only when every
  activity in the layer before it is done or skipped.

  An **activity** is a map with at least `id`, `task`, `status` and
  `type`. Its `status` is one of:

  - "pending": not yet taken; ready or waiting, as its layer is open or not;
  - "active", "done" or "skipped";
  - "blocked" or "failed", carried in place.

  A block may name the task it waits on (`waits_on`). Optional fields:
  `artifact` (what it works on), `gated`, `destination`, `action`.

  **Completion** is binary: every layer done or skipped, or the task
  dropped. Dropped counts as completion, so an abandoned blocker releases
  its waiters, as sunna#42's `release/4` does.

  **Waiting across tasks** is on a task's completion, never on one of its
  activities. A block that would make a task wait on itself, directly or
  through any chain (a→b→c→a), is refused. So is a block naming a task that
  doesn't exist. Today's `blocker/3` refuses only self-blocks and two-way
  loops; this is the stronger check Scarlett's fourth guard asks for.
  """

  @finished ~w(done skipped)
  @gated ~w(send publish spend merge promote-to-house)

  @doc "The activity types a review must stand in front of (§6.1)."
  def gated_types, do: @gated

  @doc "Whether a task is complete: dropped, or every layer done or skipped."
  def complete?(%{status: "dropped"}, _acts), do: true

  def complete?(%{layers: layers}, acts),
    do: Enum.all?(layers, fn layer -> Enum.all?(layer, &finished?(acts[&1])) end)

  @doc "The index of a task's open layer, or nil when it is complete or dropped."
  def open_layer(%{status: "dropped"}, _acts), do: nil

  def open_layer(%{layers: layers}, acts),
    do: Enum.find_index(layers, fn layer -> not Enum.all?(layer, &finished?(acts[&1])) end)

  @doc """
  What an activity is, as the screens and the bell read it:

  - `:ready`: pending and in the open layer;
  - `:waiting`: pending in a later layer;
  - otherwise its own status as an atom.
  """
  def view(act, task, acts) do
    case act.status do
      "pending" -> if layer_of(task, act.id) == open_layer(task, acts), do: :ready, else: :waiting
      other -> String.to_existing_atom(other)
    end
  end

  @doc "The layer index holding an activity, or nil."
  def layer_of(%{layers: layers}, id), do: Enum.find_index(layers, &(id in &1))

  @doc """
  Whether a block from `blocked_task` waiting on `target` may be set, as a
  verdict the aggregate turns into a sited error:

  - `:ok`;
  - `:no_such_task` when the target doesn't exist;
  - `:self` when it names its own task;
  - `:cycle` when the target already waits, through any chain, on
    `blocked_task`.

  A target already complete is allowed: the block clears at once (§1).
  """
  def block_ok?(tasks, acts, blocked_task, target) do
    cond do
      not Map.has_key?(tasks, target) -> :no_such_task
      target == blocked_task -> :self
      reaches?(tasks, acts, target, blocked_task, MapSet.new()) -> :cycle
      true -> :ok
    end
  end

  # Whether `from` waits, through any chain of live blocks, on `to`.
  defp reaches?(tasks, acts, from, to, seen) do
    if MapSet.member?(seen, from) do
      false
    else
      seen = MapSet.put(seen, from)

      tasks
      |> waits_of(acts, from)
      |> Enum.any?(fn next -> next == to or reaches?(tasks, acts, next, to, seen) end)
    end
  end

  # The tasks one task's live blocks wait on.
  defp waits_of(tasks, acts, n) do
    case tasks[n] do
      nil ->
        []

      task ->
        for layer <- task.layers,
            id <- layer,
            %{status: "blocked", waits_on: on} when is_integer(on) <- [acts[id]],
            uniq: true,
            do: on
    end
  end

  @doc """
  The activities a task's completion releases: every activity blocked
  waiting on it. Each returns to pending, and its own layer decides
  whether that reads as ready.
  """
  def releases(acts, completed) do
    for {id, %{status: "blocked", waits_on: ^completed}} <- acts, do: id
  end

  @doc """
  The shape rule (§6.1) over a task's layers as proposed: a gated activity
  sits only in the layer directly after one holding a review of the same
  artifact, naming the gated activity's destination and action. Returns
  the ids of the gated activities that break it; `[]` means the shape holds.
  `specs` maps id → activity spec.
  """
  def shape_errors(layers, specs) do
    layers
    |> Enum.with_index()
    |> Enum.flat_map(fn {layer, i} ->
      for id <- layer, gated?(specs[id]), not reviewed?(layers, specs, i, specs[id]), do: id
    end)
  end

  defp gated?(%{type: type}), do: type in @gated
  defp gated?(_spec), do: false

  defp reviewed?(_layers, _specs, 0, _gated), do: false

  defp reviewed?(layers, specs, i, gated) do
    layers
    |> Enum.at(i - 1)
    |> Enum.any?(fn id ->
      r = specs[id]

      r[:type] == "review" and r[:artifact] == gated[:artifact] and
        r[:destination] == gated[:destination] and r[:action] == gated[:type]
    end)
  end

  defp finished?(%{status: status}), do: status in @finished
  defp finished?(nil), do: false
end
