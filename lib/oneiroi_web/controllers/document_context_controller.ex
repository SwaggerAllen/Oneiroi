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

    json(conn, %{
      citation: key,
      # The revision the screen shows (sunna#110): what a review of it,
      # approved here, names as its pin.
      revision: revision(actor, citation, key, resident),
      resident_id: resident,
      mine: mine,
      house: house_thread(actor, house_path),
      tasks: if(household, do: tasks(household, key), else: []),
      review: if(household, do: review(household, Queue.me(actor), key))
    })
  end

  # A citation's pin when it carries one (`@<commit>`); else the document
  # as it stands: a pull request's head, the house's commit, her
  # repository's head.
  defp revision(actor, citation, key, resident) do
    case String.split(citation, "@", parts: 2) do
      [_bare, pin] when pin != "" -> pin
      _unpinned -> current(actor, citation, key, resident)
    end
  end

  defp current(actor, citation, key, resident) do
    cond do
      pr = Regex.run(@pull, citation) -> pr_head(pr)
      match?({:ok, _}, Seshat.house_citation(key)) -> house_head(actor, key)
      is_binary(resident) -> ok_or_nil(Oneiroi.SimaQian.repository_head(resident))
      true -> nil
    end
  end

  defp pr_head([_all, repo, number]), do: ok_or_nil(Oneiroi.Brain.pr_head(repo, number))

  defp house_head(actor, key) do
    {:ok, cite} = Seshat.house_citation(key)

    case Seshat.household_read(actor, cite.path) do
      {:ok, %{commit: commit}} when is_binary(commit) -> commit
      _unread -> nil
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
