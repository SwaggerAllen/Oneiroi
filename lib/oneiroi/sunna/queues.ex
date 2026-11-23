defmodule Oneiroi.Sunna.Queues do
  @moduledoc """
  The house queue's service functions (sunna#80): membership checked
  before any dispatch, templates resolved into a task's layers, and the
  reads the screens and the tools make.

  Every call names the household; the caller is a member of it or is
  refused (`sunna_queue_not_a_member`), and the rows are read under the
  platform scope by name only after that (gaia#17's rule).

  A template becomes a task here (§7): each role made a member (author
  the task's owner, witness the household's first witness, peer the one
  other resident, builder the owner's Claude Code, unknown as written), each artifact
  slot made the citation given or left as `slot:<name>` until it is
  filled, and a deliver by the resident whose Claude Code it is put in
  its own layer in front of every Claude Code activity (§3).
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events.Queue, as: E
  alias Oneiroi.Sunna.Queue
  alias Oneiroi.Sunna.QueueCommands, as: C
  alias Oneiroi.Sunna.QueueGraph
  alias Oneiroi.Sunna.QueueRouter
  alias Oneiroi.Sunna.QueueState
  alias Oneiroi.Sunna.QueueStore, as: S

  # ---- the starter templates (§7) ----

  @doc """
  The templates the platform ships as starting points, by name. None is
  in a household's queue until a member defines it there (the cutover's
  first act, §6.2); `define_template/5` with `from:` copies one.
  """
  def starters do
    %{
      "doc-to-pr" => %{
        title: "A design, reviewed, built",
        layers: [
          [%{name: "Draft the design", type: "draft", role: "author", artifact: "design"}],
          [
            %{
              name: "Witness review",
              type: "review",
              role: "witness",
              artifact: "design",
              destination: "house",
              action: "promote-to-house",
              throwback: "1.1"
            }
          ],
          [
            %{
              name: "Share with the house",
              type: "promote-to-house",
              role: "author",
              artifact: "design",
              destination: "house",
              optional: true
            }
          ],
          [
            %{
              name: "Peer review",
              type: "review",
              role: "peer",
              artifact: "design",
              throwback: "1.1"
            }
          ],
          [%{name: "Build it", type: "implement", role: "builder", artifact: "design"}],
          [
            %{
              name: "PR review",
              type: "review",
              role: "witness",
              artifact: "pr",
              destination: "main",
              action: "merge",
              throwback: "5.1"
            }
          ],
          [%{name: "Merge", type: "merge", role: "witness", artifact: "pr", destination: "main"}]
        ]
      }
    }
  end

  # ---- membership ----

  @doc "The household a member actor is in, or nil."
  def household_of(%Actor{} = actor), do: Gaia.household_of(actor)

  defp member(_household_id, %Actor{kind: :platform}), do: :ok

  defp member(household_id, %Actor{} = actor) do
    if is_binary(household_id) and Gaia.household_member?(household_id, actor),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_a_member, :sunna_queue_not_a_member)}
  end

  @doc "The members as the queue names them: `resident:<id>` or `witness:<id>`, with the house's name for each."
  def members(household_id) do
    for m <- Gaia.household_members(household_id),
        do: %{assignee: "#{m.kind}:#{m.id}", kind: m.kind, id: m.id, name: m.name}
  end

  # ---- commands ----

  @doc "Opens a project: slug, name, and its owner (the caller unless named)."
  def open_project(household_id, attrs, %Actor{} = actor) do
    dispatch(household_id, actor, %C.OpenProject{
      actor: actor,
      at: Clock.now(),
      id: household_id,
      slug: attrs[:slug],
      name: attrs[:name],
      owner: attrs[:owner] || Queue.me(actor)
    })
  end

  @doc "Closes a project, with a note."
  def close_project(household_id, slug, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.CloseProject{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        slug: slug,
        note: note
      })

  @doc """
  Defines a template in the household's queue (§7): `name`, `title` and
  `layers`, or `from:` a starter's name to copy it, its title and layers
  overridable. A later definition of the same name replaces it.
  """
  def define_template(household_id, name, attrs, %Actor{} = actor) do
    base = if attrs[:from], do: starters()[attrs[:from]], else: %{}

    if attrs[:from] && is_nil(base) do
      {:error, Error.new(:sunna_queue_no_such_template, :sunna_queue_define_no_starter)}
    else
      dispatch(household_id, actor, %C.DefineTemplate{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        name: name,
        title: attrs[:title] || base[:title],
        layers: attrs[:layers] || base[:layers]
      })
    end
  end

  @doc """
  Opens a task, returning its number. `attrs`:

  - `project`, `slug`, `title`, `outcome`; `owner` (the caller unless named);
  - `template`: a template's name in this household, or `layers` given
    whole (a template modified, or none);
  - `roles`: overrides, role → assignee; `slots`: artifact slot → citation;
  - `start_layer` (1-based, as the screens count) and `links`, for work
    moved in part-way (§6.2): every earlier layer imported done.
  """
  def open_task(household_id, attrs, %Actor{} = actor) do
    owner = attrs[:owner] || Queue.me(actor)

    with :ok <- member(household_id, actor),
         {:ok, layers} <- layers_for(household_id, attrs, owner) do
      command = %C.OpenTask{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        project: attrs[:project],
        slug: attrs[:slug],
        title: attrs[:title],
        outcome: attrs[:outcome],
        owner: owner,
        index: nil,
        template: attrs[:template],
        layers: layers,
        start_layer: start(attrs[:start_layer], layers),
        links: List.wrap(attrs[:links])
      }

      with {:ok, events} <- send_command(command) do
        {:ok, Enum.find_value(events, &(match?(%E.TaskOpened{}, &1) && &1.number))}
      end
    end
  end

  # The start layer as the screens count it, 1-based, moved past the
  # deliver layers this module inserted in front of claude-code's.
  defp start(nil, _layers), do: 0

  defp start(n, layers) when is_integer(n) and n >= 1 do
    originals = for {layer, i} <- Enum.with_index(layers), not inserted?(layer), do: i

    # A start that names a claude-code layer starts at its deliver.
    case Enum.at(originals, n - 1) do
      nil -> -1
      i -> if i > 0 and inserted?(Enum.at(layers, i - 1)), do: i - 1, else: i
    end
  end

  defp start(_other, _layers), do: -1

  defp inserted?(layer), do: Enum.all?(layer, &(&1[:inserted] == true))

  @doc "Takes an activity (§2.3): it goes active, an `unknown` one becoming the taker's. `head:` the artifact's head read now."
  def take(household_id, task, act, %Actor{} = actor, opts \\ []),
    do:
      dispatch(household_id, actor, %C.TakeActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        head: opts[:head]
      })

  @doc "Finishes an activity: `pin` the revision acted on, `head` the artifact's head now, `result` a citation of what it made, `note`."
  def finish(household_id, task, act, attrs, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.FinishActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        pin: attrs[:pin],
        head: attrs[:head],
        result: attrs[:result],
        note: attrs[:note],
        promoted: attrs[:promoted]
      })

  @doc "Skips an activity explicitly, with a note (§7)."
  def skip(household_id, task, act, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.SkipActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        note: note
      })

  @doc "Blocks an activity with a reason, waiting on another task's completion when `waits_on` names it."
  def block(household_id, task, act, reason, waits_on, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.BlockActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        reason: reason,
        waits_on: waits_on
      })

  @doc "Reopens a blocked or failed activity by hand, with a note."
  def reopen(household_id, task, act, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.ReopenActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        note: note
      })

  @doc "Marks an activity failed, saying what failed; it keeps its place and assignee."
  def fail(household_id, task, act, what, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.FailActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        what: what
      })

  @doc "Assigns an activity to a member, a resident's Claude Code or unknown, with an optional note."
  def assign(household_id, task, act, assignee, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.AssignActivity{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        assignee: assignee,
        note: note
      })

  @doc """
  Decides a review (§7): `outcome` approved, changes or declined; `pin`
  the revision read and `head` its head now; `return_to` for a refusal
  (the template's default when left out); `withhold` an approval that
  keeps the artifact where it is; `note`, required.
  """
  def decide(household_id, task, act, attrs, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.DecideReview{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        act: act,
        outcome: attrs[:outcome],
        pin: attrs[:pin],
        head: attrs[:head],
        return_to: attrs[:return_to],
        withhold: attrs[:withhold] == true,
        note: attrs[:note]
      })

  @doc "Fills an artifact slot a template left open (`slot:<name>`) with its citation, on every activity holding it."
  def fill_slot(household_id, task, slot, artifact, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.FillSlot{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        slot: slot,
        artifact: artifact
      })

  @doc """
  Edits an open task's layers (sunna#85): `layers` the whole new
  arrangement, each entry an existing activity by `id` (with fields to
  change while it is pending) or a new activity's spec; the owner's or a
  witness's, with a note.
  """
  def edit_layers(household_id, task, layers, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.EditLayers{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        layers: layers,
        note: note
      })

  @doc "Attaches a document to a task (sunna#91): `role` a slot name or `source` (the default)."
  def attach_document(household_id, task, citation, role, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.AttachDocument{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        citation: citation,
        role: role
      })

  @doc "Detaches a document attached to a task (sunna#91)."
  def detach_document(household_id, task, citation, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.DetachDocument{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        citation: citation
      })

  @doc """
  Each task's documents (sunna#91), by task number: the documents its
  activities work on, each under its slot's name (an unfilled slot with
  no citation), then those attached to it, one per document (its path
  without the pin).
  """
  def documents(household_id, numbers) when is_list(numbers) do
    Scope.platform(fn ->
      acts =
        Repo.all(
          from(a in S.Activity,
            where: a.household_id == ^household_id and a.task in ^numbers,
            order_by: [a.task, a.layer, a.position],
            select: {a.task, a.slot, a.artifact}
          )
        )

      attached =
        Repo.all(
          from(d in S.Document,
            where: d.household_id == ^household_id and d.task in ^numbers,
            order_by: [d.task, d.attached_at],
            select: {d.task, d.role, d.citation}
          )
        )

      (Enum.map(acts, &worked_on/1) ++ Enum.map(attached, &attached_doc/1))
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {n, docs} -> {n, Enum.uniq_by(docs, & &1.key)} end)
    end)
  end

  defp worked_on({_task, _slot, nil}), do: nil

  defp worked_on({task, slot, "slot:" <> name}),
    do: {task, %{role: slot || name, citation: nil, key: "slot:" <> name, attached: false}}

  defp worked_on({task, slot, artifact}),
    do:
      {task,
       %{
         role: slot || "worked on",
         citation: artifact,
         key: Queue.doc_key(artifact),
         attached: false
       }}

  defp attached_doc({task, role, citation}),
    do: {task, %{role: role, citation: citation, key: Queue.doc_key(citation), attached: true}}

  @doc """
  The open tasks a document belongs to (sunna#91), by its citation with
  or without a pin: attached to it, or worked on by one of its
  activities. Each `%{number, title, project}`.
  """
  def tasks_for_document(household_id, citation) do
    key = Queue.doc_key(to_string(citation))

    Scope.platform(fn ->
      attached =
        from(d in S.Document,
          where: d.household_id == ^household_id and d.key == ^key,
          select: d.task
        )

      worked =
        from(a in S.Activity,
          where:
            a.household_id == ^household_id and
              (a.artifact == ^key or like(a.artifact, ^(key <> "@%"))),
          select: a.task
        )

      numbers = Repo.all(attached) ++ Repo.all(worked)

      Repo.all(
        from(t in S.Task,
          where: t.household_id == ^household_id and t.number in ^Enum.uniq(numbers),
          order_by: [desc: t.status == "open", desc: t.number],
          select: %{number: t.number, title: t.title, project: t.project, status: t.status}
        )
      )
    end)
  end

  @doc "Drops a task, with a note: it counts as complete, releasing what waits on it (§1)."
  def drop(household_id, task, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.DropTask{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        task: task,
        note: note
      })

  @doc "Turns the house queue on (§6.2), naming the commit that holds the old queue: a witness's."
  def cut_over(household_id, commit, note, %Actor{} = actor) do
    with :ok <-
           dispatch(household_id, actor, %C.CutOver{
             actor: actor,
             at: Clock.now(),
             id: household_id,
             commit: commit,
             note: note
           }) do
      # Each resident's old loop checks once, finds the house queue on,
      # turns its line off and rests saying why.
      for %{kind: "resident", id: id} <- members(household_id),
          do: work_worker().enqueue_check(id)

      :ok
    end
  end

  @doc "The one-step revert (§6.2): the old queue's screens and loop back on over its untouched rows."
  def cut_back(household_id, note, %Actor{} = actor),
    do:
      dispatch(household_id, actor, %C.CutBack{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        note: note
      })

  defp dispatch(household_id, actor, command) do
    with :ok <- member(household_id, actor),
         {:ok, events} <- send_command(command),
         do: outcome(events)
  end

  # An approval that lapsed is recorded, and the move it stopped is
  # refused, saying why (Scarlett's first guard).
  defp outcome(events) do
    case Enum.find(events, &match?(%E.ApprovalLapsed{}, &1)) do
      nil ->
        :ok

      lapse ->
        {:error,
         Error.new(:sunna_queue_review_required, :sunna_queue_approval_lapsed,
           detail:
             "the artifact moved from #{lapse.approved_pin} to #{lapse.head} after its review approved it; review #{lapse.act} is open again"
         )}
    end
  end

  defp send_command(command) do
    case QueueRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:sunna_queue_dispatch_failed, :sunna_queue_dispatch_failed, reason)}
    end
  end

  # Named at the call, as the loop names it: the worker runs the loop,
  # which reads this module, so an alias would be a cycle.
  defp work_worker, do: Module.concat([Oneiroi, Sunna, WorkWorker])

  # ---- a template made a task's layers ----

  defp layers_for(household_id, attrs, owner) do
    case {attrs[:layers], attrs[:template]} do
      {layers, _} when is_list(layers) ->
        {:ok, route_claude_code(layers)}

      {nil, name} when is_binary(name) ->
        case template(household_id, name) do
          nil ->
            {:error, Error.new(:sunna_queue_no_such_template, :sunna_queue_task_template)}

          t ->
            household_id
            |> resolve(t.layers["layers"], owner, attrs[:roles] || %{}, attrs[:slots] || %{})
            |> then(&{:ok, route_claude_code(&1)})
        end

      _neither ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_task_no_layers)}
    end
  end

  # Roles made members and slots made citations (§7).
  defp resolve(household_id, layers, owner, roles, slots) do
    members = members(household_id)

    defaults = %{
      "author" => owner,
      "witness" => first(members, "witness"),
      "peer" => peer(members, owner),
      "builder" => claude_code(owner),
      "unknown" => "unknown"
    }

    roles = Map.merge(defaults, Map.new(roles, fn {k, v} -> {to_string(k), v} end))
    slots = Map.new(slots, fn {k, v} -> {to_string(k), v} end)

    for layer <- layers do
      for spec <- layer do
        slot = Queue.get(spec, :artifact)

        %{
          name: Queue.get(spec, :name),
          slot: slot,
          type: Queue.get(spec, :type),
          assignee: roles[Queue.get(spec, :role)] || "unknown",
          artifact: slot && (slots[slot] || "slot:#{slot}"),
          destination: Queue.get(spec, :destination),
          action: Queue.get(spec, :action),
          optional: Queue.get(spec, :optional) == true,
          throwback: Queue.get(spec, :throwback)
        }
      end
    end
  end

  defp first(members, kind),
    do: Enum.find_value(members, "unknown", &(&1.kind == kind && &1.assignee))

  # The peer: the one other resident when there is exactly one.
  defp peer(members, owner) do
    case for(m <- members, m.kind == "resident", m.assignee != owner, do: m.assignee) do
      [one] -> one
      _none_or_many -> "unknown"
    end
  end

  # The owner's Claude Code when the owner is a resident (§3): it runs on
  # her memories. A witness-owned task names its builder in `roles`.
  defp claude_code("resident:" <> id), do: "claude-code:" <> id
  defp claude_code(_other), do: "unknown"

  # A deliver by the resident whose Claude Code it is, in its own layer
  # before every layer holding Claude Code work (§3), throwbacks
  # renumbered past it.
  defp route_claude_code(layers) do
    {out, shifts} =
      layers
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{}}, &route_layer/2)

    Enum.map(out, fn layer -> Enum.map(layer, &renumber_throwback(&1, shifts)) end)
  end

  defp route_layer({layer, i}, {acc, shifts}) do
    layer = Enum.map(layer, &Map.new(&1, fn {k, v} -> {atom(k), v} end))
    shifts = Map.put(shifts, i, length(acc) + 1)

    case for(a <- layer, hers = Queue.claude_code_of(a[:assignee]), do: {a, hers}) do
      [] ->
        {acc ++ [layer], shifts}

      theirs ->
        deliver =
          for {a, hers} <- theirs,
              do: %{
                name: "Hand to Claude Code",
                type: "deliver",
                assignee: hers,
                artifact: a[:artifact],
                slot: a[:slot],
                inserted: true
              }

        {acc ++ [deliver, layer], Map.put(shifts, i, length(acc) + 2)}
    end
  end

  defp renumber_throwback(a, shifts) do
    case a[:throwback] do
      pos when is_binary(pos) -> %{a | throwback: renumber(pos, shifts)}
      _none -> a
    end
  end

  defp renumber(pos, shifts) do
    with [l, j] <- String.split(pos, "."),
         {l, ""} <- Integer.parse(l),
         %{^l => moved} <- shifts do
      "#{moved}.#{j}"
    else
      _ -> pos
    end
  end

  @known ~w(type assignee artifact destination action optional throwback inserted role id)a
  defp atom(k) when is_atom(k), do: k

  defp atom(k) when is_binary(k),
    do: Enum.find(@known, k, &(Atom.to_string(&1) == k))

  # ---- reads ----

  @doc "The queue's state: cut over or not, and the commit that holds the old queue."
  def state(household_id), do: QueueState.get(household_id)

  @doc "Whether the household has cut over to the house queue (§6.2)."
  def cut_over?(household_id), do: QueueState.cut_over?(household_id)

  @doc "The household's projects, open first, then by name."
  def projects(household_id) do
    Scope.platform(fn ->
      Repo.all(
        from(p in S.Project,
          where: p.household_id == ^household_id,
          order_by: [desc: p.status == "open", asc: p.name]
        )
      )
    end)
  end

  @doc "The household's templates by name."
  def templates(household_id) do
    Scope.platform(fn ->
      Repo.all(from(t in S.Template, where: t.household_id == ^household_id, order_by: t.name))
    end)
  end

  @doc "One template, or nil."
  def template(household_id, name) do
    Scope.platform(fn -> Repo.get_by(S.Template, household_id: household_id, name: name) end)
  end

  @doc "The tasks, open first and newest first, optionally of one project."
  def tasks(household_id, opts \\ []) do
    Scope.platform(fn ->
      query =
        from(t in S.Task,
          where: t.household_id == ^household_id,
          order_by: [desc: t.status == "open", desc: t.number]
        )

      query =
        case opts[:project] do
          nil -> query
          slug -> from(t in query, where: t.project == ^slug)
        end

      Repo.all(query)
    end)
  end

  @doc """
  One task as its page reads it (§2.4): the task, its layers of
  activities in order, its history oldest first, and what waits on it
  (activities in other tasks blocked on its completion). Nil when none.
  """
  def task(household_id, number) do
    Scope.platform(fn ->
      case Repo.get_by(S.Task, household_id: household_id, number: number) do
        nil ->
          nil

        task ->
          acts =
            Repo.all(
              from(a in S.Activity,
                where: a.household_id == ^household_id and a.task == ^number,
                order_by: [a.layer, a.position]
              )
            )

          history =
            Repo.all(
              from(h in S.History,
                where: h.household_id == ^household_id and h.task == ^number,
                order_by: [h.at, h.id]
              )
            )

          waiting =
            Repo.all(
              from(a in S.Activity,
                where:
                  a.household_id == ^household_id and a.waits_on == ^number and
                    a.status == "blocked"
              )
            )

          %{
            task: task,
            layers: acts |> Enum.group_by(& &1.layer) |> Enum.sort() |> Enum.map(&elem(&1, 1)),
            history: history,
            waiting: waiting
          }
      end
    end)
  end

  @doc """
  The activities matching a filter (§2.1): `who` an assignee, "anyone" or
  "unknown"; `views` a list of views (ready, waiting, active, blocked,
  failed, done, skipped); `project` a slug. Each with its task's title,
  project and number, and, when blocked on a task, that task's title, its
  next action and whose it is (Scarlett's guard: blockers shown plainly).
  """
  def activities(household_id, filter \\ %{}) do
    Scope.platform(fn ->
      query =
        from(a in S.Activity,
          join: t in S.Task,
          on: t.household_id == a.household_id and t.number == a.task,
          where: a.household_id == ^household_id and t.status == "open",
          order_by: [a.task, a.layer, a.position],
          select: {a, t}
        )

      query =
        query
        |> by_who(filter[:who])
        |> by_views(filter[:views])
        |> by_project(filter[:project])

      rows = Repo.all(query)
      blockers = blockers(household_id, rows)
      Enum.map(rows, fn {a, t} -> card(a, t, blockers) end)
    end)
  end

  defp by_who(query, nil), do: query
  defp by_who(query, "anyone"), do: query
  defp by_who(query, who), do: from([a, _t] in query, where: a.assignee == ^who)

  defp by_views(query, views) when is_list(views) and views != [],
    do: from([a, _t] in query, where: a.view in ^views)

  defp by_views(query, _all), do: query

  defp by_project(query, nil), do: query
  defp by_project(query, slug), do: from([_a, t] in query, where: t.project == ^slug)

  @doc """
  **Waiting on me** (§2.2): the viewer's ready activities, reviews among
  them, ordered blocking-most first (what the next layer holds behind it
  plus what other tasks wait on its task), then oldest ready first; and,
  collapsed below, the viewer's not ready (later layer or blocked, each
  naming what it waits on), and the tasks the viewer owns with their next
  action.
  """
  def waiting_on(household_id, who) do
    mine = activities(household_id, %{who: who})
    {ready, rest} = Enum.split_with(mine, &(&1.view in ["ready", "active"]))

    weights = weights(household_id)

    ready =
      Enum.sort_by(ready, fn c ->
        {-Map.get(weights, {c.task, c.layer}, 0), c.ready_at || ~U[2100-01-01 00:00:00Z]}
      end)

    later = Enum.filter(rest, &(&1.view in ["waiting", "blocked", "failed"]))

    owned =
      for t <- tasks(household_id), t.status == "open", t.owner == who do
        %{task: t, next: next_action(household_id, t)}
      end

    %{ready: ready, later: later, owned: owned}
  end

  # How much stands behind an activity: the next layer's size, plus the
  # activities in other tasks blocked on its task.
  defp weights(household_id) do
    Scope.platform(fn ->
      acts =
        Repo.all(
          from(a in S.Activity,
            join: t in S.Task,
            on: t.household_id == a.household_id and t.number == a.task,
            where: a.household_id == ^household_id and t.status == "open",
            select: %{task: a.task, layer: a.layer, waits_on: a.waits_on, status: a.status}
          )
        )

      per_layer = Enum.frequencies_by(acts, &{&1.task, &1.layer})

      waits =
        acts
        |> Enum.filter(&(&1.status == "blocked" and is_integer(&1.waits_on)))
        |> Enum.frequencies_by(& &1.waits_on)

      for {{task, layer}, _} <- per_layer, into: %{} do
        {{task, layer}, Map.get(per_layer, {task, layer + 1}, 0) + Map.get(waits, task, 0)}
      end
    end)
  end

  @doc "A task's next action: the first ready or active activity of its open layer, with whose it is; nil when none."
  def next_action(household_id, %S.Task{} = t) do
    Scope.platform(fn ->
      Repo.one(
        from(a in S.Activity,
          where:
            a.household_id == ^household_id and a.task == ^t.number and
              a.view in ["ready", "active", "blocked", "failed"],
          order_by: [a.layer, a.position],
          limit: 1
        )
      )
    end)
  end

  defp blockers(household_id, rows) do
    numbers =
      for {a, _t} <- rows,
          a.status == "blocked",
          is_integer(a.waits_on),
          uniq: true,
          do: a.waits_on

    for n <- numbers, t = Repo.get_by(S.Task, household_id: household_id, number: n), into: %{} do
      {n,
       %{
         number: n,
         title: t.title,
         project: t.project,
         status: t.status,
         next: plain(next_action(household_id, t))
       }}
    end
  end

  defp plain(nil), do: nil
  defp plain(row), do: row |> Map.from_struct() |> Map.delete(:__meta__)

  defp card(a, t, blockers) do
    %{
      act: a.act_id,
      task: a.task,
      layer: a.layer,
      position: a.position,
      name: a.name,
      type: a.type,
      assignee: a.assignee,
      status: a.status,
      view: a.view,
      gated: a.type in QueueGraph.gated_types(),
      artifact: a.artifact,
      destination: a.destination,
      action: a.action,
      optional: a.optional,
      throwback: a.throwback,
      waits_on: a.waits_on,
      blocker: a.waits_on && blockers[a.waits_on],
      reason: a.reason,
      pin: a.pin,
      approved_pin: a.approved_pin,
      note: a.note,
      ready_at: a.ready_at,
      updated_at: a.updated_at,
      task_title: t.title,
      project: t.project,
      owner: t.owner
    }
  end

  @doc "The activities assigned to an assignee that are ready or hold a review for them, for the bell (§2.5)."
  def for_bell(household_id, who) do
    activities(household_id, %{who: who, views: ["ready"]})
  end
end
