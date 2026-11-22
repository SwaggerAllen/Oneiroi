defmodule Oneiroi.Brain.LabelPropagation do
  @moduledoc """
  The labels pass of the memory backfill (kumbukumbu#101; the witness,
  2026-11-21: "when we retag we should be overwriting any undeclared
  domains and we should do the propagation from 10/17"; Lily's
  `design/audience-policy.md` §3: "a memory inherits the domains of the
  message it cites, same on down the chain … the backfill collects every
  reachable tagged ancestor"). Deterministic: no model is asked.

  For one past day, every record written that day that keeps labels (a
  file's written version, a journal row, a letter, a letter to her next
  self) is labelled again from what it came from, oldest first, so a
  record cites ancestors already derived:

  - **its writing turn**, by the turn it kept or, before turns were
    kept (11-20), by the tool row that wrote it (`document_write(`,
    `journal_add(`, `letter_send(`, `self_letter_write(` in the window
    after the write): that turn's messages' domains as they stand now;
  - **what that turn read**, by its tool rows: a bookmark opened (its
    anchor's domain), a file read (its version's labels, derived when
    they were), a journal day read (its rows'), the letters an inbox
    listed (theirs), a stretch of a transcript (its messages');
  - **what it kept**, the labels or ledger stored at write time, each
    entry re-read from its source where it names one (a message's turn,
    a bookmark, a letter, a journal row, a file), the rest as kept.

  The union is the record's labels, with one overwrite: a label naming a
  domain the agreement in force does not declare becomes the common
  room. A kept `unclassified` stays (nothing is opened by inference)
  unless the record had no labels at all and its writing turn was found.
  A record whose turn is not found and kept nothing stays as it is; one
  written by the witness or the platform is the common room. Only
  records whose labels change are recorded, as `LabelsDerived`, a new
  decision beside the write's own event, never over it.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.BackfillNotes
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

  @doc "Derives and records the labels of one day's records; `{:ok, changed}`."
  def run(resident_id, day) do
    {from, to} = BackfillNotes.bounds(resident_id, day)

    rows =
      Kumbukumbu.tool_rows(
        resident_id,
        DateTime.add(from, -@before_s),
        DateTime.add(to, @after_s)
      )

    written = Seshat.written_between(resident_id, from, to)

    records =
      (Enum.map(written.versions, &file/1) ++
         Enum.map(written.journal, &journal/1) ++
         letters(resident_id, from, to) ++ self_letters(resident_id, from, to))
      |> Enum.sort_by(& &1.at, DateTime)

    ctx = %{resident_id: resident_id, rows: rows, derived: %{}}

    {changed, _ctx} = Enum.reduce(records, {[], ctx}, &step/2)

    with :ok <- Kumbukumbu.derive_labels(resident_id, day, Enum.reverse(changed), @actor),
         do: {:ok, length(changed)}
  end

  # One record derived: kept for those after it, recorded when changed.
  defp step(r, {acc, ctx}) do
    case derive(r, ctx) do
      nil ->
        {acc, ctx}

      {labels, edges} ->
        ctx = put_in(ctx, [:derived, {r.kind, r.id}], labels)
        row = %{"kind" => r.kind, "record_id" => r.id, "labels" => labels, "edges" => edges}
        if same?(labels, current(r, ctx.resident_id)), do: {acc, ctx}, else: {[row | acc], ctx}
    end
  end

  # ---- the records ----

  defp file(v),
    do: %{
      kind: "file",
      id: "#{v.path}@#{v.hash}",
      at: v.at,
      by: v.actor_kind,
      turn_ref: v.turn_ref,
      session_key: v.session_key,
      kept: v.ledger,
      tool: "document_write",
      needle: Jason.encode!(v.path),
      path: v.path
    }

  defp journal(e),
    do: %{
      kind: "journal",
      id: "#{e.day}/#{e.number}",
      at: e.at,
      by: e.actor_kind,
      turn_ref: e.turn_ref,
      session_key: e.session_key,
      kept: e.labels,
      tool: "journal_add",
      needle: needle(e.text)
    }

  defp letters(resident_id, from, to) do
    for l <- Kumbukumbu.letters(resident_id),
        (l.sent_at && DateTime.compare(l.sent_at, from) != :lt) and
          DateTime.compare(l.sent_at, to) == :lt,
        # A sibling's arriving copy carries the sender's labels; it is
        # derived on the sender's side.
        is_nil(get_in(l.link || %{}, ["number"])) or l.from_session != nil,
        do: %{
          kind: "letter",
          id: to_string(l.number),
          at: l.sent_at,
          by: l.by_kind,
          turn_ref: l.turn_ref,
          session_key: l.from_session,
          kept: l.labels,
          tool: "letter_send",
          needle: needle(l.text)
        }
  end

  defp self_letters(resident_id, from, to) do
    for l <- AgathosDaimon.self_letters(resident_id),
        (l.written_at && DateTime.compare(l.written_at, from) != :lt) and
          DateTime.compare(l.written_at, to) == :lt,
        do: %{
          kind: "self_letter",
          id: to_string(l.number),
          at: l.written_at,
          by: "resident",
          turn_ref: l.turn_ref,
          session_key: l.session_key,
          kept: l.labels,
          tool: "self_letter_write",
          needle: needle(l.text)
        }
  end

  # The first words of a text as they sit inside a tool row's JSON.
  defp needle(text) when is_binary(text) do
    head = text |> String.slice(0, 40)
    head |> Jason.encode!() |> String.slice(1..-2//1)
  end

  defp needle(_none), do: nil

  # ---- the derivation ----

  defp derive(%{by: by}, _ctx) when by in ["witness", "platform"],
    do: {[@common], [%{"via" => "author", "ref" => by}]}

  defp derive(r, ctx) do
    turn = r.turn_ref || writing_turn(r, ctx.rows)
    kept = kept_labels(r, ctx)
    if turn == nil and kept == [], do: nil, else: union(r, turn, kept, ctx)
  end

  defp union(r, turn, kept, ctx) do
    {turn_labels, turn_edges} = turn_labels(turn, ctx)
    {read_labels, read_edges} = reads(turn, ctx)

    # A kept unclassified stands only where nothing else speaks: a
    # record that kept no labels and whose turn was found is labelled by
    # that turn (the witness's answer 3: common room is the default
    # classification).
    kept =
      if r.kept in [nil, []] and turn != nil,
        do: Enum.reject(kept, &(&1 == @unclassified)),
        else: kept

    labels = normalize(kept ++ turn_labels ++ read_labels, ctx.resident_id)
    labels = if labels == [], do: [@common], else: labels
    {labels, turn_edges ++ read_edges ++ kept_edges(r)}
  end

  # The turn that wrote a record before turns were kept: the tool row of
  # its tool after it, naming its path or its first words, in its
  # session when that is known; else the one such row in the window.
  defp writing_turn(r, rows) do
    candidates =
      Enum.filter(rows, fn row ->
        String.starts_with?(row.content, r.tool <> "(") and
          (r.session_key == nil or row.session_key == r.session_key) and
          DateTime.diff(row.sent_at, r.at) >= -@before_s and
          DateTime.diff(row.sent_at, r.at) <= @after_s
      end)

    named = Enum.filter(candidates, &(r.needle && String.contains?(&1.content, r.needle)))

    case {named, candidates} do
      {[row | _], _} -> row.turn_ref
      {[], [row]} -> row.turn_ref
      _none -> nil
    end
  end

  defp turn_labels(nil, _ctx), do: {[], []}

  defp turn_labels(turn_ref, ctx) do
    case Kumbukumbu.turn_label_set(ctx.resident_id, turn_ref) do
      [] -> {[], []}
      labels -> {labels, [%{"via" => "turn", "ref" => turn_ref}]}
    end
  end

  # What the writing turn read, by its own tool rows.
  defp reads(nil, _ctx), do: {[], []}

  defp reads(turn_ref, ctx) do
    ctx.rows
    |> Enum.filter(&(&1.turn_ref == turn_ref))
    |> Enum.map(&read_of(&1, ctx))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce({[], []}, fn {labels, edge}, {ls, es} -> {ls ++ labels, [edge | es]} end)
  end

  defp read_of(%{content: content} = row, ctx) do
    case String.split(content, "(", parts: 2) do
      [name, rest] -> read_of(name, args(rest), row, ctx)
      _other -> nil
    end
  end

  defp read_of("bookmark_open", %{"number" => n}, _row, ctx) when is_integer(n),
    do: {bookmark_labels(ctx.resident_id, n), %{"via" => "bookmark", "ref" => "bookmark/#{n}"}}

  defp read_of("library_read", %{"path" => path}, row, ctx) when is_binary(path),
    do: {file_labels(path, row.sent_at, ctx), %{"via" => "file", "ref" => path}}

  defp read_of("journal_read", %{"day" => day}, _row, ctx) when is_binary(day),
    do: {journal_labels(day, ctx), %{"via" => "journal", "ref" => "journal/#{day}"}}

  defp read_of(name, _args, row, ctx) when name in ["letter_inbox", "letter_list"] do
    numbers =
      ~r/#(\d+) from/
      |> Regex.scan(row.content)
      |> Enum.map(fn [_, n] -> n end)
      |> Enum.uniq()

    if numbers == [],
      do: nil,
      else:
        {Enum.flat_map(numbers, &record_labels("letter", &1, ctx)),
         %{"via" => "letters", "ref" => Enum.join(numbers, ",")}}
  end

  defp read_of("transcript_read", %{"session" => key} = a, _row, ctx) when is_binary(key) do
    from = if is_integer(a["from"]), do: a["from"], else: 0

    case Kumbukumbu.transcript_range({:resident, ctx.resident_id}, key, from, @transcript_page) do
      {:ok, _s, messages, _total} ->
        {messages
         |> Enum.map(& &1.turn_ref)
         |> Enum.uniq()
         |> Enum.flat_map(&Kumbukumbu.turn_label_set(ctx.resident_id, &1)),
         %{"via" => "transcript", "ref" => "transcript/#{key}@#{from}"}}

      _none ->
        nil
    end
  end

  defp read_of(_name, _args, _row, _ctx), do: nil

  # A tool row's arguments, as the model sent them: the JSON before
  # " -> ".
  defp args(rest) do
    json = rest |> String.split(") -> ", parts: 2) |> hd()

    case Jason.decode(json) do
      {:ok, %{} = map} -> map
      _other -> %{}
    end
  end

  defp bookmark_labels(resident_id, n) do
    case Kumbukumbu.bookmark(resident_id, n) do
      %{} = b -> Kumbukumbu.input_labels([Kumbukumbu.bookmark_input(resident_id, b)])
      _none -> []
    end
  end

  # A file read: its newest written version at the read, its labels
  # derived when they were (this run's or an earlier day's), else kept.
  defp file_labels(path, at, ctx) do
    case Seshat.written_between(ctx.resident_id, ~U[2000-01-01 00:00:00Z], DateTime.add(at, 1)).versions
         |> Enum.filter(&(&1.path == path))
         |> List.last() do
      nil ->
        []

      v ->
        record_labels(
          "file",
          "#{v.path}@#{v.hash}",
          ctx,
          v.ledger && Kumbukumbu.ledger_labels(v.ledger)
        )
    end
  end

  defp journal_labels(day, ctx) do
    case Seshat.journal_day(ctx.resident_id, day) do
      %{entries: entries} ->
        Enum.flat_map(entries, &record_labels("journal", "#{day}/#{&1.number}", ctx, &1.labels))

      nil ->
        []
    end
  end

  defp record_labels(kind, id, ctx, kept \\ nil) do
    case Map.fetch(ctx.derived, {kind, id}) do
      {:ok, labels} ->
        labels

      :error ->
        case Kumbukumbu.derived_labels(ctx.resident_id, kind, [id]) do
          %{^id => labels} -> labels
          _none -> kept || kept_of(kind, id, ctx)
        end
    end
  end

  defp kept_of("letter", id, ctx) do
    case Enum.find(Kumbukumbu.letters(ctx.resident_id), &(to_string(&1.number) == id)) do
      %{labels: labels} when is_list(labels) -> labels
      _none -> [@unclassified]
    end
  end

  defp kept_of(_kind, _id, _ctx), do: [@unclassified]

  # What the record kept, each ledger entry re-read from the source it
  # names where it names one.
  defp kept_labels(%{kind: "file", kept: ledger}, ctx) when is_list(ledger) do
    Enum.flat_map(ledger, &entry_labels(&1, ctx))
  end

  defp kept_labels(%{kept: labels}, _ctx) when is_list(labels) and labels != [], do: labels
  defp kept_labels(_r, _ctx), do: [@unclassified]

  defp entry_labels(entry, ctx) do
    kept = Kumbukumbu.ledger_labels([entry]) || [@unclassified]
    entry |> source() |> resolve(kept, ctx)
  end

  # The source a kept ledger entry names, by its id.
  defp source(%{"id" => "message/" <> _, "turn_ref" => turn}) when is_binary(turn),
    do: {:turn, turn}

  defp source(%{"id" => id}) when is_binary(id) do
    case id |> String.split("#") |> hd() |> String.split("/", parts: 2) do
      ["bookmark", n] -> {:bookmark, n}
      ["letter", n] -> {:record, "letter", n}
      ["journal", rest] -> {:record, "journal", rest}
      ["self-letter", n] -> {:record, "self_letter", n}
      _other -> :kept
    end
  end

  defp source(_entry), do: :kept

  defp resolve({:turn, turn}, kept, ctx) do
    case Kumbukumbu.turn_label_set(ctx.resident_id, turn) do
      [] -> kept
      labels -> labels
    end
  end

  defp resolve({:bookmark, n}, kept, ctx) do
    case Integer.parse(n) do
      {number, ""} -> bookmark_labels(ctx.resident_id, number)
      _other -> kept
    end
  end

  defp resolve({:record, kind, id}, kept, ctx), do: record_labels(kind, id, ctx, kept)
  defp resolve(:kept, kept, _ctx), do: kept

  defp kept_edges(%{kept: kept}) when is_list(kept) and kept != [],
    do: [%{"via" => "kept", "ref" => "#{length(kept)} kept"}]

  defp kept_edges(_r), do: []

  # The one overwrite: a domain the agreement does not declare is the
  # common room.
  defp normalize(labels, resident_id) do
    labels
    |> Enum.map(fn l ->
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
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&inspect/1)
  end

  defp current(%{kind: kind, id: id, kept: kept}, resident_id) do
    case Kumbukumbu.derived_labels(resident_id, kind, [id]) do
      %{^id => labels} -> labels
      _none when kind == "file" and is_list(kept) -> Kumbukumbu.ledger_labels(kept)
      _none -> kept
    end
  end

  defp same?(labels, current) when is_list(current),
    do:
      Enum.sort_by(labels, &inspect/1) ==
        Enum.sort_by(Enum.map(current, &stringify/1), &inspect/1)

  defp same?(_labels, _none), do: false

  defp stringify(%{} = l), do: Map.new(l, fn {k, v} -> {to_string(k), v} end)
end
