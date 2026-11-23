defmodule Oneiroi.Kumbukumbu.Ledger do
  @moduledoc """
  A turn's input ledger (kumbukumbu#80; Lily's `design/audience-policy.md`
  §3.5: every actual input labelled before its words are used) and the
  check every delivery of a resident's composition makes against it.

  **What a turn's model saw**, each labelled for `Audience.decide/4`:

  - her identity files, the common room, SOUL.md among them, never a
    taint, its annotations guidance (kumbukumbu#91); USER.md is retired (agathos-daimon#56)
    and in no ledger;
  - the window's last messages, each its domain, or the common room
    when it has none (the witness's answer 3: the default classification
    is the common room);
  - the lanes filtered to the conversation's current domain (pins, the
    index, the madeleine, the character exemplars): that domain;
  - the timeline's bookmarks, every domain they hold (that lane is not
    filtered);
  - what the turn read deliberately (`TurnReads`).

  A generated answer inherits all of it (§3.5), so a delivery checks the
  union: in `:hard` mode, against the audience it would reach.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu.Audience
  alias Oneiroi.Kumbukumbu.Disclosure
  alias Oneiroi.Kumbukumbu.Domains
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Kumbukumbu.TurnReads
  alias Oneiroi.Scope

  @window 40

  @doc "A turn's inputs, labelled."
  def inputs(resident_id, session_key, turn_ref, window \\ @window) do
    seen =
      case TurnReads.assembled_of(resident_id, turn_ref) do
        # Assembled for an audience (kumbukumbu#81): what was put in,
        # and nothing that was withheld from it.
        inputs when is_list(inputs) -> inputs
        nil -> window_inputs(resident_id, session_key, window)
      end

    seen ++ TurnReads.of(resident_id, turn_ref)
  end

  defp window_inputs(resident_id, session_key, window),
    do:
      identity(resident_id) ++
        messages(resident_id, session_key, window) ++
        lanes(resident_id, session_key) ++ timeline(resident_id)

  @doc "The window's messages, labelled by their domains, one input per stored row (kumbukumbu#81)."
  def message_inputs(resident_id, session_key, window \\ @window),
    do: messages(resident_id, session_key, window)

  @doc """
  A turn's ledger as a derived artifact keeps it (kumbukumbu#83): each
  input's id, ref, turn and labels as plain data, never its words, for
  an event line and a projection row.
  """
  def encode(inputs),
    do:
      for(
        i <- inputs,
        do: %{
          "id" => i.id,
          "ref" => Map.get(i, :ref),
          "turn_ref" => Map.get(i, :turn_ref),
          "labels" => encode_labels(i.labels)
        }
      )

  @doc """
  The labels a derived artifact keeps (kumbukumbu#84): the distinct
  labels of every input its turn held, each a map, `%{"person",
  "domain"}` or `%{"kind" => "common_room" | "unclassified"}`, never
  the words.
  """
  def label_set(inputs) do
    inputs
    |> Enum.flat_map(fn
      %{labels: list} when is_list(list) and list != [] -> encode_labels(list)
      %{labels: :common_room} -> [%{"kind" => "common_room"}]
      _unclassified -> [%{"kind" => "unclassified"}]
    end)
    |> Enum.uniq()
  end

  @doc """
  What reading a derived artifact adds to the reading turn's ledger
  (kumbukumbu#84): one input per label it keeps, each carrying its words
  for a disclosure judge. Kept no labels (written before they were
  kept): unclassified, never inferred (Lily's letter #1524, (a)).
  """
  def read_inputs(id, ref, labels, text) do
    labels = if is_list(labels) and labels != [], do: labels, else: [%{"kind" => "unclassified"}]

    for label <- labels,
        do: %{
          id: "#{id}##{label_key(label)}",
          ref: ref,
          text: text,
          labels: read_label(label)
        }
  end

  defp read_label(label) do
    case {kind(label), get_any(label, "domain")} do
      {"common_room", _} -> :common_room
      {_, domain} when is_binary(domain) -> [pair(label)]
      _unclassified -> :unclassified
    end
  end

  defp kind(%{} = l), do: get_any(l, "kind")
  defp kind(other), do: to_string(other)

  defp get_any(%{} = l, key), do: Map.get(l, key) || Map.get(l, String.to_existing_atom(key))
  defp get_any(_other, _key), do: nil

  defp label_key(label) do
    case kind(label) do
      nil -> "#{get_any(label, "person")}/#{get_any(label, "domain")}"
      k -> k
    end
  end

  @doc "A kept ledger read back: `encode/1`'s inverse, string keys or atom keys alike."
  def decode(rows) when is_list(rows),
    do:
      for(
        r <- rows,
        do: %{
          id: get(r, "id"),
          ref: get(r, "ref"),
          turn_ref: get(r, "turn_ref"),
          labels: decode_labels(get(r, "labels"))
        }
      )

  defp get(row, key), do: Map.get(row, key) || Map.get(row, String.to_existing_atom(key))

  defp encode_labels(labels) when is_list(labels),
    do: for(l <- labels, do: %{"person" => l.person, "domain" => l.domain})

  defp encode_labels(labels) when labels in [:common_room, :unclassified],
    do: Atom.to_string(labels)

  # Anything not readable as a label is unclassified: never inferred.
  defp decode_labels("common_room"), do: :common_room
  defp decode_labels(labels) when is_list(labels) and labels != [], do: Enum.map(labels, &pair/1)
  defp decode_labels(_unreadable), do: :unclassified

  defp pair(l), do: %{person: get(l, "person"), domain: get(l, "domain")}

  @doc """
  Whether a file's words may be delivered to `audience` (kumbukumbu#85;
  the witness's ruling 2, Lily's letters #1528 and #1530): by the
  document's domain alone, a mechanical check, no judge. Its domain is
  its author's classification when she made one (`file.classified`,
  seshat#102), else its birth, the union of every label its writing
  turn held (the conversation's domain among them, `file.ledger`), else
  unclassified, which refuses. `turn` is the delivering turn; the
  refusal names the domains in conflict, the source and the decision.
  """
  def check_file(resident_id, _turn, audience, file) do
    labels = file_labels(file)
    inputs = read_inputs("file/" <> file.source, file.source, labels, nil)
    decision = Audience.decide_for(resident_id, inputs, audience, :hard)

    if decision.withheld == [] do
      {:ok, decision}
    else
      {:error,
       Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_ledger_file_withheld,
         decision: decision.id,
         audience: audience_words(decision.audience),
         conflicts: conflicts(decision.withheld),
         grants: grants(decision),
         unruled: unruled(decision.withheld),
         source: file.source,
         classified: file[:classified] != nil
       )}
    end
  end

  # Explicit classification > birth union > unclassified.
  defp file_labels(%{classified: %{domain: nil}}), do: [%{"kind" => "common_room"}]

  defp file_labels(%{classified: %{person: person, domain: domain}}),
    do: [%{"person" => person, "domain" => domain}]

  defp file_labels(%{ledger: ledger}) when is_list(ledger), do: ledger |> decode() |> label_set()
  defp file_labels(_none), do: [%{"kind" => "unclassified"}]

  @doc "A turn's messages' labels as kept labels (kumbukumbu#89), [] when the turn is not held."
  def turn_label_set(resident_id, turn_ref) when is_binary(turn_ref) do
    case Scope.resident(resident_id, fn -> Store.turn_messages(turn_ref) end) do
      [] ->
        []

      messages ->
        messages
        |> Enum.map(&%{labels: label(Domains.pair(&1.domain_person, &1.domain))})
        |> label_set()
    end
  end

  @doc """
  Kept labels as a kept ledger, one entry each (kumbukumbu#89): what
  `withheld_domains/3` decides a fragment's labels with.
  """
  def labels_ledger(labels) do
    for l <- labels,
        do: %{
          "id" => "label",
          "labels" =>
            case Map.get(l, "kind") do
              nil -> [l]
              kind -> kind
            end
        }
  end

  @doc "The domains of a kept ledger in conflict with `audience` (kumbukumbu#87); [] when it all may reach it."
  def withheld_domains(resident_id, ledger, audience) do
    decision = Audience.decide_for(resident_id, decode(ledger), audience, :hard)
    conflicts(decision.withheld)
  end

  @doc "The timeline lane's labels (kumbukumbu#81): every domain its anchors hold, or the common room."
  def timeline_labels(resident_id) do
    resident_id
    |> timeline()
    |> Enum.flat_map(fn %{labels: l} -> if is_list(l), do: l, else: [] end)
    |> Enum.uniq()
    |> case do
      [] -> :common_room
      labels -> labels
    end
  end

  @doc "The labels of the turn's memory lanes: the session's current domain, or the common room."
  def lane_labels(resident_id, session_key), do: label(Domains.current(resident_id, session_key))

  @doc """
  Whether a turn's composition may be delivered to `audience`: `{:ok,
  decision}`, or the refusal, which names (to her, in her own context)
  the domains in conflict and the decision id, and is all the audience
  ever learns: nothing is delivered.
  """
  def check(resident_id, session_key, turn_ref, audience, candidate \\ nil) do
    inputs = inputs(resident_id, session_key, turn_ref)
    decision = Audience.decide_for(resident_id, inputs, audience, :hard)

    refused = [
      decision: decision.id,
      audience: audience_words(decision.audience),
      conflicts: conflicts(decision.withheld),
      grants: grants(decision),
      unruled: unruled(decision.withheld)
    ]

    cond do
      decision.withheld == [] ->
        {:ok, decision}

      # Review owed (kumbukumbu#82): the judge says whether the words
      # themselves disclose what was held back.
      is_binary(candidate) and String.trim(candidate) != "" ->
        turn = %{resident_id: resident_id, session_key: session_key, turn_ref: turn_ref}
        # The words behind what was held back, found here and handed in.
        shown = fn held -> fragments(resident_id, turn_ref, held) end
        Disclosure.review(turn, audience, candidate, decision, inputs, refused, shown)

      true ->
        {:error,
         Error.new(:kumbukumbu_withheld_by_policy, :kumbukumbu_ledger_delivery_withheld, refused)}
    end
  end

  # Sections that carry the session's current domain: what was recalled
  # into this room. Those of unsure provenance are unclassified; the rest
  # (her prompt, her own files, her state, her plans) are the
  # common room.
  @lane_sections ~w(pins index madeleine character where domain)
  @unclassified_sections ~w(summary self-conversation)

  @doc """
  Assembles a turn for an audience past the dyad (kumbukumbu#81, the soft
  path): each of the turn's sections (by name) and each of its window's
  messages labelled, decided `:soft` against `audience`, and what may
  reach it recorded as the turn's ledger, so its delivery is checked
  against what she was given and not against what was held back. Returns
  the section names and window rows kept, and the citations of what was
  withheld, in her words: they name the domains, to her alone.
  """
  def assemble(resident_id, session_key, turn_ref, audience, names, rows) do
    lane = lane_labels(resident_id, session_key)
    timeline = timeline_labels(resident_id)

    sections =
      Enum.flat_map(Enum.uniq(names), fn
        # A section with labels of its own (kumbukumbu#84), one input each.
        {name, labels, text} ->
          read_inputs("section/" <> name, name, labels, text)

        name ->
          [%{id: "section/" <> name, ref: name, labels: section_label(name, lane, timeline)}]
      end)

    numbered = Enum.with_index(rows)

    messages =
      for {r, i} <- numbered,
          do: %{
            id: "message/#{i}",
            ref: "transcript/#{session_key}/#{Map.get(r, :sequence)}",
            turn_ref: Map.get(r, :turn_ref),
            labels: label(Domains.pair(Map.get(r, :domain_person), Map.get(r, :domain)))
          }

    decision = Audience.decide_for(resident_id, sections ++ messages, audience, :soft)
    kept = MapSet.new(decision.allowed)

    TurnReads.assembled(
      resident_id,
      turn_ref,
      Enum.filter(sections ++ messages, &(&1.id in kept))
    )

    %{
      # A section is kept when every input it was decided by is.
      sections:
        sections
        |> Enum.group_by(& &1.ref)
        |> Enum.filter(fn {_ref, ins} -> Enum.all?(ins, &(&1.id in kept)) end)
        |> Enum.map(&elem(&1, 0)),
      # Her soul is never withheld and never taints (kumbukumbu#91, the
      # witness's ruling): the lines her annotations keep from this
      # audience are named to her as guidance, each with why.
      soul_guidance: if("SOUL.md" in names, do: soul_guidance(resident_id, audience), else: []),
      rows: for({r, i} <- numbered, "message/#{i}" in kept, do: r),
      # One citation grammar everywhere (the witness's ruling, Lily's
      # #1537): the ref, the fact, and the domain, dyad material all.
      withheld: decision.withheld |> Enum.map(&Audience.told(decision, &1)) |> Enum.uniq(),
      decision: decision.id
    }
  end

  @doc """
  The review she asks for of her own words against her soul (kumbukumbu
  #91): the annotated lines `audience` may not hear, shown to the judge
  with `text`. `{:ok, :nothing}` when none is kept from it, else the
  verdict.
  """
  def review_soul(resident_id, session_key, turn_ref, audience, text) do
    inputs = for i <- soul_inputs(resident_id, :compose), i.labels != :common_room, do: i
    decision = Audience.decide_for(resident_id, inputs, audience, :soft)
    held = MapSet.new(decision.withheld, & &1.id)

    case for(i <- inputs, i.id in held, do: %{ref: i.ref, text: i.text}) do
      [] ->
        {:ok, :nothing}

      fragments ->
        turn = %{resident_id: resident_id, session_key: session_key, turn_ref: turn_ref}
        Disclosure.advise(turn, audience, text, decision, fragments)
    end
  end

  # The annotated lines this audience may not hear, decided as guidance
  # only: never a withhold, never a ledger input.
  defp soul_guidance(resident_id, audience) do
    inputs = for i <- soul_inputs(resident_id, :compose), i.labels != :common_room, do: i
    decision = Audience.decide_for(resident_id, inputs, audience, :soft)
    for w <- decision.withheld, do: Audience.told(decision, w)
  end

  defp section_label(name, _lane, _timeline) when name in @unclassified_sections,
    do: :unclassified

  defp section_label(name, lane, _timeline) when name in @lane_sections, do: lane
  defp section_label("timeline", _lane, timeline), do: timeline
  defp section_label(_name, _lane, _timeline), do: :common_room

  # The sections whose words a judge may need: every one not the common
  # room's.
  @doc false
  def restricted_sections,
    do: @lane_sections ++ @unclassified_sections ++ ["timeline"]

  @doc """
  The words behind each held-back input (kumbukumbu#82), for the
  disclosure judge: what tripped the review, never the discussion around
  it (kumbukumbu#105): a message is itself, a bookmark its line and
  summary, the lanes only the bookmarks in them of the held domain. `{:ok, [%{ref, text}]}`, or `:unproven`
  when any input's words cannot be found: what cannot be shown cannot be
  judged, and the delivery fails closed.
  """
  def fragments(resident_id, turn_ref, inputs) do
    sections = TurnReads.sections_of(resident_id, turn_ref)

    found =
      inputs
      |> Enum.map(&fragment(resident_id, sections, &1))
      |> Enum.uniq_by(&(&1 && &1.ref))
      # A piece with nothing of the held domain in it is no piece.
      |> Enum.reject(&(is_map(&1) and String.trim(&1.text) == ""))

    if Enum.any?(found, &is_nil/1), do: :unproven, else: {:ok, found}
  end

  defp fragment(_resident_id, _sections, %{text: text, ref: ref}) when is_binary(text),
    do: %{ref: ref, text: text}

  # A held message is itself, never its whole turn (kumbukumbu#105, the
  # witness, 2026-11-23: the judge sees what tripped the review, not the
  # discussion around it). Its turn stands in only where the message
  # cannot be singled out.
  defp fragment(resident_id, _sections, %{id: "message/" <> _ = id, turn_ref: ref} = input)
       when is_binary(ref),
       do: message_fragment(resident_id, id, ref, input) || turn_fragment(resident_id, ref)

  # A held bookmark is its line and summary, never its anchor turn
  # (kumbukumbu#105).
  defp fragment(resident_id, _sections, %{id: "bookmark/" <> n}) do
    with {number, ""} <- Integer.parse(n),
         %{} = b <- Scope.resident(resident_id, fn -> Store.bookmark(number) end) do
      %{ref: "bookmark/#{number}", text: "#{b.line}\n#{b.summary}"}
    else
      _absent -> nil
    end
  end

  # The lanes are shown only for what in them is some domain's
  # (kumbukumbu#105): of the bookmark index and the pins, the bookmarks
  # in a domain, never the common room's; the other lanes whole.
  defp fragment(resident_id, sections, %{id: "lanes"} = input) do
    case for(name <- @lane_sections, text = sections[name], is_binary(text), do: {name, text}) do
      [] ->
        nil

      texts ->
        held = held_pairs(Map.get(input, :labels))

        %{
          ref: "the turn's memory lanes",
          text:
            texts
            |> Enum.map(&lane_text(resident_id, &1, held))
            |> Enum.reject(&(String.trim(&1) == ""))
            |> Enum.join("\n\n")
        }
    end
  end

  defp fragment(resident_id, sections, %{id: "section/" <> name}),
    do: section_fragment(resident_id, sections, name)

  defp fragment(resident_id, sections, %{id: name}) when is_binary(name),
    do: section_fragment(resident_id, sections, name)

  defp section_fragment(resident_id, sections, name) do
    case sections[name] || identity_text(resident_id, name) do
      text when is_binary(text) -> %{ref: name, text: text}
      nil -> nil
    end
  end

  defp identity_text(resident_id, name) do
    Enum.find_value(AgathosDaimon.identity_context(resident_id), fn
      {^name, content} -> content
      _other -> nil
    end)
  end

  defp held_pairs(labels) when is_list(labels),
    do: for(%{person: _, domain: _} = p <- labels, do: p)

  defp held_pairs(_labels), do: nil

  defp lane_text(resident_id, {name, text}, [_ | _]) when name in ~w(pins index) do
    lines = String.split(text, "\n")

    numbers =
      for line <- lines, [_, n] <- [Regex.run(~r/^#(\d+)\s/, line)], do: String.to_integer(n)

    domains =
      Scope.resident(resident_id, fn -> numbers |> Enum.map(&Store.bookmark/1) end)
      |> Enum.reject(&is_nil/1)
      |> then(&Domains.attach(resident_id, &1))
      |> Map.new(&{&1.number, &1.domain_key})

    lines
    |> Enum.filter(fn line ->
      case Regex.run(~r/^#(\d+)\s/, line) do
        # The common room's bookmarks reach every audience the lanes
        # could be held from, so they are no piece; any domain's is
        # shown, and so is one that cannot be found: unknown is not clean.
        [_, n] -> Map.get(domains, String.to_integer(n), :unknown) != nil
        nil -> false
      end
    end)
    |> Enum.join("\n")
  end

  defp lane_text(_resident_id, {_name, text}, _held), do: text

  defp message_fragment(resident_id, id, turn_ref, input) do
    wanted = message_position(id, Map.get(input, :ref))
    messages = Scope.resident(resident_id, fn -> Store.turn_messages(turn_ref) end)

    case wanted && Enum.filter(messages, &wanted.(&1)) do
      [_ | _] = mine ->
        %{ref: id, text: Enum.map_join(mine, "\n", &"#{&1.role}: #{&1.content}")}

      _none ->
        nil
    end
  end

  # `message/<session>/<sequence>/<position>` names one message; an
  # assembled window's `message/<i>` names its sequence in its ref,
  # `transcript/<session>/<sequence>`.
  defp message_position(id, ref) do
    case {String.split(id, "/"), ref && String.split(ref, "/")} do
      {["message", _session, seq, pos], _ref} ->
        with {s, ""} <- Integer.parse(seq),
             {p, ""} <- Integer.parse(pos),
             do: &(&1.sequence == s and &1.position == p),
             else: (_ -> nil)

      {["message", _i], ["transcript", _session, seq]} ->
        case Integer.parse(seq) do
          {s, ""} -> &(&1.sequence == s)
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp turn_fragment(_resident_id, nil), do: nil

  defp turn_fragment(resident_id, turn_ref) do
    case Scope.resident(resident_id, fn -> Store.turn_messages(turn_ref) end) do
      [] ->
        nil

      messages ->
        %{
          ref: "turn/#{turn_ref}",
          text: Enum.map_join(messages, "\n", &"#{&1.role}: #{&1.content}")
        }
    end
  end

  @doc "The labels of inputs a tool read: a bookmark opened, a transcript turn read."
  def bookmark_input(resident_id, %{number: n} = bookmark) do
    [%{domain_key: key}] = Domains.attach(resident_id, [bookmark])
    %{id: "bookmark/#{n}", ref: "bookmark/#{n}", labels: label(key)}
  end

  # ---- the parts ----

  defp identity(resident_id) do
    Enum.flat_map(AgathosDaimon.identity_context(resident_id), fn
      {name, _content} ->
        [%{id: name, ref: name, labels: :common_room}]
    end)
  end

  @doc """
  SOUL.md's annotated lines (agathos-daimon#55), each with its words and
  her annotation: its domains, else the common room; a private line
  `:private`. Guidance only since kumbukumbu#91 (the witness's ruling,
  2026-11-21): SOUL.md enters every ledger as the common room and never
  taints, since a soul cannot be separated from what it composes; the
  annotations tell an audience-composed run which lines are not
  legitimate input for it.
  """
  def soul_inputs(resident_id, mode) do
    for l <- AgathosDaimon.soul_lines(resident_id),
        Map.get(l, :state, "live") == "live",
        do: %{
          id: "soul/#{l.number}",
          ref: "soul/#{l.number}",
          text: l.text,
          labels: soul_label(l, mode)
        }
  end

  defp soul_label(%{private: true}, :compose), do: :private
  defp soul_label(%{private: true}, :deliver), do: :unclassified

  defp soul_label(%{domains: [_ | _] = domains}, _mode),
    do: Enum.map(domains, &pair/1)

  defp soul_label(_line, _mode), do: :common_room

  defp messages(_resident_id, nil, _window), do: []

  defp messages(resident_id, session_key, window) do
    rows = Scope.resident(resident_id, fn -> Store.recent_domains(session_key, window) end)

    for r <- rows,
        do: %{
          id: "message/#{session_key}/#{r.sequence}/#{r.position}",
          ref: "transcript/#{session_key}",
          turn_ref: r.turn_ref,
          labels: label(Domains.pair(r.person, r.domain))
        }
  end

  defp lanes(resident_id, session_key),
    do: [
      %{
        id: "lanes",
        ref: "the turn's memory lanes",
        labels: label(Domains.current(resident_id, session_key))
      }
    ]

  defp timeline(resident_id) do
    marks = Scope.resident(resident_id, fn -> Store.timeline_anchors() end)

    resident_id
    |> Domains.attach(marks)
    |> Enum.map(&%{id: "bookmark/#{&1.number}", ref: "timeline", labels: label(&1.domain_key)})
  end

  defp label(nil), do: :common_room
  defp label(%{person: _, domain: _} = pair), do: [pair]

  # The domains withheld for want of any policy (Lily's #1564): an
  # absence, never to be told as a rule.
  defp unruled(withheld) do
    withheld
    |> Enum.flat_map(fn
      %{reason: :no_policy, conflicts: cs} -> Enum.map(cs, & &1.domain)
      _other -> []
    end)
    |> Enum.uniq()
  end

  # The audience as a grant names it (kumbukumbu#102): its kind and id,
  # and the other names a grant may use for it.
  defp audience_words(%{kind: kind, id: id} = audience) do
    case Map.get(audience, :aliases, []) do
      [] -> "#{kind}:#{id}"
      aliases -> "#{kind}:#{id} (#{Enum.join(aliases, ", ")})"
    end
  end

  # What each conflicting domain's policy grants, said in the refusal
  # (Scarlett's report #25: a refusal should print the grant it failed
  # to match).
  defp grants(decision) do
    names = decision.withheld |> conflicts() |> MapSet.new()

    for p <- decision.snapshot.policies, MapSet.member?(names, p.domain.domain) do
      list = fn gs -> Enum.map_join(gs, ", ", &"#{&1.kind}:#{&1.id}") end
      allow = if p.allow == [], do: "allows none", else: "allows " <> list.(p.allow)
      deny = if p.deny == [], do: "", else: "; denies " <> list.(p.deny)
      "#{p.domain.domain} (default #{p.default}; #{allow}#{deny})"
    end
  end

  defp conflicts([]), do: []

  defp conflicts(withheld) do
    withheld
    |> Enum.flat_map(fn
      %{reason: :unclassified} -> ["unclassified"]
      %{conflicts: cs} -> Enum.map(cs, & &1.domain)
    end)
    |> Enum.uniq()
  end
end
