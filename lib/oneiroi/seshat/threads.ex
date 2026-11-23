defmodule Oneiroi.Seshat.Threads do
  @moduledoc """
  A resident's own threads (seshat#106, design/document-threads.md): the
  workspace the resident and her witness share, holding threads the way
  the house does, in her own repository, under the same layout
  (`threads/<id>/trunk.md`, `threads/<id>/replies/<nnnn>-<author>.md`)
  and through the same files (`Household.Files`).

  Its audience is the dyad: she and her witness write and read it, and
  nothing in it reaches the house, a housemate or a house citation. The
  house's machinery stays the house's: no beats, no quota, no ballots,
  no rounds, no mentions. A document has one thread here, opened by the
  first post on it and found again by every later one (seshat#107). A
  reply by her witness wakes her main chat with a letter naming the
  thread and the reply, never the words (seshat#108).
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian.Repos

  @trunk "trunk.md"
  @watch_actor Actor.new(:job, "resident_threads")

  @doc "Every thread in her space, the last active first, each with its document if it has one."
  def list(%Actor{} = actor, resident_id) do
    with :ok <- party(actor, resident_id),
         {:ok, view} <- view(resident_id) do
      threads =
        view
        |> Files.thread_ids()
        |> Enum.map(&summary(view, &1))
        |> Enum.sort_by(&(&1.last_reply_at || &1.posted_at || ""), :desc)

      {:ok, %{threads: threads}}
    end
  end

  @doc "One thread whole: its trunk, its replies, its document as it stands, and the text a turn reads."
  def read(%Actor{} = actor, resident_id, name) do
    with :ok <- party(actor, resident_id),
         {:ok, view} <- view(resident_id),
         thread when is_binary(thread) <- Files.thread_path(name) || Files.no_thread(name),
         {:ok, t} <- Files.load_thread(view, thread) do
      doc = Files.posted_doc(view, t)

      {:ok,
       %{
         path: thread,
         title: t.trunk.meta["title"],
         trunk: %{meta: t.trunk.meta, body: t.trunk.body},
         replies: Enum.map(t.replies, &%{meta: &1.meta, body: &1.body}),
         doc: doc && Map.take(doc, [:path, :commit, :present]),
         text: Files.thread_text(thread, t, nil, doc)
       }}
    end
  end

  @doc "The thread on one of her documents, or nil: the document's one thread in her space."
  def for_document(%Actor{} = actor, resident_id, path) do
    with :ok <- party(actor, resident_id),
         {:ok, view} <- view(resident_id) do
      {:ok, thread_on(view, path)}
    end
  end

  @doc """
  Posts a thread (title and content), or a document's thread (doc: one of
  her documents' paths). A document has one thread: posting on it again
  answers the thread it has, the words, if any, added as a reply.
  """
  def post(%Actor{} = actor, resident_id, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with :ok <- party(actor, resident_id) do
      case Files.blank(attrs["doc"]) do
        nil -> post_thread(actor, resident_id, attrs)
        doc -> post_on_doc(actor, resident_id, doc, attrs)
      end
    end
  end

  @doc "Replies in one of her threads; her witness's reply wakes her chat."
  def reply(%Actor{} = actor, resident_id, name, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    text = to_string(attrs["content"] || "")

    with :ok <- party(actor, resident_id),
         :ok <- Files.worded(text, false),
         thread when is_binary(thread) <- Files.thread_path(name) || Files.no_thread(name),
         reply = {text, Files.integer(attrs["in_reply_to"])},
         {:ok, written} <- locked(resident_id, &reply_in(&1, actor, thread, reply)) do
      poke(actor, resident_id, thread, written)
      {:ok, Map.put(written, :thread, thread)}
    end
  end

  defp reply_in(view, actor, thread, {text, in_reply_to}) do
    with {:ok, t} <- Files.load_thread(view, thread),
         do: append(actor, view, {thread, t}, text, in_reply_to)
  end

  # ---- who ----

  # She and her witness, and the platform writing for either. A resident
  # whose agreement is not in force writes nothing here either
  # (agathos-daimon#51).
  defp party(%Actor{kind: :resident, id: id}, id) do
    if AgathosDaimon.held?(id), do: not_party(), else: :ok
  end

  defp party(%Actor{kind: :witness, id: account}, resident_id) do
    if resident_id in Gaia.witnessed_residents(account), do: :ok, else: not_party()
  end

  defp party(%Actor{kind: kind}, _resident_id) when kind in [:platform, :job], do: :ok

  defp party(%Actor{}, _resident_id), do: not_party()

  defp not_party,
    do: {:error, Error.new(:seshat_threads_not_party, :seshat_threads_not_party)}

  # ---- writing ----

  defp post_thread(actor, resident_id, attrs) do
    title = Files.one_line(attrs["title"])
    text = to_string(attrs["content"] || "")

    with :ok <- Files.titled(title),
         :ok <- Files.worded(text, false) do
      locked(resident_id, fn view ->
        trunk(actor, view, title, text, [])
      end)
      |> poked(actor, resident_id)
    end
  end

  defp post_on_doc(actor, resident_id, doc, attrs) do
    text = to_string(attrs["content"] || "")

    with {:ok, path} <- document(resident_id, doc),
         :ok <- Files.worded(text, true) do
      title = Files.one_line(attrs["title"]) || "On #{path}"

      resident_id
      |> locked(&on_doc(&1, actor, path, {title, text}))
      |> poked(actor, resident_id)
    end
  end

  defp on_doc(view, actor, path, {title, text}) do
    cond do
      not Files.has?(view, path) ->
        {:error, Error.new(:seshat_threads_no_document, :seshat_threads_doc_absent, path: path)}

      existing = thread_on(view, path) ->
        again(actor, view, existing, text)

      true ->
        open_on_doc(view, actor, path, {title, text})
    end
  end

  defp open_on_doc(view, actor, path, {title, text}) do
    with :ok <- Files.titled(title) do
      meta = [{"doc", path}] ++ Files.optional("doc_commit", Files.doc_commit(view, path))
      body = if String.trim(text) == "", do: "A thread on #{path}.", else: text
      trunk(actor, view, title, body, meta)
    end
  end

  # Posting on a document that has its thread answers that thread; words,
  # when there are any, are a reply in it.
  defp again(actor, view, existing, text) do
    if String.trim(text) == "" do
      {:ok, Map.merge(existing, %{existing: true})}
    else
      {:ok, t} = Files.load_thread(view, existing.path)

      with {:ok, w} <- append(actor, view, {existing.path, t}, text, nil),
           do: {:ok, Map.merge(existing, %{existing: true, reply: w.number})}
    end
  end

  defp trunk(actor, view, title, text, doc_meta) do
    thread = "threads/" <> Files.fresh_id(view, title)
    by = Repos.author(actor)

    meta =
      [
        {"title", title},
        {"by", by.name},
        {"by_kind", Atom.to_string(actor.kind)},
        {"by_id", actor.id},
        {"posted_at", Files.iso(Clock.now())}
      ] ++ doc_meta

    changes = [{:create, Path.join(thread, @trunk), Files.render(meta, text)} | descriptor(view)]

    with {:ok, _} <- Files.commit(view, changes, "Thread: #{title}", by),
         do: {:ok, %{path: thread, title: title, doc: Files.blank(meta_doc(doc_meta))}}
  end

  defp meta_doc(meta), do: Enum.find_value(meta, fn {k, v} -> if k == "doc", do: v end)

  defp append(actor, view, {thread, t}, text, in_reply_to) do
    number = Files.next_reply(view, thread)
    by = Repos.author(actor)

    stamp =
      case t.trunk.meta["doc"] do
        nil -> []
        path -> Files.optional("doc_commit", Files.doc_commit(view, path))
      end

    meta =
      [
        {"by", by.name},
        {"by_kind", Atom.to_string(actor.kind)},
        {"by_id", actor.id},
        {"at", Files.iso(Clock.now())},
        {"reply", Integer.to_string(number)}
      ] ++
        Files.optional("in_reply_to", in_reply_to && Integer.to_string(in_reply_to)) ++ stamp

    path = Files.reply_path(thread, number, by.name)

    with {:ok, _} <-
           Files.commit(
             view,
             [{:create, path, Files.render(meta, text)}],
             "Reply ##{number} to #{t.trunk.meta["title"]}",
             by
           ),
         do: {:ok, %{path: path, number: number}}
  end

  # ---- her chat ----

  defp poked({:ok, %{path: thread} = posted} = ok, actor, resident_id) do
    poke(actor, resident_id, thread, posted)
    ok
  end

  defp poked(other, _actor, _resident_id), do: other

  # Her witness's words in her space wake her main chat (the witness,
  # 2026-11-23): a letter naming the thread and the reply, never the
  # words, from a sender the tick wakes the chat for (sunna#49). Her own
  # writes, and the platform's, wake nobody.
  defp poke(%Actor{kind: :witness}, resident_id, thread, written) do
    where =
      case written do
        %{number: n} -> "reply ##{n} in"
        %{reply: n} -> "reply ##{n} in"
        _new -> "a new thread,"
      end

    text =
      "Your witness wrote #{where} #{thread} in your own threads. " <>
        "household_read with space: mine and that path reads it; household_reply with space: mine answers."

    _ = Kumbukumbu.send_letter(resident_id, nil, %{to: "Oneiroi chat", text: text}, @watch_actor)
    :ok
  end

  defp poke(_actor, _resident_id, _thread, _written), do: :ok

  # ---- her repository ----

  defp view(resident_id) do
    repo = {:resident, resident_id}
    with {:ok, files} <- Repos.snapshot(repo), do: {:ok, %{repo: repo, files: files}}
  end

  # Her space's writes in order, one at a time, as the house's are.
  defp locked(resident_id, fun) do
    :global.trans({{__MODULE__, resident_id}, self()}, fn ->
      with {:ok, view} <- view(resident_id), do: fun.(view)
    end)
  end

  # One of her documents: a path of a kind of hers, never a thread.
  defp document(resident_id, doc) do
    with {:ok, path} <- Kinds.normalize(resident_id, String.trim(to_string(doc))) do
      if String.starts_with?(path, "threads/"),
        do:
          {:error, Error.new(:seshat_threads_no_document, :seshat_threads_doc_thread, path: path)},
        else: {:ok, path}
    end
  end

  @doc false
  # The document's one thread (seshat#107): the oldest posted on it.
  def thread_on(view, path) do
    view
    |> Files.thread_ids()
    |> Enum.sort()
    |> Enum.find_value(fn id ->
      thread = "threads/" <> id

      case Files.load_thread(view, thread) do
        {:ok, %{trunk: %{meta: %{"doc" => ^path} = meta}} = t} ->
          %{path: thread, title: meta["title"], doc: path, replies: length(t.replies)}

        _other ->
          nil
      end
    end)
  end

  defp summary(view, id) do
    thread = "threads/" <> id
    {:ok, t} = Files.load_thread(view, thread)
    last = List.last(t.replies)

    %{
      path: thread,
      title: t.trunk.meta["title"],
      by: t.trunk.meta["by"],
      by_kind: t.trunk.meta["by_kind"],
      posted_at: t.trunk.meta["posted_at"],
      doc: t.trunk.meta["doc"],
      replies: length(t.replies),
      last_reply_at: last && last.meta["at"],
      last_by: last && last.meta["by"]
    }
  end

  # The thread kind's descriptor in her repository, written once, for a
  # reader of it with no platform beside it.
  defp descriptor(view) do
    kind = Kinds.named("thread")
    path = Path.join(kind.folder, Kinds.descriptor_name())

    if Files.has?(view, path) do
      []
    else
      body = %{
        "kind" => kind.kind,
        "folder" => kind.folder,
        "label" => kind[:label] || kind.kind,
        "layout" => kind.layout,
        "container" => Kinds.container?(kind),
        "cites" => kind.cites,
        "access" => "dyad",
        "written_by" =>
          "the resident and her witness, each under their own name; no one else reads"
      }

      [{:create, path, Jason.encode_to_iodata!(body, pretty: true)}]
    end
  end
end
