defmodule OneiroiWeb.QueueController do
  @moduledoc """
  The house queue (sunna#80, lily:design/queue-ia rev 5) as the Work
  screen reads and moves it: one queue a household, every member's. The
  household is the caller's own (`Gaia.household_of/1`); the queue
  refuses anyone not a member. Takes, finishes and decisions read the
  artifact's head at the moment of the move (`Oneiroi.Brain.queue_take/4` and its kin).
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Brain
  alias Oneiroi.Gaia
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Error, as: SunnaError
  alias Oneiroi.Sunna.Queue
  alias Oneiroi.Sunna.QueueGraph
  alias OpenApiSpex.Schema

  tags(["household"])

  plug(:household)

  operation(:show,
    summary:
      "The house queue's overview: whether it is paused, the members as the queue names them, the projects, the templates (and the starters the platform ships), and the tasks open first",
    responses: [ok: {"the queue", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params) do
    h = conn.assigns.household_id
    state = Sunna.queue_state(h)

    json(conn, %{
      household_id: h,
      me: me(conn),
      # The house queue's one switch (sunna#94).
      paused: state.paused == true,
      paused_at: state.paused_at,
      members: Sunna.queue_members(h),
      projects: Enum.map(Sunna.queue_projects(h), &project/1),
      templates: Enum.map(Sunna.queue_templates(h), &template/1),
      starters:
        for(
          {name, t} <- Sunna.queue_starters(),
          do: %{name: name, title: t.title, layers: t.layers}
        ),
      tasks: with_documents(h, Enum.map(Sunna.queue_tasks(h), &task/1))
    })
  end

  defp with_documents(h, tasks) do
    docs = Sunna.queue_documents(h, Enum.map(tasks, & &1.number))
    Enum.map(tasks, &Map.put(&1, :documents, Map.get(docs, &1.number, [])))
  end

  operation(:waiting,
    summary:
      "Waiting on me (§2.2): who's ready activities, reviews among them, blocking-most first and then oldest ready; the later and blocked ones, each naming what it waits on; and the tasks who owns with their next action. `who` defaults to the caller",
    parameters: [who: [in: :query, type: :string]],
    responses: [ok: {"the view", "application/json", %Schema{type: :object}}]
  )

  def waiting(conn, params) do
    h = conn.assigns.household_id
    who = blank(params["who"]) || me(conn)
    w = Sunna.queue_waiting_on(h, who)

    json(conn, %{
      who: who,
      ready: w.ready,
      later: w.later,
      owned: Enum.map(w.owned, &%{task: task(&1.task), next: activity(&1.next)})
    })
  end

  operation(:activities,
    summary:
      "Activities by filter (§2.1): `who` (an assignee, anyone, unknown), `view` (comma-separated: ready, waiting, active, blocked, failed, done, skipped), `project`; each with its task and, when blocked on a task, that task's title, next action and whose it is",
    parameters: [
      who: [in: :query, type: :string],
      view: [in: :query, type: :string],
      project: [in: :query, type: :string]
    ],
    responses: [ok: {"the activities", "application/json", %Schema{type: :array}}]
  )

  def activities(conn, params) do
    views =
      case blank(params["view"]) do
        nil -> []
        v -> String.split(v, ",", trim: true)
      end

    json(
      conn,
      Sunna.queue_activities(conn.assigns.household_id, %{
        who: blank(params["who"]),
        views: views,
        project: blank(params["project"])
      })
    )
  end

  operation(:task_page,
    summary:
      "One task's page (§2.4): the task, its layers of activities in order, what waits on it, and its history",
    parameters: [number: [in: :path, type: :integer]],
    responses: [ok: {"the task", "application/json", %Schema{type: :object}}]
  )

  def task_page(conn, %{"number" => number}) do
    case Sunna.queue_task(conn.assigns.household_id, int(number)) do
      nil ->
        error(conn, 404, SunnaError.new(:sunna_queue_no_such_task, :sunna_web_queue_task_absent))

      page ->
        json(conn, %{
          task: hd(with_documents(conn.assigns.household_id, [task(page.task)])),
          layers: Enum.map(page.layers, fn l -> Enum.map(l, &activity/1) end),
          waiting: Enum.map(page.waiting, &activity/1),
          history: Enum.map(page.history, &history/1)
        })
    end
  end

  operation(:open_project,
    summary: "Opens a project: slug, name, and owner (the caller unless named)",
    request_body: {"the project", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def open_project(conn, params) do
    attrs = %{slug: params["slug"], name: params["name"], owner: blank(params["owner"])}
    done(conn, Sunna.queue_open_project(conn.assigns.household_id, attrs, actor(conn)))
  end

  operation(:close_project,
    summary: "Closes a project, with a note",
    parameters: [slug: [in: :path, type: :string]],
    request_body: {"the note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def close_project(conn, %{"slug" => slug} = params) do
    done(
      conn,
      Sunna.queue_close_project(conn.assigns.household_id, slug, params["note"], actor(conn))
    )
  end

  operation(:define_template,
    summary:
      "Defines a template (§7): name, and title and layers, or `from` a starter's name to copy it; a later definition of a name replaces it",
    request_body: {"the template", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def define_template(conn, params) do
    attrs = %{
      from: blank(params["from"]),
      title: params["title"],
      layers: params["layers"],
      roles: params["roles"]
    }

    done(
      conn,
      Sunna.queue_define_template(conn.assigns.household_id, params["name"], attrs, actor(conn))
    )
  end

  operation(:open_task,
    summary:
      "Opens a task: project, slug, title, outcome, owner; template (with roles and slots) or layers whole; start_layer (1-based) and links for work moved in part-way. Answers its number",
    request_body: {"the task", "application/json", %Schema{type: :object}},
    responses: [ok: {"its number", "application/json", %Schema{type: :object}}]
  )

  def open_task(conn, params) do
    attrs = %{
      project: params["project"],
      slug: params["slug"],
      title: params["title"],
      outcome: params["outcome"],
      owner: blank(params["owner"]),
      template: blank(params["template"]),
      layers: params["layers"],
      roles: params["roles"],
      slots: params["slots"],
      start_layer: int(params["start_layer"]),
      links: params["links"]
    }

    h = conn.assigns.household_id

    # Every document it names is one that exists (sunna#95).
    with :ok <- Brain.queue_document_check(h, Brain.queue_document_citations(attrs)),
         {:ok, n} <- Sunna.queue_open_task(h, attrs, actor(conn)) do
      json(conn, %{number: n})
    else
      {:error, _} = refused -> done(conn, refused)
    end
  end

  operation(:move,
    summary:
      "Moves an activity: take, finish (note, result), skip (note), block (reason, waits_on), reopen (note), fail (reason), assign (assignee, note), or decide a review (outcome approved, changes or declined; pin, return_to, withhold, note)",
    parameters: [
      number: [in: :path, type: :integer],
      act: [in: :path, type: :string],
      move: [in: :path, type: :string]
    ],
    request_body: {"the move's fields", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def move(conn, %{"number" => number, "act" => act, "move" => move} = p) do
    h = conn.assigns.household_id
    a = actor(conn)
    n = int(number)

    done(conn, apply_move(move, p, {h, n, act}, a))
  end

  operation(:fill_slot,
    summary: "Fills a template's open artifact slot (slot:<name>) with its citation",
    parameters: [number: [in: :path, type: :integer]],
    request_body: {"slot and artifact", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def fill_slot(conn, %{"number" => number} = p) do
    h = conn.assigns.household_id

    result =
      with :ok <- Brain.queue_document_check(h, [p["artifact"]]),
           do: Sunna.queue_fill_slot(h, int(number), p["slot"], p["artifact"], actor(conn))

    done(conn, result)
  end

  operation(:attach_document,
    summary:
      "Attaches a document to a task (sunna#91): citation, and role, a slot name or source (the default); its owner's, a witness's, or the holder of one of its activities",
    parameters: [number: [in: :path, type: :integer]],
    request_body: {"citation and role", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def attach_document(conn, %{"number" => number} = p) do
    h = conn.assigns.household_id

    result =
      with :ok <- Brain.queue_document_check(h, [p["citation"]]),
           do: Sunna.queue_attach_document(h, int(number), p["citation"], p["role"], actor(conn))

    done(conn, result)
  end

  operation(:detach_document,
    summary: "Detaches a document attached to a task (sunna#91)",
    parameters: [number: [in: :path, type: :integer]],
    request_body: {"citation", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def detach_document(conn, %{"number" => number} = p) do
    done(
      conn,
      Sunna.queue_detach_document(
        conn.assigns.household_id,
        int(number),
        p["citation"],
        actor(conn)
      )
    )
  end

  operation(:document_tasks,
    summary: "The tasks a document belongs to (sunna#91), by its citation, open first",
    parameters: [citation: [in: :query, type: :string, required: true]],
    responses: [ok: {"the tasks", "application/json", %Schema{type: :array}}]
  )

  def document_tasks(conn, p),
    do:
      json(
        conn,
        Sunna.queue_tasks_for_document(conn.assigns.household_id, to_string(p["citation"] || ""))
      )

  operation(:edit_layers,
    summary:
      "Edits an open task's layers (sunna#85): layers, the whole new arrangement, each entry an existing activity by id (with fields to change while it is pending) or a new activity's spec; note, why. What started stays put; the layers before the open one stay as they are",
    parameters: [number: [in: :path, type: :integer]],
    request_body: {"layers and note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def edit_layers(conn, %{"number" => number} = p) do
    h = conn.assigns.household_id

    # A document it names is one that exists (sunna#95).
    result =
      with :ok <-
             Brain.queue_document_check(h, Brain.queue_document_citations(%{layers: p["layers"]})),
           do: Sunna.queue_edit_layers(h, int(number), p["layers"], p["note"], actor(conn))

    done(conn, result)
  end

  operation(:drop,
    summary: "Drops a task, with a note; what waits on it is released",
    parameters: [number: [in: :path, type: :integer]],
    request_body: {"the note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def drop(conn, %{"number" => number} = p) do
    done(conn, Sunna.queue_drop(conn.assigns.household_id, int(number), p["note"], actor(conn)))
  end

  operation(:pause,
    summary:
      "Pauses the house queue for every resident (sunna#94): nothing starts on anyone's line until it runs again; a witness's, with a note",
    request_body: {"the note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def pause(conn, p),
    do: done(conn, Sunna.queue_pause(conn.assigns.household_id, p["note"], actor(conn)))

  operation(:resume,
    summary: "Lets the house queue run again (sunna#94); every resident's line checks at once",
    request_body: {"the note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def resume(conn, p),
    do: done(conn, Sunna.queue_resume(conn.assigns.household_id, p["note"], actor(conn)))

  operation(:backlog,
    summary:
      "The backlog (sunna#103): the open tasks' entries in priority order, each a batch (number, name, tasks in order) or a task in no batch, open or closed, the top always open; and what finished, newest first",
    responses: [ok: {"the backlog", "application/json", %Schema{type: :object}}]
  )

  def backlog(conn, _params), do: json(conn, Sunna.queue_backlog(conn.assigns.household_id))

  operation(:arrange,
    summary:
      "Arranges the backlog (sunna#103), a witness's: entries in order, each {batch, tasks, open} or {task, open}; every resident's line checks at once",
    request_body: {"the entries", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def arrange(conn, p),
    do:
      done(
        conn,
        Sunna.queue_arrange(conn.assigns.household_id, List.wrap(p["entries"]), actor(conn))
      )

  operation(:make_batch,
    summary:
      "Makes the next numbered batch of the backlog (sunna#103), a witness's, with an optional name",
    request_body: {"the name", "application/json", %Schema{type: :object}},
    responses: [ok: {"its number", "application/json", %Schema{type: :object}}]
  )

  def make_batch(conn, p) do
    case Sunna.queue_make_batch(conn.assigns.household_id, p["name"], actor(conn)) do
      {:ok, n} -> json(conn, %{number: n})
      other -> done(conn, other)
    end
  end

  # ---- helpers ----

  defp household(conn, _opts) do
    case Gaia.household_of(actor(conn)) do
      id when is_binary(id) ->
        assign(conn, :household_id, id)

      _none ->
        conn
        |> error(404, SunnaError.new(:sunna_queue_not_a_member, :sunna_web_queue_no_household))
        |> halt()
    end
  end

  defp me(conn), do: Queue.me(actor(conn))

  defp apply_move("take", _p, {h, n, act}, a), do: Brain.queue_take(h, n, act, a)

  defp apply_move("finish", p, {h, n, act}, a),
    do: Brain.queue_finish(h, n, act, %{note: blank(p["note"]), result: blank(p["result"])}, a)

  defp apply_move("skip", p, {h, n, act}, a), do: Sunna.queue_skip(h, n, act, p["note"], a)

  defp apply_move("block", p, {h, n, act}, a),
    do: Sunna.queue_block(h, n, act, p["reason"], int(p["waits_on"]), a)

  defp apply_move("reopen", p, {h, n, act}, a), do: Sunna.queue_reopen(h, n, act, p["note"], a)
  defp apply_move("fail", p, {h, n, act}, a), do: Sunna.queue_fail(h, n, act, p["reason"], a)

  defp apply_move("assign", p, {h, n, act}, a),
    do: Sunna.queue_assign(h, n, act, p["assignee"], blank(p["note"]), a)

  defp apply_move("decide", p, {h, n, act}, a) do
    Brain.queue_decide(
      h,
      n,
      act,
      %{
        outcome: p["outcome"],
        pin: blank(p["pin"]),
        return_to: blank(p["return_to"]),
        withhold: p["withhold"] == true,
        note: p["note"]
      },
      a
    )
  end

  defp apply_move(_other, _p, _where, _a),
    do: {:error, SunnaError.new(:sunna_queue_invalid, :sunna_web_queue_move_unknown)}

  defp done(conn, :ok), do: json(conn, %{ok: true})
  defp done(conn, {:error, %{kind: :sunna_queue_not_a_member} = e}), do: error(conn, 404, e)

  # A document that does not exist (sunna#95): its remedy names what was
  # meant, when the house holds it.
  defp done(conn, {:error, %{kind: :brain_queue_document_absent} = e}),
    do: error(conn, 422, %{e | remedy: Brain.queue_document_said(e)})

  defp done(conn, {:error, e}), do: error(conn, 422, e)

  defp project(p),
    do: Map.take(p, [:slug, :name, :owner, :status, :opened_at, :closed_at, :note])

  defp template(t),
    do: %{name: t.name, title: t.title, layers: t.layers["layers"], defined_at: t.defined_at}

  defp task(t),
    do:
      Map.take(t, [
        :number,
        :project,
        :slug,
        :title,
        :outcome,
        :owner,
        :index_doc,
        :template,
        :template_version,
        :forked,
        :links,
        :status,
        :open_layer,
        :opened_by,
        :opened_at,
        :completed_at,
        :note
      ])

  defp activity(nil), do: nil

  defp activity(a),
    do:
      a
      |> Map.take([
        :act_id,
        :task,
        :layer,
        :position,
        :name,
        :slot,
        :type,
        :assignee,
        :status,
        :view,
        :artifact,
        :destination,
        :action,
        :optional,
        :throwback,
        :imported,
        :waits_on,
        :reason,
        :pin,
        :approved_pin,
        :result,
        :note,
        :ready_at,
        :updated_at
      ])
      |> Map.put(:gated, a.type in QueueGraph.gated_types())

  defp history(h),
    do: Map.take(h, [:act_id, :what, :outcome, :pin, :note, :actor_kind, :actor_id, :at])

  defp blank(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))
  defp blank(_v), do: nil

  defp int(n) when is_integer(n), do: n

  defp int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp int(_other), do: nil
end
