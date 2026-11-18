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
  alias Oneiroi.SimaQian.Repos

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
         true <- Gaia.household_member?(id, actor),
         # A resident with no agreement in force is not in the house yet
         # (agathos-daimon#51): no read, no write.
         false <- actor.kind == :resident and AgathosDaimon.held?(actor.id) do
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
    with {:ok, view} <- view(household_id) do
      case descriptor(view, Kinds.named("thread")) ++ render_contract(view, household_id) do
        [] ->
          {:ok, view}

        changes ->
          # Two first readers may both write the descriptor; the second
          # finds it there, and reads the house again.
          _ =
            Repos.write(
              view.repo,
              changes,
              "Household: the shelf's kinds and its contract",
              @platform
            )

          view(household_id)
      end
    end
  end

  # The household's repository at its head (sima-qian#57): one tree call,
  # the files read from it through the blob cache.
  defp view(household_id) do
    repo = {:household, household_id}
    with {:ok, files} <- Repos.snapshot(repo), do: {:ok, %{repo: repo, files: files}}
  end

  defp file(view, path), do: Repos.at(view.repo, view.files, path)
  defp has?(view, path), do: Map.has_key?(view.files, path)

  # The kind's descriptor in its folder (seshat#51's `kind.json`): written
  # once, for a reader of the repository with no platform beside it.
  defp descriptor(view, kind) do
    path = Path.join(kind.folder, Kinds.descriptor_name())

    if has?(view, path) do
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

      [{:create, path, Jason.encode_to_iodata!(body, pretty: true)}]
    end
  end

  defp render_contract(view, household_id) do
    body = contract_text(Gaia.household_contract(household_id))

    if file(view, @contract) == body,
      do: [],
      else: [{:put, @contract, body, Map.get(view.files, @contract)}]
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
         {:ok, view} <- provision(household_id) do
      ballots = Map.new(Gaia.household_contract(household_id).ballots, &{&1.thread, &1})

      threads =
        view
        |> thread_ids()
        |> Enum.map(&thread_summary(view, &1, ballots))
        |> Enum.filter(&visible?(actor, household_id, &1.ids))
        |> Enum.sort_by(&{&1.posted_at, &1.path}, :desc)

      documents =
        view
        |> documents()
        |> Enum.filter(&visible?(actor, household_id, [&1.by_id]))

      items = threads ++ documents
      page = items |> Enum.drop(from) |> Enum.take(@page)

      {:ok,
       %{
         household_id: household_id,
         # Its name for citations (gaia#44), nil until a witness names it.
         slug: Gaia.household_slug(household_id),
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
  The house searched (seshat#80; the witness, 2026-11-17: "the same
  search functionality/ui as resident workspaces"): every term of `q`,
  case aside, in a thread (its trunk and every reply), a household
  document, or the charter and the beats; `scope` narrows to `threads`,
  `records` or `charter`. Only what this member may read is searched.
  Each hit names its path (what Records opens), its title, when, and the
  words around the first match; best match first, then newest.
  """
  def search(%Actor{} = actor, q, scope \\ "everything") do
    terms = q |> to_string() |> String.downcase() |> String.split(~r/\s+/, trim: true)

    with {:ok, household_id} <- household(actor),
         {:ok, view} <- provision(household_id) do
      hits =
        actor
        |> searchable(household_id, view, scope)
        |> Enum.map(&hit(&1, terms))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(&{&1.score, &1.at || ""}, :desc)
        |> Enum.take(50)
        |> Enum.map(&Map.delete(&1, :score))

      {:ok, %{q: q, scope: scope, results: hits}}
    end
  end

  defp searchable(actor, household_id, view, scope) do
    threads =
      if scope in ["everything", "threads"] do
        for id <- thread_ids(view),
            {:ok, t} = load_thread(view, "threads/" <> id),
            visible?(actor, household_id, ids(t)) do
          %{
            type: "thread",
            path: "threads/" <> id,
            title: t.trunk.meta["title"],
            at: (List.last(t.replies) || t.trunk).meta["at"] || t.trunk.meta["posted_at"],
            text: Enum.map_join([t.trunk | t.replies], "\n\n", & &1.body)
          }
        end
      else
        []
      end

    documents =
      if scope in ["everything", "records"] do
        for d <- documents(view), visible?(actor, household_id, [d.by_id]) do
          {_meta, body} = view |> file(d.path) |> to_string() |> frontmatter()
          %{type: "document", path: d.path, title: d.title, at: d.posted_at, text: body}
        end
      else
        []
      end

    charter =
      if scope in ["everything", "charter"] do
        for {path, title} <- [
              {@contract, "The household contract"},
              {@beats, "The household's beats"}
            ],
            text = file(view, path),
            is_binary(text),
            do: %{type: "charter", path: path, title: title, at: nil, text: text}
      else
        []
      end

    threads ++ documents ++ charter
  end

  # Every term somewhere in its title or words; the score counts them.
  defp hit(_item, []), do: nil

  defp hit(item, terms) do
    haystack = String.downcase("#{item.title}\n#{item.text}")

    if Enum.all?(terms, &String.contains?(haystack, &1)) do
      score = Enum.sum(Enum.map(terms, &(length(String.split(haystack, &1)) - 1)))

      item
      |> Map.take([:type, :path, :title, :at])
      |> Map.put(:snippet, snippet(item.text, hd(terms)))
      |> Map.put(:score, score)
    end
  end

  # About 160 characters around the first match, on one line.
  defp snippet(text, term) do
    flat = String.replace(text, ~r/\s+/, " ")

    case :binary.match(String.downcase(flat), term) do
      {at, _} ->
        from = max(at - 60, 0)
        piece = flat |> binary_slice(from, 160) |> String.trim()
        if from > 0, do: "…" <> piece <> "…", else: piece <> "…"

      :nomatch ->
        flat |> binary_slice(0, 160) |> String.trim()
    end
  end

  @doc """
  The household's repository as the Records view lists it (seshat#76):
  every file a member may read, in the library's shape, folder by kind.
  The house's own (`CONTRACT.md`, `BEATS.md`) under `house`; each thread
  one entry under `thread`, read whole; each household document under
  its kind. Unpaged: a household's repository is small, and the tree
  wants all of it.
  """
  def files(%Actor{} = actor) do
    with {:ok, household_id} <- household(actor),
         {:ok, view} <- provision(household_id) do
      ballots = Map.new(Gaia.household_contract(household_id).ballots, &{&1.thread, &1})

      own =
        for {path, title} <- [
              {@contract, "The household contract"},
              {@beats, "The household's beats"}
            ],
            has?(view, path),
            do: file_row("house", path, title, nil, nil)

      threads =
        view
        |> thread_ids()
        |> Enum.map(&thread_summary(view, &1, ballots))
        |> Enum.filter(&visible?(actor, household_id, &1.ids))
        |> Enum.map(
          &file_row("thread", &1.path, &1.title, &1.last_reply_at || &1.posted_at, &1.by,
            created_at: &1.posted_at,
            versions: &1.replies + 1
          )
        )

      documents =
        view
        |> documents()
        |> Enum.filter(&visible?(actor, household_id, [&1.by_id]))
        |> Enum.map(&file_row(&1.kind, &1.path, &1.title, &1.posted_at, &1.by))

      rows = own ++ threads ++ documents
      present = rows |> Enum.map(& &1.kind) |> MapSet.new()

      kinds =
        ([%{kind: "house", label: "The house"}] ++
           for(
             k <- Kinds.shelf(),
             Map.get(k, :household, false),
             do: %{kind: k.kind, label: house_label(k)}
           ))
        |> Enum.with_index()
        |> Enum.map(fn {k, i} -> Map.put(k, :position, i) end)

      {:ok,
       %{
         household_id: household_id,
         kinds: Enum.filter(kinds, &MapSet.member?(present, &1.kind)),
         documents: rows,
         unadopted: []
       }}
    end
  end

  # In a resident's records human/ is the witness's own ("Yours"); in the
  # house it is every witness's, a folder each (seshat#81).
  defp house_label(%{kind: "human"}), do: "Witnesses"
  defp house_label(k), do: k.label

  defp file_row(kind, path, title, at, by, extra \\ []) do
    %{
      kind: kind,
      path: path,
      title: title,
      status: nil,
      bytes: nil,
      versions: Keyword.get(extra, :versions, 1),
      written_at: at,
      created_at: Keyword.get(extra, :created_at, at),
      written_by: by,
      missing_at: nil,
      note: nil
    }
  end

  @doc """
  One thing on the shelf, whole: a thread (by `threads/<id>`, its trunk's
  path, or its id alone) with every reply in order, a document by its
  path, or `CONTRACT.md`. Answers `%{path, kind, title, content}`, with a
  thread's `trunk` and `replies` as data beside the text.
  """
  def read(%Actor{} = actor, name, opts \\ []) do
    with {:ok, household_id} <- household(actor),
         {:ok, now} <- provision(household_id),
         {:ok, head} <- Repos.head(now.repo),
         {:ok, view, commit} <- pinned(now, Keyword.get(opts, :at), head),
         {:ok, doc} <- read_in(actor, household_id, view, name) do
      {:ok,
       doc
       |> Map.put(:commit, commit)
       |> Map.put(:cited_as, cited_as(household_id, doc, commit))
       |> Map.put(:since, since(actor, household_id, now, doc, commit, head))}
    end
  end

  @doc "A witness names the house for citations (gaia#44), once; answers the shelf."
  def name(%Actor{} = actor, slug) do
    with {:ok, household_id} <- household(actor),
         :ok <- Gaia.name_household(household_id, to_string(slug || ""), actor),
         do: shelf(actor)
  end

  @doc """
  What a house citation names, read as it stood at its commit (gaia#44,
  sima-qian#61), for a member of that house. A house that is not the
  reader's says so: one she has left opens from her clone of it at
  leaving, which is not built yet.
  """
  def read_cited(%Actor{} = actor, %{house: house, path: path, at: at}) do
    with {:ok, mine} <- household(actor) do
      case Gaia.household_by_slug(house) do
        ^mine ->
          read(actor, path, at: at)

        nil ->
          {:error,
           Error.new(:seshat_household_no_such_document, :seshat_household_cited_house_unknown,
             house: house
           )}

        _another ->
          {:error,
           Error.new(:seshat_household_not_member, :seshat_household_cited_house_not_mine,
             house: house
           )}
      end
    end
  end

  defp read_in(actor, household_id, view, name) do
    cond do
      name in [@contract, "contract"] -> read_contract(view)
      name in [@beats, "beats"] -> read_beats(view)
      thread = thread_path(name) -> read_thread(actor, household_id, view, thread)
      true -> read_document(actor, household_id, view, name)
    end
  end

  # The house as it stood at a commit a citation pinned (sima-qian#61),
  # or as it stands now.
  defp pinned(now, nil, head), do: {:ok, now, head}

  defp pinned(now, at, _head) do
    with {:ok, files} <- Repos.snapshot_at(now.repo, at), do: {:ok, %{now | files: files}, at}
  end

  @doc """
  How a citation names what was read (gaia#44, sima-qian#61): the
  house's slug, the thread or the document, and the commit it was read
  at, `house/<slug>:thread/<id>@<commit>`; nil while the house is unnamed
  or before its first commit.
  """
  def cited_as(household_id, doc, commit) do
    with slug when is_binary(slug) <- Gaia.household_slug(household_id),
         sha when is_binary(sha) <- commit do
      ref =
        case doc.kind do
          "thread" -> "thread/" <> String.replace_prefix(doc.path, "threads/", "")
          _document -> "doc/" <> doc.path
        end

      "house/#{slug}:#{ref}@#{String.slice(sha, 0, 12)}"
    else
      _unnamed -> nil
    end
  end

  # What changed since the pin, said plainly (sima-qian#61): a thread
  # only grows (its replies are create-only), so how many replies came
  # since; a document, whether its words are still the ones cited. Nil
  # when read as it stands.
  defp since(_actor, _household_id, _now, _doc, _commit, nil), do: nil

  defp since(actor, household_id, now, doc, commit, head) do
    cond do
      String.starts_with?(head, commit) -> nil
      doc.kind == "thread" -> thread_since(actor, household_id, now, doc)
      true -> document_since(now, doc)
    end
  end

  defp thread_since(actor, household_id, now, doc) do
    case read_thread(actor, household_id, now, doc.path) do
      {:ok, current} -> replies_since(length(current.replies) - length(doc.replies))
      _gone -> "the thread is no longer on the shelf"
    end
  end

  defp replies_since(n) when n <= 0, do: nil
  defp replies_since(1), do: "1 reply since it was cited"
  defp replies_since(n), do: "#{n} replies since it was cited"

  defp document_since(now, doc) do
    cond do
      not has?(now, doc.path) -> "the document is no longer on the shelf"
      file(now, doc.path) == doc.content -> nil
      true -> "changed since it was cited; read it without the commit for its words now"
    end
  end

  # The contract's rendering, at the root of a directory the household's
  # id named; no request value reaches the path.
  defp read_contract(view),
    do:
      {:ok,
       %{
         path: @contract,
         kind: "contract",
         title: "The household contract",
         content: file(view, @contract) || ""
       }}

  # The beats' record (seshat#71), at the root as the contract is; before
  # the first beat event it is not there yet.
  defp read_beats(view) do
    case file(view, @beats) do
      text when is_binary(text) ->
        {:ok, %{path: @beats, kind: "beats", title: "The household's beats", content: text}}

      {:error, _} ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_beats_absent,
           path: @beats
         )}
    end
  end

  defp read_thread(actor, household_id, view, thread) do
    with {:ok, t} <- load_thread(view, thread),
         true <- visible?(actor, household_id, ids(t)) || :hidden do
      ballot = Gaia.household_ballot_for_thread(household_id, thread)
      doc = posted_doc(view, t)

      {:ok,
       %{
         path: thread,
         kind: "thread",
         title: t.trunk.meta["title"],
         trunk: t.trunk,
         replies: t.replies,
         ballot: ballot,
         doc: doc,
         content: thread_text(thread, t, ballot, doc)
       }}
    else
      :hidden -> no_thread(thread)
      other -> other
    end
  end

  defp read_document(actor, household_id, view, name) do
    with {:ok, path} <- household_path(name),
         text when is_binary(text) <- file(view, path) || :absent,
         {meta, _body} = frontmatter(text),
         true <- visible?(actor, household_id, [meta["by_id"]]) || :absent do
      share = sharing_of(meta)

      {:ok,
       %{
         path: path,
         kind: Kinds.kind_of(path).kind,
         title: meta["title"] || path,
         content: text,
         sharing: Map.put(share, :owner, owner_name(household_id, share.owner_id)),
         discussed: discussed(view, path)
       }}
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
         {:ok, view} <- provision(household_id) do
      case {attrs["kind"] || "thread", attrs["doc"]} do
        {"thread", doc} when is_binary(doc) -> post_doc_thread(actor, household_id, view, attrs)
        {"thread", _none} -> post_thread(actor, household_id, view, attrs)
        _document -> post_document(actor, household_id, view, attrs)
      end
    end
  end

  defp post_thread(actor, household_id, _view, attrs) do
    title = one_line(attrs["title"])
    text = to_string(attrs["content"] || "")
    ballot = attrs["ballot"]

    with :ok <- titled(title),
         :ok <- worded(text, ballot != nil) do
      locked(household_id, fn view ->
        write_thread(actor, household_id, view, {title, text, ballot})
      end)
    end
  end

  defp write_thread(actor, household_id, view, {title, text, ballot}) do
    thread = "threads/" <> fresh_id(view, title)
    by = author(household_id, actor)

    with :ok <- gate(actor, household_id, view, thread, :post),
         {:ok, opened} <- open_ballot(household_id, thread, ballot, actor),
         meta = thread_meta(title, by, actor) ++ ballot_meta(opened),
         path = Path.join(thread, @trunk),
         changes = [
           {:create, path, render(meta, text <> bundle_text(opened))}
           | descriptor(view, Kinds.named("thread"))
         ],
         {:ok, _} <- commit(view, changes, "Post: #{title}", by) do
      {:ok,
       %{path: thread, title: title, ballot: opened && Map.take(opened, [:ballot, :closes_at])}}
    end
  end

  # ---- document posts (seshat#83) ----

  # A document post: a thread whose trunk is a citation of a household
  # document, flagged `doc:`, pinned at its latest commit, which reads as
  # the document itself; feedback on it is its replies.
  defp post_doc_thread(actor, household_id, view, attrs) do
    text = to_string(attrs["content"] || "")

    with {:ok, path} <- household_path(attrs["doc"]),
         false <- Kinds.container?(Kinds.kind_of(path)),
         doc when is_binary(doc) <- file(view, path) || absent(path),
         {meta, _body} = frontmatter(doc),
         title = one_line(attrs["title"]) || "On #{meta["title"] || Path.basename(path, ".md")}",
         :ok <- titled(title) do
      locked(household_id, &write_doc_thread(actor, household_id, &1, {path, title, text}))
    else
      true -> {:error, Error.new(:seshat_household_invalid, :seshat_household_doc_post_thread)}
      other -> other
    end
  end

  defp write_doc_thread(actor, household_id, view, {path, title, text}) do
    thread = "threads/" <> fresh_id(view, title)
    by = author(household_id, actor)
    commit = doc_commit(view, path)

    with :ok <- gate(actor, household_id, view, thread, :post),
         meta = thread_meta(title, by, actor) ++ [{"doc", path}] ++ optional("doc_commit", commit),
         body =
           "A document post on #{path}#{draft_at(commit)}." <>
             if(String.trim(text) == "", do: "", else: "\n\n" <> text),
         changes = [
           {:create, Path.join(thread, @trunk), render(meta, body)}
           | descriptor(view, Kinds.named("thread"))
         ],
         {:ok, _} <- commit(view, changes, "Post: #{title}", by) do
      {:ok, %{path: thread, title: title, doc: path, doc_commit: commit, ballot: nil}}
    end
  end

  # The commit that last changed a document: its draft.
  defp doc_commit(view, path) do
    case Repos.history(view.repo, path, 1) do
      {:ok, [%{commit: sha} | _]} -> sha
      _none -> nil
    end
  end

  defp draft_at(nil), do: ""
  defp draft_at(sha), do: ", draft #{short(sha)}"

  defp short(sha), do: String.slice(sha, 0, 12)

  # After an edit, a line in every thread on the document saying its
  # draft changed (seshat#83), so which draft is being talked about is
  # plain at every point and the latest draft's talk can be found. The
  # platform's lines, in their own commit, never gated.
  defp draft_changed(household_id, path, from, to) do
    {:ok, view} = view(household_id)

    changes =
      for id <- thread_ids(view),
          thread = "threads/" <> id,
          {:ok, t} <- [load_thread(view, thread)],
          t.trunk.meta["doc"] == path do
        number = next_reply(view, thread)

        meta = [
          {"by", @platform.name},
          {"by_kind", "platform"},
          {"at", iso(Clock.now())},
          {"reply", Integer.to_string(number)},
          {"draft", "changed"},
          {"doc_commit", to}
        ]

        {:create, reply_path(thread, number, "oneiroi"),
         render(meta, "Draft changed: #{short(from || "")} → #{short(to)}.")}
      end

    _ = commit(view, changes, "Draft changed: #{path}", @platform)
    :ok
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

  defp post_document(actor, household_id, _view, attrs) do
    title = one_line(attrs["title"])

    with {:ok, path} <- household_path(attrs["path"] || ""),
         false <- Kinds.container?(Kinds.kind_of(path)),
         :ok <- own_folder(actor, path),
         {:ok, sharing} <- sharing(attrs, actor),
         {:ok, text, source} <- words_from(actor, attrs),
         text = text || "",
         :ok <- worded(text, false) do
      locked(household_id, fn view ->
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
    by = author(household_id, actor)
    meta = thread_meta(title || Path.basename(path, ".md"), by, actor) ++ sharing

    with :ok <- gate(actor, household_id, view, path, :file),
         false <- has?(view, path),
         changes = [{:create, path, render(meta, text)} | descriptor(view, Kinds.kind_of(path))],
         {:ok, _} <- commit(view, changes, "Post: #{path}", by) do
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

  # A document's words, given (`content`) or copied from a file of the
  # resident's own (`from`, a path in her repository), which the copy
  # names as its source at the commit it was copied at, `<slug>:<path>@
  # <commit>`, so her local draft never becomes a quiet competing
  # edition; her own front matter stays behind.
  defp words_from(%Actor{kind: :resident, id: id}, %{"from" => from}) when is_binary(from) do
    repo = {:resident, id}

    with {:ok, text, _blob} <- Repos.read(repo, from),
         {:ok, [%{commit: commit} | _]} <- Repos.history(repo, from, 1),
         {:ok, r} <- AgathosDaimon.fetch(id) do
      {_meta, body} = frontmatter(text)
      {:ok, body, [{"source", "#{r.slug}:#{from}@#{short(commit)}"}]}
    else
      _absent ->
        {:error,
         Error.new(:seshat_household_no_such_document, :seshat_household_source_absent,
           path: from
         )}
    end
  end

  defp words_from(%Actor{}, %{"from" => from}) when is_binary(from),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_source_residents)}

  defp words_from(_actor, attrs) do
    if is_binary(attrs["content"]), do: {:ok, attrs["content"], []}, else: {:ok, nil, []}
  end

  @doc """
  The household documents shared from a file of the resident's own
  (seshat#84), each with the document posts on it: what her library read
  of that file says, so the feedback on its shared edition follows her
  back to where she works. Empty outside a house.
  """
  def shared_from(%Actor{kind: :resident, id: id} = actor, path) do
    with {:ok, household_id} <- household(actor),
         {:ok, r} <- AgathosDaimon.fetch(id),
         {:ok, view} <- view(household_id) do
      prefix = "#{r.slug}:#{path}@"

      for d <- documents(view),
          source = d.source,
          is_binary(source) and String.starts_with?(source, prefix),
          do: %{
            path: d.path,
            at: String.replace_prefix(source, prefix, ""),
            discussed: discussed(view, d.path)
          }
    else
      _none -> []
    end
  end

  def shared_from(_actor, _path), do: []

  @doc """
  The sharing a document's front matter states (seshat#82): `%{mode,
  owner_id}`. One written before modes is its poster's, in owner mode.
  """
  def sharing_of(meta) when is_map(meta) do
    case meta do
      %{"mode" => "open"} -> %{mode: "open", owner_id: meta["owner_id"]}
      _owned -> %{mode: "owner", owner_id: meta["owner_id"] || meta["by_id"]}
    end
  end

  @doc """
  A member edits a household document (seshat#82): its owner, in owner
  mode; any member, in open mode. Through the beats like any write (a
  resident in her turn, a witness once a target a beat). `content`
  rewrites its words; `mode` (`owner` or `open`) is the owner's alone to
  change. The path keeps its history; a thread is never edited.
  """
  def edit(%Actor{} = actor, name, attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, household_id} <- household(actor),
         :ok <- may_post(actor, household_id),
         {:ok, path} <- household_path(name),
         false <- Kinds.container?(Kinds.kind_of(path)),
         {:ok, _view} <- provision(household_id) do
      locked(household_id, fn view -> write_edit(actor, household_id, view, path, attrs) end)
    else
      true -> {:error, Error.new(:seshat_household_invalid, :seshat_household_edit_thread)}
      other -> other
    end
  end

  defp write_edit(actor, household_id, view, path, attrs) do
    with text when is_binary(text) <- file(view, path) || absent(path),
         {meta, body} = frontmatter(text),
         before = doc_commit(view, path),
         share = sharing_of(meta),
         :ok <- may_edit(actor, share, path),
         {:ok, mode} <- new_mode(actor, share, attrs["mode"]),
         {:ok, given, source} <- words_from(actor, attrs),
         words = given || body,
         :ok <- worded(words, false),
         :ok <- gate(actor, household_id, view, path, :file),
         by = author(household_id, actor),
         meta =
           meta
           |> Map.merge(%{
             "mode" => mode,
             "edited_by" => by.name,
             "edited_by_id" => actor.id,
             "edited_at" => iso(Clock.now())
           })
           |> Map.merge(Map.new(source))
           |> Map.put_new("owner_id", share.owner_id),
         {:ok, commit} <-
           commit(
             view,
             [{:put, path, render(ordered(meta), words), Map.get(view.files, path)}],
             "Edit: #{path}",
             by
           ) do
      if commit != :nothing and given != nil,
        do: draft_changed(household_id, path, before, commit)

      {:ok, %{path: path, mode: mode, owner_id: meta["owner_id"], commit: commit}}
    end
  end

  defp owner_name(_household_id, nil), do: nil

  defp owner_name(household_id, id),
    do: Enum.find_value(Gaia.household_members(household_id), &(&1.id == id && &1.name))

  defp may_edit(_actor, %{mode: "open"}, _path), do: :ok
  defp may_edit(%Actor{id: id}, %{owner_id: id}, _path), do: :ok

  defp may_edit(_actor, _share, path),
    do:
      {:error,
       Error.new(:seshat_household_not_owner, :seshat_household_edit_not_owner, path: path)}

  defp new_mode(_actor, share, nil), do: {:ok, share.mode}
  defp new_mode(_actor, %{mode: m}, m), do: {:ok, m}

  defp new_mode(%Actor{id: id}, %{owner_id: id}, mode) when mode in ["owner", "open"],
    do: {:ok, mode}

  defp new_mode(_actor, %{owner_id: nil}, _mode),
    do: {:error, Error.new(:seshat_household_not_owner, :seshat_household_mode_no_owner)}

  defp new_mode(_actor, _share, mode) when mode in ["owner", "open"],
    do: {:error, Error.new(:seshat_household_not_owner, :seshat_household_mode_not_owner)}

  defp new_mode(_actor, _share, _mode),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_edit_mode_unknown)}

  # The front matter in the order a person reads it: who and when first.
  @meta_order ~w(title by by_kind by_id posted_at owner_id mode source edited_by edited_by_id edited_at)
  defp ordered(meta) do
    known = for k <- @meta_order, Map.has_key?(meta, k), do: {k, meta[k]}
    known ++ Enum.sort(for {k, v} <- meta, k not in @meta_order, do: {k, v})
  end

  defp absent(path),
    do:
      {:error,
       Error.new(:seshat_household_no_such_document, :seshat_household_edit_absent, path: path)}

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
         {:ok, view} <- provision(household_id),
         thread when is_binary(thread) <- thread_path(thread_name) || no_thread(thread_name),
         {:ok, t} <- load_thread(view, thread),
         :ok <- cast(household_id, thread, vote, actor),
         by = author(household_id, actor),
         reply = {text, vote, integer(attrs["in_reply_to"])},
         {:ok, written} <-
           locked(household_id, fn view ->
             write_reply(actor, household_id, view, {thread, t}, by, reply)
           end) do
      poke(household_id, thread, t, written, by, actor)
      _ = wake_house_on_witness(household_id, thread, t, written, actor)
      {:ok, Map.merge(written, %{thread: thread, vote: vote})}
    end
  end

  defp write_reply(actor, household_id, view, {thread, t}, by, {text, vote, in_reply_to}) do
    # A vote is governance, never a post (seshat#67, #68): it waits on no
    # turn and spends no quota. A resident's answer to a house check-in is
    # the check-in's, not the beats' (seshat#75): her first reply there
    # waits on no turn either. Anything else goes through the beats.
    exempt? = vote != nil or checkin_answer?(actor, t)

    with :ok <- if(exempt?, do: :ok, else: gate(actor, household_id, view, thread, :post)) do
      append_reply(actor, household_id, view, {thread, t}, by, {text, vote, in_reply_to})
    end
  end

  defp append_reply(actor, _household_id, view, {thread, t}, by, {text, vote, in_reply_to}) do
    number = next_reply(view, thread)

    meta =
      [
        {"by", by.name},
        {"by_kind", Atom.to_string(actor.kind)},
        {"by_id", actor.id},
        {"at", iso(Clock.now())},
        {"reply", Integer.to_string(number)}
      ] ++
        optional("in_reply_to", in_reply_to && Integer.to_string(in_reply_to)) ++
        optional("vote", vote) ++
        stamp(view, t)

    body = if text == "", do: "Votes #{vote}.", else: text
    path = reply_path(thread, number, by.name)

    with {:ok, _} <-
           commit(
             view,
             [{:create, path, render(meta, body)}],
             "Reply ##{number} to #{t.trunk.meta["title"]}",
             by
           ),
         do: {:ok, %{path: path, number: number}}
  end

  # A reply on a document post is stamped with the draft it answers
  # (seshat#83): an out-of-date reply says so, whether or not a
  # draft-changed line was ever written.
  defp stamp(view, %{trunk: %{meta: %{"doc" => path}}}),
    do: optional("doc_commit", doc_commit(view, path))

  defp stamp(_view, _t), do: []

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

  # ---- house check-ins (gaia#41, seshat#75) ----

  @house_wake_worker :"Elixir.Oneiroi.Seshat.HouseholdTurnWorker"

  defp checkin_answer?(%Actor{kind: :resident, id: id}, %{trunk: %{meta: meta}, replies: replies}),
       do: is_binary(meta["checkin"]) and not Enum.any?(replies, &(&1.meta["by_id"] == id))

  defp checkin_answer?(_actor, _thread), do: false

  @doc """
  Opens a house check-in's thread for a day (seshat#75): written by the
  platform under `threads/checkin-<day>-<key>`, its trunk naming the
  check-in; one a day, so a second call for the day answers the same
  thread and writes nothing.
  """
  def open_checkin(household_id, key, label, day) do
    with {:ok, view} <- provision(household_id) do
      thread = "threads/checkin-#{day}-#{key}"
      path = Path.join(thread, @trunk)

      if has?(view, path),
        do: {:ok, thread},
        else: write_checkin(household_id, view, thread, key, label, day)
    end
  end

  defp write_checkin(household_id, _view, thread, key, label, day) do
    path = Path.join(thread, @trunk)

    meta = [
      {"title", "#{label}, #{day}"},
      {"by", @platform.name},
      {"by_kind", "platform"},
      {"posted_at", iso(Clock.now())},
      {"checkin", key}
    ]

    body =
      "The house checks in: #{label}. Each of you answers here, once, in your own words; " <>
        "your witness's reply wakes you all, and from there the household's beats hold the talk."

    locked(household_id, fn view ->
      changes = [{:create, path, render(meta, body)} | descriptor(view, Kinds.named("thread"))]

      case commit(view, changes, "House check-in: #{label}, #{day}", @platform) do
        {:ok, _} -> {:ok, thread}
        # Opened already, by a tick on another node: the same thread.
        {:error, %{kind: :sima_qian_repos_conflict}} -> {:ok, thread}
        other -> other
      end
    end)
  end

  @doc "Wakes every resident of the house open to it with a note of their own, each its own job, so all go at once (seshat#75)."
  def wake_house(household_id, note_for) do
    for %{kind: "resident", id: id} <- Gaia.household_members(household_id),
        not AgathosDaimon.held?(id) do
      Jobs.enqueue(@house_wake_worker, %{
        "household_id" => household_id,
        "house_wake" => id,
        "note" => note_for.(id)
      })
    end
  end

  # The witness's reply in a check-in thread wakes the whole house; after
  # it the beats and the watch hold the talk (the witness, 2026-11-16).
  defp wake_house_on_witness(
         household_id,
         thread,
         %{trunk: %{meta: %{"checkin" => _}}} = t,
         written,
         %Actor{kind: :witness}
       ) do
    title = t.trunk.meta["title"]

    wake_house(household_id, fn _id ->
      "Your witness replied in the house check-in thread #{thread} (\"#{title}\"), reply ##{written.number}. " <>
        "household_read with that path reads it. To answer again, register for a beat (household_register) " <>
        "or watch the thread (household_watch): the beats hold the talk from here."
    end)
  end

  defp wake_house_on_witness(_household_id, _thread, _t, _written, _actor), do: :ok

  # ---- the watch (gaia#32, seshat#62) ----

  @doc "A resident watches a thread for the hours it states: never on by default, and over when the term is."
  def watch(%Actor{} = actor, thread_name, hours) do
    with {:ok, household_id} <- household(actor),
         {:ok, view} <- provision(household_id),
         thread when is_binary(thread) <- thread_path(thread_name) || no_thread(thread_name),
         {:ok, _t} <- load_thread(view, thread),
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
    locked(household_id, fn view ->
      with {:ok, _} <- commit(view, render_contract(view, household_id), message, by),
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
         {:ok, _view} <- provision(household_id) do
      thread =
        Enum.find_value(
          Gaia.household_contract(household_id).ballots,
          &(&1.number == ballot && &1.thread)
        )

      locked(household_id, fn view ->
        write_outcome(household_id, view, thread, ballot, outcome)
      end)
    end
  end

  defp write_outcome(household_id, view, thread, ballot, outcome) do
    number = next_reply(view, thread)
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

    changes = [
      {:create, path, render(meta, "Ballot ##{ballot} closed. #{outcome.outcome}" <> carried)}
      | render_contract(view, household_id)
    ]

    with {:ok, _} <- commit(view, changes, "Ballot ##{ballot} closed", @platform),
         do: {:ok, outcome}
  end

  # ---- the beats' gate (seshat#67 to #69) ----

  # Every household write but a vote passes here, inside the household's
  # lock so two writes cannot both pass on one count: a resident only in
  # her turn and each target once in it; a witness, who is never fired,
  # once in each thread a beat; and everyone within the post quota.
  defp gate(actor, household_id, view, target, what) do
    shape = Gaia.household_beat_shape(household_id)
    now = Clock.now()
    writes = writes(view)

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

  # The refusal outside a turn names when she can next act (seshat#67):
  # her next registration and its place, or the next beat to register for.
  defp not_your_turn(household_id, actor, shape, now) do
    beats = Gaia.household_beats(household_id, now)

    # The beat running orders by turns had in it too; a beat to come by
    # what each has missed and when she registered.
    mine =
      case Enum.find(beats.queue, &(&1.resident_id == actor.id)) do
        %{position: place} ->
          {beats.beat.top, place}

        nil ->
          Enum.find_value(beats.registrations, &place_in(&1, actor.id))
      end

    remedy =
      case mine do
        nil ->
          top = Beats.ahead(household_id, shape, now, 1)

          "household_register signs you up for a coming beat: the next begins #{iso(top)} and its turns fire one after another from #{iso(Beats.signup_closes(top, shape))}, the most starved first; your writes go in during your turn. A vote is never held to the turns."

        {top, place} ->
          "You are registered for the beat at #{iso(top)}, #{ordinal(place)} as things stand; its turns fire from #{iso(Beats.signup_closes(top, shape))}, and your writes go in during your turn. A vote is never held to the turns."
      end

    %{
      Error.new(:seshat_household_not_your_turn, :seshat_household_write_outside_turn)
      | remedy: remedy
    }
  end

  defp place_in(registration, id) do
    case Enum.find_index(registration.residents, &(&1.resident_id == id)) do
      nil -> nil
      i -> {registration.beat_top, i + 1}
    end
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
  def writes(view) do
    threads =
      for id <- thread_ids(view),
          thread = "threads/" <> id,
          {:ok, t} <- [load_thread(view, thread)],
          w <- thread_writes(thread, t),
          do: w

    documents =
      for d <- documents(view),
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

    # The last edit of each document counts as its editor's write (seshat#82).
    edits =
      for d <- documents(view),
          at = instant(d.edited_at),
          at != nil,
          do: %{
            kind: "document",
            target: d.path,
            path: d.path,
            title: d.title,
            by: d.edited_by,
            by_id: d.edited_by_id,
            at: at,
            vote: nil
          }

    Enum.filter(threads, & &1.at) ++ documents ++ edits
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
  def write_beats(household_id, body, message) do
    locked(household_id, fn view ->
      if file(view, @beats) == body,
        do: {:ok, :unchanged},
        else:
          commit(view, [{:put, @beats, body, Map.get(view.files, @beats)}], message, @platform)
    end)
  end

  # ---- files ----

  defp thread_ids(view) do
    for path <- Map.keys(view.files),
        [_, id] <- [Regex.run(~r{\Athreads/([^/]+)/trunk\.md\z}, path)],
        do: id
  end

  defp thread_summary(view, id, ballots) do
    thread = "threads/" <> id
    {:ok, t} = load_thread(view, thread)
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

  defp documents(view) do
    for kind <- Kinds.household(),
        not Kinds.container?(kind),
        path <- Repos.under(view.files, kind.folder),
        name = Path.basename(path),
        in_folder?(kind, path),
        name != Kinds.descriptor_name() do
      {meta, _} = view |> file(path) |> to_string() |> frontmatter()

      %{
        kind: kind.kind,
        path: path,
        title: meta["title"] || name,
        by: meta["by"],
        by_id: meta["by_id"],
        posted_at: meta["posted_at"],
        edited_by: meta["edited_by"],
        edited_by_id: meta["edited_by_id"],
        edited_at: meta["edited_at"],
        source: meta["source"]
      }
    end
  end

  # A document sits in its kind's folder; a witness's, one deeper, in the
  # folder named for them (seshat#81).
  defp in_folder?(%{kind: "human"}, path), do: length(Path.split(path)) == 3
  defp in_folder?(kind, path), do: Path.dirname(path) == kind.folder

  defp load_thread(view, thread) do
    trunk = Path.join(thread, @trunk)

    if has?(view, trunk) do
      replies = replies(view, thread)
      {meta, body} = view |> file(trunk) |> to_string() |> frontmatter()

      {:ok,
       %{trunk: %{path: Path.join(thread, @trunk), meta: meta, body: body}, replies: replies}}
    else
      no_thread(thread)
    end
  end

  defp replies(view, thread) do
    for path <- Repos.under(view.files, Path.join(thread, "replies")) do
      {meta, body} = view |> file(path) |> to_string() |> frontmatter()
      %{path: path, meta: meta, body: body}
    end
  end

  # The document a document post is on (seshat#83), as it stands now:
  # its path, its latest draft and its words; nil for any other thread.
  defp posted_doc(view, %{trunk: %{meta: %{"doc" => path}}}) do
    text = file(view, path)
    {_meta, body} = frontmatter(to_string(text))
    %{path: path, commit: doc_commit(view, path), content: body, present: is_binary(text)}
  end

  defp posted_doc(_view, _t), do: nil

  # The document posts on a document (seshat#83): where its feedback is.
  defp discussed(view, path) do
    for id <- thread_ids(view),
        thread = "threads/" <> id,
        {:ok, t} <- [load_thread(view, thread)],
        t.trunk.meta["doc"] == path,
        do: %{path: thread, title: t.trunk.meta["title"], replies: length(t.replies)}
  end

  defp thread_text(thread, t, ballot, doc) do
    head =
      "# #{t.trunk.meta["title"]}\n#{thread}, posted by #{t.trunk.meta["by"]} at #{t.trunk.meta["posted_at"]}" <>
        ballot_line(ballot)

    replies =
      Enum.map_join(t.replies, "\n\n", fn
        %{meta: %{"draft" => "changed"}} = r ->
          "--- #{String.trim(r.body)} (#{r.meta["at"]})"

        r ->
          vote = if r.meta["vote"], do: ", votes #{r.meta["vote"]}", else: ""

          answers =
            if r.meta["in_reply_to"], do: ", answering ##{r.meta["in_reply_to"]}", else: ""

          "--- Reply ##{r.meta["reply"]} by #{r.meta["by"]} at #{r.meta["at"]}#{vote}#{answers}#{earlier(r, doc)}:\n#{String.trim(r.body)}"
      end)

    head <>
      "\n\n" <>
      String.trim(t.trunk.body) <>
      doc_text(doc) <>
      if(replies == "", do: "\n\nNo replies yet.", else: "\n\n" <> replies)
  end

  defp doc_text(nil), do: ""

  defp doc_text(%{present: false} = doc),
    do: "\n\n(#{doc.path} is no longer in the house.)"

  defp doc_text(doc),
    do:
      "\n\n=== #{doc.path}, its latest draft#{draft_at(doc.commit)} ===\n#{String.trim(doc.content)}\n=== end of #{doc.path} ==="

  # A reply on an earlier draft than the latest says so (seshat#83).
  defp earlier(%{meta: %{"doc_commit" => c}}, %{commit: latest}) when c != latest,
    do: ", on an earlier draft (#{short(c)})"

  defp earlier(_reply, _doc), do: ""

  defp ballot_line(nil), do: ""

  defp ballot_line(%{closed_at: nil} = b),
    do:
      "\nBallot ##{b.number}, open until #{iso(b.closes_at)}: #{votes_cast(length(b.votes))} so far."

  defp ballot_line(b), do: "\nBallot ##{b.number}, closed #{iso(b.closed_at)}: #{b.outcome}"

  defp votes_cast(1), do: "1 vote cast"
  defp votes_cast(n), do: "#{n} votes cast"

  defp next_reply(view, thread) do
    view.files
    |> Repos.under(Path.join(thread, "replies"))
    |> Enum.map(
      &(&1
        |> Path.basename()
        |> String.split("-", parts: 2)
        |> hd()
        |> Integer.parse())
    )
    |> Enum.map(fn
      {n, ""} -> n
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
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

  defp fresh_id(view, title) do
    base = "#{Date.to_iso8601(DateTime.to_date(Clock.now()))}-#{slug(title)}"

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(Repos.under(view.files, "threads/" <> &1) == []))
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

  # One commit under the writer's name (sima-qian#52), every file created
  # where it was absent (seshat#59: written once, so two writers never
  # land on one file) or put where it was as read (sima-qian#57).
  defp commit(view, changes, message, by), do: Repos.write(view.repo, changes, message, by)

  # The gate and the write it allows are one step (seshat#67): two writes
  # cannot both pass on one count. The repository itself is ordered by
  # its server; this orders the household's rules. Each step reads the
  # house fresh, so a number or a name it picks is the next one.
  defp locked(household_id, fun) do
    :global.trans({{__MODULE__, household_id}, self()}, fn ->
      with {:ok, view} <- view(household_id), do: fun.(view)
    end)
  end

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
