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

    # Its version counts its definitions (sunna#90): a task records the
    # version it was opened from.
    Multi.insert(
      multi,
      :template,
      struct(S.Template, [household_id: e.id, name: e.name, version: 1] ++ set),
      on_conflict: [set: set, inc: [version: 1]],
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
          name: Queue.get(spec, :name),
          slot: Queue.get(spec, :slot),
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
    |> Multi.run(:template_version, fn repo, _ ->
      version =
        e.template &&
          repo.one(
            # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
            from(t in S.Template,
              where: t.household_id == ^e.id and t.name == ^e.template,
              select: t.version
            )
          )

      {:ok,
       repo.update_all(
         # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
         from(t in S.Task, where: t.household_id == ^e.id and t.number == ^e.number),
         set: [template_version: version]
       )}
    end)
    # Its links are its first documents, sources (sunna#91).
    |> Multi.insert_all(
      :documents,
      S.Document,
      for link <- Enum.uniq_by(List.wrap(e.links), &Queue.doc_key/1) do
        %{
          household_id: e.id,
          task: e.number,
          key: Queue.doc_key(link),
          citation: link,
          role: "source",
          attached_by: who(e.actor),
          attached_at: e.at
        }
      end,
      on_conflict: :nothing,
      conflict_target: [:household_id, :task, :key]
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
    |> act(e, status: "pending", waits_on: nil, reason: nil, approved_pin: nil, note: e.note)
    # A finished activity reopened reopens a completed task (sunna#116).
    |> Multi.update_all(
      :reopened_task,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(t in S.Task,
        where: t.household_id == ^e.id and t.number == ^e.task and t.status == "complete"
      ),
      set: [status: "open", completed_at: nil]
    )
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
      set: [
        status: "pending",
        waits_on: nil,
        reason: nil,
        approved_pin: nil,
        note: e.note,
        updated_at: e.at
      ]
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

  # A task's layers edited (sunna#85): the removed pending rows gone,
  # every kept row at its new layer and place with its spec, the new ones
  # pending; then the views read again.
  fold(%E.LayersEdited{} = e, _metadata, fn multi ->
    removed = List.wrap(e.removed)

    placed =
      for {layer, i} <- Enum.with_index(e.layers), {spec, j} <- Enum.with_index(layer) do
        {spec, i, j}
      end

    multi
    |> Multi.delete_all(
      :removed,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(a in S.Activity, where: a.household_id == ^e.id and a.act_id in ^removed)
    )
    |> Multi.run(:placed, fn repo, _ ->
      for {spec, i, j} <- placed do
        place(repo, e, spec, i, j)
      end

      {:ok, length(placed)}
    end)
    # Its own copy of its template from here on (sunna#90).
    |> Multi.update_all(
      :forked,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(t in S.Task, where: t.household_id == ^e.id and t.number == ^e.task),
      set: [forked: true]
    )
    |> history(e, nil, "layers edited", nil, nil, e.note)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.DocumentAttached{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :document,
      %S.Document{
        household_id: e.id,
        task: e.task,
        key: Queue.doc_key(e.citation),
        citation: e.citation,
        role: e.role,
        attached_by: who(e.actor),
        attached_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :task, :key]
    )
    |> history(e, nil, "document attached", e.role, nil, e.citation)
    |> refresh(e.id, e.task, e.at)
  end)

  fold(%E.DocumentDetached{} = e, _metadata, fn multi ->
    key = Queue.doc_key(e.citation)

    multi
    |> Multi.delete_all(
      :document,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
      from(d in S.Document,
        where: d.household_id == ^e.id and d.task == ^e.task and d.key == ^key
      )
    )
    |> history(e, nil, "document detached", nil, nil, e.citation)
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

  fold(%E.BatchMade{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :batch,
      %S.Batch{household_id: e.id, number: e.number, name: e.name, made_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:household_id, :number]
    )
  end)

  # The arrangement (sunna#103): each entry's rank its place; a batch's
  # tasks ranked within it; a task left out keeps where it was.
  fold(%E.BacklogArranged{} = e, _metadata, fn multi ->
    e.entries
    |> Enum.map(&plain/1)
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {entry, i}, multi -> arrange(multi, e.id, entry, i) end)
  end)

  fold(%E.QueuePaused{} = e, _metadata, fn multi ->
    state(multi, e.id, paused: true, paused_at: e.at, note: e.note)
  end)

  fold(%E.QueueResumed{} = e, _metadata, fn multi ->
    state(multi, e.id, paused: false, paused_at: nil, note: e.note)
  end)

  defp place(repo, e, spec, i, j) do
    id = Queue.get(spec, :id)

    set = [
      layer: i,
      position: j,
      name: Queue.get(spec, :name),
      slot: Queue.get(spec, :slot),
      type: Queue.get(spec, :type),
      assignee: Queue.get(spec, :assignee),
      artifact: Queue.get(spec, :artifact),
      destination: Queue.get(spec, :destination),
      action: Queue.get(spec, :action),
      optional: Queue.get(spec, :optional) == true,
      throwback: Queue.get(spec, :throwback),
      updated_at: e.at
    ]

    repo.insert(
      struct(
        S.Activity,
        [household_id: e.id, act_id: id, task: e.task, status: "pending", view: "waiting"] ++
          set
      ),
      on_conflict: [set: set],
      conflict_target: [:household_id, :act_id]
    )
  end

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

  defp arrange(multi, h, %{"batch" => n, "tasks" => tasks} = entry, i) do
    multi =
      Multi.update_all(
        multi,
        {:batch, n},
        # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
        from(b in S.Batch, where: b.household_id == ^h and b.number == ^n),
        set: [rank: i, open: entry["open"] == true]
      )

    tasks
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {t, j}, multi ->
      place(multi, h, t, batch: n, rank: j, open: false)
    end)
  end

  defp arrange(multi, h, %{"task" => t} = entry, i),
    do: place(multi, h, t, batch: nil, rank: i, open: entry["open"] == true)

  defp arrange(multi, _h, _entry, _i), do: multi

  # An entry as the store gives it back, its keys read as strings.
  defp plain(entry) when is_map(entry), do: Map.new(entry, fn {k, v} -> {to_string(k), v} end)
  defp plain(other), do: other

  defp place(multi, h, t, set),
    do:
      Multi.update_all(
        multi,
        {:place, t},
        # oneiroi:allow projector_scope: the household's id is unique across the store, and every row is within it
        from(x in S.Task, where: x.household_id == ^h and x.number == ^t),
        set: set
      )
end
