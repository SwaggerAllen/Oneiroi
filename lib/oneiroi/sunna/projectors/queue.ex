defmodule Oneiroi.Sunna.Projectors.Queue do
  @moduledoc """
  Folds the house queue (sunna#80) into its rows: projects, tasks,
  activities, each activity's history, templates and the queue's state.
  After every change to a task its activities' `view` (ready, waiting,
  or their own status) and the task's open layer are read again off the
  rows by `Oneiroi.Sunna.QueueGraph`, so the screens filter on a column
  and never recompute the layers.
  """
  use Oneiroi.Projection, name: "sunna_queue"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Sunna.Events.Queue, as: E
  alias Oneiroi.Sunna.Queue
  alias Oneiroi.Sunna.QueueGraph
  alias Oneiroi.Sunna.QueueStore, as: S

  fold(%E.ProjectOpened{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :project,
      %S.Project{
        household_id: e.id,
        slug: e.slug,
        name: e.name,
        owner: e.owner,
        status: "open",
        opened_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :slug]
    )
  end)

  fold(%E.ProjectClosed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :project,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(p in S.Project, where: p.household_id == ^e.id and p.slug == ^e.slug),
      set: [status: "closed", closed_at: e.at, note: e.note]
    )
  end)

  fold(%E.TemplateDefined{} = e, _metadata, fn multi ->
    set = [
      title: e.title,
      layers: %{"layers" => stringify(e.layers)},
      defined_by: who(e.actor),
      defined_at: e.at
    ]

    Multi.insert(
      multi,
      :template,
      struct(S.Template, [household_id: e.id, name: e.name] ++ set),
      on_conflict: [set: set],
      conflict_target: [:household_id, :name]
    )
  end)

  fold(%E.TaskOpened{} = e, _metadata, fn multi ->
    start = e.start_layer || 0

    rows =
      for {layer, i} <- Enum.with_index(e.layers),
          {spec, j} <- Enum.with_index(layer) do
        imported = i < start

        %{
          household_id: e.id,
          act_id: Queue.get(spec, :id),
          task: e.number,
          layer: i,
          position: j,
          type: Queue.get(spec, :type),
          assignee: Queue.get(spec, :assignee),
          status: if(imported, do: "done", else: "pending"),
          view: if(imported, do: "done", else: "waiting"),
          artifact: Queue.get(spec, :artifact),
          destination: Queue.get(spec, :destination),
          action: Queue.get(spec, :action),
          optional: Queue.get(spec, :optional) == true,
          throwback: Queue.get(spec, :throwback),
          imported: imported,
          updated_at: e.at
        }
      end

    multi
    |> Multi.insert(
      :task,
      %S.Task{
        household_id: e.id,
        number: e.number,
        project: e.project,
        slug: e.slug,
        title: e.title,
        outcome: e.outcome,
        owner: e.owner,
        index_doc: e.index,
        template: e.template,
        links: List.wrap(e.links),
        status: "open",
        opened_by: who(e.actor),
        opened_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :number]
    )
    |> Multi.insert_all(:acts, S.Activity, rows,
      on_conflict: :nothing,
      conflict_target: [:household_id, :act_id]
    )
    |> history(e, nil, "opened", nil, nil, imported_note(start))
    |> refresh(e.id, e.number, e.at)
  end)

  fold(%E.ActivityTaken{} = e, _metadata, fn multi ->
    multi
    |> act(e, status: "active", assignee: e.assignee)
    |> history(e, e.act, "taken", nil, nil, nil)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivityDone{} = e, _metadata, fn multi ->
    multi
    |> act(e,
      status: "done",
      waits_on: nil,
      reason: nil,
      pin: e.pin,
      result: e.result,
      note: e.note
    )
    |> history(e, e.act, "done", nil, e.pin, e.note)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivitySkipped{} = e, _metadata, fn multi ->
    multi
    |> act(e, status: "skipped", waits_on: nil, reason: nil, note: e.note)
    |> history(e, e.act, "skipped", nil, nil, e.note)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivityBlocked{} = e, _metadata, fn multi ->
    multi
    |> act(e, status: "blocked", waits_on: e.waits_on, reason: e.reason)
    |> history(e, e.act, "blocked", nil, nil, e.reason)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivityReopened{} = e, _metadata, fn multi ->
    multi
    |> act(e, status: "pending", waits_on: nil, reason: nil, note: e.note)
    |> history(e, e.act, if(e.released, do: "released", else: "reopened"), nil, nil, e.note)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivityFailed{} = e, _metadata, fn multi ->
    multi
    |> act(e, status: "failed", reason: e.what)
    |> history(e, e.act, "failed", nil, nil, e.what)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ActivityAssigned{} = e, _metadata, fn multi ->
    multi
    |> act(e, assignee: e.assignee)
    |> history(e, e.act, "assigned", e.assignee, nil, e.note)
  end)

  fold(%E.ReviewDecided{outcome: "approved"} = e, _metadata, fn multi ->
    skipped = List.wrap(e.skipped)

    multi
    |> act(e, status: "done", approved_pin: e.pin, pin: e.pin, note: e.note)
    |> history(e, e.act, "decided", "approved", e.pin, e.note)
    |> Multi.update_all(
      :skipped,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(a in S.Activity, where: a.household_id == ^e.id and a.act_id in ^skipped),
      set: [status: "skipped", note: "The review chose to keep it where it is.", updated_at: e.at]
    )
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ReviewDecided{} = e, _metadata, fn multi ->
    returned = List.wrap(e.returned)

    multi
    |> act(e, status: "pending", approved_pin: nil, pin: nil, note: e.note)
    |> history(e, e.act, "decided", e.outcome, e.pin, e.note)
    |> Multi.update_all(
      :returned,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(a in S.Activity, where: a.household_id == ^e.id and a.act_id in ^returned),
      set: [status: "pending", waits_on: nil, reason: nil, note: e.note, updated_at: e.at]
    )
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.ApprovalLapsed{} = e, _metadata, fn multi ->
    note =
      "The artifact moved from #{e.approved_pin} to #{e.head} after approval: review it again."

    multi
    |> act(e, status: "pending", approved_pin: nil, note: note)
    |> Multi.update_all(
      :gated,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(a in S.Activity, where: a.household_id == ^e.id and a.act_id == ^e.gated),
      set: [status: "pending", updated_at: e.at]
    )
    |> history(e, e.act, "lapsed", nil, e.head, note)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.SlotFilled{} = e, _metadata, fn multi ->
    acts = List.wrap(e.acts)

    multi
    |> Multi.update_all(
      :filled,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(a in S.Activity, where: a.household_id == ^e.id and a.act_id in ^acts),
      set: [artifact: e.artifact, updated_at: e.at]
    )
    |> history(e, nil, "filled", e.slot, nil, e.artifact)
  end)

  fold(%E.TaskCompleted{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :task,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(t in S.Task, where: t.household_id == ^e.id and t.number == ^e.task),
      set: [status: "complete", completed_at: e.at, open_layer: nil]
    )
    |> history(e, nil, "completed", nil, nil, nil)
  end)

  fold(%E.TaskDropped{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :task,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(t in S.Task, where: t.household_id == ^e.id and t.number == ^e.task),
      set: [status: "dropped", completed_at: e.at, open_layer: nil, note: e.note]
    )
    |> history(e, nil, "dropped", nil, nil, e.note)
  end)

  fold(%E.CutOver{} = e, _metadata, fn multi ->
    state(multi, e.id, cut_over: true, cut_at: e.at, commit: e.commit, note: e.note)
  end)

  fold(%E.CutBack{} = e, _metadata, fn multi ->
    state(multi, e.id, cut_over: false, note: e.note)
  end)

  defp act(multi, e, set),
    do:
      Multi.update_all(
        multi,
        {:act, e.act},
        # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
        from(a in S.Activity, where: a.household_id == ^e.id and a.act_id == ^e.act),
        set: set ++ [updated_at: e.at]
      )

  defp history(multi, e, act_id, what, outcome, pin, note) do
    Multi.insert(multi, {:history, what, act_id}, %S.History{
      household_id: e.id,
      act_id: act_id,
      task: Map.get(e, :task) || Map.get(e, :number),
      what: what,
      outcome: outcome,
      pin: pin,
      note: note,
      actor_kind: kind(e.actor),
      actor_id: actor_id(e.actor),
      at: e.at
    })
  end

  # The task's activities read again off the rows: each one's view, when
  # a newly ready one became ready, and the task's open layer.
  defp refresh(multi, household_id, number, at) do
    Multi.run(multi, {:refresh, number}, fn repo, _ ->
      {:ok, refresh_task(repo, household_id, number, at)}
    end)
  end

  defp refresh_task(repo, household_id, number, at) do
    rows =
      repo.all(
        # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
        from(a in S.Activity,
          where: a.household_id == ^household_id and a.task == ^number,
          order_by: [a.layer, a.position]
        )
      )

    task = %{
      number: number,
      status: task_status(repo, household_id, number),
      layers:
        rows
        |> Enum.group_by(& &1.layer, & &1.act_id)
        |> Enum.sort()
        |> Enum.map(&elem(&1, 1))
    }

    acts = Map.new(rows, &{&1.act_id, %{id: &1.act_id, status: &1.status}})
    open = QueueGraph.open_layer(task, acts)

    for row <- rows, do: refresh_row(repo, household_id, row, task, acts, at)

    repo.update_all(
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(t in S.Task,
        where: t.household_id == ^household_id and t.number == ^number and t.status == "open"
      ),
      set: [open_layer: open]
    )

    open
  end

  defp refresh_row(repo, household_id, row, task, acts, at) do
    view = Atom.to_string(QueueGraph.view(acts[row.act_id], task, acts))
    ready_at = if view == "ready", do: row.ready_at || at, else: nil

    if view != row.view or ready_at != row.ready_at,
      do:
        repo.update_all(
          # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
          from(a in S.Activity,
            where: a.household_id == ^household_id and a.act_id == ^row.act_id
          ),
          set: [view: view, ready_at: ready_at]
        )
  end

  defp task_status(repo, household_id, number) do
    case repo.one(
           # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
           from(t in S.Task,
             where: t.household_id == ^household_id and t.number == ^number,
             select: t.status
           )
         ) do
      "dropped" -> "dropped"
      _other -> "open"
    end
  end

  defp state(multi, household_id, set),
    do:
      Multi.insert(
        multi,
        :state,
        struct(S.State, [household_id: household_id] ++ set),
        on_conflict: [set: set],
        conflict_target: [:household_id]
      )

  defp imported_note(0), do: nil
  defp imported_note(start), do: "Imported with layers 1–#{start} done, carrying no approvals."

  defp stringify(layers),
    do: Enum.map(layers, fn layer -> Enum.map(layer, &stringify_spec/1) end)

  defp stringify_spec(spec), do: Map.new(spec, fn {k, v} -> {to_string(k), v} end)

  defp who(actor), do: "#{kind(actor)}:#{actor_id(actor)}"

  defp kind(%{kind: kind}), do: to_string(kind)
  defp kind(_none), do: "platform"

  defp actor_id(%{id: id}), do: id
  defp actor_id(_none), do: nil
end
