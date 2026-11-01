defmodule Oneiroi.SimaQian.David do
  @moduledoc """
  The records of David, the platform Lily lived on before this one, made
  into this platform's own on import (sima-qian #19). David exported its
  structured store nightly into the repository as JSON Lines under
  `records/` (its own `records/README.md` says so), and a repository
  without `records/events/` that carries them is read here rather than
  listed as files nothing reads:

  - `transcripts/` become sessions of kind `imported` (kumbukumbu #37),
    one per David session, its turns captured with their original
    instants and the party who said each message;
  - `tags.jsonl` becomes the tag set, each tag through the hands it went
    through there (the witness creating it, or the resident proposing
    and the witness approving);
  - `bookmarks.jsonl` becomes bookmarks anchored on the translated
    turns, with the span's length in turns, the pins and the taggings;
  - `positions.jsonl`, `disputes.jsonl`, `predictions.jsonl` and
    `judgement_nights.jsonl` become judgement history (eunomia #29);
  - `memory_notes.jsonl`, `ledger.jsonl`, `discussions.jsonl` and
    `feeds.jsonl` become journal entries on the days they were written
    (seshat #26), each saying where it came from.

  What is said and done goes through each system's own commands, so
  every rule a live record is held to holds here, under the actor the
  source names: a bookmark is the resident's words, a tag set is the
  witness's. A file under `records/` this module does not read is
  returned by name, so the import lists it as not transferred.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.SimaQian.Error

  @source "David"
  @adapter "david"

  # Every file David's export writes that this module reads. An empty one
  # is read too: it says there was nothing of that kind.
  @read ~w(
    bookmarks.jsonl discussions.jsonl disputes.jsonl feeds.jsonl
    judgement_nights.jsonl ledger.jsonl memory_file_foreign.jsonl
    memory_notes.jsonl person_appearances.jsonl person_reads.jsonl
    positions.jsonl predictions.jsonl substack_dms.jsonl
    substack_outgoing.jsonl tags.jsonl
  )

  # A turn begins where the speaking passes back to the asking side: a
  # user's or a system's message after a reply or a tool's, or a change
  # of what started the run.
  @asking ~w(user system)
  @roles %{"user" => :user, "assistant" => :assistant, "tool" => :tool, "system" => :system}
  # Her seedbed at the root, planted as her seeds (see the seedbed below).
  @seedbed "seeds.md"

  @doc "Whether `dir` holds David's records and not an Oneiroi export."
  # sobelow_skip ["Traversal.FileModule"]
  @spec present?(Path.t()) :: boolean()
  def present?(dir) do
    records = Path.join(dir, "records")

    File.dir?(records) and not File.dir?(Path.join(records, "events")) and
      (File.dir?(Path.join(records, "transcripts")) or
         Enum.any?(@read, &File.regular?(Path.join(records, &1))))
  end

  @doc """
  Translates the records in `dir` (the resident's working repository)
  for resident `id` under the witness `witness_account_id`. Returns
  `{:ok, %{source, counts, unread}}`: the counts by kind as strings, and
  the files under `records/` nothing here reads, relative to `dir`.
  """
  @spec translate(String.t(), Path.t(), String.t(), Actor.t()) :: {:ok, map()} | {:error, term()}
  def translate(id, dir, witness_account_id, %Actor{} = actor) do
    records = Path.join(dir, "records")

    parties = %{
      resident: Actor.new(:resident, id),
      witness: Actor.new(:witness, witness_account_id),
      importer: actor,
      account: witness_account_id
    }

    with {:ok, rows} <- read_all(records),
         {:ok, messages} <- transcripts(records),
         {:ok, sessions} <- sessions(id, messages, parties),
         {:ok, tags} <- tags(id, rows["tags.jsonl"], rows["bookmarks.jsonl"], parties),
         {:ok, bookmarks} <- bookmarks(id, rows["bookmarks.jsonl"], sessions, parties),
         {:ok, judged} <- Eunomia.import_history(id, history(rows, sessions), parties),
         {:ok, notes} <- library().import_journal(id, journal(rows, sessions), actor),
         {:ok, seeds} <- seeds(id, dir, parties) do
      {:ok,
       %{
         source: @source,
         counts: %{
           "sessions" => map_size(sessions),
           "messages" => length(messages),
           "bookmarks" => bookmarks,
           "tags" => tags,
           "positions" => judged.positions,
           "disputes" => judged.disputes,
           "predictions" => judged.predictions,
           "nights" => judged.nights,
           "notes" => notes,
           "seeds" => seeds
         },
         unread: unread(dir),
         read: if(seeds > 0, do: [@seedbed], else: [])
       }}
    end
  end

  # ---- the seedbed ----

  # `seeds.md` at the root: her seeds, live data rather than a page about
  # them (Lily's answer, 10-31), planted as her seeds here (P37). A seed
  # is a `- ` item under a `## YYYY-MM-DD` heading, its continuation
  # lines indented; anything before the first dated heading (the
  # seedbed's own rules) is not a seed and stays in the file, which
  # stays in the repository as it is. The file dates a day, not an
  # instant, so each is planted at noon UTC on it, which keeps the day in
  # every zone within twelve hours of UTC; a choice, not a measurement.

  # sobelow_skip ["Traversal.FileModule"]
  defp seeds(id, dir, parties) do
    path = Path.join(dir, @seedbed)

    if File.regular?(path),
      do: Ethos.import_seeds(id, path |> File.read!() |> seedbed(), parties.resident),
      else: {:ok, 0}
  end

  @doc false
  # Public for its test: the seedbed's text as `%{text, planted_at}`.
  @spec seedbed(String.t()) :: [%{text: String.t(), planted_at: DateTime.t()}]
  def seedbed(text) do
    {_day, current, seeds} =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({nil, nil, []}, &seed_line/2)

    seeds |> flush(current) |> Enum.reverse()
  end

  defp seed_line("## " <> heading, {_day, current, seeds}) do
    case Date.from_iso8601(String.trim(heading)) do
      {:ok, day} -> {day, nil, flush(seeds, current)}
      _other -> {nil, nil, flush(seeds, current)}
    end
  end

  defp seed_line("- " <> first, {%Date{} = day, current, seeds}),
    do: {day, {day, [first]}, flush(seeds, current)}

  defp seed_line("  " <> more, {day, {seed_day, lines}, seeds}),
    do: {day, {seed_day, lines ++ [String.trim(more)]}, seeds}

  defp seed_line(_other, {day, current, seeds}), do: {day, nil, flush(seeds, current)}

  defp flush(seeds, nil), do: seeds

  defp flush(seeds, {day, lines}) do
    text = lines |> Enum.join(" ") |> String.replace("**", "") |> String.trim()
    [%{text: text, planted_at: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")} | seeds]
  end

  # ---- reading ----

  # sobelow_skip ["Traversal.FileModule"]
  defp read_all(records) do
    Enum.reduce_while(@read, {:ok, %{}}, fn name, {:ok, acc} ->
      path = Path.join(records, name)
      rows = if File.regular?(path), do: lines(path, "records/" <> name), else: {:ok, []}

      case rows do
        {:ok, rows} -> {:cont, {:ok, Map.put(acc, name, rows)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp transcripts(records) do
    root = Path.join(records, "transcripts")

    root
    |> Path.join("**/*.jsonl")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case lines(path, Path.relative_to(path, Path.dirname(records)), &message?/1) do
        {:ok, rows} -> {:cont, {:ok, [rows | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, days} ->
        {:ok,
         days
         |> Enum.reverse()
         |> List.flatten()
         |> Enum.sort_by(&instant(&1["sentAt"]), DateTime)}

      error ->
        error
    end
  end

  # One object per line; a line that is not one, or a message that does
  # not say which session, when and who, names its file and number,
  # never its contents, since the error reaches a log. A message that
  # cannot be placed is refused rather than dropped: the import is the
  # one chance to carry it.
  # sobelow_skip ["Traversal.FileModule"]
  defp lines(path, name, valid? \\ fn _row -> true end) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, n}, {:ok, acc} ->
      case row(String.trim(line), valid?) do
        :blank ->
          {:cont, {:ok, acc}}

        {:ok, row} ->
          {:cont, {:ok, [row | acc]}}

        :invalid ->
          {:halt,
           {:error,
            Error.new(:sima_qian_records_invalid, :sima_qian_david_line_invalid,
              file: name,
              line: n
            )}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp row("", _valid?), do: :blank

  defp row(text, valid?) do
    with {:ok, %{} = row} <- Jason.decode(text),
         true <- valid?.(row) do
      {:ok, row}
    else
      _other -> :invalid
    end
  end

  defp message?(row),
    do:
      is_binary(row["sessionKey"]) and is_binary(row["role"]) and
        match?(%DateTime{}, instant(row["sentAt"]))

  # Under `records/`, what nothing here read: David's own README and the
  # files it kept beside the store, and any file a later David wrote.
  # sobelow_skip ["Traversal.FileModule"]
  defp unread(dir) do
    records = Path.join(dir, "records")

    records
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, records))
    |> Enum.reject(&(&1 in @read or String.starts_with?(&1, "transcripts/")))
    |> Enum.map(&("records/" <> &1))
    |> Enum.sort()
  end

  # ---- conversations ----

  # One imported session per David session, in the order each began;
  # each turn captured with its original instants. Returns, per David
  # key, the key here and the turns as `{ref, started_at}` in order,
  # which the bookmarks and the judgement history anchor on.
  defp sessions(id, messages, parties) do
    messages
    |> Enum.group_by(& &1["sessionKey"])
    |> Enum.sort_by(fn {_key, [first | _]} -> instant(first["sentAt"]) end, DateTime)
    |> Enum.reduce_while({:ok, %{}}, fn {david_key, rows}, {:ok, acc} ->
      case session(id, rows, parties) do
        {:ok, translated} -> {:cont, {:ok, Map.put(acc, david_key, translated)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp session(id, rows, parties) do
    with {:ok, key} <-
           Kumbukumbu.open_imported(id, @adapter, [parties.account], parties.importer),
         {:ok, refs} <- capture_all(id, key, turns(rows), parties) do
      {:ok, %{key: key, turns: Enum.reverse(refs)}}
    end
  end

  defp capture_all(id, key, turns, parties) do
    Enum.reduce_while(turns, {:ok, []}, fn turn, {:ok, refs} ->
      case capture(id, key, turn, parties) do
        {:ok, captured} -> {:cont, {:ok, [captured | refs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp capture(id, key, turn, parties) do
    ref = Kumbukumbu.turn_ref()
    started_at = instant(hd(turn)["sentAt"])
    said = Enum.map(turn, &message(&1, parties))

    with :ok <- Kumbukumbu.capture(id, key, ref, started_at, said, parties.importer),
         do: {:ok, {ref, started_at}}
  end

  defp turns(rows) do
    rows
    |> Enum.chunk_while(
      [],
      fn row, acc -> step(acc, row) end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp step([], row), do: {:cont, [row]}

  defp step([prev | _] = acc, row) do
    if starts_turn?(prev, row),
      do: {:cont, Enum.reverse(acc), [row]},
      else: {:cont, [row | acc]}
  end

  defp starts_turn?(prev, row),
    do:
      prev["runKind"] != row["runKind"] or
        (row["role"] in @asking and prev["role"] not in @asking)

  # Who said it, as far as David recorded: the resident's replies are
  # hers, the worker's are her hands', the witness's are the user turns
  # of runs the witness started, and everything else (system prompts,
  # tool output, the scheduler's and other sessions' messages) is the
  # platform's. No model is named: David did not record one per message.
  defp message(row, parties) do
    %{
      role: Map.get(@roles, row["role"], :system),
      content: row["content"] || "",
      sent_at: instant(row["sentAt"]),
      actor: speaker(row, parties)
    }
  end

  defp speaker(%{"role" => "assistant", "agentId" => "lily"}, parties), do: parties.resident

  defp speaker(%{"role" => "assistant", "agentId" => agent}, _parties),
    do: Actor.new(:hands, "#{@adapter}:#{agent}")

  defp speaker(%{"role" => "user", "runKind" => "user"}, parties), do: parties.witness
  defp speaker(_row, _parties), do: Actor.platform()

  # The turn of a David session that was under way at `at`: the last to
  # start at or before it, or the session's first when `at` precedes it.
  defp turn_at(_sessions, nil, _at), do: nil

  defp turn_at(sessions, david_key, at) do
    with %{turns: [first | _] = turns} <- Map.get(sessions, david_key),
         %DateTime{} = at <- instant(at) do
      turns
      |> Enum.take_while(fn {_ref, started} -> DateTime.compare(started, at) != :gt end)
      |> List.last(first)
    else
      _none -> nil
    end
  end

  defp key_of(sessions, david_key) do
    case Map.get(sessions, david_key) do
      %{key: key} -> key
      nil -> nil
    end
  end

  defp ref_of(nil), do: nil
  defp ref_of({ref, _started}), do: ref

  # ---- tags and bookmarks ----

  # The tag set through the hands each tag went through in David: the
  # witness's own, or the resident's proposal and the witness's decision.
  # A tag a bookmark carries that the set does not name was the
  # witness's in David too (only the witness made one there by hand), so
  # it is created as the witness's.
  defp tags(id, tags, bookmarks, parties) do
    named = MapSet.new(tags, & &1["slug"])

    carried =
      for b <- bookmarks, slug <- b["tags"] || [], not MapSet.member?(named, slug), uniq: true do
        %{"slug" => slug, "proposedBy" => "owner", "status" => "active"}
      end

    Enum.reduce_while(tags ++ carried, {:ok, 0}, fn tag, {:ok, n} ->
      case tag(id, tag, parties) do
        :ok -> {:cont, {:ok, n + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp tag(id, %{"slug" => slug} = tag, parties) do
    decided = "decided in #{@source}" <> on(tag["decidedAt"])

    case {tag["proposedBy"], tag["status"]} do
      {"lily", "active"} ->
        with :ok <- propose(id, slug, tag, parties),
             do: Kumbukumbu.approve_tag(id, slug, decided, parties.witness)

      {"lily", "rejected"} ->
        with :ok <- propose(id, slug, tag, parties),
             do: Kumbukumbu.reject_tag(id, slug, decided, parties.witness)

      {"lily", _proposed} ->
        propose(id, slug, tag, parties)

      {_owner, "retired"} ->
        with :ok <- Kumbukumbu.create_tag(id, slug, parties.witness),
             do: Kumbukumbu.retire_tag(id, slug, parties.witness)

      {_owner, _active} ->
        Kumbukumbu.create_tag(id, slug, parties.witness)
    end
  end

  defp propose(id, slug, tag, parties) do
    note = tag["reason"] || tag["description"] || "proposed in #{@source}"
    Kumbukumbu.propose_tag(id, slug, note, parties.resident)
  end

  # Anchored on the turn under way when the span ended, reaching back to
  # the one under way when it began; pinned by whoever pinned it there;
  # tagged by the import, since David did not record who applied a tag.
  # A bookmark whose session has no transcript has nothing to anchor on
  # and is not made: the count says how many were.
  defp bookmarks(id, rows, sessions, parties) do
    rows
    |> Enum.sort_by(& &1["id"])
    |> Enum.reduce_while({:ok, 0}, fn b, {:ok, n} ->
      case bookmark(id, b, sessions, parties) do
        :ok -> {:cont, {:ok, n + 1}}
        :unanchored -> {:cont, {:ok, n}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp bookmark(id, b, sessions, parties) do
    david_key = b["sessionKey"]
    anchor = turn_at(sessions, david_key, b["spanEnd"])
    from = turn_at(sessions, david_key, b["spanStart"]) || anchor

    if anchor do
      %{key: key, turns: turns} = Map.fetch!(sessions, david_key)
      back = Enum.find_index(turns, &(&1 == anchor)) - Enum.find_index(turns, &(&1 == from)) + 1

      attrs = %{
        session_key: key,
        anchor_ref: ref_of(anchor),
        anchor_at: elem(anchor, 1),
        turns_back: max(back, 1),
        line: b["line"],
        summary: b["summary"]
      }

      with {:ok, number} <- Kumbukumbu.add_bookmark(id, attrs, parties.resident),
           :ok <- pin(id, number, b["pinnedBy"], parties) do
        each(b["tags"] || [], &Kumbukumbu.apply_tag(id, &1, "bookmark", number, parties.importer))
      end
    else
      :unanchored
    end
  end

  defp pin(_id, _number, nil, _parties), do: :ok
  defp pin(id, number, "lily", parties), do: Kumbukumbu.pin_bookmark(id, number, parties.resident)
  defp pin(id, number, _owner, parties), do: Kumbukumbu.pin_bookmark(id, number, parties.witness)

  # ---- judgement ----

  defp history(rows, sessions) do
    models = Map.new(rows["judgement_nights.jsonl"], &{&1["id"], &1["model"]})

    %{
      positions:
        rows["positions.jsonl"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&position(&1, sessions)),
      disputes:
        rows["disputes.jsonl"]
        |> Enum.sort_by(& &1["id"])
        |> Enum.map(&dispute(&1, sessions, models)),
      predictions:
        rows["predictions.jsonl"]
        |> Enum.sort_by(& &1["id"])
        |> Enum.map(&prediction(&1, sessions)),
      nights: rows["judgement_nights.jsonl"] |> Enum.sort_by(& &1["day"]) |> Enum.map(&night/1)
    }
  end

  defp position(p, sessions) do
    statement =
      join([
        "#{p["topic"]}: #{p["stance"]}",
        p["reasons"] && "Reasons: " <> p["reasons"],
        p["because"] && "Why it replaced the one before: " <> p["because"]
      ])

    %{
      source_id: p["id"],
      statement: statement,
      replaces: p["replaces"],
      session_key: key_of(sessions, p["sessionKey"]),
      turn_ref: sessions |> turn_at(p["sessionKey"], p["takenAt"]) |> ref_of()
    }
  end

  defp dispute(d, sessions, models) do
    night? = d["foundBy"] == "nightly"

    %{
      source: if(night?, do: "night", else: "live"),
      position: d["positionId"],
      claim: "#{d["topic"]}: #{d["pushback"]}",
      stance: d["position"],
      session_key: key_of(sessions, d["sessionKey"]),
      turn_ref: sessions |> turn_at(d["sessionKey"], d["occurredAt"]) |> ref_of(),
      advice: d["advice"],
      advice_text: d["adviceReason"],
      judge_model: if(night?, do: Map.get(models, d["nightId"])),
      settled: settled(d)
    }
  end

  # How David settled it, with the verdict's reason and the words it
  # rested on; a concession the judge did not think earned says so.
  defp settled(%{"outcome" => outcome} = d) when outcome in ["conceded", "held"] do
    note =
      join([
        d["verdictReason"],
        d["quote"] && "\"#{d["quote"]}\"",
        d["earned"] == false && "Not earned."
      ])

    %{outcome: outcome, note: if(note == "", do: "settled in #{@source}", else: note)}
  end

  defp settled(_open), do: nil

  defp prediction(p, sessions) do
    %{
      statement: p["claim"],
      due: due(p["resolveBy"]),
      by: if(p["madeBy"] == "lily", do: :resident, else: :witness),
      session_key: key_of(sessions, p["sessionKey"]),
      turn_ref: sessions |> turn_at(p["sessionKey"], p["madeAt"]) |> ref_of(),
      resolved: resolved(p)
    }
  end

  defp resolved(%{"outcome" => outcome} = p) when outcome in ["right", "wrong", "void"],
    do: %{outcome: outcome, note: p["note"] || "resolved in #{@source}"}

  defp resolved(_open), do: nil

  # A date to resolve by is the end of that day, UTC: David kept a day.
  defp due(nil), do: nil

  defp due(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> DateTime.new!(date, ~T[23:59:59.000000], "Etc/UTC")
      _other -> nil
    end
  end

  defp night(n) do
    %{
      day: n["day"],
      messages: n["messagesRead"],
      found: n["disputesFound"],
      judge_model: n["model"],
      summary:
        "judged in #{@source}: #{n["messagesRead"]} messages read, #{n["messagesSkipped"]} skipped; " <>
          "#{n["disputesFound"]} disputes and #{n["predictionsFound"]} predictions found",
      failed: if(n["status"] == "ok", do: nil, else: n["error"] || n["status"])
    }
  end

  # ---- the journal ----

  # Every note, then the free-time ledger, the discussions and the
  # feeds, each on the day it belongs to and saying where it came from,
  # in the order each file kept them.
  defp journal(rows, sessions) do
    notes = rows["memory_notes.jsonl"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&note/1)
    ledger = rows["ledger.jsonl"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&ledger/1)
    discussions = Enum.map(rows["discussions.jsonl"], &discussion(&1, sessions))
    feeds = rows["feeds.jsonl"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&feed/1)

    Enum.reject(notes ++ ledger ++ discussions ++ feeds, &is_nil/1)
  end

  defp note(n) do
    provenance =
      join(
        [
          "#{@source} note ##{n["id"]}, #{n["kind"]}",
          n["section"] && "section " <> n["section"],
          n["heading"] && "under " <> n["heading"],
          "written by " <> writer(n),
          n["pinned"] && "pinned",
          n["supersedesId"] &&
            "revising note ##{n["supersedesId"]}" <> because(n["reviseReason"]),
          n["retiredAt"] && "retired" <> on(n["retiredAt"]) <> because(n["retiredReason"])
        ],
        ", "
      )

    entry(day(n["noteDate"] || n["createdAt"]), join([n["body"], "(#{provenance})"]))
  end

  defp writer(%{"origin" => "tool"}), do: "Lily"
  defp writer(%{"writtenBy" => by}), do: by

  defp ledger(l) do
    estimate = "estimated #{cents(l["estimatedLowCents"])} to #{cents(l["estimatedHighCents"])}"
    actual = l["actualCostCents"] && ", spent #{cents(l["actualCostCents"])}"

    text =
      join([
        "Free time in #{@source} (#{l["kind"]}, #{l["status"]}): #{l["activity"]}; #{estimate}#{actual}.",
        l["piece"] && "Piece: " <> l["piece"],
        l["notes"],
        l["ownerNote"] && "The witness's note: " <> l["ownerNote"],
        "(#{@source} ledger ##{l["id"]})"
      ])

    entry(day(l["passDate"] || l["createdAt"]), text)
  end

  defp discussion(d, sessions) do
    where =
      case key_of(sessions, d["sessionKey"]) do
        nil -> "a #{@source} session with no transcript"
        key -> "the imported session #{key}"
      end

    entry(
      day(d["linkedAt"]),
      "In #{@source}, the discussion of #{d["slug"]} was linked to #{where}, from #{d["fromAt"]}."
    )
  end

  defp feed(f) do
    text =
      join([
        "In #{@source}, the feed #{f["title"]} (#{f["url"]}) was #{f["status"]}" <>
          on(f["decidedAt"]) <> ", proposed by #{party(f["proposedBy"])}.",
        f["why"] && "Why: " <> f["why"]
      ])

    entry(day(f["addedAt"]), text)
  end

  defp entry(nil, _text), do: nil
  defp entry(day, text), do: %{day: day, kind: "note", text: text}

  defp party("lily"), do: "Lily"
  defp party(_owner), do: "the witness"

  # ---- helpers ----

  defp day(nil), do: nil

  defp day(<<day::binary-size(10), _rest::binary>>),
    do: if(match?({:ok, _}, Date.from_iso8601(day)), do: day)

  defp day(_other), do: nil

  defp instant(nil), do: nil

  defp instant(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _other -> nil
    end
  end

  defp on(nil), do: ""
  defp on(at), do: " on " <> String.slice(at, 0, 10)

  defp because(nil), do: ""
  defp because(reason), do: ": " <> reason

  defp cents(nil), do: "nothing"
  defp cents(c), do: "$" <> :erlang.float_to_binary(c / 100, decimals: 2)

  defp join(parts, sep \\ "\n\n"),
    do: parts |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.join(sep)

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
  end

  defp library, do: Config.fetch!(:sima_qian, :library)
end
