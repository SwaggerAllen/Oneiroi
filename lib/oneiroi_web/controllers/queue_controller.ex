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
      "The house queue's overview: whether the household has cut over and at which commit, the resident whose conversation Claude Code is, the members as the queue names them, the projects, the templates (and the starters the platform ships), and the tasks open first",
    responses: [ok: {"the queue", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params) do
    h = conn.assigns.household_id
    state = Sunna.queue_state(h)

    json(conn, %{
      household_id: h,
      me: me(conn),
      cut_over: state.cut_over,
      cut_at: state.cut_at,
      commit: state.commit,
      carrier: Sunna.queue_carrier(h),
      members: Sunna.queue_members(h),
      projects: Enum.map(Sunna.queue_projects(h), &project/1),
      templates: Enum.map(Sunna.queue_templates(h), &template/1),
      starters:
        for(
          {name, t} <- Sunna.queue_starters(),
          do: %{name: name, title: t.title, layers: t.layers}
        ),
      tasks: Enum.map(Sunna.queue_tasks(h), &task/1)
    })
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
          task: task(page.task),
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
    attrs = %{from: blank(params["from"]), title: params["title"], layers: params["layers"]}

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

    case Sunna.queue_open_task(conn.assigns.household_id, attrs, actor(conn)) do
      {:ok, n} -> json(conn, %{number: n})
      {:error, e} -> error(conn, 422, e)
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
    done(
      conn,
      Sunna.queue_fill_slot(
        conn.assigns.household_id,
        int(number),
        p["slot"],
        p["artifact"],
        actor(conn)
      )
    )
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

  operation(:snapshot,
    summary:
      "The cutover's first step (§6.2): every resident's old work queue committed to the household repository as records/work-queue-at-cutover.md with its raw rows; answers the commit the cutover then names. A witness's",
    responses: [ok: {"the commit", "application/json", %Schema{type: :object}}]
  )

  def snapshot(conn, _params) do
    case Brain.queue_snapshot(conn.assigns.household_id, actor(conn)) do
      {:ok, sha} -> json(conn, %{commit: sha})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:cut_over,
    summary:
      "Turns the house queue on (§6.2): commit names the house repository commit holding the old queue, note says why; a witness's",
    request_body: {"commit and note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def cut_over(conn, p),
    do:
      done(
        conn,
        Sunna.queue_cut_over(conn.assigns.household_id, p["commit"], p["note"], actor(conn))
      )

  operation(:cut_back,
    summary: "The one-step revert (§6.2): the old queue's screens and loop back on, with a note",
    request_body: {"the note", "application/json", %Schema{type: :object}},
    responses: [ok: {"done", "application/json", %Schema{type: :object}}]
  )

  def cut_back(conn, p),
    do: done(conn, Sunna.queue_cut_back(conn.assigns.household_id, p["note"], actor(conn)))

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
