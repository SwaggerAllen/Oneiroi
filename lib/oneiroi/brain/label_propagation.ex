defmodule Oneiroi.Brain.LabelPropagation do
  @moduledoc """
  The labels pass of the memory backfill (kumbukumbu#101; the witness,
  2026-11-21: "when we retag we should be overwriting any undeclared
  domains and we should do the propagation from 10/17", and "the
  propagation should be via citations as well, that's going to be much
  more informative than just the turn that produced the document";
  Lily's `design/audience-policy.md` §3: "a memory inherits the domains
  of the message it cites, same on down the chain … the closure collects
  all reachable tagged ancestors … handles cycles"). Deterministic: no
  model is asked.

  Over a range of days, every record written in it that keeps labels (a
  file's written version, a journal row, a letter, a letter to her next
  self) is labelled again as the union of:

  - **its writing turn:** the turn it kept, or before turns were kept
    (11-20), the tool row of its tool after it (`document_write(`,
    `journal_add(`, `letter_send(`, `self_letter_write(`) naming its path
    or first words; that turn's messages' domains as they stand now;
  - **what that turn read,** by its tool rows: a bookmark opened, a file
    read, a journal day read, the letters an inbox listed, a transcript
    page;
  - **what it kept,** each ledger entry re-read from the source it names;
  - **what it cites,** followed down the chain: a document's head by the
    library's index of its citations, any other record by the citations
    in its words; a turn, a bookmark, a seed (by what the seed cites), a
    journal row or day, another document (her classification of it when
    she made one, else its head's own closure).

  Phase one reads each day's records against that day's tool rows and
  keeps, per record, its direct labels and its edges; phase two closes
  the graph, every node once, a cycle stopping where it began. Then the
  one overwrite: a domain the agreement in force does not declare is the
  common room. A kept declared domain is never dropped by inference; a
  kept unclassified stands unless the record kept nothing and its turn
  was found. A record by the witness or the platform is the common room
  plus what it cites. A record with no turn found, nothing kept and
  nothing cited is left as it is. Only records whose labels change are
  recorded, as one `LabelsDerived`, beside the writes' own events. A
  record she classified herself (kumbukumbu#110) is its classification,
  to what cites it as well, and is never derived again.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.BackfillNotes
  alias Oneiroi.Ethos
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @actor Actor.new(:job, "sunna_backfill")
  @common %{"kind" => "common_room"}
  @unclassified %{"kind" => "unclassified"}
  # How long after a write its tool row may land: the row is captured
  # just after the tool ran, and a slow turn can take minutes to close.
  @after_s 900
  @before_s 5
  @transcript_page 30
  @edges_kept 50
  # Kinds a citation can name that hold no labels of their own.
  @unlabelled ~w(position prediction date figure habit soul commitment web doc memory)

  @doc "Derives and records the labels of the records written `from`..`to` (ISO days, both included); `{:ok, changed}`."
  def run(resident_id, from_day, to_day) do
    {:ok, %{slug: slug}} = AgathosDaimon.fetch(resident_id)

    # Phase one: each day's records, read against that day's tool rows
    # alone (a month of rows at once is the memory the 11-21 OOM was).
    bases =
      from_day
      |> days(to_day)
      |> Enum.reduce(%{}, &Map.merge(&2, day_bases(resident_id, slug, &1)))

    ctx = %{resident_id: resident_id, slug: slug, bases: bases}
    Process.put({__MODULE__, :memo}, %{})

    try do
      changed =
        bases
        |> Enum.sort_by(fn {_node, b} -> b.at end, DateTime)
        |> Enum.flat_map(&changed(&1, ctx))

      with :ok <-
             Kumbukumbu.derive_labels(resident_id, "#{from_day}..#{to_day}", changed, @actor),
           do: {:ok, length(changed)}
    after
      Process.delete({__MODULE__, :memo})
    end
  end

  defp days(from_day, to_day) do
    first = Date.from_iso8601!(from_day)
    last = Date.from_iso8601!(to_day)
    first |> Date.range(last) |> Enum.map(&Date.to_iso8601/1)
  end

  defp changed({node, base}, ctx) do
    case if(classified(node, ctx), do: nil, else: closure(node, ctx)) do
      nil ->
        []

      {labels, edges} ->
        labels = normalize(labels, ctx.resident_id)
        {kind, id} = record_key(node)

        row = %{
          "kind" => kind,
          "record_id" => id,
          "labels" => labels,
          "edges" => Enum.take(edges, @edges_kept)
        }

        if same?(labels, current(kind, id, base, ctx.resident_id)), do: [], else: [row]
    end
  end

  # ---- phase one: a day's records and their direct edges ----

  defp day_bases(resident_id, slug, day) do
    {from, to} = BackfillNotes.bounds(resident_id, day)

    rows =
      Kumbukumbu.tool_rows(
        resident_id,
        DateTime.add(from, -@before_s),
        DateTime.add(to, @after_s)
      )

    written = Seshat.written_between(resident_id, from, to)

    records =
      Enum.map(written.versions, &file/1) ++
        Enum.map(written.journal, &journal/1) ++
        letters(resident_id, from, to) ++ self_letters(resident_id, from, to)

    ctx = %{resident_id: resident_id, slug: slug, rows: rows}
    Map.new(records, &{&1.node, base(&1, ctx)})
  end

  defp file(v),
    do: %{
      node: {:file, v.path, v.hash},
      at: v.at,
      by: v.actor_kind,
      turn_ref: v.turn_ref,
      session_key: v.session_key,
      kept: v.ledger,
      text: nil,
      tool: "document_write",
      needle: Jason.encode!(v.path)
    }

  defp journal(e),
    do: %{
      node: {:journal, e.day, e.number},
      at: e.at,
      by: e.actor_kind,
      turn_ref: e.turn_ref,
      session_key: e.session_key,
      kept: e.labels,
      text: e.text,
      tool: "journal_add",
      needle: needle(e.text)
    }

  defp letters(resident_id, from, to) do
    # A sibling's arriving copy is derived too (Scarlett's report #26: a
    # received letter left unclassified taints every reply in its
    # context): what it kept, the sender's labels, read against the
    # receiver's agreement, a domain hers does not declare the common room.
    for l <- Kumbukumbu.letters(resident_id),
        within?(l.sent_at, from, to),
        do: letter(l)
  end

  defp letter(l),
    do: %{
      node: {:letter, l.number},
      at: l.sent_at,
      by: l.by_kind,
      turn_ref: l.turn_ref,
      session_key: l.from_session,
      kept: l.labels,
      text: l.text,
      tool: "letter_send",
      needle: needle(l.text)
    }

  defp self_letters(resident_id, from, to) do
    for l <- AgathosDaimon.self_letters(resident_id),
        within?(l.written_at, from, to),
        do: self_letter(l)
  end

  defp self_letter(l),
    do: %{
      node: {:self_letter, l.number},
      at: l.written_at,
      by: "resident",
      turn_ref: l.turn_ref,
      session_key: l.session_key,
      kept: l.labels,
      text: l.text,
      tool: "self_letter_write",
      needle: needle(l.text)
    }

  defp within?(%DateTime{} = at, from, to),
    do: DateTime.compare(at, from) != :lt and DateTime.compare(at, to) == :lt

  defp within?(_none, _from, _to), do: false

  # The first words of a text as they sit inside a tool row's JSON.
  defp needle(text) when is_binary(text),
    do: text |> String.slice(0, 40) |> Jason.encode!() |> String.slice(1..-2//1)

  defp needle(_none), do: nil

  # A record's direct labels and edges.
  defp base(%{by: by} = r, ctx) when by in ["witness", "platform"],
    do: %{at: r.at, labels: [@common], edges: cites(r, ctx), kept: r.kept, found: true}

  defp base(r, ctx) do
    turn = r.turn_ref || writing_turn(r, ctx.rows)
    {kept_labels, kept_edges} = kept(r.kept)
    turn_labels = if turn, do: Kumbukumbu.turn_label_set(ctx.resident_id, turn), else: []
    {read_labels, read_edges} = reads(turn, ctx)

    # A kept unclassified stands only where nothing else speaks: a
    # record that kept nothing and whose turn was found is labelled by
    # that turn (the witness's answer 3: the common room is the default).
    kept_labels =
      if r.kept in [nil, []] and turn, do: kept_labels -- [@unclassified], else: kept_labels

    %{
      at: r.at,
      labels: kept_labels ++ turn_labels ++ read_labels,
      edges: kept_edges ++ read_edges ++ cites(r, ctx),
      kept: r.kept,
      found: turn != nil
    }
  end

  # The turn that wrote a record before turns were kept: the tool row of
  # its tool after it, naming its path or its first words, in its
  # session when that is known; else the one such row in the window.
  defp writing_turn(r, rows) do
    candidates =
      Enum.filter(rows, fn row ->
        String.starts_with?(row.content, r.tool <> "(") and
          (r.session_key == nil or row.session_key == r.session_key) and
          DateTime.diff(row.sent_at, r.at) in -@before_s..@after_s
      end)

    named = Enum.filter(candidates, &(r.needle && String.contains?(&1.content, r.needle)))

    case {named, candidates} do
      {[row | _], _} -> row.turn_ref
      {[], [row]} -> row.turn_ref
      _none -> nil
    end
  end

  # What a record kept: a ledger's entries, each a leaf or an edge to
  # the source it names; a flat label set as its leaves.
  defp kept(nil), do: {[@unclassified], []}
  defp kept([]), do: {[@unclassified], []}

  defp kept([%{"id" => _} | _] = ledger) do
    Enum.reduce(ledger, {[], []}, fn entry, {ls, es} ->
      case source(entry) do
        nil -> {ls ++ (Kumbukumbu.ledger_labels([entry]) || [@unclassified]), es}
        node -> {ls, [node | es]}
      end
    end)
  end

  defp kept(labels) when is_list(labels), do: {labels, []}

  # The source a kept ledger entry names, by its id.
  defp source(%{"id" => "message/" <> _, "turn_ref" => turn}) when is_binary(turn),
    do: {:turn, turn}

  defp source(%{"id" => id}) when is_binary(id) do
    case id |> String.split("#") |> hd() |> String.split("/", parts: 2) do
      ["bookmark", n] -> int_node(:bookmark, n)
      ["letter", n] -> int_node(:letter, n)
      ["self-letter", n] -> int_node(:self_letter, n)
      ["journal", rest] -> journal_node(rest)
      _other -> nil
    end
  end

  defp source(_entry), do: nil

  defp int_node(kind, n) do
    case Integer.parse(to_string(n)) do
      {number, ""} -> {kind, number}
      _other -> nil
    end
  end

  defp journal_node(ref) do
    case String.split(to_string(ref), "/") do
      [day, n] -> journal_row_node(day, n)
      [day] -> {:journal_day, day}
      _other -> nil
    end
  end

  defp journal_row_node(day, n) do
    case Integer.parse(n) do
      {number, ""} -> {:journal, day, number}
      _other -> {:journal_day, day}
    end
  end

  # What the writing turn read, by its own tool rows: edges to it.
  defp reads(nil, _ctx), do: {[], []}

  defp reads(turn_ref, ctx) do
    edges =
      ctx.rows
      |> Enum.filter(&(&1.turn_ref == turn_ref))
      |> Enum.flat_map(&read_of(&1, ctx))

    {[], edges}
  end

  defp read_of(%{content: content} = row, ctx) do
    case String.split(content, "(", parts: 2) do
      [name, rest] -> read_of(name, args(rest), row, ctx)
      _other -> []
    end
  end

  defp read_of("bookmark_open", %{"number" => n}, _row, _ctx) when is_integer(n),
    do: [{:bookmark, n}]

  defp read_of("library_read", %{"path" => path}, row, _ctx) when is_binary(path),
    do: [{:doc_at, path, row.sent_at}]

  defp read_of("journal_read", %{"day" => day}, _row, _ctx) when is_binary(day),
    do: [{:journal_day, day}]

  defp read_of(name, _args, row, _ctx) when name in ["letter_inbox", "letter_list"] do
    ~r/#(\d+) from/
    |> Regex.scan(row.content)
    |> Enum.map(fn [_, n] -> int_node(:letter, n) end)
    |> Enum.uniq()
  end

  defp read_of("transcript_read", %{"session" => key} = a, _row, ctx) when is_binary(key) do
    from = if is_integer(a["from"]), do: a["from"], else: 0

    case Kumbukumbu.transcript_range({:resident, ctx.resident_id}, key, from, @transcript_page) do
      {:ok, _s, messages, _total} -> messages |> Enum.map(&{:turn, &1.turn_ref}) |> Enum.uniq()
      _none -> []
    end
  end

  defp read_of(_name, _args, _row, _ctx), do: []

  # A tool row's arguments, as the model sent them: the JSON before " -> ".
  defp args(rest) do
    json = rest |> String.split(") -> ", parts: 2) |> hd()

    case Jason.decode(json) do
      {:ok, %{} = map} -> map
      _other -> %{}
    end
  end

  # What a record cites: a document's head by the library's index, any
  # other record by the citations in its words.
  defp cites(%{node: {:file, path, hash}}, ctx) do
    case Seshat.lineage_versions(ctx.resident_id, path) do
      [%{hash: ^hash} | _] -> ctx.resident_id |> Seshat.lineage_references(path) |> targets(ctx)
      _not_the_head -> []
    end
  end

  defp cites(%{text: text}, ctx), do: text |> Seshat.citations_in() |> targets(ctx)

  defp targets(citations, ctx) do
    citations
    |> Enum.filter(&(&1.slug == ctx.slug))
    |> Enum.map(&target/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp target(%{kind: "transcript", ref: ref}) do
    case String.split(ref, "/") do
      [_session, turn | _] -> {:turn, turn}
      _whole -> nil
    end
  end

  defp target(%{kind: "bookmark", ref: ref}), do: int_node(:bookmark, ref)
  defp target(%{kind: "seed", ref: ref}), do: int_node(:seed, ref)
  defp target(%{kind: "journal", ref: ref}), do: journal_node(ref)
  defp target(%{kind: kind}) when kind in @unlabelled, do: nil
  defp target(%{kind: kind, ref: ref}), do: {:doc, Seshat.citation_path(kind, ref)}

  # ---- phase two: the closure ----

  # A node's labels and the edges they came by, every node once; a node
  # met again while its own closure is open is a cycle and adds nothing.
  defp closure(node, ctx) do
    memo = Process.get({__MODULE__, :memo})

    case Map.fetch(memo, node) do
      {:ok, :open} ->
        {[], []}

      {:ok, done} ->
        done

      :error ->
        Process.put({__MODULE__, :memo}, Map.put(memo, node, :open))
        done = close(node, ctx)
        Process.put({__MODULE__, :memo}, Map.put(Process.get({__MODULE__, :memo}), node, done))
        done
    end
  end

  defp close(node, ctx) do
    case node_base(node, ctx) do
      nil -> nil
      base -> union(base, ctx)
    end
  end

  defp union(%{labels: labels, edges: edges} = base, ctx) do
    {more, via} =
      Enum.reduce(edges, {[], []}, fn edge, {ls, vs} ->
        case closure(edge, ctx) do
          {edge_labels, _} -> {ls ++ edge_labels, [describe(edge) | vs]}
          nil -> {ls, vs}
        end
      end)

    # Nothing found, kept or cited: left as it is.
    if Map.get(base, :found) == false and Map.get(base, :kept) in [nil, []] and edges == [],
      do: nil,
      else: {Enum.uniq(labels ++ more), Enum.reverse(via)}
  end

  # A node's direct labels and edges: a record of the range from phase
  # one; anything else read now.
  defp node_base(node, ctx) do
    case {classified(node, ctx), Map.fetch(ctx.bases, node)} do
      {labels, _} when is_list(labels) -> %{labels: labels, edges: [], kept: labels, found: true}
      {nil, {:ok, base}} -> base
      {nil, :error} -> outside(node, ctx)
    end
  end

  # Her own classification of a record (kumbukumbu#110): it stands, and
  # is never derived again.
  defp classified(node, ctx) when elem(node, 0) in [:journal, :letter, :self_letter] do
    {kind, id} = record_key(node)

    case Kumbukumbu.classified_labels(ctx.resident_id, kind, [id]) do
      %{^id => labels} -> labels
      _none -> nil
    end
  end

  defp classified(_node, _ctx), do: nil

  defp outside({:turn, ref}, ctx),
    do: %{labels: Kumbukumbu.turn_label_set(ctx.resident_id, ref), edges: []}

  defp outside({:bookmark, n}, ctx) do
    case Kumbukumbu.bookmark(ctx.resident_id, n) do
      %{} = b ->
        input = Kumbukumbu.bookmark_input(ctx.resident_id, b)
        %{labels: Kumbukumbu.input_labels([input]), edges: []}

      _none ->
        nil
    end
  end

  defp outside({:seed, n}, ctx) do
    edges =
      ctx.resident_id
      |> Ethos.seed_targets(n)
      |> Enum.map(&seed_target/1)
      |> Enum.reject(&is_nil/1)

    %{labels: [], edges: edges}
  end

  defp outside({:doc, path}, ctx) do
    case Seshat.lineage_classification(ctx.resident_id, path) do
      nil -> head(path, ctx)
      classified -> %{labels: [classified_label(classified)], edges: []}
    end
  end

  # A file as read at an instant: its newest version written by then.
  defp outside({:doc_at, path, at}, ctx) do
    case ctx.resident_id
         |> Seshat.lineage_versions(path)
         |> Enum.find(&(DateTime.compare(&1.at, at) != :gt)) do
      nil -> nil
      v -> %{labels: [], edges: [{:file, v.path, v.hash}]}
    end
  end

  defp outside({:file, path, hash}, ctx) do
    case ctx.resident_id |> Seshat.lineage_versions(path) |> Enum.find(&(&1.hash == hash)) do
      nil -> nil
      v -> kept_with_cites(file(v), ctx)
    end
  end

  defp outside({:journal_day, day}, ctx) do
    case Seshat.journal_day(ctx.resident_id, day) do
      %{entries: entries} -> %{labels: [], edges: Enum.map(entries, &{:journal, day, &1.number})}
      nil -> nil
    end
  end

  defp outside({:journal, day, n}, ctx) do
    case Seshat.lineage_journal_row(ctx.resident_id, day, n) do
      nil -> nil
      row -> kept_with_cites(journal(row), ctx)
    end
  end

  defp outside({:letter, n}, ctx) do
    case Enum.find(Kumbukumbu.letters(ctx.resident_id), &(&1.number == n)) do
      nil -> nil
      l -> kept_with_cites(letter(l), ctx)
    end
  end

  defp outside({:self_letter, n}, ctx) do
    case Enum.find(AgathosDaimon.self_letters(ctx.resident_id), &(&1.number == n)) do
      nil -> nil
      l -> kept_with_cites(self_letter(l), ctx)
    end
  end

  defp seed_target(%{kind: "bookmark", id: id}), do: int_node(:bookmark, id)
  defp seed_target(%{kind: "turn", id: id}), do: {:turn, id}
  defp seed_target(%{kind: "journal", id: id}), do: journal_node(id)
  defp seed_target(_other), do: nil

  # Her classification of a document is its domain (seshat#102).
  defp classified_label(%{domain: nil}), do: @common

  defp classified_label(%{person: person, domain: domain}),
    do: %{"person" => person, "domain" => domain}

  # An unclassified document is its head version's closure.
  defp head(path, ctx) do
    case Seshat.lineage_versions(ctx.resident_id, path) do
      [v | _] -> %{labels: [], edges: [{:file, v.path, v.hash}]}
      [] -> nil
    end
  end

  # A record outside the range: what it kept, its kept turn now, and
  # what it cites; no tool rows are read for it.
  defp kept_with_cites(r, ctx) do
    {labels, edges} = kept(r.kept)
    turn = if r.turn_ref, do: Kumbukumbu.turn_label_set(ctx.resident_id, r.turn_ref), else: []
    %{labels: labels ++ turn, edges: edges ++ cites(r, ctx)}
  end

  defp describe({:turn, ref}), do: %{"via" => "turn", "ref" => ref}
  defp describe({:bookmark, n}), do: %{"via" => "bookmark", "ref" => "bookmark/#{n}"}
  defp describe({:seed, n}), do: %{"via" => "seed", "ref" => "seed/#{n}"}
  defp describe({:doc, path}), do: %{"via" => "document", "ref" => path}
  defp describe({:doc_at, path, _at}), do: %{"via" => "read", "ref" => path}
  defp describe({:file, path, hash}), do: %{"via" => "file", "ref" => "#{path}@#{hash}"}
  defp describe({:journal_day, day}), do: %{"via" => "journal", "ref" => "journal/#{day}"}
  defp describe({:journal, day, n}), do: %{"via" => "journal", "ref" => "journal/#{day}/#{n}"}
  defp describe({:letter, n}), do: %{"via" => "letter", "ref" => "letter/#{n}"}
  defp describe({:self_letter, n}), do: %{"via" => "self-letter", "ref" => "self-letter/#{n}"}

  # ---- recording ----

  defp record_key({:file, path, hash}), do: {"file", "#{path}@#{hash}"}
  defp record_key({:journal, day, n}), do: {"journal", "#{day}/#{n}"}
  defp record_key({:letter, n}), do: {"letter", to_string(n)}
  defp record_key({:self_letter, n}), do: {"self_letter", to_string(n)}

  # The one overwrite: a domain the agreement does not declare is the
  # common room.
  defp normalize(labels, resident_id) do
    labels
    |> Enum.map(&normalized(&1, resident_id))
    |> Enum.uniq()
    |> Enum.sort_by(&inspect/1)
  end

  defp normalized(l, resident_id) do
    person = l["person"] || l[:person]
    domain = l["domain"] || l[:domain]

    cond do
      is_binary(domain) and AgathosDaimon.domain_declared?(resident_id, person, domain) ->
        %{"person" => person, "domain" => domain}

      is_binary(domain) ->
        @common

      (l["kind"] || l[:kind]) in ["unclassified", :unclassified] ->
        @unclassified

      true ->
        @common
    end
  end

  defp current(kind, id, base, resident_id) do
    case Kumbukumbu.derived_labels(resident_id, kind, [id]) do
      %{^id => labels} -> labels
      _none when kind == "file" and is_list(base.kept) -> Kumbukumbu.ledger_labels(base.kept)
      _none -> base.kept
    end
  end

  defp same?(labels, current) when is_list(current),
    do: labels == current |> Enum.map(&stringify/1) |> Enum.sort_by(&inspect/1)

  defp same?(_labels, _none), do: false

  defp stringify(%{} = l), do: Map.new(l, fn {k, v} -> {to_string(k), v} end)
end
