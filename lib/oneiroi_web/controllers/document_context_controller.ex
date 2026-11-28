defmodule OneiroiWeb.DocumentContextController do
  @moduledoc """
  What the one document screen shows around a document
  (design/document-threads.md §5): its thread in her own threads
  (seshat#106, #107) and in the house (seshat#109), the house queue's
  tasks it belongs to (sunna#91), and the review of it open for the
  caller, if any. The document's words are read where they always are:
  the library for hers, the household for the house's.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Queue
  alias OpenApiSpex.Schema

  tags(["documents"])

  @pull ~r{\Ahttps://github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)/?\z}

  operation(:show,
    summary:
      "Around one document, by its citation (<slug>:<path> for a resident's, house/<slug>:doc/<path> for the house's, a pin allowed): its thread in her own threads (mine), its thread in the house (house, for a house document or her file's shared copy), the tasks it belongs to, and the review of it open for the caller",
    parameters: [citation: [in: :query, type: :string, required: true]],
    responses: [ok: {"the context", "application/json", %Schema{type: :object}}]
  )

  def show(conn, params) do
    citation = to_string(params["citation"] || "") |> String.trim()
    key = Queue.doc_key(citation)
    actor = actor(conn)
    household = Gaia.household_of(actor)

    {mine, house_path, resident} = place(conn, key)
    open_review = if(household, do: review(household, Queue.me(actor), key))

    json(conn, %{
      citation: key,
      # The revision the screen shows (sunna#110, #112): an open review's
      # by its own artifact, as its decision reads it; else the screen's.
      revision: revision(household, (open_review && open_review.artifact) || citation),
      resident_id: resident,
      mine: mine,
      house: house_thread(actor, house_path),
      tasks: if(household, do: tasks(household, key), else: []),
      review: open_review
    })
  end

  # A citation's pin when it carries one (`@<commit>`); else the document
  # as a review's decision reads it (sunna#112): the commit that last
  # changed this file, the house's or a member's, exactly the head the
  # decision is checked against; or a pull request's head.
  defp revision(household, citation) do
    case String.split(citation, "@", parts: 2) do
      [_bare, pin] when pin != "" -> pin
      _unpinned -> current(household, citation)
    end
  end

  defp current(household, citation) do
    case Regex.run(@pull, citation) do
      [_all, repo, number] -> ok_or_nil(Oneiroi.Brain.pr_head(repo, number))
      nil -> if household, do: Oneiroi.Brain.queue_head(household, citation)
    end
  end

  defp ok_or_nil({:ok, sha}) when is_binary(sha), do: sha
  defp ok_or_nil(_other), do: nil

  # Hers: her one thread on it, and the house thread on its shared copy.
  # The house's: its thread there.
  defp place(conn, key) do
    case Seshat.house_citation(key) do
      {:ok, %{path: path}} -> {nil, path, nil}
      :error -> hers(conn, key)
    end
  end

  defp hers(conn, key) do
    with [slug, rest] <- String.split(key, ":", parts: 2),
         id when is_binary(id) <- witnessed(conn, slug) do
      path = if Path.extname(rest) == "", do: rest <> ".md", else: rest
      {mine(conn, id, path), Path.join(["shared", slug, path]), id}
    else
      _none -> {nil, nil, nil}
    end
  end

  defp mine(conn, id, path) do
    case Seshat.thread_for_document(actor(conn), id, path) do
      {:ok, t} -> t
      _none -> nil
    end
  end

  defp witnessed(conn, slug) do
    Enum.find(Gaia.witnessed_residents(actor(conn).id), fn id ->
      match?({:ok, %{slug: ^slug}}, AgathosDaimon.fetch(id))
    end)
  end

  defp house_thread(_actor, nil), do: nil

  defp house_thread(actor, path) do
    case Seshat.household_doc_thread(actor, path) do
      {:ok, t} -> t
      _none -> nil
    end
  end

  # A resident's file is cited with or without its `.md`.
  defp keys(key), do: Enum.uniq([key, String.replace_suffix(key, ".md", "")])

  defp tasks(household, key),
    do: keys(key) |> Enum.flat_map(&Sunna.queue_tasks_for_document(household, &1)) |> Enum.uniq()

  defp review(household, me, key) do
    wanted = keys(key)

    household
    |> Sunna.queue_activities(%{who: me, views: ["ready", "active"]})
    |> Enum.find(
      &(&1.type == "review" and is_binary(&1.artifact) and Queue.doc_key(&1.artifact) in wanted)
    )
  end
end
