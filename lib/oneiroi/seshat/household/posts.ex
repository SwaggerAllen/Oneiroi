defmodule Oneiroi.Seshat.Household.Posts do
  @moduledoc """
  A post (seshat#59, #60): a thread, a thread on a document, or a
  household document, through the beats' gate, with its mentions and
  the round after.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Documents
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.Household.Mentions
  alias Oneiroi.Seshat.Household.Replies
  alias Oneiroi.Seshat.Kinds

  @trunk "trunk.md"

  @doc false
  def post(%Actor{} = actor, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, household_id} <- Core.household(actor),
         :ok <- Core.may_post(actor, household_id),
         {:ok, view} <- Core.provision(household_id) do
      case {attrs["kind"] || "thread", attrs["doc"]} do
        # A document has one thread in the house (seshat#109): a post on
        # one that has it is a reply there, or, with no words, the thread.
        {"thread", doc} when is_binary(doc) ->
          doc_post(actor, household_id, view, attrs, Documents.doc_thread(view, doc))

        {"thread", _none} ->
          post_thread(actor, household_id, view, attrs)
          |> Replies.rounds_after(household_id, actor, attrs)
          |> Mentions.mentioned(household_id, actor, attrs, nil)

        _document ->
          Documents.post_document(actor, household_id, view, attrs)
      end
    end
  end

  defp doc_post(actor, household_id, view, attrs, nil) do
    Documents.post_doc_thread(actor, household_id, view, attrs)
    |> Replies.rounds_after(household_id, actor, attrs)
    |> Mentions.mentioned(household_id, actor, attrs, nil)
  end

  defp doc_post(actor, _household_id, _view, attrs, t), do: on_existing(actor, t, attrs)

  defp on_existing(actor, t, attrs) do
    text = to_string(attrs["content"] || "")

    if String.trim(text) == "" do
      {:ok, Map.merge(t, %{existing: true, ballot: nil})}
    else
      with {:ok, r} <- Replies.reply(actor, t.path, %{"content" => text}),
           do: {:ok, Map.merge(t, %{existing: true, reply: r.number, ballot: nil})}
    end
  end

  defp post_thread(actor, household_id, _view, attrs) do
    title = Files.one_line(attrs["title"])
    text = to_string(attrs["content"] || "")
    ballot = attrs["ballot"]

    with :ok <- Files.titled(title),
         :ok <- Files.worded(text, ballot != nil) do
      Files.locked(household_id, fn view ->
        write_thread(actor, household_id, view, {title, text, ballot})
      end)
    end
  end

  defp write_thread(actor, household_id, view, {title, text, ballot}) do
    thread = "threads/" <> Files.fresh_id(view, title)
    by = Core.author(household_id, actor)

    with :ok <- Gate.gate(actor, household_id, view, thread, :post),
         {:ok, opened} <- Documents.open_ballot(household_id, thread, ballot, actor),
         meta = Documents.thread_meta(title, by, actor) ++ Documents.ballot_meta(opened),
         path = Path.join(thread, @trunk),
         changes = [
           {:create, path, Files.render(meta, text <> Documents.bundle_text(opened))}
           | Core.descriptor(view, Kinds.named("thread"))
         ],
         {:ok, _} <- Files.commit(view, changes, "Post: #{title}", by) do
      {:ok,
       %{path: thread, title: title, ballot: opened && Map.take(opened, [:ballot, :closes_at])}}
    end
  end
end
