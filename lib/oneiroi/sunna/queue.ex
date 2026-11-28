defmodule Oneiroi.Sunna.Queue do
  @moduledoc """
  The house queue aggregate (sunna#80, lily:design/queue-ia rev 5), on
  `queue-<household_id>`: projects → tasks → layered activities, one
  queue a household, every member's.

  The rules are `Oneiroi.Sunna.QueueGraph`'s (layers, completion, cycles,
  the shape rule); this module holds the state they read and the
  permissions:

  - an activity is worked (taken, finished, blocked, failed) by its
    assignee, the task's owner or a witness; an `unknown` one by whoever
    takes it, and a resident's Claude Code one (`claude-code:<id>`) by
    that resident, whose memories it runs on (§3), once she has handed it
    off to it (sunna#117);
  - a review is decided by its assignee alone, since the decision is the
    authorization (§6.1);
  - an activity is skipped by the task's owner, or by its assignee when
    the template declared it optional (§7), and a review standing in front
    of a live gated activity is never skipped;
  - a task is dropped by its owner or a witness.

  Scarlett's guards (her revision-3 review): a gated activity runs only on
  the pin its review approved, re-read at execution, and a head that moved
  lapses the approval (1); a task imported part-way carries no approval,
  so it cannot start at a gated layer (3); blocks refuse cycles at any
  length (4). Promotion's own audience check (2) is the library's, run by
  the caller before it finishes a `promote-to-house`.
  """

  import Kernel, except: [apply: 2]

  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events.Queue, as: E
  alias Oneiroi.Sunna.QueueCommands, as: C
  alias Oneiroi.Sunna.QueueGraph, as: G

  defstruct projects: %{},
            templates: %{},
            next_task: 1,
            tasks: %{},
            acts: %{},
            cut_over: false,
            paused: false,
            batches: %{},
            next_batch: 1

  @outcomes ~w(approved changes declined)
  @spec_fields [
    :name,
    :slot,
    :type,
    :assignee,
    :artifact,
    :destination,
    :action,
    :optional,
    :throwback
  ]
  @name 80
  @words 4_000
  @verb 40

  # ---- projects and templates ----

  def execute(%__MODULE__{} = s, %C.OpenProject{} = c) do
    cond do
      not slug?(c.slug) or not words?(c.name, 120) or not assignee?(c.owner) ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_project_invalid)}

      Map.has_key?(s.projects, c.slug) ->
        {:error, Error.new(:sunna_queue_project_exists, :sunna_queue_project_exists)}

      true ->
        %E.ProjectOpened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          slug: c.slug,
          name: String.trim(c.name),
          owner: c.owner
        }
    end
  end

  def execute(%__MODULE__{} = s, %C.CloseProject{} = c) do
    case s.projects[c.slug] do
      %{status: "open"} ->
        %E.ProjectClosed{actor: c.actor, at: c.at, id: c.id, slug: c.slug, note: c.note}

      _none ->
        {:error, Error.new(:sunna_queue_no_such_project, :sunna_queue_close_unknown)}
    end
  end

  def execute(%__MODULE__{}, %C.DefineTemplate{} = c) do
    case template_layers(c.layers) do
      {:ok, layers} ->
        if slug?(c.name) and words?(c.title, 120),
          do: %E.TemplateDefined{
            actor: c.actor,
            at: c.at,
            id: c.id,
            name: c.name,
            title: String.trim(c.title),
            layers: layers
          },
          else: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_template_invalid)}

      :shape ->
        {:error, Error.new(:sunna_queue_shape, :sunna_queue_template_shape)}

      :error ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_template_layers)}
    end
  end

  # ---- tasks ----

  def execute(%__MODULE__{} = s, %C.OpenTask{} = c) do
    n = s.next_task

    with :ok <- task_head_ok(s, c),
         {:ok, layers} <- task_layers(n, c.layers),
         :ok <- task_shape_ok(layers, c.start_layer),
         true <-
           builders_ok?(List.flatten(layers), c.builders) ||
             {:error, Error.new(:sunna_queue_builder_required, :sunna_queue_task_builder)} do
      %E.TaskOpened{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: n,
        project: c.project,
        slug: c.slug,
        title: String.trim(c.title),
        outcome: String.trim(c.outcome),
        owner: c.owner,
        index: c.index || "tasks/#{c.project}/#{c.slug}.md",
        template: c.template,
        layers: layers,
        start_layer: c.start_layer || 0,
        links: List.wrap(c.links)
      }
    end
  end

  def execute(%__MODULE__{} = s, %C.EditLayers{} = c) do
    with {:ok, task} <- open_task(s, c.task),
         :ok <- may_edit(task, c.actor),
         {:ok, layers, removed} <- edited_layers(s, task, c.layers),
         :ok <- edited_shape_ok(layers),
         true <-
           builders_ok?(changed_holders(s, layers), c.builders) ||
             {:error, Error.new(:sunna_queue_builder_required, :sunna_queue_edit_builder)} do
      edited = %E.LayersEdited{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        layers: layers,
        removed: removed,
        note: c.note
      }

      completing(s, [edited], c)
    end
  end

  def execute(%__MODULE__{} = s, %C.DropTask{} = c) do
    with {:ok, task} <- open_task(s, c.task),
         :ok <- owner_or_witness(task, c.actor) do
      dropped = %E.TaskDropped{actor: c.actor, at: c.at, id: c.id, task: c.task, note: c.note}
      [dropped | releases(follow(s, [dropped]), c.task, "dropped", c)]
    end
  end

  # ---- activities ----

  def execute(%__MODULE__{} = s, %C.TakeActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- ready(s, task, act),
         :ok <- may_work(task, act, c.actor) do
      unless_lapsed(lapsed(s, task, act, c.head, c), fn -> taken(act, c) end)
    end
  end

  def execute(%__MODULE__{} = s, %C.FinishActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- live(s, task, act),
         :ok <- not_review(act),
         :ok <- promoted(act, c.promoted),
         :ok <- may_work(task, act, c.actor),
         :ok <- optional_words(c.note) do
      unless_lapsed(lapsed(s, task, act, c.head, c), fn -> finished(s, task, act, c) end)
    end
  end

  def execute(%__MODULE__{} = s, %C.SkipActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- unfinished(act),
         :ok <- may_skip(task, act, c.actor),
         :ok <- not_guarding(s, task, act) do
      skipped = %E.ActivitySkipped{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        note: c.note
      }

      completing(s, [skipped], c)
    end
  end

  def execute(%__MODULE__{} = s, %C.BlockActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- blockable(act),
         :ok <- may_work(task, act, c.actor),
         :ok <- reason_ok(c.reason),
         :ok <- block_ok(s, task, c.waits_on) do
      blocked = %E.ActivityBlocked{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        reason: String.trim(c.reason),
        waits_on: c.waits_on
      }

      # A target already complete clears the block at once (§1).
      if is_integer(c.waits_on) and G.complete?(s.tasks[c.waits_on], s.acts),
        do: [blocked, released(c, c.task, c.act, c.waits_on, status_of(s.tasks[c.waits_on]))],
        else: blocked
    end
  end

  def execute(%__MODULE__{} = s, %C.ReopenActivity{} = c) do
    with {:ok, task, act} <- any_activity(s, c.task, c.act),
         :ok <- may_reopen(s, task, act, c.actor) do
      %E.ActivityReopened{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        released: false,
        note: c.note
      }
    end
  end

  def execute(%__MODULE__{} = s, %C.FailActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- live(s, task, act),
         :ok <- may_work(task, act, c.actor),
         :ok <- reason_ok(c.what) do
      %E.ActivityFailed{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        what: String.trim(c.what)
      }
    end
  end

  def execute(%__MODULE__{} = s, %C.AssignActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- unfinished(act),
         :ok <- may_assign(task, act, c.actor),
         :ok <- assignee_ok(act, c.assignee, c.builders),
         :ok <- optional_words(c.note) do
      %E.ActivityAssigned{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        assignee: c.assignee,
        note: c.note && String.trim(c.note)
      }
    end
  end

  def execute(%__MODULE__{} = s, %C.HandOffActivity{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- hand_off_ok(s, task, act, c.actor) do
      %E.ActivityHandedOff{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        note: c.note
      }
    end
  end

  # The pull request merged (sunna#118): at the approved head the review
  # is done; at another, what merged was never approved, and the review
  # is blocked for a person to settle.
  def execute(%__MODULE__{} = s, %C.SettleMerge{} = c) do
    with {:ok, _task, act} <- activity(s, c.task, c.act),
         :ok <- platform_only(c.actor),
         :ok <- awaiting_merge(act) do
      if is_binary(c.sha) and is_binary(act.approved_pin) and same_pin?(c.sha, act.approved_pin) do
        completing(
          s,
          [
            %E.MergeSettled{
              actor: c.actor,
              at: c.at,
              id: c.id,
              task: c.task,
              act: c.act,
              sha: c.sha
            }
          ],
          c
        )
      else
        %E.ActivityBlocked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          task: c.task,
          act: c.act,
          reason:
            "the pull request merged at #{short(c.sha)}, not at #{short(act.approved_pin)}, the revision approved; reopen the review to approve what merged, or skip it",
          waits_on: nil
        }
      end
    end
  end

  def execute(%__MODULE__{} = s, %C.DecideReview{} = c) do
    with {:ok, task, act} <- activity(s, c.task, c.act),
         :ok <- review(act),
         :ok <- live(s, task, act),
         :ok <- reviewer(act, c.actor),
         :ok <- outcome_ok(c.outcome),
         :ok <- seen_ok(act, c.pin, c.head) do
      decide(s, task, act, c)
    end
  end

  def execute(%__MODULE__{} = s, %C.AttachDocument{} = c) do
    citation = blank_nil(c.citation)
    role = blank_nil(c.role) || "source"

    with {:ok, task} <- open_task(s, c.task),
         :ok <- may_attach(task, s, c.actor) do
      cond do
        not words?(citation, 300) or not words?(role, 64) or
            String.starts_with?(citation, "slot:") ->
          {:error, Error.new(:sunna_queue_invalid, :sunna_queue_attach_invalid)}

        Map.has_key?(Map.get(task, :documents, %{}), doc_key(citation)) ->
          []

        true ->
          %E.DocumentAttached{
            actor: c.actor,
            at: c.at,
            id: c.id,
            task: c.task,
            citation: citation,
            role: role
          }
      end
    end
  end

  def execute(%__MODULE__{} = s, %C.DetachDocument{} = c) do
    with {:ok, task} <- open_task(s, c.task),
         :ok <- may_attach(task, s, c.actor) do
      if Map.has_key?(Map.get(task, :documents, %{}), doc_key(to_string(c.citation))),
        do: %E.DocumentDetached{
          actor: c.actor,
          at: c.at,
          id: c.id,
          task: c.task,
          citation: c.citation
        },
        else: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_detach_absent)}
    end
  end

  def execute(%__MODULE__{} = s, %C.FillSlot{} = c) do
    slot = "slot:#{c.slot}"

    with {:ok, task} <- open_task(s, c.task) do
      held = for layer <- task.layers, id <- layer, s.acts[id].artifact == slot, do: id
      mine = me(c.actor)

      cond do
        held == [] ->
          {:error, Error.new(:sunna_queue_no_such_activity, :sunna_queue_fill_no_slot)}

        not words?(c.artifact, 300) or String.starts_with?(c.artifact, "slot:") ->
          {:error, Error.new(:sunna_queue_invalid, :sunna_queue_fill_invalid)}

        c.actor.kind != :witness and mine != task.owner and
            not Enum.any?(held, &(s.acts[&1].assignee == mine)) ->
          {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_fill_not_yours)}

        true ->
          %E.SlotFilled{
            actor: c.actor,
            at: c.at,
            id: c.id,
            task: c.task,
            slot: c.slot,
            artifact: String.trim(c.artifact),
            acts: held
          }
      end
    end
  end

  # ---- the backlog (sunna#103) ----

  # Batches are numbered in the order they are made; a witness's.
  def execute(%__MODULE__{next_batch: n}, %C.MakeBatch{actor: %{kind: :witness}} = c) do
    name = if is_binary(c.name) and String.trim(c.name) != "", do: String.trim(c.name)
    %E.BatchMade{actor: c.actor, at: c.at, id: c.id, number: n, name: name}
  end

  def execute(%__MODULE__{}, %C.MakeBatch{}),
    do: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_batch_witness_only)}

  # The whole arrangement at once, a witness's: every entry a known task
  # or a made batch, each task in it once.
  def execute(%__MODULE__{} = s, %C.ArrangeBacklog{actor: %{kind: :witness}} = c) do
    case arranged(s, c.entries) do
      {:ok, entries} ->
        %E.BacklogArranged{actor: c.actor, at: c.at, id: c.id, entries: entries}

      :error ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_backlog_entries)}
    end
  end

  def execute(%__MODULE__{}, %C.ArrangeBacklog{}),
    do: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_backlog_witness_only)}

  # The house queue's switch (sunna#94): a witness's, said with a note;
  # pausing what is paused, or resuming what runs, is nothing.
  def execute(%__MODULE__{paused: false}, %C.PauseQueue{actor: %{kind: :witness}} = c),
    do: %E.QueuePaused{actor: c.actor, at: c.at, id: c.id, note: c.note}

  def execute(%__MODULE__{paused: true}, %C.ResumeQueue{actor: %{kind: :witness}} = c),
    do: %E.QueueResumed{actor: c.actor, at: c.at, id: c.id, note: c.note}

  def execute(%__MODULE__{}, %C.PauseQueue{actor: %{kind: :witness}}), do: []
  def execute(%__MODULE__{}, %C.ResumeQueue{actor: %{kind: :witness}}), do: []

  def execute(%__MODULE__{}, %C.PauseQueue{}),
    do: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_pause_witness_only)}

  def execute(%__MODULE__{}, %C.ResumeQueue{}),
    do: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_resume_witness_only)}

  # ---- apply ----

  def apply(%__MODULE__{} = s, %E.ProjectOpened{} = e),
    do: %{s | projects: Map.put(s.projects, e.slug, %{status: "open", owner: e.owner})}

  def apply(%__MODULE__{} = s, %E.ProjectClosed{} = e),
    do: %{s | projects: Map.update!(s.projects, e.slug, &%{&1 | status: "closed"})}

  def apply(%__MODULE__{} = s, %E.TemplateDefined{} = e),
    do: %{s | templates: Map.put(s.templates, e.name, e.layers)}

  def apply(%__MODULE__{} = s, %E.TaskOpened{} = e) do
    start = e.start_layer || 0

    layers =
      Enum.map(e.layers, fn layer -> Enum.map(layer, &get(&1, :id)) end)

    acts =
      for {layer, i} <- Enum.with_index(e.layers), spec <- layer, into: s.acts do
        act = activity_from(spec, e.number, i < start)
        {act.id, act}
      end

    task = %{
      number: e.number,
      status: "open",
      layers: layers,
      owner: e.owner,
      project: e.project,
      slug: e.slug,
      next_k: next_k(layers)
    }

    %{s | next_task: e.number + 1, tasks: Map.put(s.tasks, e.number, task), acts: acts}
  end

  def apply(%__MODULE__{} = s, %E.LayersEdited{} = e) do
    acts = Map.drop(s.acts, List.wrap(e.removed))

    acts =
      for layer <- e.layers, spec <- layer, into: acts do
        id = get(spec, :id)

        act =
          case acts[id] do
            nil -> activity_from(spec, e.task, false)
            old -> edited_act(old, activity_from(spec, e.task, false))
          end

        {id, act}
      end

    layers = Enum.map(e.layers, fn layer -> Enum.map(layer, &get(&1, :id)) end)
    given = next_k(layers ++ [List.wrap(e.removed)])

    %{
      s
      | acts: acts,
        tasks:
          Map.update!(s.tasks, e.task, fn t ->
            %{t | layers: layers} |> Map.put(:next_k, max(Map.get(t, :next_k) || 0, given))
          end)
    }
  end

  def apply(%__MODULE__{} = s, %E.ActivityTaken{} = e),
    do: put_act(s, e.act, status: "active", assignee: e.assignee)

  def apply(%__MODULE__{} = s, %E.ActivityDone{} = e),
    do: put_act(s, e.act, status: "done", waits_on: nil)

  def apply(%__MODULE__{} = s, %E.ActivitySkipped{} = e),
    do: put_act(s, e.act, status: "skipped", waits_on: nil)

  def apply(%__MODULE__{} = s, %E.ActivityBlocked{} = e),
    do: put_act(s, e.act, status: "blocked", waits_on: e.waits_on)

  def apply(%__MODULE__{} = s, %E.ActivityReopened{} = e),
    do:
      put_act(s, e.act,
        status: "pending",
        waits_on: nil,
        approved_pin: nil,
        handed_off: false,
        awaiting_merge: false
      )

  def apply(%__MODULE__{} = s, %E.ActivityHandedOff{} = e),
    do: put_act(s, e.act, handed_off: true)

  def apply(%__MODULE__{} = s, %E.MergeAwaited{} = e),
    do: put_act(s, e.act, status: "active", approved_pin: e.pin, awaiting_merge: true)

  def apply(%__MODULE__{} = s, %E.MergeSettled{} = e),
    do: put_act(s, e.act, status: "done", awaiting_merge: false)

  def apply(%__MODULE__{} = s, %E.ActivityFailed{} = e),
    do: put_act(s, e.act, status: "failed")

  # A new holder starts from her own handoff (sunna#117).
  def apply(%__MODULE__{} = s, %E.ActivityAssigned{} = e),
    do: put_act(s, e.act, assignee: e.assignee, handed_off: false)

  def apply(%__MODULE__{} = s, %E.ReviewDecided{outcome: "approved"} = e) do
    s = put_act(s, e.act, status: "done", approved_pin: e.pin)
    Enum.reduce(List.wrap(e.skipped), s, &put_act(&2, &1, status: "skipped"))
  end

  def apply(%__MODULE__{} = s, %E.ReviewDecided{} = e) do
    s = put_act(s, e.act, status: "pending", approved_pin: nil, awaiting_merge: false)
    # A returned review's approval goes with it (sunna#114): it approved
    # a revision that has just been sent back.
    Enum.reduce(
      List.wrap(e.returned),
      s,
      # Work sent back is handed off again, with what the review asked
      # (sunna#117).
      &put_act(&2, &1, status: "pending", waits_on: nil, approved_pin: nil, handed_off: false)
    )
  end

  def apply(%__MODULE__{} = s, %E.ApprovalLapsed{} = e) do
    s
    |> put_act(e.act, status: "pending", approved_pin: nil)
    |> put_act(e.gated, status: "pending")
  end

  def apply(%__MODULE__{} = s, %E.DocumentAttached{} = e),
    do: update_docs(s, e.task, &Map.put(&1, doc_key(e.citation), e.role))

  def apply(%__MODULE__{} = s, %E.DocumentDetached{} = e),
    do: update_docs(s, e.task, &Map.delete(&1, doc_key(e.citation)))

  def apply(%__MODULE__{} = s, %E.SlotFilled{} = e),
    do: Enum.reduce(List.wrap(e.acts), s, &put_act(&2, &1, artifact: e.artifact))

  def apply(%__MODULE__{} = s, %E.TaskCompleted{}), do: s

  def apply(%__MODULE__{} = s, %E.TaskDropped{} = e),
    do: %{s | tasks: Map.update!(s.tasks, e.task, &%{&1 | status: "dropped"})}

  # The cutover's history (sunna#80), kept for replay since the old work
  # queue retired (sunna#102); nothing records it any more.
  def apply(%__MODULE__{} = s, %E.CutOver{}), do: %{s | cut_over: true}
  def apply(%__MODULE__{} = s, %E.CutBack{}), do: %{s | cut_over: false}

  def apply(%__MODULE__{} = s, %E.BatchMade{number: n, name: name}),
    do: %{s | batches: Map.put(s.batches, n, name), next_batch: n + 1}

  def apply(%__MODULE__{} = s, %E.BacklogArranged{}), do: s

  def apply(%__MODULE__{} = s, %E.QueuePaused{}), do: %{s | paused: true}
  def apply(%__MODULE__{} = s, %E.QueueResumed{}), do: %{s | paused: false}

  # ---- shared readers ----

  @doc "A nested field read with an atom or a string key, as a fresh event and a decoded one differ."
  def get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  def get(_other, _key), do: nil

  @doc "Whether an assignee is one the queue knows: a member (`resident:<id>`, `witness:<id>`), a resident's Claude Code (`claude-code:<id>`) or `unknown`."
  def assignee?("unknown"), do: true
  def assignee?("claude-code:" <> id), do: uuid?(id)
  def assignee?(a), do: member?(a)

  @doc "Whether a string names a member: `resident:<id>` or `witness:<id>`."
  def member?("resident:" <> id), do: uuid?(id)
  def member?("witness:" <> id), do: uuid?(id)
  def member?(_other), do: false

  @doc """
  The resident a Claude Code assignee belongs to (§3): Claude Code runs on
  a resident's memories, so `claude-code:<id>` is hers, named in the
  assignee itself and never looked up. Nil for any other assignee.
  """
  def claude_code_of("claude-code:" <> id), do: "resident:" <> id
  def claude_code_of(_other), do: nil

  @doc "The assignee string an actor is."
  def me(%{kind: kind, id: id}) when kind in [:resident, :witness], do: "#{kind}:#{id}"
  def me(_actor), do: nil

  # ---- the review's decision ----

  defp decide(s, task, act, %{outcome: "approved"} = c) do
    cond do
      slot?(act.artifact) ->
        {:error, Error.new(:sunna_queue_slot_open, :sunna_queue_decide_slot)}

      act.artifact && not words?(c.pin, 64) ->
        {:error, Error.new(:sunna_queue_pin_required, :sunna_queue_decide_pin)}

      true ->
        approve(s, task, act, c)
    end
  end

  defp decide(s, task, act, c) do
    target = c.return_to || act.throwback

    case returned(s, task, act, target) do
      {:ok, returned} ->
        %E.ReviewDecided{
          actor: c.actor,
          at: c.at,
          id: c.id,
          task: c.task,
          act: c.act,
          outcome: c.outcome,
          pin: c.pin,
          return_to: target,
          withhold: false,
          returned: returned,
          skipped: [],
          note: c.note
        }

      :error ->
        {:error, Error.new(:sunna_queue_return_required, :sunna_queue_decide_return)}
    end
  end

  defp approve(s, task, act, c) do
    skipped = if c.withhold == true, do: authorized(s, task, act), else: []

    decided = %E.ReviewDecided{
      actor: c.actor,
      at: c.at,
      id: c.id,
      task: c.task,
      act: c.act,
      outcome: "approved",
      pin: c.pin,
      return_to: nil,
      withhold: c.withhold == true,
      returned: [],
      skipped: skipped,
      note: c.note
    }

    if merge_awaited?(s, task, act),
      do:
        completing(
          s,
          [
            decided,
            %E.MergeAwaited{
              actor: c.actor,
              at: c.at,
              id: c.id,
              task: c.task,
              act: c.act,
              pin: c.pin
            }
          ],
          c
        ),
      else: completing(s, [decided], c)
  end

  # A pull request's review with no merge step after it is the merge
  # (sunna#118; the witness, 2026-11-27: "the conclusion of the pr review
  # is the merge"): approving it waits for the merge, at the pin approved.
  # A task that still has its merge step keeps it.
  defp merge_awaited?(s, task, review) do
    i = G.layer_of(task, review.id)

    review.action == "merge" and is_binary(review.artifact) and
      not Enum.any?(
        Enum.at(task.layers, i + 1) || [],
        &(s.acts[&1].type == "merge" and guards?(review, s.acts[&1]))
      )
  end

  # A merge is settled by what the platform reads off GitHub, never by a
  # person's word.
  defp platform_only(%{kind: kind}) when kind in [:job, :platform], do: :ok

  defp platform_only(_actor),
    do: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_merge_settle_not_yours)}

  defp awaiting_merge(act) do
    if Map.get(act, :awaiting_merge) == true and act.status == "active",
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_merge_not_awaited)}
  end

  defp short(sha) when is_binary(sha), do: String.slice(sha, 0, 7)
  defp short(_none), do: "an unknown head"

  # A Claude Code activity is handed off once, while it is ready, by the
  # resident whose Claude Code it is or a witness (sunna#117).
  defp hand_off_ok(s, task, act, actor) do
    hers = claude_code_of(act.assignee)

    cond do
      is_nil(hers) ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_hand_off_not_claude_code)}

      Map.get(act, :handed_off) == true ->
        {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_hand_off_done)}

      not (actor.kind == :witness or me(actor) == hers) ->
        {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_hand_off_not_yours)}

      true ->
        ready(s, task, act)
    end
  end

  # What a refusal sends back (§7): the target, an earlier activity of
  # the same task, ready again; everything finished between it and the
  # review back to waiting, and everything finished beside the review in
  # its own layer (sunna#114, the witness, 2026-11-27: a peer review
  # sharing the final review's layer kept its approval of the text sent
  # back). The review itself opens again (a new review, the refused one
  # kept in history).
  defp returned(_s, _task, _act, nil), do: :error

  defp returned(s, task, act, target) do
    from = G.layer_of(task, target)
    to = G.layer_of(task, act.id)

    if is_integer(from) and from < to do
      between =
        for i <- (from + 1)..to//1,
            id <- Enum.at(task.layers, i),
            id != act.id,
            s.acts[id].status in ~w(done skipped),
            do: id

      {:ok, [target | between]}
    else
      :error
    end
  end

  # The gated activities a review authorizes (§6.1): in the layer after
  # it, of its artifact, destination and action, still standing.
  defp authorized(s, task, review) do
    i = G.layer_of(task, review.id)

    for id <- Enum.at(task.layers, i + 1) || [],
        a = s.acts[id],
        a.type in G.guarded_types(),
        a.status not in ~w(done skipped),
        guards?(review, a),
        do: id
  end

  defp guards?(review, gated),
    do:
      review.artifact == gated.artifact and review.destination == gated.destination and
        review.action == gated.type

  # The approving review in front of a gated activity, or nil.
  defp review_of(s, task, act) do
    case G.layer_of(task, act.id) do
      i when is_integer(i) and i > 0 ->
        task.layers
        |> Enum.at(i - 1)
        |> Enum.map(&s.acts[&1])
        |> Enum.find(&(&1.type == "review" and guards?(&1, act)))

      _first ->
        nil
    end
  end

  # Scarlett's first guard: a head that moved past the approved pin
  # lapses the approval, at the moment of execution.
  defp lapsed(s, task, act, head, c) do
    with true <- act.type in G.guarded_types(),
         %{approved_pin: approved} = review when is_binary(approved) <- review_of(s, task, act),
         true <- is_binary(head) and not same_pin?(head, approved) do
      %E.ApprovalLapsed{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: task.number,
        act: review.id,
        gated: act.id,
        approved_pin: approved,
        head: head
      }
    else
      _ -> nil
    end
  end

  # The move itself, unless the approval it rests on has lapsed: then the
  # lapse is the event instead.
  defp unless_lapsed(nil, move), do: move.()
  defp unless_lapsed(lapse, _move), do: lapse

  defp taken(act, c) do
    assignee = if act.assignee == "unknown", do: me(c.actor), else: act.assignee

    %E.ActivityTaken{
      actor: c.actor,
      at: c.at,
      id: c.id,
      task: c.task,
      act: c.act,
      assignee: assignee
    }
  end

  defp finished(s, task, act, c) do
    with :ok <- pin_ok(s, task, act, c.pin) do
      done = %E.ActivityDone{
        actor: c.actor,
        at: c.at,
        id: c.id,
        task: c.task,
        act: c.act,
        pin: c.pin,
        result: c.promoted || c.result,
        note: c.note && String.trim(c.note)
      }

      completing(s, [done], c)
    end
  end

  # A gated activity is done on the revision its review approved, named.
  defp pin_ok(s, task, act, pin) do
    cond do
      act.type in G.gated_types() ->
        approved_pin_ok(review_of(s, task, act), pin)

      # A promotion with a review in front of it is done on the revision
      # that review approved; with none, or none approving, on any (sunna#105).
      act.type in G.guarded_types() ->
        case review_of(s, task, act) do
          %{approved_pin: approved} = review when is_binary(approved) ->
            approved_pin_ok(review, pin)

          _no_review ->
            :ok
        end

      true ->
        :ok
    end
  end

  defp approved_pin_ok(%{approved_pin: approved}, pin) when is_binary(approved) do
    if is_binary(pin) and same_pin?(pin, approved),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_pin_mismatch, :sunna_queue_finish_pin)}
  end

  defp approved_pin_ok(_unapproved, _pin),
    do: {:error, Error.new(:sunna_queue_review_required, :sunna_queue_finish_unreviewed)}

  # The reviewer approves what was in front of them: a head read now that
  # differs from the pin they saw means the artifact changed as they read.
  defp seen_ok(_act, _pin, nil), do: :ok
  defp seen_ok(%{artifact: nil}, _pin, _head), do: :ok

  defp seen_ok(_act, pin, head) do
    if is_binary(pin) and same_pin?(pin, head),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_changed_while_read, :sunna_queue_decide_moved)}
  end

  # A short sha and the full one are one revision.
  defp same_pin?(a, b),
    do: String.starts_with?(a, b) or String.starts_with?(b, a)

  # ---- completion and release ----

  # The events, then the task's completion and what it releases when the
  # events complete it.
  defp completing(s, events, c) do
    after_s = follow(s, events)
    task = after_s.tasks[c.task]

    if task.status == "open" and G.complete?(task, after_s.acts) do
      completed = %E.TaskCompleted{actor: c.actor, at: c.at, id: c.id, task: c.task}
      events ++ [completed | releases(after_s, c.task, "done", c)]
    else
      events
    end
  end

  defp releases(s, n, how, c) do
    for id <- Enum.sort(G.releases(s.acts, n)),
        do: released(c, s.acts[id].task, id, n, how)
  end

  defp released(c, task, act, n, how),
    do: %E.ActivityReopened{
      actor: c.actor,
      at: c.at,
      id: c.id,
      task: task,
      act: act,
      released: true,
      note: "Task ##{n} is complete (#{how}), so this is no longer blocked."
    }

  defp status_of(%{status: "dropped"}), do: "dropped"
  defp status_of(_task), do: "done"

  defp follow(s, events), do: Enum.reduce(events, s, &apply(&2, &1))

  # ---- checks ----

  defp task_head_ok(s, c) do
    cond do
      not match?(%{status: "open"}, s.projects[c.project]) ->
        {:error, Error.new(:sunna_queue_no_such_project, :sunna_queue_task_project)}

      not task_head_valid?(c) ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_task_invalid)}

      Enum.any?(s.tasks, fn {_n, t} -> t.project == c.project and t.slug == c.slug end) ->
        {:error, Error.new(:sunna_queue_task_exists, :sunna_queue_task_exists)}

      true ->
        :ok
    end
  end

  defp task_head_valid?(c) do
    slug?(c.slug) and words?(c.title, 200) and words?(c.outcome, @words) and
      assignee?(c.owner) and c.owner != "unknown" and is_nil(claude_code_of(c.owner))
  end

  defp task_shape_ok(layers, start) do
    start = start || 0

    cond do
      not start_ok?(start, layers) ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_task_start)}

      shape_bad?(layers) ->
        {:error, Error.new(:sunna_queue_shape, :sunna_queue_task_shape)}

      import_gated?(layers, start) ->
        {:error, Error.new(:sunna_queue_import_gated, :sunna_queue_task_import_gated)}

      true ->
        :ok
    end
  end

  defp start_ok?(start, layers),
    do: is_integer(start) and start >= 0 and start < length(layers)

  defp shape_bad?(layers) do
    specs = for layer <- layers, a <- layer, into: %{}, do: {a.id, a}
    ids = Enum.map(layers, fn layer -> Enum.map(layer, & &1.id) end)

    G.shape_errors(ids, specs) != [] or
      Enum.any?(specs, fn {_id, a} -> a.type in G.artifact_types() and is_nil(a.artifact) end)
  end

  # Scarlett's third guard: an import carries no approvals, so a task
  # cannot start where a gated activity's review would be imported.
  defp import_gated?(layers, start),
    do: start > 0 and Enum.any?(Enum.at(layers, start), &(&1.type in G.gated_types()))

  # Who builds (sunna#117; the witness, 2026-11-27: "implementation
  # tickets should only be assignable to residents with a coding agent
  # attached"): an implement is held by a resident's Claude Code, or by
  # nobody yet; and a Claude Code is one its resident has attached
  # (`builders`, the residents with a Claude Code conversation, read by
  # the caller). The deliver step that once stood before it is gone: her
  # handoff is the activity's own first turn.
  defp builders_ok?(specs, builders),
    do: Enum.all?(specs, &builder_ok?(get(&1, :type), get(&1, :assignee), builders))

  defp builder_ok?(type, assignee, builders) do
    case claude_code_of(assignee) do
      nil -> type != "implement" or assignee in [nil, "unknown"]
      "resident:" <> id -> id in List.wrap(builders)
    end
  end

  # What an edit gives a holder or a type: new activities, and pending
  # ones whose holder or type it changes. One it leaves as it was is not
  # its to answer for (the witness, 2026-11-27: removing #15's deliver was
  # refused for the implement beside it, held by him before #117).
  defp changed_holders(s, layers) do
    Enum.filter(List.flatten(layers), fn spec ->
      case s.acts[spec.id] do
        nil ->
          true

        old ->
          old.status == "pending" and (old.assignee != spec.assignee or old.type != spec.type)
      end
    end)
  end

  # A task's layers as given, each activity numbered `<task>.<k>`, a
  # throwback named by position ("2.1": layer 2's first) made an id.
  defp task_layers(n, layers) when is_list(layers) and layers != [] do
    numbered =
      layers
      |> Enum.with_index()
      |> Enum.map_reduce(1, fn {layer, _i}, k -> number_layer(n, layer, k) end)
      |> elem(0)

    positions =
      for {layer, i} <- Enum.with_index(numbered),
          is_list(layer),
          {a, j} <- Enum.with_index(layer, 1),
          into: %{},
          do: {"#{i + 1}.#{j}", a && a.id}

    cond do
      Enum.any?(numbered, &(not is_list(&1))) -> invalid_layers()
      Enum.any?(List.flatten(numbered), &is_nil/1) -> invalid_layers()
      true -> resolve_throwbacks(numbered, positions)
    end
  end

  defp task_layers(_n, _layers), do: invalid_layers()

  defp number_layer(n, layer, k) when is_list(layer) and layer != [],
    do: Enum.map_reduce(layer, k, fn spec, k -> {spec_of(spec, "#{n}.#{k}"), k + 1} end)

  defp number_layer(_n, _layer, k), do: {:error, k}

  defp resolve_throwbacks(layers, positions) do
    resolved =
      Enum.map(layers, fn layer -> Enum.map(layer, &resolve_throwback(&1, positions)) end)

    if Enum.any?(List.flatten(resolved), &(&1.throwback == :bad)),
      do: invalid_layers(),
      else: {:ok, resolved}
  end

  defp resolve_throwback(%{throwback: nil} = a, _positions), do: a

  defp resolve_throwback(%{throwback: pos} = a, positions),
    do: %{a | throwback: Map.get(positions, pos, :bad)}

  defp invalid_layers, do: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_task_layers)}

  defp spec_of(spec, id) when is_map(spec) do
    a = %{
      id: id,
      name: blank_nil(get(spec, :name)),
      slot: blank_nil(get(spec, :slot)),
      type: get(spec, :type),
      assignee: get(spec, :assignee) || "unknown",
      artifact: blank_nil(get(spec, :artifact)),
      destination: blank_nil(get(spec, :destination)),
      action: blank_nil(get(spec, :action)),
      optional: get(spec, :optional) == true,
      throwback: blank_nil(get(spec, :throwback))
    }

    if words?(a.type, @verb) and assignee?(a.assignee) and short?(a.artifact, 300) and
         short?(a.destination, 120) and short?(a.action, @verb) and short?(a.name, @name) and
         short?(a.slot, 64),
       do: a,
       else: nil
  end

  defp spec_of(_spec, _id), do: nil

  # A template's layers (§7): each spec a type, a role, an artifact slot,
  # and its destination, action, optional and throwback; the shape rule
  # checked with the slots standing in for artifacts.
  @roles ~w(author witness peer builder unknown)
  defp template_layers(layers) when is_list(layers) and layers != [] do
    specs = for {layer, i} <- Enum.with_index(layers), do: template_layer(layer, i)

    flat = List.flatten(specs)

    cond do
      Enum.any?(flat, &is_nil/1) ->
        :error

      template_shape?(specs) ->
        {:ok, Enum.map(specs, fn layer -> Enum.map(layer, &Map.delete(&1, :pos)) end)}

      true ->
        :shape
    end
  end

  defp template_layers(_layers), do: :error

  defp template_layer(layer, i) when is_list(layer) and layer != [],
    do: layer |> Enum.with_index(1) |> Enum.map(fn {s, j} -> template_spec(s, i, j) end)

  defp template_layer(_layer, _i), do: [nil]

  defp template_spec(spec, _i, j) when is_map(spec) do
    assignee = blank_nil(get(spec, :assignee))

    t = %{
      pos: j,
      name: blank_nil(get(spec, :name)),
      type: get(spec, :type),
      # Who holds it, set in the template (sunna#93): a member, a
      # resident's Claude Code, or unknown; never who opens the task. A
      # role (author, witness, peer, builder) stays readable on a template
      # written before, resolved as it was.
      assignee: assignee,
      role: if(assignee, do: nil, else: get(spec, :role) || "unknown"),
      artifact: blank_nil(get(spec, :artifact)),
      destination: blank_nil(get(spec, :destination)),
      action: blank_nil(get(spec, :action)),
      optional: get(spec, :optional) == true,
      throwback: blank_nil(get(spec, :throwback))
    }

    # A template names every activity (sunna#90): the name every task
    # made from it shows.
    if template_spec_ok?(t), do: t, else: nil
  end

  defp template_spec(_spec, _i, _j), do: nil

  defp template_spec_ok?(t) do
    words?(t.name, @name) and words?(t.type, @verb) and holder_ok?(t) and
      short?(t.artifact, 64) and short?(t.destination, 120) and short?(t.action, @verb) and
      short?(t.throwback, 16)
  end

  defp holder_ok?(%{assignee: a}) when is_binary(a), do: assignee?(a)
  defp holder_ok?(%{role: role}), do: role in @roles

  defp template_shape?(specs) do
    keyed =
      for {layer, i} <- Enum.with_index(specs), t <- layer, into: %{} do
        {"#{i + 1}.#{t.pos}", t}
      end

    ids = for {layer, i} <- Enum.with_index(specs), do: Enum.map(layer, &"#{i + 1}.#{&1.pos}")

    G.shape_errors(ids, keyed) == [] and
      Enum.all?(keyed, fn {_k, t} ->
        t.type not in G.artifact_types() or not is_nil(t.artifact)
      end) and
      Enum.all?(keyed, fn {k, t} -> throwback_earlier?(k, t.throwback, keyed) end)
  end

  # A template's throwback names an activity, by position, in an earlier layer.
  defp throwback_earlier?(_at, nil, _keyed), do: true

  defp throwback_earlier?(at, back, keyed) do
    layer = fn pos -> pos |> String.split(".") |> hd() |> Integer.parse() end
    Map.has_key?(keyed, back) and elem(layer.(back), 0) < elem(layer.(at), 0)
  end

  defp activity_from(spec, task, imported?) do
    %{
      id: get(spec, :id),
      task: task,
      name: get(spec, :name),
      slot: get(spec, :slot),
      type: get(spec, :type),
      assignee: get(spec, :assignee),
      artifact: get(spec, :artifact),
      destination: get(spec, :destination),
      action: get(spec, :action),
      optional: get(spec, :optional) == true,
      throwback: get(spec, :throwback),
      status: if(imported?, do: "done", else: "pending"),
      imported: imported?,
      waits_on: nil,
      approved_pin: nil,
      handed_off: false,
      awaiting_merge: false
    }
  end

  # An edit that gives a Claude Code activity another holder starts it
  # from that holder's handoff (sunna#117).
  defp edited_act(old, new) do
    merged = Map.merge(old, Map.take(new, @spec_fields))
    if merged.assignee == old.assignee, do: merged, else: Map.put(merged, :handed_off, false)
  end

  defp put_act(s, id, kv), do: %{s | acts: Map.update!(s.acts, id, &Enum.into(kv, &1))}

  defp open_task(s, n) do
    case s.tasks[n] do
      %{status: "open"} = task ->
        if G.complete?(task, s.acts),
          do: {:error, Error.new(:sunna_queue_no_such_task, :sunna_queue_task_complete)},
          else: {:ok, task}

      _none ->
        {:error, Error.new(:sunna_queue_no_such_task, :sunna_queue_task_absent)}
    end
  end

  defp activity(s, n, id) do
    with {:ok, task} <- open_task(s, n) do
      case s.acts[id] do
        %{task: ^n} = act -> {:ok, task, act}
        _none -> {:error, Error.new(:sunna_queue_no_such_activity, :sunna_queue_activity_absent)}
      end
    end
  end

  # A task's activity whether the task is open or complete (a finished
  # activity reopened can reopen its task, sunna#116); never a dropped one.
  defp any_activity(s, n, id) do
    case {s.tasks[n], s.acts[id]} do
      {%{status: "dropped"}, _act} ->
        {:error, Error.new(:sunna_queue_no_such_task, :sunna_queue_task_dropped)}

      {%{} = task, %{task: ^n} = act} ->
        {:ok, task, act}

      {nil, _act} ->
        {:error, Error.new(:sunna_queue_no_such_task, :sunna_queue_reopen_task_absent)}

      _none ->
        {:error, Error.new(:sunna_queue_no_such_activity, :sunna_queue_reopen_act_absent)}
    end
  end

  # Stuck work (blocked or failed) reopens for whoever may work it. A
  # finished one (done or skipped) reopens for a witness or the task's
  # owner, and only while nothing after it has moved (sunna#116, the
  # witness, 2026-11-27: he finished 15.6 meaning to reassign it): undoing
  # it must not leave later work resting on undone work.
  defp may_reopen(s, task, act, actor) do
    cond do
      act.status in ~w(blocked failed) ->
        may_work(task, act, actor)

      act.status in ~w(done skipped) ->
        with :ok <- may_edit(task, actor), do: nothing_after(s, task, act)

      true ->
        {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_reopen_not_stuck)}
    end
  end

  defp nothing_after(s, task, act) do
    i = G.layer_of(task, act.id)

    moved =
      for later <- Enum.drop(task.layers, i + 1),
          id <- later,
          s.acts[id].status != "pending",
          do: id

    if moved == [],
      do: :ok,
      else:
        {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_reopen_moved_on, moved: moved)}
  end

  # Ready: pending in the open layer.
  defp ready(s, task, act) do
    if G.view(act, task, s.acts) == :ready,
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_activity_not_ready)}
  end

  # Live: ready or active.
  defp live(s, task, act) do
    if G.view(act, task, s.acts) in [:ready, :active],
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_activity_not_live)}
  end

  defp unfinished(act) do
    if act.status in ~w(done skipped),
      do: {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_activity_finished)},
      else: :ok
  end

  defp blockable(act) do
    if act.status in ~w(pending active),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_ready, :sunna_queue_block_not_live)}
  end

  defp not_review(%{type: "review"}),
    do: {:error, Error.new(:sunna_queue_review_decides, :sunna_queue_finish_review)}

  defp not_review(_act), do: :ok

  # Scarlett's second guard: a promotion to the house is finished only by
  # the promotion, which runs the library's audience check on its own.
  defp promoted(%{type: "promote-to-house"}, copy) do
    if words?(copy, 300),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_promote_by_promotion, :sunna_queue_finish_promote)}
  end

  defp promoted(_act, _copy), do: :ok

  defp review(%{type: "review"}), do: :ok

  defp review(_act),
    do: {:error, Error.new(:sunna_queue_not_a_review, :sunna_queue_decide_not_review)}

  defp reviewer(act, actor) do
    if act.assignee == me(actor),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_decide_not_reviewer)}
  end

  defp outcome_ok(outcome) when outcome in @outcomes, do: :ok

  defp outcome_ok(_other),
    do: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_decide_outcome)}

  defp may_work(task, act, actor) do
    mine = me(actor)

    if actor.kind == :witness or work_line?(actor) or member_may_work?(task, act, mine),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_activity_not_yours)}
  end

  # Her work line's own job (sunna#109): it fails the activity a stop
  # ended, on her behalf, its actor saying it was the line, not she.
  defp work_line?(%{kind: :job, id: "sunna_work"}), do: true
  defp work_line?(_actor), do: false

  defp member_may_work?(_task, _act, nil), do: false

  defp member_may_work?(task, act, mine) do
    mine in [act.assignee, task.owner] or act.assignee == "unknown" or
      (not is_nil(mine) and mine == claude_code_of(act.assignee))
  end

  # The task's owner, a witness (sunna#115, the witness, 2026-11-27: he
  # could work an activity but never skip one), or an optional
  # activity's assignee. A review guarding the next layer stays unskipped
  # whoever asks (sunna#82).
  defp may_skip(task, act, actor) do
    mine = me(actor)

    cond do
      actor.kind == :witness -> :ok
      not is_nil(mine) and mine == task.owner -> :ok
      act.optional and not is_nil(mine) and mine == act.assignee -> :ok
      true -> {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_skip_not_yours)}
    end
  end

  defp may_assign(task, act, actor) do
    mine = me(actor)

    if actor.kind == :witness or (not is_nil(mine) and mine in [task.owner, act.assignee]),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_assign_not_yours)}
  end

  defp assignee_ok(act, assignee, builders) do
    cond do
      not assignee?(assignee) ->
        {:error, Error.new(:sunna_queue_invalid, :sunna_queue_assign_assignee)}

      not builder_ok?(act.type, assignee, builders) ->
        {:error, Error.new(:sunna_queue_builder_required, :sunna_queue_assign_builder)}

      true ->
        :ok
    end
  end

  # ---- editing a task's layers ----

  # A task's documents are changed by its owner, the witness, or anyone
  # holding one of its activities (sunna#91).
  defp may_attach(task, s, actor) do
    mine = me(actor)

    held? =
      Enum.any?(List.flatten(task.layers), fn id ->
        get(Map.get(s.acts, id, %{}), :assignee) == mine
      end)

    if actor.kind == :witness or mine == task.owner or held?,
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_attach_not_yours)}
  end

  defp update_docs(s, n, fun),
    do: %{
      s
      | tasks:
          Map.update!(s.tasks, n, &Map.put(&1, :documents, fun.(Map.get(&1, :documents, %{}))))
    }

  @doc """
  A document's key: its citation without the pin (`@<commit>`), its last
  segment with `.md` where it names no extension, as every citation
  resolves (sunna#108): `lily:design/x` and `lily:design/x.md` are one
  document, never two on a task.
  """
  def doc_key(citation) when is_binary(citation) do
    bare = citation |> String.split("@", parts: 2) |> hd() |> String.trim()
    if bare == "" or Path.extname(bare) != "", do: bare, else: bare <> ".md"
  end

  defp may_edit(task, actor) do
    if actor.kind == :witness or me(actor) == task.owner,
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_edit_not_yours)}
  end

  # The new arrangement, each activity whole: an existing one by its id
  # (a pending one with its changes), a new one numbered on from the
  # task's highest. What started stays put and unchanged; the layers
  # before the open one stay as they were; new and moved activities go in
  # the open layer or after it.
  defp edited_layers(s, task, given) do
    open = G.open_layer(task, s.acts) || length(task.layers)
    before = Enum.flat_map(task.layers, & &1)
    next = Map.get(task, :next_k) || next_k(task.layers)

    with {:ok, layers} <- arrange(s, task, given, next),
         ids = Enum.flat_map(layers, fn l -> Enum.map(l, & &1.id) end),
         true <- Enum.uniq(ids) == ids || :refused,
         true <- kept_in_place?(s, task, layers, open) || :refused,
         removed = before -- ids,
         true <- Enum.all?(removed, &(s.acts[&1].status == "pending")) || :refused,
         true <- throwbacks_earlier?(layers) || :throwback do
      {:ok, layers, removed}
    else
      :refused -> {:error, Error.new(:sunna_queue_edit_refused, :sunna_queue_edit_started)}
      :throwback -> {:error, Error.new(:sunna_queue_throwback_order, :sunna_queue_edit_throwback)}
      _invalid -> {:error, Error.new(:sunna_queue_invalid, :sunna_queue_edit_layers)}
    end
  end

  defp arrange(s, task, given, next) when is_list(given) and given != [] do
    {layers, _k} =
      Enum.map_reduce(given, next, fn layer, k ->
        if is_list(layer) and layer != [],
          do: Enum.map_reduce(layer, k, &arranged(s, task, &1, &2)),
          else: {[nil], k}
      end)

    flat = List.flatten(layers)

    cond do
      :started in flat -> :refused
      Enum.any?(flat, &is_nil/1) -> :invalid
      true -> {:ok, layers}
    end
  end

  defp arrange(_s, _task, _given, _next), do: :invalid

  # An entry naming an activity of this task: kept, its spec changed only
  # while it is pending; any other entry: a new activity.
  defp arranged(s, task, entry, k) do
    case is_map(entry) && get(entry, :id) do
      id when is_binary(id) ->
        case s.acts[id] do
          %{task: n} = old when n == task.number -> {changed(old, entry), k}
          _other -> {nil, k}
        end

      # One added to an open task is named by whoever adds it (sunna#90):
      # the task's own copy of its template holds the name.
      _new ->
        spec = spec_of(entry, "#{task.number}.#{k}")
        {spec && spec.name && spec, k + 1}
    end
  end

  defp changed(%{status: "pending"} = old, entry) do
    merged =
      Map.merge(
        Map.take(old, @spec_fields),
        Map.new(Map.take(entry, @spec_fields ++ Enum.map(@spec_fields, &Atom.to_string/1)), fn {k,
                                                                                                v} ->
          {to_key(k), v}
        end)
      )

    spec_of(merged, old.id)
  end

  defp changed(old, entry) do
    asked = Map.new(Map.drop(entry, [:id, "id"]), fn {k, v} -> {to_key(k), v} end)
    kept = Map.take(old, @spec_fields) |> Map.put(:id, old.id)
    # Started work is kept as it is: a change to it is refused, not read
    # as a malformed entry.
    if Enum.all?(asked, fn {k, v} -> Map.get(old, k) == v end), do: kept, else: :started
  end

  defp to_key(k) when is_atom(k), do: k
  defp to_key(k), do: Enum.find(@spec_fields, :unknown, &(Atom.to_string(&1) == k))

  # Started work in the layer it was in, and nothing new or moved before
  # the open layer.
  defp kept_in_place?(s, task, layers, open) do
    Enum.with_index(layers)
    |> Enum.all?(fn {layer, i} -> Enum.all?(layer, &placed_ok?(s, task, &1, i, open)) end) and
      Enum.take(layers, open) |> Enum.map(fn l -> Enum.map(l, & &1.id) end) ==
        Enum.take(task.layers, open)
  end

  defp placed_ok?(s, task, a, i, open) do
    case s.acts[a.id] do
      nil -> i >= open
      %{status: "pending"} -> i >= open or G.layer_of(task, a.id) == i
      _started -> G.layer_of(task, a.id) == i
    end
  end

  # A throwback names an activity in an earlier layer.
  defp throwbacks_earlier?(layers) do
    at = for {l, i} <- Enum.with_index(layers), a <- l, into: %{}, do: {a.id, i}

    Enum.all?(at, fn {id, i} ->
      a = Enum.find(Enum.at(layers, i), &(&1.id == id))
      is_nil(a.throwback) or (Map.has_key?(at, a.throwback) and at[a.throwback] < i)
    end)
  end

  # One past the highest activity number in these layers: an id is never
  # given twice in a task, a removed one's included (the task keeps the
  # highest it has given, `next_k`).
  defp next_k(layers) do
    layers
    |> List.flatten()
    |> Enum.map(fn id -> id |> String.split(".") |> List.last() |> String.to_integer() end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp edited_shape_ok(layers) do
    if shape_bad?(layers),
      do: {:error, Error.new(:sunna_queue_shape, :sunna_queue_edit_shape)},
      else: :ok
  end

  defp owner_or_witness(task, actor) do
    if actor.kind == :witness or me(actor) == task.owner,
      do: :ok,
      else: {:error, Error.new(:sunna_queue_not_yours, :sunna_queue_drop_not_yours)}
  end

  # A review standing in front of a gated activity still to run is never
  # skipped (§7): skip the gated activity first, or approve it.
  defp not_guarding(s, task, %{type: "review"} = act) do
    if authorized(s, task, act) == [],
      do: :ok,
      else: {:error, Error.new(:sunna_queue_review_required, :sunna_queue_skip_review)}
  end

  defp not_guarding(_s, _task, _act), do: :ok

  defp block_ok(_s, _task, nil), do: :ok

  defp block_ok(s, task, waits_on) when is_integer(waits_on) do
    case G.block_ok?(s.tasks, s.acts, task.number, waits_on) do
      :ok -> :ok
      :self -> {:error, Error.new(:sunna_queue_block_refused, :sunna_queue_block_self)}
      :cycle -> {:error, Error.new(:sunna_queue_block_refused, :sunna_queue_block_cycle)}
      :no_such_task -> {:error, Error.new(:sunna_queue_block_refused, :sunna_queue_block_missing)}
    end
  end

  defp block_ok(_s, _task, _other),
    do: {:error, Error.new(:sunna_queue_block_refused, :sunna_queue_block_not_a_task)}

  defp reason_ok(text) do
    if words?(text, 500),
      do: :ok,
      else: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_reason_invalid)}
  end

  defp optional_words(nil), do: :ok

  defp optional_words(text) do
    if is_binary(text) and String.length(text) <= @words,
      do: :ok,
      else: {:error, Error.new(:sunna_queue_invalid, :sunna_queue_note_invalid)}
  end

  defp slot?(artifact), do: is_binary(artifact) and String.starts_with?(artifact, "slot:")

  defp slug?(s), do: is_binary(s) and Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,63}\z/, s)

  defp uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  defp words?(text, max),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= max

  defp short?(nil, _max), do: true
  defp short?(text, max), do: is_binary(text) and String.length(text) <= max

  defp blank_nil(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))
  defp blank_nil(v), do: v

  # An arrangement's entries, read plainly: `%{"batch" => n, "tasks" =>
  # [n], "open" => bool}` or `%{"task" => n, "open" => bool}`.
  defp arranged(s, entries) when is_list(entries) do
    read = Enum.map(entries, &entry(s, &1))
    tasks = Enum.flat_map(read, &entry_tasks/1)

    if Enum.all?(read, &is_map/1) and length(tasks) == length(Enum.uniq(tasks)),
      do: {:ok, read},
      else: :error
  end

  defp arranged(_s, _entries), do: :error

  defp entry(s, e) when is_map(e) do
    batch = key(e, "batch")
    task = key(e, "task")
    open = key(e, "open") == true

    cond do
      is_integer(batch) and Map.has_key?(s.batches, batch) ->
        batch_entry(s, batch, key(e, "tasks"), open)

      is_integer(task) and Map.has_key?(s.tasks, task) ->
        %{"task" => task, "open" => open}

      true ->
        nil
    end
  end

  defp entry(_s, _e), do: nil

  defp batch_entry(s, batch, tasks, open) do
    tasks = List.wrap(tasks)

    if Enum.all?(tasks, &Map.has_key?(s.tasks, &1)),
      do: %{"batch" => batch, "tasks" => tasks, "open" => open},
      else: nil
  end

  # An entry's field by its string key, or its atom key as a test gives it.
  defp key(e, k), do: Map.get(e, k, Map.get(e, String.to_existing_atom(k)))

  defp entry_tasks(%{"tasks" => tasks}), do: tasks
  defp entry_tasks(%{"task" => task}), do: [task]
  defp entry_tasks(_none), do: []
end
