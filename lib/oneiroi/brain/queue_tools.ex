defmodule Oneiroi.Brain.QueueTools do
  @moduledoc """
  A resident's tools for the house queue (sunna#80, lily:design/queue-ia
  §2.1: her view is the same query with her as the viewer). Words she
  writes here reach every member, so the tools are the house's: held
  with the house and checked against the household audience before they
  run (`Oneiroi.Brain.Tools`).
  """

  alias Oneiroi.Brain.HouseQueue
  alias Oneiroi.Gaia
  alias Oneiroi.Sunna

  @not_done "Not done: "

  @doc "The tool names, all of the house."
  def names,
    do:
      ~w(queue_list queue_task queue_templates queue_template_define queue_project_open queue_task_open queue_task_edit queue_move queue_decide queue_fill_slot queue_task_document queue_drop)

  @doc "The tools that carry her words to the house."
  def delivering, do: names() -- ~w(queue_list queue_task queue_templates)

  @doc "The words a call carries, for the house audience's check."
  def candidate(args),
    do:
      [args["name"], args["title"], args["outcome"], args["note"], args["reason"]]
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> Enum.join("\n\n")

  @doc "The definitions."
  def definitions do
    act = %{task: %{type: "integer"}, act: %{type: "string"}}

    [
      tool(
        "queue_list",
        "The house queue (sunna#80): what waits on you, ready first (reviews among them), ordered by how much stands behind each, then what is yours in a later layer or blocked (each naming what it waits on), then the tasks you own with their next action. who widens it: \"anyone\", \"unknown\", or a member as resident:<id> / witness:<id>; status narrows it (ready, waiting, active, blocked, failed); project one project's. Your witness reads the same queue on his Work screen.",
        %{
          who: %{type: "string"},
          status: %{type: "string"},
          project: %{type: "string"}
        },
        []
      ),
      tool(
        "queue_task",
        "One task of the house queue: its outcome, owner and index document, its layers in order (each activity's id, verb, assignee, status, artifact and pins, the open layer marked), what waits on it, and its history.",
        %{task: %{type: "integer"}},
        [:task]
      ),
      tool(
        "queue_templates",
        "The house's templates (each a title and its layers of activities, with roles) and the starters the platform ships; and the members, as assignees.",
        %{},
        []
      ),
      tool(
        "queue_template_define",
        "Write a house template (sunna#88): name (lowercase, hyphens; the same name replaces it), title, and layers, an array of layers each an array of activities {name, type, assignee, artifact, destination, action, optional, throwback}. name is what every task made from the template calls the activity, as \"Witness review\" (sunna#90); every activity has one. assignee is who holds it in every task made from the template, whoever opens the task (sunna#93): a member as queue_templates lists them (resident:<id>, witness:<id>), a resident's Claude Code (claude-code:<id>) or unknown. With from (a starter), roles names its holders: {\"author\": \"resident:<id>\", \"witness\": ..., \"peer\": ...}, the author's Claude Code building unless builder is named. artifact is a slot name (design, pr) filled when the task opens. A gated step (send, publish, spend, merge, promote-to-house) sits right after a review of the same slot whose destination matches and whose action is that step; throwback names an earlier activity by position (\"1.1\"). Or from: a starter's name, to copy it.",
        %{
          name: %{type: "string"},
          title: %{type: "string"},
          roles: %{type: "object"},
          layers: %{type: "array", items: %{type: "array", items: %{type: "object"}}},
          from: %{type: "string"}
        },
        [:name]
      ),
      tool(
        "queue_project_open",
        "Open a project of the house queue: slug (lowercase, hyphens), name. You own it.",
        %{slug: %{type: "string"}, name: %{type: "string"}},
        [:slug, :name]
      ),
      tool(
        "queue_task_open",
        "Open a task in a project: slug, title, outcome (what done looks like), and template (a name from queue_templates; roles become members, author you unless owner says) or layers given whole (an array of layers, each an array of {type, assignee, artifact, destination, action, optional, throwback}). slots fills a template's artifact slots, as {\"design\": \"lily:design/x\"}. Work already under way: start_layer (1-based) where it stands, every earlier layer imported done, links its citations; an import carries no approvals, so it cannot start at a gated layer. Activity ids are <task>.<k>.",
        %{
          project: %{type: "string"},
          slug: %{type: "string"},
          title: %{type: "string"},
          outcome: %{type: "string"},
          template: %{type: "string"},
          layers: %{type: "array", items: %{type: "array", items: %{type: "object"}}},
          roles: %{type: "object"},
          slots: %{type: "object"},
          owner: %{type: "string"},
          start_layer: %{type: "integer", minimum: 1},
          links: %{type: "array", items: %{type: "string"}}
        },
        [:project, :slug, :title, :outcome]
      ),
      tool(
        "queue_task_edit",
        "Edit an open task's layers (sunna#85): layers is the whole new arrangement, an array of layers, each an array of entries: an existing activity as {\"id\": \"12.3\"} (with any of type, assignee, artifact, destination, action, optional, throwback to change it while it is pending) or a new activity's spec, with its name (the task then runs its own copy of its template). What has started (done, skipped, active, blocked, failed) stays in its layer unchanged; the layers before the open one stay as they are; a pending activity left out is removed. Yours when you own the task; note says why.",
        %{
          task: %{type: "integer"},
          layers: %{type: "array", items: %{type: "array", items: %{type: "object"}}},
          note: %{type: "string"}
        },
        [:task, :layers, :note]
      ),
      tool(
        "queue_move",
        "Move an activity of the house queue (task and act, as 12 and \"12.3\"): take (you are on it), finish (with note; result a citation of what it made, a PR say), skip (explicitly, with note: an optional activity, or any in a task you own; never a review in front of a gated activity still to run), block (reason, and waits_on a task number when it waits on that task's completion: it clears by itself when that task is done or dropped), reopen (a blocked or failed one, with note), fail (reason says what failed; it keeps its place) or assign (assignee: a member, a resident's Claude Code as claude-code:<her id>, or unknown). A promote-to-house activity finishes by household_promote with its task and act, never here. Reviews are decided with queue_decide.",
        Map.merge(act, %{
          move: %{
            type: "string",
            enum: ["take", "finish", "skip", "block", "reopen", "fail", "assign"]
          },
          note: %{type: "string"},
          reason: %{type: "string"},
          waits_on: %{type: "integer"},
          result: %{type: "string"},
          assignee: %{type: "string"}
        }),
        [:task, :act, :move]
      ),
      tool(
        "queue_decide",
        "Decide a review assigned to you (§7): approved, changes or declined, with a note. Approval authorizes exactly this revision, this destination, this action: pin is the commit you read (the artifact's head now if you leave it out), and a head that moved after you approve lapses the approval. withhold approves keeping it where it is (\"keep private\"), skipping the gated step it would authorize. changes and declined send the work back to return_to (an earlier activity's id; the template's default when it has one), with your note, and this review opens again for the revision.",
        Map.merge(act, %{
          outcome: %{type: "string", enum: ["approved", "changes", "declined"]},
          note: %{type: "string"},
          pin: %{type: "string"},
          return_to: %{type: "string"},
          withhold: %{type: "boolean"}
        }),
        [:task, :act, :outcome, :note]
      ),
      tool(
        "queue_fill_slot",
        "Fill an artifact slot a template left open (an activity's artifact reads slot:<name>, as slot:pr) with its citation, on every activity of the task holding it.",
        %{task: %{type: "integer"}, slot: %{type: "string"}, artifact: %{type: "string"}},
        [:task, :slot, :artifact]
      ),
      tool(
        "queue_task_document",
        "Attach a document to a task, or with detach: true take it off (sunna#91): citation, as lily:design/x.md, and role, a slot's name (design, pr) or source (the default). The task's documents are what its activities work on and what is attached. Yours when you own the task or hold one of its activities.",
        %{
          task: %{type: "integer"},
          citation: %{type: "string"},
          role: %{type: "string"},
          detach: %{type: "boolean"}
        },
        [:task, :citation]
      ),
      tool(
        "queue_drop",
        "Drop a task you own, with a note: it counts as complete, so whatever waits on it is released.",
        %{task: %{type: "integer"}, note: %{type: "string"}},
        [:task, :note]
      )
    ]
  end

  @doc "Runs a queue tool for the turn's resident."
  def call(name, args, turn) do
    case Gaia.resident_household(turn.resident_id) do
      %{id: h} -> run(name, args, h, turn.resident, "resident:#{turn.resident_id}")
      nil -> @not_done <> "you are in no household, so there is no house queue."
    end
  end

  defp run("queue_list", args, h, _actor, me) do
    who = blank(args["who"]) || me

    if who == me and is_nil(blank(args["status"])) and is_nil(blank(args["project"])) do
      waiting_text(Sunna.queue_waiting_on(h, me), h)
    else
      filter = %{
        who: who,
        views: List.wrap(blank(args["status"])),
        project: blank(args["project"])
      }

      case Sunna.queue_activities(h, filter) do
        [] -> "Nothing matches."
        cards -> Enum.map_join(cards, "\n", &card_line(&1, names(h)))
      end
    end
  end

  defp run("queue_task", args, h, _actor, _me) do
    case Sunna.queue_task(h, integer(args["task"])) do
      nil ->
        @not_done <> "no task ##{args["task"]}."

      page ->
        task_text(
          page,
          names(h),
          Map.get(Sunna.queue_documents(h, [page.task.number]), page.task.number, [])
        )
    end
  end

  defp run("queue_templates", _args, h, _actor, _me) do
    defined = Sunna.queue_templates(h)

    templates =
      case defined do
        [] -> "No templates are defined in the house yet."
        ts -> Enum.map_join(ts, "\n\n", &template_text(&1.name, &1.title, &1.layers["layers"]))
      end

    starters =
      Enum.map_join(Sunna.queue_starters(), "\n\n", fn {name, t} ->
        template_text(name, t.title, t.layers)
      end)

    members = Enum.map_join(Sunna.queue_members(h), ", ", &"#{&1.name} (#{&1.assignee})")

    "Templates in the house:\n#{templates}\n\nStarters the platform ships:\n#{starters}\n\nMembers: #{members}. A resident's Claude Code is claude-code:<her id>, reached through her own deliver step."
  end

  defp run("queue_template_define", args, h, actor, _me) do
    attrs = %{
      from: blank(args["from"]),
      title: args["title"],
      layers: args["layers"],
      roles: args["roles"]
    }

    with :ok <- Sunna.queue_define_template(h, to_string(args["name"] || ""), attrs, actor),
         do: "Template #{args["name"]} is saved in the house."
  end

  defp run("queue_project_open", args, h, actor, _me) do
    with :ok <- Sunna.queue_open_project(h, %{slug: args["slug"], name: args["name"]}, actor),
         do: "Opened project #{args["slug"]}."
  end

  defp run("queue_task_open", args, h, actor, _me) do
    attrs = %{
      project: args["project"],
      slug: args["slug"],
      title: args["title"],
      outcome: args["outcome"],
      owner: blank(args["owner"]),
      template: blank(args["template"]),
      layers: args["layers"],
      roles: args["roles"],
      slots: args["slots"],
      start_layer: integer(args["start_layer"]),
      links: args["links"]
    }

    with {:ok, n} <- Sunna.queue_open_task(h, attrs, actor) do
      "Opened task ##{n}.\n\n" <> page_text(h, n)
    end
  end

  defp run("queue_move", args, h, actor, _me) do
    task = integer(args["task"])
    act = to_string(args["act"] || "")

    result = move(args["move"], args, {h, task, act}, actor)
    with :ok <- result, do: "#{act}: #{args["move"]} recorded.#{next_line(h, task)}"
  end

  defp run("queue_decide", args, h, actor, _me) do
    task = integer(args["task"])
    act = to_string(args["act"] || "")

    attrs = %{
      outcome: args["outcome"],
      note: args["note"],
      pin: blank(args["pin"]),
      return_to: blank(args["return_to"]),
      withhold: args["withhold"] == true
    }

    with :ok <- HouseQueue.decide(h, task, act, attrs, actor),
         do: "#{act}: #{args["outcome"]}.#{next_line(h, task)}"
  end

  defp run("queue_task_document", %{"detach" => true} = args, h, actor, _me) do
    with :ok <-
           Sunna.queue_detach_document(
             h,
             integer(args["task"]),
             to_string(args["citation"] || ""),
             actor
           ),
         do: "#{args["citation"]} is off task ##{args["task"]}."
  end

  defp run("queue_task_document", args, h, actor, _me) do
    role = blank(args["role"]) || "source"

    with :ok <-
           Sunna.queue_attach_document(
             h,
             integer(args["task"]),
             to_string(args["citation"] || ""),
             role,
             actor
           ),
         do: "#{args["citation"]} is on task ##{args["task"]}, as its #{role}."
  end

  defp run("queue_fill_slot", args, h, actor, _me) do
    with :ok <-
           Sunna.queue_fill_slot(h, integer(args["task"]), args["slot"], args["artifact"], actor),
         do: "slot:#{args["slot"]} is #{args["artifact"]} now."
  end

  defp run("queue_task_edit", args, h, actor, _me) do
    task = integer(args["task"])

    with :ok <-
           Sunna.queue_edit_layers(h, task, args["layers"], to_string(args["note"] || ""), actor) do
      "Task ##{task}'s layers edited.\n\n" <> page_text(h, task)
    end
  end

  defp run("queue_drop", args, h, actor, _me) do
    with :ok <- Sunna.queue_drop(h, integer(args["task"]), to_string(args["note"] || ""), actor),
         do: "Task ##{args["task"]} dropped; what waited on it is released."
  end

  # ---- text ----

  defp waiting_text(%{ready: ready, later: later, owned: owned}, h) do
    names = names(h)

    [
      section("Waiting on you", ready, &card_line(&1, names)),
      section("Yours, not ready yet", later, &card_line(&1, names)),
      section("Tasks you own", owned, fn %{task: t, next: next} ->
        "##{t.number} #{t.title} (#{t.project}): next #{next_text(next, names)}"
      end)
    ]
    |> Enum.join("\n\n")
  end

  defp section(title, [], _line), do: "#{title}: nothing."
  defp section(title, rows, line), do: "#{title}:\n" <> Enum.map_join(rows, "\n", line)

  defp card_line(c, names) do
    art = if c.artifact, do: " · #{c.artifact}#{pin(c.approved_pin || c.pin)}", else: ""

    base =
      "#{c.act} #{c.type}#{if c.gated, do: " (gated)", else: ""}#{art} · #{c.task_title} › #{c.project} · #{c.view} · #{name_of(c.assignee, names)}"

    base <> waits(c, names)
  end

  defp waits(%{view: "blocked", blocker: %{} = b}, names),
    do:
      "\n    blocked on ##{b.number} #{b.title} · next: #{next_text(b.next, names)}" <>
        if(b.status != "open", do: " (#{b.status})", else: "")

  defp waits(%{view: "blocked", reason: reason}, _names), do: "\n    blocked: #{reason}"
  defp waits(%{view: "failed", reason: reason}, _names), do: "\n    failed: #{reason}"
  defp waits(_card, _names), do: ""

  defp next_text(nil, _names), do: "nothing open"
  defp next_text(a, names), do: "#{a.type} (#{a.act_id}), #{name_of(a.assignee, names)}"

  defp move("take", _args, {h, task, act}, actor), do: HouseQueue.take(h, task, act, actor)

  defp move("finish", args, {h, task, act}, actor) do
    HouseQueue.finish(
      h,
      task,
      act,
      %{note: blank(args["note"]), result: blank(args["result"])},
      actor
    )
  end

  defp move("skip", args, {h, task, act}, actor),
    do: Sunna.queue_skip(h, task, act, to_string(args["note"] || ""), actor)

  defp move("block", args, {h, task, act}, actor),
    do: Sunna.queue_block(h, task, act, args["reason"], integer(args["waits_on"]), actor)

  defp move("reopen", args, {h, task, act}, actor),
    do: Sunna.queue_reopen(h, task, act, to_string(args["note"] || ""), actor)

  defp move("fail", args, {h, task, act}, actor),
    do: Sunna.queue_fail(h, task, act, args["reason"] || args["note"], actor)

  defp move("assign", args, {h, task, act}, actor),
    do: Sunna.queue_assign(h, task, act, args["assignee"], blank(args["note"]), actor)

  defp move(other, _args, _where, _actor) do
    @not_done <>
      "#{inspect(other)} is not a move: take, finish, skip, block, reopen, fail or assign."
  end

  defp task_text(%{task: t, layers: layers, history: history, waiting: waiting}, names, docs) do
    from =
      cond do
        is_nil(t.template) -> ""
        t.forked -> " · forked from #{t.template}"
        true -> " · from #{t.template}"
      end

    head =
      "##{t.number} #{t.title} · #{t.project} · #{t.status} · owner #{name_of(t.owner, names)}#{from}\nOutcome: #{t.outcome}\nIndex: #{t.index_doc}" <>
        docs_line(docs)

    layer_lines =
      layers
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {layer, i} -> layer_line(layer, i, t, names) end)

    waiting_line =
      case waiting do
        [] -> ""
        ws -> "\nWaiting on this task: " <> Enum.map_join(ws, ", ", & &1.act_id)
      end

    history_lines =
      history
      |> Enum.take(-20)
      |> Enum.map_join("\n", &history_line/1)

    "#{head}\n#{layer_lines}#{waiting_line}\nHistory:\n#{history_lines}"
  end

  defp page_text(h, n) do
    page = Sunna.queue_task(h, n)
    task_text(page, names(h), Map.get(Sunna.queue_documents(h, [n]), n, []))
  end

  # Its documents (sunna#91): each by its role, an unfilled slot said so.
  defp docs_line([]), do: ""

  defp docs_line(docs),
    do:
      "\nDocuments: " <>
        Enum.map_join(docs, "; ", fn d -> "#{d.role} #{d.citation || "(not yet filled)"}" end)

  defp layer_line(layer, i, t, names) do
    open = if t.open_layer == i - 1, do: " (open)", else: ""
    "Layer #{i}#{open}: " <> Enum.map_join(layer, "; ", &act_line(&1, names))
  end

  defp act_line(a, names) do
    art = if a.artifact, do: " on #{a.artifact}#{pin(a.approved_pin || a.pin)}", else: ""
    named = if a.name, do: "#{a.name} (#{a.type})", else: a.type
    "#{a.act_id} #{named}#{art} · #{name_of(a.assignee, names)} · #{a.view}#{extra(a)}"
  end

  defp history_line(h) do
    what = Enum.join(Enum.reject([h.act_id, h.what, h.outcome], &is_nil/1), " ")
    note = if h.note, do: ": #{h.note}", else: ""
    "  #{Calendar.strftime(h.at, "%Y-%m-%d %H:%MZ")} #{what} (#{h.actor_kind})#{note}"
  end

  defp extra(%{view: "blocked"} = a),
    do: " (#{a.reason}#{if a.waits_on, do: "; waits on ##{a.waits_on}", else: ""})"

  defp extra(%{view: "failed"} = a), do: " (#{a.reason})"
  defp extra(%{imported: true}), do: " (imported)"
  defp extra(%{note: note}) when is_binary(note), do: " — #{note}"
  defp extra(_a), do: ""

  defp template_text(name, title, layers) do
    lines =
      layers
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {layer, i} ->
        "  #{i}. " <> Enum.map_join(layer, "; ", &template_spec_text/1)
      end)

    "#{name}: #{title}\n#{lines}"
  end

  defp template_spec_text(s) do
    get = &(Map.get(s, &1) || Map.get(s, Atom.to_string(&1)))
    gated = if get.(:destination), do: " → #{get.(:destination)}", else: ""
    named = if get.(:name), do: "#{get.(:name)}: ", else: ""
    "#{named}#{get.(:type)} (#{get.(:assignee) || "by role: #{get.(:role)}"})#{gated}"
  end

  defp next_line(h, task) do
    case Sunna.queue_task(h, task) do
      %{task: %{status: "open"} = t} ->
        case Sunna.queue_next_action(h, t) do
          nil -> ""
          a -> " Next: #{a.type} (#{a.act_id}), #{a.assignee}."
        end

      %{task: %{status: status}} ->
        " Task ##{task} is #{status}."

      nil ->
        ""
    end
  end

  defp names(h), do: Map.new(Sunna.queue_members(h), &{&1.assignee, &1.name})

  # A resident's Claude Code by her name (§3).
  defp name_of("claude-code:" <> id = a, names) do
    case names["resident:" <> id] do
      nil -> a
      hers -> "#{hers}'s Claude Code"
    end
  end

  defp name_of(a, names), do: Map.get(names, a, a)

  defp pin(nil), do: ""
  defp pin(p), do: "@" <> String.slice(p, 0, 7)

  defp blank(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))
  defp blank(_v), do: nil

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(String.trim_leading(s, "#")) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil

  defp tool(name, description, properties, required),
    do: %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: %{type: "object", properties: properties, required: required}
      }
    }
end
