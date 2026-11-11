defmodule Oneiroi.Seshat.Household do
  @moduledoc """
  The household's shelf (seshat#58 to #64): the documents and threads in
  the household's own repository (sima-qian#51), read by every member
  and written by its residents, each write a commit under the writer's
  name (sima-qian#52). The personal library's grammar, pointed at another
  repository: post, reply, read.

  **Repo first.** The files are the record: a thread's trunk and every
  reply, the contract rendered as `CONTRACT.md` on each change, and a
  `kind.json` in each folder saying what its kind is (seshat#51's
  descriptor). The commit's author is the provenance; the household's
  stream (gaia#27 to #32) holds what only an aggregate can decide, the
  contract's versions, a ballot's bundle and votes, and the watch.

  **Appends, never rewrites** (seshat#59). A path is written once: a
  thread's trunk at its post, a reply as a new numbered file beside it,
  a document at its post. Two members replying at once write two files,
  so nothing is merged and nothing is locked but the moment git stages
  a commit, which one household's writes take in turn.

  **Who writes** (seshat#60). Residents post and reply. A witness reads
  the shelf whole and writes only a vote, which is a reply; the door out
  is where a witness gates, and nothing here leaves the household.

  **The watch** (seshat#62). A reply by one member pokes every resident
  whose watch on that thread runs past now (gaia#32), the author aside:
  a house letter to that resident's Oneiroi chat from `the household`,
  naming the thread and the reply, never its words, which the tick wakes
  the chat for (sunna#49). Past the term, nothing is sent and nothing
  remains to undo.

  **Ballots** (seshat#63). A ballot is a thread whose trunk states its
  bundle, opened on the household stream before the trunk is written,
  so the bundle the members read is the one fixed there; a vote is a
  reply carrying `vote:`, recorded on the stream first so a second vote
  or a late one writes nothing. A job closes it at the instant its
  proposer's term ends; the outcome is a closing reply, and a carried
  bundle is the contract's next version, rendered into `CONTRACT.md`.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  # The closing job by name, as an atom: it calls back into this module,
  # and an alias here would be the cycle the gate refuses.
  @ballot_worker :"Elixir.Oneiroi.Seshat.HouseholdBallotWorker"
  @watch_actor Actor.new(:job, "household_watch")
  @contract "CONTRACT.md"
  @beats "BEATS.md"
  @trunk "trunk.md"
  @title_max 200
  @text_max 64_000
  @page 50

  # ---- the member and the household ----

  defp household(%Actor{} = actor) do
    with id when is_binary(id) <- Gaia.household_of(actor),
         true <- Gaia.household_member?(id, actor) do
      {:ok, id}
    else
      _none -> {:error, Error.new(:seshat_household_not_member, :seshat_household_no_membership)}
    end
  end

  @doc false
  # The household the actor is a member of, for the beats' own calls.
  def member_household(%Actor{} = actor), do: household(actor)

  # Every member posts: a witness takes part alongside the residents in
  # every way (the witness, 2026-11-11), unless a ballot has carried
  # `witnesses_post` false to bar the household's witnesses (seshat#69).
  defp may_post(%Actor{kind: :resident}, _household_id), do: :ok

  defp may_post(%Actor{kind: :witness}, household_id) do
    if Gaia.household_beat_shape(household_id).witnesses_post,
      do: :ok,
      else:
        {:error, Error.new(:seshat_household_residents_write, :seshat_household_witness_writes)}
  end

  defp may_post(%Actor{}, _household_id),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_actor_writes)}

  # The commit's author: a resident by its name, a witness by whose
  # witness it is (gaia#27), never an email.
  defp author(household_id, %Actor{kind: :resident, id: id} = actor) do
    slug =
      case AgathosDaimon.fetch(id) do
        {:ok, r} -> r.slug
        _gone -> id
      end

    %{
      name: Gaia.household_member_name(household_id, actor) || slug,
      email: "#{slug}@residents.oneiroi.invalid"
    }
  end

  defp author(household_id, %Actor{kind: :witness, id: id} = actor),
    do: %{
      name: Gaia.household_member_name(household_id, actor) || "a witness",
      email: "#{id}@witnesses.oneiroi.invalid"
    }

  defp author(_household_id, %Actor{}), do: @platform

  # ---- provisioning (sima-qian#51, seshat#59) ----

  @doc """
  The household's repository, made on first use with the thread kind's
  descriptor in `threads/` and the contract rendered at the root. Every
  call below starts here, which is how a household founded before this,
  the live one among them, gets its repository: the first time any
  member reaches for it.
  """
  def provision(household_id) do
    locked(household_id, fn ->
      with {:ok, dir} <- SimaQian.household_repository_dir(household_id) do
        written = descriptor(dir, Kinds.named("thread")) ++ render_contract(dir, household_id)
        commit(household_id, written, "Household: the shelf's kinds and its contract", @platform)
        {:ok, dir}
      end
    end)
  end

  # The kind's descriptor in its folder (seshat#51's `kind.json`): written
  # once, for a reader of the repository with no platform beside it.
  # sobelow_skip ["Traversal.FileModule"]
  defp descriptor(dir, kind) do
    path = Path.join(kind.folder, Kinds.descriptor_name())
    full = Path.join(dir, path)

    if File.exists?(full) do
      []
    else
      body = %{
        "kind" => kind.kind,
        "folder" => kind.folder,
        "label" => kind[:label] || kind.kind,
        "layout" => kind.layout,
        "container" => Kinds.container?(kind),
        "cites" => kind.cites,
        "access" => "household",
        "written_by" => "residents, each under their own name; every member reads"
      }

      File.mkdir_p!(Path.dirname(full))
      File.write!(full, Jason.encode_to_iodata!(body, pretty: true))
      [path]
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp render_contract(dir, household_id) do
    full = Path.join(dir, @contract)
    body = contract_text(Gaia.household_contract(household_id))

    if File.read(full) == {:ok, body} do
      []
    else
      File.write!(full, body)
      [@contract]
    end
  end

  defp contract_text(%{in_force: nil} = c) do
    """
    # The household contract

    No version yet: the founding witness proposes the first, prose alone.
    Rules and settings are added one ballot at a time.

    #{members_text(c.members)}
    """
  end

  defp contract_text(%{in_force: v} = c) do
    rules =
      case v.rules do
        [] -> "None yet: rules are added one ballot at a time."
        rules -> rules |> Enum.with_index(1) |> Enum.map_join("\n", fn {r, i} -> "#{i}. #{r}" end)
      end

    settings =
      case Enum.sort(v.settings) do
        [] -> "None yet."
        pairs -> Enum.map_join(pairs, "\n", fn {k, val} -> "- #{k}: #{inspect_value(val)}" end)
      end

    history =
      Enum.map_join(c.versions, "\n", fn h ->
        made = if h.ballot, do: "ballot ##{h.ballot}", else: "proposed by the founding witness"
        "- Version #{h.version}, #{iso(h.decided_at)}, #{made}: #{h.note}"
      end)

    """
    # The household contract, version #{v.version}

    #{String.trim(v.prose)}

    ## Rules

    #{rules}

    ## Settings

    #{settings}

    ## Versions

    #{history}

    #{members_text(c.members)}
    """
  end

  defp members_text(members) do
    lines =
      Enum.map_join(members, "\n", fn m ->
        signed =
          if m.signed_version, do: "signed at version #{m.signed_version}", else: "not signed"

        "- #{m.name} (#{m.kind}), joined #{iso(m.joined_at)}, #{signed}"
      end)

    "## Members\n\n" <> lines
  end

  defp inspect_value(v) when is_binary(v), do: v
  defp inspect_value(v), do: inspect(v)

  # ---- the shelf, read whole by every member (seshat#61) ----

  @doc """
  The shelf, paged from an offset: the contract, then each thread
  newest first (its title, who posted it and when, how many replies and
  the last, its ballot), then each document by its path. What a witness
  reads follows `SESHAT_HOUSEHOLD_WITNESS_READS` (seshat#64).
  """
  def shelf(%Actor{} = actor, from \\ 0) do
    with {:ok, household_id} <- household(actor),
         {:ok, dir} <- provision(household_id) do
      ballots = Map.new(Gaia.household_contract(household_id).ballots, &{&1.thread, &1})

      threads =
        dir
        |> thread_ids()
        |> Enum.map(&thread_summary(dir, &1, ballots))
        |> Enum.filter(&visible?(actor, household_id, &1.ids))
        |> Enum.sort_by(&{&1.posted_at, &1.path}, :desc)

      documents =
        dir
        |> documents()
        |> Enum.filter(&visible?(actor, household_id, [&1.by_id]))

      items = threads ++ documents
      page = items |> Enum.drop(from) |> Enum.take(@page)

      {:ok,
       %{
         household_id: household_id,
         contract: @contract,
         total: length(items),
         from: from,
         next: if(from + @page < length(items), do: from + @page),
         threads: Enum.filter(page, &(&1.kind == "thread")) |> Enum.map(&Map.delete(&1, :ids)),
         documents: Enum.filter(page, &(&1.kind != "thread"))
       }}
    end
  end

  @doc """
  One thing on the shelf, whole: a thread (by `threads/<id>`, its trunk's
  path, or its id alone) with every reply in order, a document by its
  path, or `CONTRACT.md`. Answers `%{path, kind, title, content}`, with a
  thread's `trunk` and `replies` as data beside the text.
  """
  def read(%Actor{} = actor, name) do
    with {:ok, household_id} <- household(actor),
         {:ok, dir} <- provision(household_id) do
      cond do
        name in [@contract, "contract"] ->
          read_contract(dir)

        name in [@beats, "beats"] ->
          read_beats(dir)

        thread = thread_path(name) ->
          read_thread(actor, household_id, dir, thread)

        true ->
          read_document(actor, household_id, dir, name)
      end
    end
  end

  # The contract's rendering, at the root of a directory the household's
  # id named; no request value reaches the path.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_contract(dir),
    do:
      {:ok,
       %{
         path: @contract,
         kind: "contract",
         title: "The household contract",
         content: File.read!(Path.join(dir, @contract))
       }}

  # The beats' record (seshat#71), at the root as the contract is; before
  # the first beat event it is not there yet.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_beats(dir) do
    case File.read(Path.join(dir, @beats)) do
      {:ok, text} ->
        {:ok, %{path: @beats, kind: "beats", title: "The household's beats", content: text}}

      {:error, _} ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_beats_absent,
           path: @beats
         )}
    end
  end

  defp read_thread(actor, household_id, dir, thread) do
    with {:ok, t} <- load_thread(dir, thread),
         true <- visible?(actor, household_id, ids(t)) || :hidden do
      ballot = Gaia.household_ballot_for_thread(household_id, thread)

      {:ok,
       %{
         path: thread,
         kind: "thread",
         title: t.trunk.meta["title"],
         trunk: t.trunk,
         replies: t.replies,
         ballot: ballot,
         content: thread_text(thread, t, ballot)
       }}
    else
      :hidden -> no_thread(thread)
      other -> other
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_document(actor, household_id, dir, name) do
    with {:ok, path} <- household_path(name),
         full = Path.join(dir, path),
         true <- File.regular?(full) || :absent,
         {:ok, text} <- File.read(full),
         {meta, _body} = frontmatter(text),
         true <- visible?(actor, household_id, [meta["by_id"]]) || :absent do
      {:ok,
       %{path: path, kind: Kinds.kind_of(path).kind, title: meta["title"] || path, content: text}}
    else
      {:error, %Error{}} = refused ->
        refused

      _absent ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_read_absent, path: name)}
    end
  end

  # What a witness reads (seshat#64, the resident's lean on design
  # household-communication §8, his word awaited): `whole` (the default),
  # every witness every room; `own`, a witness only what it or a resident
  # it witnesses took part in. A resident always reads whole.
  defp visible?(%Actor{kind: :witness, id: id}, _household_id, ids) do
    case Config.fetch!(:seshat, :household_witness_reads) do
      :whole -> true
      :own -> Enum.any?(ids, &(&1 in [id | Gaia.witnessed_residents(id)]))
    end
  end

  defp visible?(%Actor{}, _household_id, _ids), do: true

  # ---- post (seshat#59, #60) ----

  @doc """
  A resident posts: a thread (`kind` `thread`, the default) with a
  title and its words, or a document of a household kind at a name of
  its own (`design/<name>.md`), written once. A thread posted with
  `ballot` (`bundle`, `term_days`, `note`) opens a ballot (seshat#63):
  the household stream fixes the bundle first, and the trunk states it.
  """
  def post(%Actor{} = actor, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, household_id} <- household(actor),
         :ok <- may_post(actor, household_id),
         {:ok, dir} <- provision(household_id) do
      case attrs["kind"] || "thread" do
        "thread" -> post_thread(actor, household_id, dir, attrs)
        _document -> post_document(actor, household_id, dir, attrs)
      end
    end
  end

  defp post_thread(actor, household_id, dir, attrs) do
    title = one_line(attrs["title"])
    text = to_string(attrs["content"] || "")
    ballot = attrs["ballot"]

    with :ok <- titled(title),
         :ok <- worded(text, ballot != nil) do
      locked(household_id, fn -> write_thread(actor, household_id, dir, {title, text, ballot}) end)
    end
  end

  defp write_thread(actor, household_id, dir, {title, text, ballot}) do
    thread = "threads/" <> fresh_id(dir, title)
    by = author(household_id, actor)

    with :ok <- gate(actor, household_id, dir, thread, :post),
         {:ok, opened} <- open_ballot(household_id, thread, ballot, actor),
         meta = thread_meta(title, by, actor) ++ ballot_meta(opened),
         path = Path.join(thread, @trunk),
         :ok <- write_new!(dir, path, render(meta, text <> bundle_text(opened))),
         written = descriptor(dir, Kinds.named("thread")) ++ [path],
         {:ok, _} <- commit(household_id, written, "Post: #{title}", by) do
      {:ok,
       %{path: thread, title: title, ballot: opened && Map.take(opened, [:ballot, :closes_at])}}
    end
  end

  defp thread_meta(title, by, actor),
    do: [
      {"title", title},
      {"by", by.name},
      {"by_kind", Atom.to_string(actor.kind)},
      {"by_id", actor.id},
      {"posted_at", iso(Clock.now())}
    ]

  defp open_ballot(_household_id, _thread, nil, _actor), do: {:ok, nil}

  defp open_ballot(household_id, thread, ballot, actor) when is_map(ballot) do
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

  defp open_ballot(_household_id, _thread, _other, _actor),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_ballot_shape)}

  defp ballot_meta(nil), do: []

  defp ballot_meta(o),
    do: [
      {"ballot", Integer.to_string(o.ballot)},
      {"term_days", Integer.to_string(o.term_days)},
      {"closes_at", iso(o.closes_at)}
    ]

  defp bundle_text(nil), do: ""

  defp bundle_text(o) do
    items =
      o.bundle
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {%{"rule" => r}, i} -> "#{i}. Rule: #{r}"
        {%{"setting" => k, "value" => v}, i} -> "#{i}. Setting: #{k} = #{inspect_value(v)}"
      end)

    """


    ## Ballot ##{o.ballot}: the bundle, voted on as a unit

    #{items}

    Fixed when the ballot opened; nothing is added, changed or removed while it runs. Every member, witness or resident, votes once by replying with a vote of yes or no, until #{iso(o.closes_at)}. A majority of the members carries the whole bundle into the contract; otherwise the whole of it fails.
    """
  end

  defp post_document(actor, household_id, dir, attrs) do
    title = one_line(attrs["title"])
    text = to_string(attrs["content"] || "")

    with {:ok, path} <- household_path(attrs["path"] || ""),
         false <- Kinds.container?(Kinds.kind_of(path)),
         :ok <- worded(text, false) do
      locked(household_id, fn -> write_document(actor, household_id, dir, {path, title, text}) end)
    else
      true ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_document_in_threads)}

      other ->
        other
    end
  end

  defp write_document(actor, household_id, dir, {path, title, text}) do
    by = author(household_id, actor)
    meta = thread_meta(title || Path.basename(path, ".md"), by, actor)

    with :ok <- gate(actor, household_id, dir, path, :file),
         false <- File.exists?(Path.join(dir, path)),
         :ok <- write_new!(dir, path, render(meta, text)),
         written = descriptor(dir, Kinds.kind_of(path)) ++ [path],
         {:ok, _} <- commit(household_id, written, "Post: #{path}", by) do
      {:ok, %{path: path, title: title}}
    else
      true ->
        {:error,
         Error.new(:seshat_household_written, :seshat_household_document_exists, path: path)}

      other ->
        other
    end
  end

  # A household document is a resident's (seshat#69): a witness who posts
  # posts threads and replies.
  # ---- reply (seshat#59, #60, #62, #63) ----

  @doc """
  A member appends to a thread: a resident with words, a vote, or both;
  a witness only with a vote. A vote is recorded on the household's
  stream first (gaia#30), so a refused one writes nothing. Each reply is
  a new file; the trunk is never touched. Watchers are poked after.
  """
  def reply(%Actor{} = actor, thread_name, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    text = to_string(attrs["content"] || "")
    vote = attrs["vote"] |> blank() |> downcase()

    with {:ok, household_id} <- household(actor),
         :ok <- may_reply(actor, vote, household_id),
         :ok <- worded(text, vote != nil),
         {:ok, dir} <- provision(household_id),
         thread when is_binary(thread) <- thread_path(thread_name) || no_thread(thread_name),
         {:ok, t} <- load_thread(dir, thread),
         :ok <- cast(household_id, thread, vote, actor),
         by = author(household_id, actor),
         reply = {text, vote, integer(attrs["in_reply_to"])},
         {:ok, written} <-
           locked(household_id, fn ->
             write_reply(actor, household_id, dir, {thread, t}, by, reply)
           end) do
      poke(household_id, thread, t, written, by, actor)
      {:ok, Map.merge(written, %{thread: thread, vote: vote})}
    end
  end

  defp write_reply(actor, household_id, dir, {thread, t}, by, {text, vote, in_reply_to}) do
    # A vote is governance, never a post (seshat#67, #68): it waits on no
    # turn and spends no quota. Anything else goes through the beats.
    with :ok <- if(vote, do: :ok, else: gate(actor, household_id, dir, thread, :post)) do
      append_reply(actor, household_id, dir, {thread, t}, by, {text, vote, in_reply_to})
    end
  end

  defp append_reply(actor, household_id, dir, {thread, t}, by, {text, vote, in_reply_to}) do
    number = next_reply(dir, thread)

    meta =
      [
        {"by", by.name},
        {"by_kind", Atom.to_string(actor.kind)},
        {"by_id", actor.id},
        {"at", iso(Clock.now())},
        {"reply", Integer.to_string(number)}
      ] ++
        optional("in_reply_to", in_reply_to && Integer.to_string(in_reply_to)) ++
        optional("vote", vote)

    body = if text == "", do: "Votes #{vote}.", else: text
    path = reply_path(thread, number, by.name)

    with :ok <- write_new!(dir, path, render(meta, body)),
         {:ok, _} <-
           commit(household_id, [path], "Reply ##{number} to #{t.trunk.meta["title"]}", by),
         do: {:ok, %{path: path, number: number}}
  end

  defp optional(_key, nil), do: []
  defp optional(key, value), do: [{key, value}]

  defp downcase(nil), do: nil
  defp downcase(v), do: String.downcase(v)

  defp may_reply(%Actor{kind: :resident}, _vote, _household_id), do: :ok
  defp may_reply(%Actor{kind: :witness}, vote, _household_id) when is_binary(vote), do: :ok

  defp may_reply(%Actor{kind: :witness}, _vote, household_id) do
    if Gaia.household_beat_shape(household_id).witnesses_post,
      do: :ok,
      else:
        {:error, Error.new(:seshat_household_residents_write, :seshat_household_witness_replies)}
  end

  defp may_reply(%Actor{}, _vote, _household_id),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_actor_replies)}

  defp cast(_household_id, _thread, nil, _actor), do: :ok

  defp cast(household_id, thread, vote, actor) do
    case Gaia.household_ballot_for_thread(household_id, thread) do
      nil ->
        {:error, Error.new(:seshat_household_not_a_ballot, :seshat_household_vote_no_ballot)}

      ballot ->
        Gaia.vote_household_ballot(household_id, ballot.number, vote, actor)
    end
  end

  # The watch's poke (seshat#62): every resident watching the thread now,
  # the author aside, gets a letter to its chat naming the thread and the
  # reply, never the words.
  defp poke(household_id, thread, t, written, by, actor) do
    now = Clock.now()

    for watcher <- Gaia.household_watchers(household_id, thread, now),
        watcher != actor.id do
      text =
        "#{by.name} replied in the household thread #{thread} (\"#{t.trunk.meta["title"]}\"), reply ##{written.number}. " <>
          "household_read with that path reads it. You asked to be told of new replies here for a while; the watch ends on its own."

      Kumbukumbu.send_letter(watcher, nil, %{to: "Oneiroi chat", text: text}, @watch_actor)
    end

    :ok
  end

  # ---- the watch (gaia#32, seshat#62) ----

  @doc "A resident watches a thread for the hours it states: never on by default, and over when the term is."
  def watch(%Actor{} = actor, thread_name, hours) do
    with {:ok, household_id} <- household(actor),
         {:ok, dir} <- provision(household_id),
         thread when is_binary(thread) <- thread_path(thread_name) || no_thread(thread_name),
         {:ok, _t} <- load_thread(dir, thread),
         {:ok, until} <- Gaia.watch_household_thread(household_id, thread, hours, actor) do
      {:ok, %{thread: thread, until: until}}
    end
  end

  # ---- the contract (gaia#27, #28; seshat#63) ----

  @doc "The founding witness proposes the contract's version 1; `CONTRACT.md` is rendered from it."
  def propose_contract(%Actor{} = actor, prose, note) do
    with {:ok, household_id} <- household(actor),
         :ok <- Gaia.propose_household_contract(household_id, prose, note, actor),
         do: rendered(household_id, "Contract: version 1 proposed", author(household_id, actor))
  end

  @doc "A member signs the version in force; `CONTRACT.md` says so."
  def sign_contract(%Actor{} = actor) do
    with {:ok, household_id} <- household(actor),
         %{in_force: %{version: v}} <- Gaia.household_contract(household_id) do
      with :ok <- Gaia.sign_household_contract(household_id, v, actor),
           do:
             rendered(
               household_id,
               "Contract: signed at version #{v}",
               author(household_id, actor)
             )
    else
      %{in_force: nil} ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_sign_no_contract)}

      other ->
        other
    end
  end

  @doc "The contract as the members read it (gaia#27 to #31), from the household stream."
  def contract(%Actor{} = actor) do
    with {:ok, household_id} <- household(actor),
         {:ok, _dir} <- provision(household_id),
         do: {:ok, Gaia.household_contract(household_id)}
  end

  defp rendered(household_id, message, by) do
    locked(household_id, fn ->
      with {:ok, dir} <- SimaQian.household_repository_dir(household_id),
           written = render_contract(dir, household_id),
           {:ok, _} <- commit(household_id, written, message, by),
           do: {:ok, Gaia.household_contract(household_id)}
    end)
  end

  @doc """
  Closes a ballot whose term has run (gaia#30, #31): the outcome is a
  closing reply in its thread, by the platform, and a carried bundle is
  the contract's next version in `CONTRACT.md`. A ballot closed already
  answers `{:ok, :closed}`.
  """
  def close_ballot(household_id, ballot, %Actor{} = actor) do
    with {:ok, outcome} when is_map(outcome) <-
           Gaia.close_household_ballot(household_id, ballot, actor),
         {:ok, dir} <- provision(household_id) do
      thread =
        Enum.find_value(
          Gaia.household_contract(household_id).ballots,
          &(&1.number == ballot && &1.thread)
        )

      locked(household_id, fn -> write_outcome(household_id, dir, thread, ballot, outcome) end)
    end
  end

  defp write_outcome(household_id, dir, thread, ballot, outcome) do
    number = next_reply(dir, thread)
    path = reply_path(thread, number, "oneiroi")

    carried =
      if outcome.version,
        do: " The bundle is the household contract's version #{outcome.version}.",
        else: ""

    meta = [
      {"by", "Oneiroi"},
      {"by_kind", "platform"},
      {"at", iso(Clock.now())},
      {"reply", Integer.to_string(number)},
      {"outcome", if(outcome.passed, do: "carried", else: "failed")}
    ]

    with :ok <-
           write_new!(
             dir,
             path,
             render(meta, "Ballot ##{ballot} closed. #{outcome.outcome}" <> carried)
           ),
         written = [path | render_contract(dir, household_id)],
         {:ok, _} <- commit(household_id, written, "Ballot ##{ballot} closed", @platform),
         do: {:ok, outcome}
  end

  # ---- the beats' gate (seshat#67 to #69) ----

  # Every household write but a vote passes here, inside the household's
  # lock so two writes cannot both pass on one count: a resident only in
  # her turn and each target once in it; a witness, who is never fired,
  # once in each thread a beat; and everyone within the post quota.
  defp gate(actor, household_id, dir, target, what) do
    shape = Gaia.household_beat_shape(household_id)
    now = Clock.now()
    writes = writes(dir)

    with :ok <- window(actor, household_id, shape, writes, target, now),
         do: quota(actor, shape, writes, what, now)
  end

  defp window(%Actor{kind: :resident} = actor, household_id, shape, writes, target, now) do
    case Gaia.household_open_turn_of(household_id, actor.id, now) do
      nil ->
        {:error, not_your_turn(household_id, actor, shape, now)}

      turn ->
        if touched?(writes, actor, target, second(turn.fired_at)),
          do:
            {:error,
             Error.new(:seshat_household_turn_spent, :seshat_household_turn_target_twice,
               path: target
             )},
          else: :ok
    end
  end

  defp window(%Actor{kind: :witness} = actor, household_id, shape, writes, target, now) do
    top = Beats.top(household_id, shape, now)

    if touched?(writes, actor, target, top) do
      next = Beats.ends(top, shape)

      {:error,
       %{
         Error.new(:seshat_household_beat_spent, :seshat_household_witness_thread_twice,
           path: target
         )
         | remedy:
             "You have posted in #{target} this beat; the next beat begins at #{iso(next)}, and a vote is never held to it."
       }}
    else
      :ok
    end
  end

  defp window(%Actor{}, _household_id, _shape, _writes, _target, _now), do: :ok

  defp touched?(writes, actor, target, since),
    do:
      Enum.any?(
        writes,
        &(&1.by_id == actor.id and &1.target == target and is_nil(&1.vote) and
            DateTime.compare(&1.at, since) != :lt)
      )

  # The refusal outside a turn names when she can next act (seshat#67).
  defp not_your_turn(household_id, actor, shape, now) do
    beats = Gaia.household_beats(household_id, now)
    queued = Enum.find(beats.queue, &(&1.resident_id == actor.id))

    remedy =
      case queued do
        nil ->
          top = Beats.registers_for(household_id, shape, now)

          "household_register now queues you for the beat at #{iso(top)}; its turns fire one after another from #{iso(Beats.signup_closes(top, shape))}, the most starved first, and your writes go in during your turn. A vote is never held to the turns."

        q ->
          "You are registered, #{ordinal(q.position)} in the queue for the beat at #{iso(q.waits_for)}; its turns fire from #{iso(Beats.signup_closes(q.waits_for, shape))}, and your writes go in during your turn. A vote is never held to the turns."
      end

    %{
      Error.new(:seshat_household_not_your_turn, :seshat_household_write_outside_turn)
      | remedy: remedy
    }
  end

  defp ordinal(1), do: "first"
  defp ordinal(2), do: "second"
  defp ordinal(3), do: "third"
  defp ordinal(n), do: "number #{n}"

  # The post quota (seshat#68): threads and replies, a vote never, a
  # document never, over the window's hours, the same for every member.
  defp quota(_actor, _shape, _writes, :file, _now), do: :ok

  defp quota(actor, shape, writes, :post, now) do
    since = DateTime.add(now, -shape.window * 3600, :second)
    counted = posts(writes, actor.id, since)

    if length(counted) < shape.quota do
      :ok
    else
      free =
        counted |> Enum.map(& &1.at) |> Enum.min(DateTime) |> DateTime.add(shape.window * 3600)

      {:error,
       %{
         Error.new(:seshat_household_quota_spent, :seshat_household_post_quota)
         | remedy:
             "You have posted #{length(counted)} times in the last #{shape.window} hours, the household's quota; your next post is free at #{iso(free)}. A vote never counts."
       }}
    end
  end

  @doc false
  # A member's posts since an instant: threads and replies, never a vote.
  def posts(writes, member_id, since),
    do:
      Enum.filter(
        writes,
        &(&1.by_id == member_id and &1.kind in ["thread", "reply"] and is_nil(&1.vote) and
            DateTime.compare(&1.at, since) == :gt)
      )

  @doc false
  # Every write on the shelf, read from its files (repo first): each
  # thread's trunk, each reply by a member, each document; who, when,
  # what it targets (the thread, or the document's path), and a vote.
  def writes(dir) do
    threads =
      for id <- thread_ids(dir),
          thread = "threads/" <> id,
          {:ok, t} <- [load_thread(dir, thread)],
          w <- thread_writes(thread, t),
          do: w

    documents =
      for d <- documents(dir),
          at = instant(d.posted_at),
          at != nil,
          do: %{
            kind: "document",
            target: d.path,
            path: d.path,
            title: d.title,
            by: d.by,
            by_id: d.by_id,
            at: at,
            vote: nil
          }

    Enum.filter(threads, & &1.at) ++ documents
  end

  defp thread_writes(thread, t) do
    m = t.trunk.meta
    title = m["title"]

    trunk = %{
      kind: "thread",
      target: thread,
      path: thread,
      title: title,
      by: m["by"],
      by_id: m["by_id"],
      at: instant(m["posted_at"]),
      vote: nil
    }

    replies =
      for r <- t.replies, r.meta["by_id"] do
        %{
          kind: "reply",
          target: thread,
          path: r.path,
          title: title,
          by: r.meta["by"],
          by_id: r.meta["by_id"],
          at: instant(r.meta["at"]),
          vote: r.meta["vote"],
          number: r.meta["reply"]
        }
      end

    [trunk | replies]
  end

  defp instant(nil), do: nil

  defp instant(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _other -> nil
    end
  end

  # The files carry instants to the second, so a turn's start is read so.
  defp second(at), do: DateTime.truncate(at, :second)

  @doc false
  # `BEATS.md` rendered at the root (seshat#71), committed by the platform
  # when it changed.
  # sobelow_skip ["Traversal.FileModule"]
  def write_beats(household_id, body, message) do
    locked(household_id, fn ->
      with {:ok, dir} <- SimaQian.household_repository_dir(household_id),
           do: beats_written(household_id, Path.join(dir, @beats), body, message)
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp beats_written(household_id, full, body, message) do
    if File.read(full) == {:ok, body} do
      {:ok, :unchanged}
    else
      File.write!(full, body)
      commit(household_id, [@beats], message, @platform)
    end
  end

  # ---- files ----

  defp thread_ids(dir) do
    case File.ls(Path.join(dir, "threads")) do
      {:ok, names} -> Enum.filter(names, &File.regular?(Path.join([dir, "threads", &1, @trunk])))
      {:error, _} -> []
    end
  end

  defp thread_summary(dir, id, ballots) do
    thread = "threads/" <> id
    {:ok, t} = load_thread(dir, thread)
    last = List.last(t.replies)
    ballot = ballots[thread]

    %{
      kind: "thread",
      path: thread,
      title: t.trunk.meta["title"],
      by: t.trunk.meta["by"],
      posted_at: t.trunk.meta["posted_at"],
      replies: length(t.replies),
      last_reply_at: last && last.meta["at"],
      ballot: ballot && Map.take(ballot, [:number, :closes_at, :closed_at, :passed]),
      ids: ids(t)
    }
  end

  defp ids(t), do: [t.trunk.meta["by_id"] | Enum.map(t.replies, & &1.meta["by_id"])]

  # sobelow_skip ["Traversal.FileModule"]
  defp documents(dir) do
    for kind <- Kinds.household(),
        not Kinds.container?(kind),
        name <-
          (case File.ls(Path.join(dir, kind.folder)) do
             {:ok, names} -> Enum.sort(names)
             {:error, _} -> []
           end),
        name != Kinds.descriptor_name() do
      path = Path.join(kind.folder, name)
      {meta, _} = path |> then(&File.read!(Path.join(dir, &1))) |> frontmatter()

      %{
        kind: kind.kind,
        path: path,
        title: meta["title"] || name,
        by: meta["by"],
        by_id: meta["by_id"],
        posted_at: meta["posted_at"]
      }
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp load_thread(dir, thread) do
    trunk = Path.join([dir, thread, @trunk])

    if File.regular?(trunk) do
      replies = replies(dir, thread)
      {meta, body} = trunk |> File.read!() |> frontmatter()

      {:ok,
       %{trunk: %{path: Path.join(thread, @trunk), meta: meta, body: body}, replies: replies}}
    else
      no_thread(thread)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp replies(dir, thread) do
    replies_dir = Path.join([dir, thread, "replies"])

    case File.ls(replies_dir) do
      {:ok, names} -> names |> Enum.sort() |> Enum.map(&reply_file(replies_dir, thread, &1))
      {:error, _} -> []
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp reply_file(replies_dir, thread, name) do
    {meta, body} = replies_dir |> Path.join(name) |> File.read!() |> frontmatter()
    %{path: Path.join([thread, "replies", name]), meta: meta, body: body}
  end

  defp thread_text(thread, t, ballot) do
    head =
      "# #{t.trunk.meta["title"]}\n#{thread}, posted by #{t.trunk.meta["by"]} at #{t.trunk.meta["posted_at"]}" <>
        ballot_line(ballot)

    replies =
      Enum.map_join(t.replies, "\n\n", fn r ->
        vote = if r.meta["vote"], do: ", votes #{r.meta["vote"]}", else: ""
        answers = if r.meta["in_reply_to"], do: ", answering ##{r.meta["in_reply_to"]}", else: ""

        "--- Reply ##{r.meta["reply"]} by #{r.meta["by"]} at #{r.meta["at"]}#{vote}#{answers}:\n#{String.trim(r.body)}"
      end)

    head <>
      "\n\n" <>
      String.trim(t.trunk.body) <>
      if(replies == "", do: "\n\nNo replies yet.", else: "\n\n" <> replies)
  end

  defp ballot_line(nil), do: ""

  defp ballot_line(%{closed_at: nil} = b),
    do:
      "\nBallot ##{b.number}, open until #{iso(b.closes_at)}: #{votes_cast(length(b.votes))} so far."

  defp ballot_line(b), do: "\nBallot ##{b.number}, closed #{iso(b.closed_at)}: #{b.outcome}"

  defp votes_cast(1), do: "1 vote cast"
  defp votes_cast(n), do: "#{n} votes cast"

  defp next_reply(dir, thread) do
    case File.ls(Path.join([dir, thread, "replies"])) do
      {:ok, names} ->
        names
        |> Enum.map(&(&1 |> String.split("-", parts: 2) |> hd() |> Integer.parse()))
        |> Enum.map(fn
          {n, ""} -> n
          _ -> 0
        end)
        |> Enum.max(fn -> 0 end)
        |> Kernel.+(1)

      {:error, _} ->
        1
    end
  end

  defp reply_path(thread, number, name),
    do:
      Path.join([
        thread,
        "replies",
        "#{String.pad_leading(Integer.to_string(number), 4, "0")}-#{slug(name)}.md"
      ])

  # A path in the household's repository: plain segments under a
  # household kind's folder (`Kinds.normalize/1` holds the shape).
  defp household_path(name) do
    with {:ok, path} <- Kinds.normalize(to_string(name)) do
      if Enum.any?(Kinds.household(), &(&1.kind == Kinds.kind_of(path).kind)),
        do: {:ok, path},
        else:
          {:error,
           Error.new(:seshat_household_invalid, :seshat_household_kind_not_hosted, path: path)}
    end
  end

  # `threads/<id>`, its trunk's path, a reply's, or the id alone.
  defp thread_path(name) when is_binary(name) do
    case String.split(String.trim(name), "/", trim: true) do
      ["threads", id | _] -> if segment?(id), do: "threads/" <> id
      [id] -> if segment?(id) and id not in [@contract, "contract", "beats"], do: "threads/" <> id
      _ -> nil
    end
  end

  defp thread_path(_other), do: nil

  defp segment?(s), do: Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,99}\z/, s)

  defp no_thread(name),
    do:
      {:error,
       Error.new(:seshat_household_no_such_thread, :seshat_household_thread_absent,
         path: to_string(name)
       )}

  defp fresh_id(dir, title) do
    base = "#{Date.to_iso8601(DateTime.to_date(Clock.now()))}-#{slug(title)}"

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not File.exists?(Path.join([dir, "threads", &1]))))
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 60)
    |> String.trim("-")
    |> case do
      "" -> "post"
      s -> s
    end
  end

  # Written once (seshat#59): `:exclusive` refuses a path that exists, so
  # two writers can never land on one file.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_new!(dir, path, content) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content, [:exclusive])
  end

  defp render(meta, body) do
    lines = Enum.map_join(meta, "\n", fn {k, v} -> "#{k}: #{one_line(v)}" end)
    "---\n#{lines}\n---\n\n#{String.trim_trailing(body)}\n"
  end

  defp frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [head, body] ->
        meta = head |> String.split("\n", trim: true) |> Enum.flat_map(&meta_line/1) |> Map.new()
        {meta, String.trim_leading(body, "\n")}

      _ ->
        {%{}, rest}
    end
  end

  defp frontmatter(text), do: {%{}, text}

  defp meta_line(line) do
    case String.split(line, ": ", parts: 2) do
      [k, v] -> [{k, v}]
      _ -> []
    end
  end

  defp commit(_household_id, [], _message, _by), do: {:ok, :nothing}

  defp commit(household_id, paths, message, by),
    do: SimaQian.household_commit(household_id, paths, message, by)

  # One household's git index takes one write at a time: the files never
  # meet (each is new), but a commit stages through one index.
  defp locked(household_id, fun), do: :global.trans({{__MODULE__, household_id}, self()}, fun)

  defp titled(nil),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_title_missing)}

  defp titled(title) do
    if String.length(title) <= @title_max,
      do: :ok,
      else: {:error, Error.new(:seshat_household_invalid, :seshat_household_title_long)}
  end

  defp worded(text, optional?) do
    cond do
      String.length(text) > @text_max ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_text_long)}

      String.trim(text) == "" and not optional? ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_text_missing)}

      true ->
        :ok
    end
  end

  defp one_line(nil), do: nil

  defp one_line(v),
    do: v |> to_string() |> String.replace(~r/\s*\n\s*/, " ") |> String.trim() |> blank()

  defp blank(nil), do: nil
  defp blank(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))
  defp blank(v), do: to_string(v)

  defp integer(n) when is_integer(n) and n > 0, do: n
  defp integer(_), do: nil

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso(other), do: to_string(other)
end
