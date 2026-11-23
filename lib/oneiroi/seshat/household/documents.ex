defmodule Oneiroi.Seshat.Household.Documents do
  @moduledoc """
  Document posts (seshat#83) and sharing modes (seshat#82): a thread
  opened on a household document, a document posted from the resident's
  own folder, the draft-changed reply, and the trunk's and the ballot's
  frontmatter that plain posts share.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian.Repos

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  # The closing job by name, as an atom: it calls back into this module,
  # and an alias here would be the cycle the gate refuses.
  @ballot_worker :"Elixir.Oneiroi.Seshat.HouseholdBallotWorker"
  @trunk "trunk.md"

  # ---- document posts (seshat#83) ----

  @doc false
  # A document post: a thread whose trunk is a citation of a household
  # document, flagged `doc:`, pinned at its latest commit, which reads as
  # the document itself; feedback on it is its replies.
  def post_doc_thread(actor, household_id, view, attrs) do
    text = to_string(attrs["content"] || "")

    with {:ok, path} <- Files.household_path(attrs["doc"]),
         false <- Kinds.container?(Kinds.kind_of(path)),
         doc when is_binary(doc) <- Files.file(view, path) || absent(path),
         {meta, _body} = Files.frontmatter(doc),
         title =
           Files.one_line(attrs["title"]) || "On #{meta["title"] || Path.basename(path, ".md")}",
         :ok <- Files.titled(title) do
      Files.locked(household_id, &write_doc_thread(actor, household_id, &1, {path, title, text}))
    else
      true -> {:error, Error.new(:seshat_household_invalid, :seshat_household_doc_post_thread)}
      other -> other
    end
  end

  defp write_doc_thread(actor, household_id, view, {path, title, text}) do
    thread = "threads/" <> Files.fresh_id(view, title)
    by = Core.author(household_id, actor)
    commit = Files.doc_commit(view, path)

    with :ok <- Gate.gate(actor, household_id, view, thread, :post),
         meta =
           thread_meta(title, by, actor) ++
             [{"doc", path}] ++ Files.optional("doc_commit", commit),
         body =
           "A document post on #{path}#{Files.draft_at(commit)}." <>
             if(String.trim(text) == "", do: "", else: "\n\n" <> text),
         changes = [
           {:create, Path.join(thread, @trunk), Files.render(meta, body)}
           | Core.descriptor(view, Kinds.named("thread"))
         ],
         {:ok, _} <- Files.commit(view, changes, "Post: #{title}", by) do
      {:ok, %{path: thread, title: title, doc: path, doc_commit: commit, ballot: nil}}
    end
  end

  @doc false
  # A household document's one thread (seshat#109): the oldest posted on
  # it, or nil.
  def doc_thread(view, doc) do
    case Files.household_path(doc) do
      {:ok, path} ->
        view
        |> Files.thread_ids()
        |> Enum.flat_map(&on_doc(view, "threads/" <> &1, path))
        |> Enum.min_by(&{&1.posted_at, &1.path}, fn -> nil end)
        |> then(&(&1 && Map.delete(&1, :posted_at)))

      _not_a_path ->
        nil
    end
  end

  defp on_doc(view, thread, path) do
    case Files.load_thread(view, thread) do
      {:ok, %{trunk: %{meta: %{"doc" => ^path} = meta}}} ->
        [%{path: thread, title: meta["title"], doc: path, posted_at: meta["posted_at"] || ""}]

      _other ->
        []
    end
  end

  @doc false
  # The platform's line in a household document's one thread (seshat#110,
  # a review's decision), opening the thread under the platform's name
  # when it has none: never gated, never a member's quota.
  def platform_note(household_id, path, text) do
    Files.locked(household_id, fn view ->
      commit = Files.doc_commit(view, path)

      case doc_thread(view, path) do
        nil -> platform_thread(view, path, commit, text)
        %{path: thread} -> platform_reply(view, {thread, path}, commit, text)
      end
    end)
  end

  defp platform_thread(view, path, commit, text) do
    thread = "threads/" <> Files.fresh_id(view, "on-" <> Path.basename(path, ".md"))

    meta =
      [
        {"title", "On #{Path.basename(path, ".md")}"},
        {"by", @platform.name},
        {"by_kind", "platform"},
        {"posted_at", Files.iso(Clock.now())},
        {"doc", path}
      ] ++ Files.optional("doc_commit", commit)

    body = "A document post on #{path}#{Files.draft_at(commit)}.\n\n" <> text

    changes = [
      {:create, Path.join(thread, @trunk), Files.render(meta, body)}
      | Core.descriptor(view, Kinds.named("thread"))
    ]

    with {:ok, _} <- Files.commit(view, changes, "Post: on #{path}", @platform),
         do: {:ok, %{path: thread}}
  end

  defp platform_reply(view, {thread, path}, commit, text) do
    number = Files.next_reply(view, thread)

    meta =
      [
        {"by", @platform.name},
        {"by_kind", "platform"},
        {"at", Files.iso(Clock.now())},
        {"reply", Integer.to_string(number)}
      ] ++ Files.optional("doc_commit", commit)

    change = {:create, Files.reply_path(thread, number, "oneiroi"), Files.render(meta, text)}

    with {:ok, _} <- Files.commit(view, [change], "Reply ##{number} on #{path}", @platform),
         do: {:ok, %{path: thread, reply: number}}
  end

  @doc false
  # After an edit, a line in every thread on the document saying its
  # draft changed (seshat#83), so which draft is being talked about is
  # plain at every point and the latest draft's talk can be found. The
  # platform's lines, in their own commit, never gated.
  def draft_changed(household_id, path, from, to) do
    {:ok, view} = Files.view(household_id)

    changes =
      for id <- Files.thread_ids(view),
          thread = "threads/" <> id,
          {:ok, t} <- [Files.load_thread(view, thread)],
          t.trunk.meta["doc"] == path do
        number = Files.next_reply(view, thread)

        meta = [
          {"by", @platform.name},
          {"by_kind", "platform"},
          {"at", Files.iso(Clock.now())},
          {"reply", Integer.to_string(number)},
          {"draft", "changed"},
          {"doc_commit", to}
        ]

        {:create, Files.reply_path(thread, number, "oneiroi"),
         Files.render(meta, "Draft changed: #{Files.short(from || "")} → #{Files.short(to)}.")}
      end

    _ = Files.commit(view, changes, "Draft changed: #{path}", @platform)
    :ok
  end

  @doc false
  def thread_meta(title, by, actor),
    do: [
      {"title", title},
      {"by", by.name},
      {"by_kind", Atom.to_string(actor.kind)},
      {"by_id", actor.id},
      {"posted_at", Files.iso(Clock.now())}
    ]

  @doc false
  def open_ballot(_household_id, _thread, nil, _actor), do: {:ok, nil}

  def open_ballot(household_id, thread, ballot, actor) when is_map(ballot) do
    b = Map.new(ballot, fn {k, v} -> {to_string(k), v} end)

    with {:ok, opened} <-
           Gaia.open_household_ballot(
             household_id,
             thread,
             b["bundle"],
             b["term_days"],
             to_string(b["note"] || "a ballot opened in the household"),
             actor
           ),
         {:ok, _job} <-
           Jobs.enqueue(
             @ballot_worker,
             %{"household_id" => household_id, "ballot" => opened.ballot},
             scheduled_at: opened.closes_at
           ) do
      {:ok, Map.put(opened, :term_days, b["term_days"])}
    end
  end

  def open_ballot(_household_id, _thread, _other, _actor),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_ballot_shape)}

  @doc false
  def ballot_meta(nil), do: []

  def ballot_meta(o),
    do: [
      {"ballot", Integer.to_string(o.ballot)},
      {"term_days", Integer.to_string(o.term_days)},
      {"closes_at", Files.iso(o.closes_at)}
    ]

  @doc false
  def bundle_text(nil), do: ""

  def bundle_text(o) do
    items =
      o.bundle
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {%{"rule" => r}, i} -> "#{i}. Rule: #{r}"
        {%{"setting" => k, "value" => v}, i} -> "#{i}. Setting: #{k} = #{Core.inspect_value(v)}"
      end)

    """


    ## Ballot ##{o.ballot}: the bundle, voted on as a unit

    #{items}

    Fixed when the ballot opened; nothing is added, changed or removed while it runs. Every member, witness or resident, votes once by replying with a vote of yes or no, until #{Files.iso(o.closes_at)}. A majority of the members carries the whole bundle into the contract; otherwise the whole of it fails.
    """
  end

  # A kind the platform renders (a task's index document, seshat#104) is
  # never written by a post: the queue is where it changes.
  defp not_rendered(path) do
    if Kinds.kind_of(path).access == :core,
      do: {:error, Error.new(:seshat_household_invalid, :seshat_household_document_rendered)},
      else: :ok
  end

  @doc false
  def post_document(actor, household_id, _view, attrs) do
    title = Files.one_line(attrs["title"])

    with :ok <- path_given(attrs["path"]),
         {:ok, path} <- Files.household_path(attrs["path"]),
         false <- Kinds.container?(Kinds.kind_of(path)),
         :ok <- not_rendered(path),
         :ok <- own_folder(actor, path),
         {:ok, sharing} <- sharing(attrs, actor),
         {:ok, text, source} <- words_from(actor, attrs),
         text = text || "",
         :ok <- Files.worded(text, false) do
      Files.locked(household_id, fn view ->
        write_document(actor, household_id, view, {path, title, text, sharing ++ source})
      end)
    else
      true ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_document_in_threads)}

      other ->
        other
    end
  end

  defp write_document(actor, household_id, view, {path, title, text, sharing}) do
    by = Core.author(household_id, actor)
    meta = thread_meta(title || Path.basename(path, ".md"), by, actor) ++ sharing

    with :ok <- Gate.document_gate(actor, household_id, view, path),
         false <- Files.has?(view, path),
         changes = [
           {:create, path, Files.render(meta, text)} | Core.descriptor(view, Kinds.kind_of(path))
         ],
         {:ok, _} <- Files.commit(view, changes, "Post: #{path}", by) do
      {:ok, %{path: path, title: title}}
    else
      true ->
        {:error,
         Error.new(:seshat_household_written, :seshat_household_document_exists, path: path)}

      other ->
        other
    end
  end

  # ---- sharing modes and the owner (seshat#82) ----

  # A document's sharing, as its front matter says it: `owner` mode (the
  # default), its owner the poster, who alone edits it while the others'
  # edits are feedback; `open`, everyone edits. Posted with `owner: false`
  # it has no owner and is open, for the flows a resident automates.
  defp sharing(attrs, %Actor{id: id}) do
    case {attrs["mode"] || "owner", attrs["owner"]} do
      {_mode, false} -> {:ok, [{"mode", "open"}]}
      {mode, _} when mode in ["owner", "open"] -> {:ok, [{"owner_id", id}, {"mode", mode}]}
      _other -> {:error, Error.new(:seshat_household_invalid, :seshat_household_mode_unknown)}
    end
  end

  # ---- the source-and-revision link (seshat#84) ----

  @doc false
  # A document's words, given (`content`) or copied from a file of the
  # resident's own (`from`, a path in her repository), which the copy
  # names as its source at the commit it was copied at, `<slug>:<path>@
  # <commit>`, so her local draft never becomes a quiet competing
  # edition; her own front matter stays behind.
  # A book and her reading of it stay hers (seshat#98).
  def words_from(%Actor{kind: :resident}, %{"from" => "books/" <> _ = from}),
    do: {:error, Error.new(:seshat_book_private, :seshat_household_source_book, path: from)}

  def words_from(%Actor{kind: :resident, id: id}, %{"from" => from}) when is_binary(from) do
    repo = {:resident, id}

    with {:ok, text, _blob} <- Repos.read(repo, from),
         {:ok, [%{commit: commit} | _]} <- Repos.history(repo, from, 1),
         {:ok, r} <- AgathosDaimon.fetch(id) do
      {_meta, body} = Files.frontmatter(text)
      {:ok, body, [{"source", "#{r.slug}:#{from}@#{Files.short(commit)}"}]}
    else
      _absent ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_source_absent,
           path: from
         )}
    end
  end

  def words_from(%Actor{}, %{"from" => from}) when is_binary(from),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_source_residents)}

  def words_from(_actor, attrs) do
    if is_binary(attrs["content"]), do: {:ok, attrs["content"], []}, else: {:ok, nil, []}
  end

  @doc false
  def absent(path),
    do:
      {:error,
       Error.new(:seshat_household_no_such_document, :seshat_household_edit_absent, path: path)}

  # A document posted with no path is told so first (2026-11-18, Lily's
  # letter #1175: the path's format, given alone, read as a format fault
  # through eight tries).
  defp path_given(path) do
    if is_binary(path) and String.trim(path) != "",
      do: :ok,
      else: {:error, Error.new(:seshat_household_no_path, :seshat_household_document_no_path)}
  end

  # Whose folder a household document goes in (seshat#81): a witness's
  # in human/<their name>/, made by its first file; a resident's in a
  # household kind's folder, never in human/.
  defp own_folder(%Actor{kind: :witness, id: id}, path) do
    case Gaia.witness_folder(id) do
      nil ->
        {:error, Error.new(:seshat_witness_unnamed, :seshat_household_witness_unnamed)}

      folder ->
        if String.starts_with?(path, "human/#{folder}/") and length(Path.split(path)) == 3,
          do: :ok,
          else:
            {:error,
             Error.new(:seshat_not_your_folder, :seshat_household_not_your_folder,
               path: path,
               folder: "human/#{folder}/"
             )}
    end
  end

  defp own_folder(%Actor{}, "human/" <> _ = path),
    do:
      {:error,
       Error.new(:seshat_household_invalid, :seshat_household_human_is_witnesses, path: path)}

  defp own_folder(%Actor{}, _path), do: :ok
end
