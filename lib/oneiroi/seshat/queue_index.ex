defmodule Oneiroi.Seshat.QueueIndex do
  @moduledoc """
  A house queue task's index document (sunna#80, lily:design/queue-ia
  §4): the citable anchor for the task, rendered from its rows. Its
  outcome line, owner and template; its links; its layers and activities,
  each with its assignee, status and artifact at the pin it was approved
  or done on; what waits on it; and its history, every decision with its
  note. Written by the platform, never by hand: an edit is overwritten by
  the next render, and the queue is where the task changes.

  Also the cutover's record of the old queue (§6.2):
  `records/work-queue-at-cutover.md`, every resident's Sunna work queue as
  it stood, and its raw rows beside it as JSON.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Records
  alias Oneiroi.Sunna

  @doc "Renders task `n`'s index document; `{:ok, commit | :nothing}`."
  def render(household_id, n) do
    case Sunna.queue_task(household_id, n) do
      nil ->
        {:ok, :nothing}

      page ->
        names = Map.new(Sunna.queue_members(household_id), &{&1.assignee, &1.name})

        Records.write(
          household_id,
          [{page.task.index_doc, text(page, names)}],
          "Task ##{n}: #{page.task.title}",
          Actor.platform()
        )
    end
  end

  @doc false
  def text(%{task: t, layers: layers, waiting: waiting, history: history}, names) do
    """
    ---
    title: #{yaml(t.title)}
    kind: task
    task: #{t.number}
    project: #{t.project}
    owner: #{yaml(name(t.owner, names))}
    by: #{yaml(name(t.owner, names))}
    posted_at: #{DateTime.to_iso8601(t.opened_at)}
    edited_at: #{edited(history, t)}
    status: #{t.status}
    template: #{t.template || "none"}
    rendered: from the house queue's rows; edits here are overwritten
    ---

    # #{t.title}

    **Done when:** #{t.outcome}

    Project `#{t.project}` · owner #{name(t.owner, names)} · #{t.status}#{open(t)}

    #{links(t.links)}## Layers

    #{Enum.with_index(layers, 1) |> Enum.map_join("\n", &layer(&1, t, names))}
    #{waiting_text(waiting)}
    ## History

    #{Enum.map_join(history, "\n", &history_line(&1, names))}
    """
  end

  # The last change the task's history records: what the Records list
  # reads as written.
  defp edited([], t), do: DateTime.to_iso8601(t.opened_at)
  defp edited(history, _t), do: history |> List.last() |> Map.fetch!(:at) |> DateTime.to_iso8601()

  defp open(%{status: "open", open_layer: i}) when is_integer(i), do: ", layer #{i + 1} open"
  defp open(_t), do: ""

  defp links([]), do: ""
  defp links(links), do: "## Links\n\n" <> Enum.map_join(links, "\n", &"- #{&1}") <> "\n\n"

  defp layer({acts, i}, t, names) do
    mark = if t.open_layer == i - 1, do: " (open)", else: ""

    "#{i}.#{mark} " <> Enum.map_join(acts, "; ", &act_text(&1, names))
  end

  defp act_text(a, names) do
    pin = a.approved_pin || a.pin
    art = if a.artifact, do: " on #{a.artifact}#{pin_text(pin)}", else: ""
    imported = if a.imported, do: ", imported", else: ""
    "`#{a.act_id}` #{a.type}#{art}, #{name(a.assignee, names)}, #{a.view}#{imported}"
  end

  defp pin_text(nil), do: ""
  defp pin_text(false), do: ""
  defp pin_text(pin), do: "@#{short(pin)}"

  defp waiting_text([]), do: ""

  defp waiting_text(waiting),
    do:
      "\n## Waiting on this task\n\n" <> Enum.map_join(waiting, "\n", &"- `#{&1.act_id}`") <> "\n"

  defp history_line(h, names) do
    who = name("#{h.actor_kind}:#{h.actor_id}", names)

    what =
      [h.act_id && "`#{h.act_id}`", h.what, h.outcome] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    pin = if h.pin, do: " @#{short(h.pin)}", else: ""
    note = if h.note, do: ": #{h.note}", else: ""
    "- #{Calendar.strftime(h.at, "%Y-%m-%d %H:%M")}Z #{what}#{pin} (#{who})#{note}"
  end

  # ---- the old queue at cutover (§6.2) ----

  @doc """
  Writes every resident's Sunna work queue into the household repository
  as `records/work-queue-at-cutover.md` and its raw rows as
  `records/work-queue-at-cutover.json`, in one commit by `actor`;
  answers the commit.
  """
  def commit_old_queue(household_id, residents, %Actor{} = actor) do
    queues = for {id, name} <- residents, do: {name, Sunna.work_queue(id)}

    raw =
      Jason.encode!(
        for({name, q} <- queues, do: %{resident: name, items: Enum.map(q.items, &plain/1)}),
        pretty: true
      )

    md = """
    # The work queue at cutover

    Every resident's Sunna work queue as it stood when the house queue took
    the work (sunna#80, lily:design/queue-ia §6.2). The rows and events stay
    in place, read-only, so the revert is one step; this is the readable
    record of exactly what moved. Raw rows: `records/work-queue-at-cutover.json`.

    #{Enum.map_join(queues, "\n", &old_queue/1)}
    """

    Records.write(
      household_id,
      [
        {"records/work-queue-at-cutover.md", md},
        {"records/work-queue-at-cutover.json", raw <> "\n"}
      ],
      "The old work queue, at cutover",
      actor
    )
  end

  defp old_queue({name, %{items: items}}) do
    rows =
      case items do
        [] -> "Empty."
        items -> Enum.map_join(items, "\n", &old_item/1)
      end

    "## #{name}\n\n#{rows}\n"
  end

  defp old_item(i) do
    extra =
      cond do
        i.status == "held" -> " — held: #{i.held_ask}"
        i.status == "blocked" -> " — blocked on #{i.blocked_on}"
        true -> ""
      end

    wrap = if i.shipped, do: "\n  - last wrap: #{i.shipped}", else: ""
    "- ##{i.number} [#{i.status}] #{i.what}#{extra}\n  - done when: #{i.done_when}#{wrap}"
  end

  defp plain(%{__struct__: _} = row), do: row |> Map.from_struct() |> Map.delete(:__meta__)
  defp plain(row), do: row

  defp name("claude-code:" <> id = a, names) do
    case names["resident:" <> id] do
      nil -> a
      hers -> "#{hers}'s Claude Code"
    end
  end

  defp name(a, names), do: Map.get(names, a, a)
  defp short(pin), do: String.slice(pin, 0, 7)
  # One line of the house's front matter, as `Files.render/2` writes it.
  defp yaml(text), do: Files.one_line(to_string(text))
end
