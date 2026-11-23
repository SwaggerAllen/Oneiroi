defmodule Oneiroi.Seshat.ReviewThreadWorker do
  @moduledoc """
  A review's decision posted into its document's thread (seshat#110;
  design/document-threads.md §4): the activity's name, the outcome, the
  pin it was made on, who made it, and the note, as the platform's line.
  The thread is the house's once the document is shared there (a house
  document, or her file with its copy on the house's shelf), else the
  one in its resident's own threads (seshat#106). A document the
  platform cannot read (a PR, a page) has no thread, and nothing is
  posted.
  """
  use Oneiroi.Worker, queue: :seshat_household

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Household.Documents
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Threads
  alias Oneiroi.Sunna

  @actor Actor.new(:job, "review_thread")

  def run(%{"household_id" => h, "task" => n, "act" => act_id} = args) do
    with %{layers: layers} <- Sunna.queue_task(h, n),
         %{} = act <- Enum.find(List.flatten(layers), &(&1.act_id == act_id)),
         citation when is_binary(citation) <- act.artifact do
      post(h, citation, line(h, act, args))
    else
      _nothing -> :ok
    end
  end

  @doc false
  def line(h, act, args) do
    who = who(h, args["actor_kind"], args["actor_id"]) || "a member"
    pin = if args["pin"], do: " on @#{String.slice(args["pin"], 0, 12)}", else: ""

    "#{act.name || act.type}: #{outcome(args["outcome"])}#{pin}, by #{who}.#{note(args["note"])}"
  end

  defp outcome("approved"), do: "approved"
  defp outcome("changes"), do: "changes asked"
  defp outcome("declined"), do: "declined"
  defp outcome(other), do: to_string(other)

  defp who(h, "witness", id), do: Gaia.household_member_name(h, Actor.new(:witness, id))
  defp who(h, "resident", id), do: Gaia.household_member_name(h, Actor.new(:resident, id))
  defp who(_h, _kind, _id), do: nil

  defp note(text) when is_binary(text) do
    if String.trim(text) == "", do: "", else: "\n\n" <> text
  end

  defp note(_text), do: ""

  defp post(h, citation, text) do
    case Citations.house(citation) do
      {:ok, %{path: path}} -> ok(Documents.platform_note(h, path, text))
      :error -> post_hers(h, citation, text)
    end
  end

  defp post_hers(h, citation, text) do
    with [slug, rest] <- String.split(String.split(citation, "@") |> hd(), ":", parts: 2),
         id when is_binary(id) <- resident(h, slug) do
      path = if Path.extname(rest) == "", do: rest <> ".md", else: rest
      copy = Path.join(["shared", slug, path])

      if shared?(h, copy),
        do: ok(Documents.platform_note(h, copy, text)),
        else: ok(Threads.post(@actor, id, %{"doc" => path, "content" => text}))
    else
      _not_hers -> :ok
    end
  end

  defp shared?(h, copy) do
    case Files.view(h) do
      {:ok, view} -> Files.has?(view, copy)
      _none -> false
    end
  end

  defp resident(h, slug) do
    Enum.find_value(Gaia.household_members(h), fn
      %{kind: "resident", id: id} ->
        case AgathosDaimon.fetch(id) do
          {:ok, %{slug: ^slug}} -> id
          _other -> nil
        end

      _witness ->
        nil
    end)
  end

  defp ok({:ok, _}), do: :ok
  defp ok(other), do: other
end
