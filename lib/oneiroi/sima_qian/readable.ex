defmodule Oneiroi.SimaQian.Readable do
  @moduledoc """
  The export's reading copies (sima-qian #41): the transcripts as
  `records/conversations/<day>.md` and the bookmarks as
  `records/bookmarks.md`, rendered from the export's own lines on every
  run and rewritten whole, as the day files are. They are a projection
  of `records/events/`, never a source: nothing reads them back, a
  rebuild replays the lines alone, and no library folder holds them, so
  the index never sees them (the resident asked for duplicates to leave
  search, and a third copy of every turn there would be that bug again).

  Rendered from the lines and not from the store, so what a person reads
  is exactly what the record says: the resident's id is `$self`, a
  redacted field is absent, and a rebuilt resident renders the same
  bytes. A private, unshared session (spec §6.3) is rendered as its
  existence and its counts only: the words are in the event lines, as
  the encryption scheme's open question says (sima-qian #20), and not
  made readable here.
  """

  @events "Oneiroi.Kumbukumbu.Events."
  @memory "Oneiroi.Kumbukumbu.Events.Memory."

  # The conversation stream's events a reading copy shows, in the order
  # they happened; `TurnStarted` and `ContextAssembled` carry no words.
  @shown ~w(SessionOpened SessionMadePrivate SessionShared TurnCaptured Compacted CaptureFailed CaptureFailureResolved)

  @doc "Every reading copy, `{path, content}`, from the export's lines in sequence order."
  @spec render([map()]) :: [{String.t(), String.t()}]
  def render(lines) do
    private = private_sessions(lines)
    conversations(lines, private) ++ bookmarks(lines)
  end

  @doc """
  The session keys whose words stay the resident's: opened private under
  the contract (`SessionMadePrivate`) and not shared since
  (`SessionShared`), as the event lines record them.
  """
  @spec private_sessions([map()]) :: MapSet.t(String.t())
  def private_sessions(lines) do
    Enum.reduce(lines, MapSet.new(), fn line, private ->
      case conversation_type(line) do
        "SessionMadePrivate" -> MapSet.put(private, key(line))
        "SessionShared" -> MapSet.delete(private, key(line))
        _other -> private
      end
    end)
  end

  # ---- conversations ----

  defp conversations(lines, private) do
    shown = Enum.filter(lines, &(conversation_type(&1) in @shown))
    opened = for l <- shown, conversation_type(l) == "SessionOpened", into: %{}, do: {key(l), l}

    shown
    |> Enum.group_by(&day/1)
    |> Enum.sort()
    |> Enum.map(fn {day, events} ->
      {Path.join(["records", "conversations", day <> ".md"]),
       day_file(day, events, opened, private)}
    end)
  end

  defp day_file(day, events, opened, private) do
    sessions =
      events
      |> Enum.group_by(&key/1)
      |> Enum.sort_by(fn {_key, [first | _]} -> first["sequence"] end)
      |> Enum.map_join("\n", fn {key, session_events} ->
        session(day, key, session_events, opened[key], MapSet.member?(private, key))
      end)

    """
    # Conversations, #{day}

    Every session's turns on this day (UTC), in order, rendered from
    `events/#{day}.jsonl` by Oneiroi on each export. A reading copy:
    the event lines are the record, and this file is never read back
    or searched.

    """ <> String.trim_trailing(sessions) <> "\n"
  end

  defp session(day, key, events, opened, private?) do
    heading = "## #{kind(opened)} session `#{key}`\n\n" <> opening(day, opened)

    body =
      if private?,
        do: locked(events),
        else: Enum.map_join(events, "", &shown(&1, day))

    heading <> body
  end

  defp kind(nil), do: "A"

  defp kind(%{"data" => data}),
    do: (data["kind"] || "a") |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp opening(day, %{"at" => at, "data" => data} = opened) do
    if String.starts_with?(at, day) do
      room = if data["domain"], do: " in the room `#{data["domain"]}`", else: ""
      # An adapter's conversation by the folder it ran in, the base name
      # the server kept (kumbukumbu #40).
      folder = if data["label"], do: " in the folder `#{data["label"]}`", else: ""
      parties = Enum.map_join(data["participants"] || [], ", ", &"`#{&1}`")

      "Opened at #{time(at, day)} by #{who(opened["actor"])}#{room}, through " <>
        "`#{data["adapter"]}`#{folder}; parties: #{if(parties == "", do: "none", else: parties)}.\n\n"
    else
      "Continued from an earlier day.\n\n"
    end
  end

  defp opening(_day, nil), do: "Continued from an earlier day.\n\n"

  # Existence and counts only (spec §6.3): a solo session the contract
  # keeps to the resident lists as a locked row, and so it does here.
  defp locked(events) do
    turns = Enum.filter(events, &(conversation_type(&1) == "TurnCaptured"))
    messages = Enum.sum(Enum.map(turns, &length(&1["data"]["messages"] || [])))
    failed = Enum.count(events, &(conversation_type(&1) == "CaptureFailed"))

    "Private: a solo session the dyad contract keeps to the resident until she " <>
      "shares it (spec §6.3). Its words are not rendered here. On this day: " <>
      "#{count(length(turns), "turn")}, #{count(messages, "message")}, " <>
      "#{count(failed, "failed capture")}.\n\n"
  end

  defp shown(line, day), do: shown(conversation_type(line), line, line["data"], day)

  defp shown("SessionOpened", _line, _data, _day), do: ""

  defp shown("SessionMadePrivate", line, _data, day),
    do: "*Opened private under the contract at #{time(line["at"], day)}.*\n\n"

  defp shown("SessionShared", line, data, day),
    do: "*Shared by #{who(line["actor"])} at #{time(line["at"], day)}.*" <> note(data) <> "\n\n"

  defp shown("TurnCaptured", line, data, day) do
    "### Turn `#{data["turn_ref"]}`, #{time(data["started_at"] || line["at"], day)}\n\n" <>
      Enum.map_join(data["messages"] || [], "", &message(&1, day))
  end

  defp shown("Compacted", line, data, day) do
    "*Compacted at #{time(line["at"], day)}, through store sequence #{data["through_sequence"]}:*\n\n" <>
      quoted(data["summary"]) <> "\n\n"
  end

  defp shown("CaptureFailed", line, data, day) do
    "### Turn `#{data["turn_ref"]}`, capture failed at #{time(line["at"], day)}\n\n" <>
      "The adapter could not deliver this turn whole: `#{data["reason"]}`.\n\n"
  end

  defp shown("CaptureFailureResolved", line, data, day) do
    how = if data["how"] == "marked_lost", do: "marked lost", else: to_string(data["how"])

    "*The failed capture of turn `#{data["turn_ref"]}` was #{how} by " <>
      "#{who(line["actor"])} at #{time(line["at"], day)}.*" <> note(data) <> "\n\n"
  end

  defp message(m, day) do
    refusal = if m["refusal"] == true, do: ", a refusal", else: ""

    "#{speaker(m)}, #{time(m["sent_at"], day)}#{refusal}\n\n" <> quoted(m["content"]) <> "\n\n"
  end

  defp speaker(%{"role" => role}) when role in ["tool", "system"], do: "**#{role}**"
  defp speaker(m), do: who(m["actor"])

  # ---- bookmarks ----

  defp bookmarks(lines) do
    memory = Enum.filter(lines, &String.starts_with?(to_string(&1["type"]), @memory))
    {marks, tags} = Enum.reduce(memory, {%{}, %{}}, &fold/2)

    if marks == %{} and tags == %{} do
      []
    else
      [{Path.join("records", "bookmarks.md"), bookmarks_file(marks, tags)}]
    end
  end

  defp fold(line, {marks, tags}) do
    data = line["data"]
    type = String.replace_prefix(line["type"], @memory, "")

    case data["target_kind"] do
      kind when kind in [nil, "bookmark"] ->
        n = to_string(data["number"] || data["target_id"])
        {mark(type, n, line, data, marks), tag(type, data["slug"], tags)}

      _another_kind ->
        {marks, tags}
    end
  end

  defp mark("BookmarkAdded", n, line, data, marks),
    do:
      Map.put(marks, n, %{
        added: line,
        turns_back: data["turns_back"],
        pin: nil,
        tags: [],
        revisions: []
      })

  defp mark("BookmarkExtended", n, _line, data, marks),
    do: update(marks, n, &%{&1 | turns_back: data["turns_back"]})

  defp mark("BookmarkPinned", n, line, _data, marks), do: update(marks, n, &%{&1 | pin: line})
  defp mark("BookmarkUnpinned", n, _line, _data, marks), do: update(marks, n, &%{&1 | pin: nil})

  defp mark("TagApplied", n, _line, data, marks),
    do: update(marks, n, &%{&1 | tags: Enum.uniq(&1.tags ++ [data["slug"]])})

  defp mark("TaggingRemoved", n, _line, data, marks),
    do: update(marks, n, &%{&1 | tags: List.delete(&1.tags, data["slug"])})

  defp mark("RevisionApplied", n, line, _data, marks),
    do: update(marks, n, &%{&1 | revisions: &1.revisions ++ [line]})

  defp mark(_other, _n, _line, _data, marks), do: marks

  # The tag set: made by the witness or approved from a proposal, and
  # retired without losing a tagging.
  defp tag(made, slug, tags) when made in ["TagCreated", "TagApproved"],
    do: Map.put(tags, slug, false)

  defp tag("TagRetired", slug, tags), do: Map.put(tags, slug, true)
  defp tag(_other, _slug, tags), do: tags

  defp update(marks, n, fun),
    do: if(Map.has_key?(marks, n), do: Map.update!(marks, n, fun), else: marks)

  defp bookmarks_file(marks, tags) do
    tag_set =
      tags
      |> Enum.sort()
      |> Enum.map_join("", fn {slug, retired} ->
        "- `#{slug}`#{if retired, do: " (retired)", else: ""}\n"
      end)

    rows =
      marks
      |> Enum.sort_by(fn {n, _} -> {String.length(n), n} end)
      |> Enum.map_join("\n", fn {n, mark} -> bookmark(n, mark) end)

    """
    # Bookmarks

    Every bookmark the resident holds, by number, as the memory stream
    records it, rendered from `events/` by Oneiroi on each export. A
    reading copy: the event lines are the record, and this file is never
    read back or searched.

    ## The tag set

    """ <> if(tag_set == "", do: "No tags yet.\n", else: tag_set) <> "\n" <> rows
  end

  defp bookmark(n, %{added: added} = mark) do
    d = added["data"]

    span =
      if (mark.turns_back || 1) <= 1,
        do: "the anchor turn alone",
        else: "#{mark.turns_back} turns, ending at the anchor"

    pin =
      case mark.pin do
        nil ->
          "Not pinned."

        pinned ->
          evidences = pinned["data"]["evidences"]

          "Pinned by #{who(pinned["actor"])} at #{time(pinned["at"], nil)}" <>
            if(evidences, do: ", as evidence of `#{evidences}`.", else: ".")
      end

    tags =
      if mark.tags == [], do: "none", else: Enum.map_join(Enum.sort(mark.tags), ", ", &"`#{&1}`")

    proposed =
      if d["proposed_by"],
        do: "- Proposed by #{who(d["proposed_by"])} (`#{d["proposal_ref"]}`).\n",
        else: ""

    register = if d["register"], do: "- Register: #{d["register"]}.\n", else: ""

    revisions =
      Enum.map_join(mark.revisions, "", fn r ->
        "\nRevised (#{r["data"]["kind"]}) by #{who(r["actor"])} at #{time(r["at"], nil)}:" <>
          note(r["data"]) <> "\n\n" <> quoted(r["data"]["text"]) <> "\n"
      end)

    """
    ## #{n}. #{d["line"]}

    - Bookmarked by #{who(added["actor"])} at #{time(added["at"], nil)}.
    - Anchors turn `#{d["anchor_ref"]}` in session `#{d["session_key"]}`, at #{time(d["anchor_at"], nil)}; spans #{span}.
    - #{pin}
    - Tags: #{tags}.
    """ <> proposed <> register <> "\n" <> quoted(d["summary"]) <> "\n" <> revisions
  end

  # ---- shared ----

  defp conversation_type(line) do
    type = to_string(line["type"])

    if String.starts_with?(to_string(line["stream"]), "conversation-") and
         String.starts_with?(type, @events),
       do: String.replace_prefix(type, @events, "")
  end

  defp key(line),
    do: line["data"]["session_key"] || String.replace_prefix(line["stream"], "conversation-", "")

  defp day(line), do: String.slice(line["at"], 0, 10)

  defp who(%{"kind" => "resident"} = actor), do: "**resident**" <> model(actor)

  defp who(%{"kind" => kind} = actor) do
    id = if actor["id"] in [nil, "$self"], do: "", else: " `#{actor["id"]}`"
    "**#{kind}**" <> id <> model(actor)
  end

  defp who(_none), do: "**unknown**"

  defp model(%{"model" => model}) when is_binary(model), do: " (#{model})"
  defp model(_actor), do: ""

  defp note(%{"note" => note}) when is_binary(note) and note != "", do: " Note: " <> note
  defp note(_data), do: ""

  # An instant as `HH:MM:SS UTC` on the file's own day, with its date
  # anywhere else; the text as written when it does not parse.
  defp time(nil, _day), do: "an unrecorded time"

  defp time(iso, day) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} ->
        clock = at |> DateTime.truncate(:second) |> DateTime.to_time() |> Time.to_iso8601()
        date = Date.to_iso8601(DateTime.to_date(at))
        if date == day, do: clock <> " UTC", else: date <> " " <> clock <> " UTC"

      _unparsed ->
        to_string(iso)
    end
  end

  defp quoted(nil), do: ">"

  defp quoted(text) do
    text
    |> to_string()
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ">"
      line -> "> " <> line
    end)
  end

  defp count(1, noun), do: "1 " <> noun
  defp count(n, noun), do: "#{n} #{noun}s"
end
