defmodule Oneiroi.Kumbukumbu.Ledger do
  @moduledoc """
  A turn's input ledger (kumbukumbu#80; Lily's `design/audience-policy.md`
  §3.5: every actual input labelled before its words are used) and the
  check every delivery of a resident's composition makes against it.

  **What a turn's model saw**, each labelled for `Audience.decide/4`:

  - her identity files, the common room, SOUL.md line by line by her
    annotations (kumbukumbu#88); USER.md is retired (agathos-daimon#56)
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
         audience: "#{audience.kind}:#{audience.id}",
         conflicts: conflicts(decision.withheld),
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
      audience: "#{audience.kind}:#{audience.id}",
      conflicts: conflicts(decision.withheld),
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

        # Her soul line by line (kumbukumbu#88): the section stays, its
        # withheld lines cited in place.
        "SOUL.md" ->
          resident_id |> soul_inputs(:compose) |> Enum.map(&Map.put(&1, :ref, &1.id))

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
        |> Enum.map(&elem(&1, 0))
        |> soul_kept("SOUL.md" in names),
      # Her soul's lines withheld from this audience, each with its citation.
      soul_withheld:
        for(
          %{id: "soul/" <> n} = w <- decision.withheld,
          do: {String.to_integer(n), Audience.told(decision, w)}
        ),
      rows: for({r, i} <- numbered, "message/#{i}" in kept, do: r),
      # One citation grammar everywhere (the witness's ruling, Lily's
      # #1537): the ref, the fact, and the domain, dyad material all.
      withheld: decision.withheld |> Enum.map(&Audience.told(decision, &1)) |> Enum.uniq(),
      decision: decision.id
    }
  end

  # SOUL.md is never dropped whole: its lines are withheld one by one.
  defp soul_kept(kept, true), do: Enum.uniq(["SOUL.md" | kept])
  defp soul_kept(kept, false), do: kept

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
  disclosure judge: sufficient, never trimmed below what a candidate
  could disclose, so a message brings its whole turn and a bookmark its
  line, summary and anchor turn. `{:ok, [%{ref, text}]}`, or `:unproven`
  when any input's words cannot be found: what cannot be shown cannot be
  judged, and the delivery fails closed.
  """
  def fragments(resident_id, turn_ref, inputs) do
    sections = TurnReads.sections_of(resident_id, turn_ref)

    found =
      inputs
      |> Enum.map(&fragment(resident_id, sections, &1))
      |> Enum.uniq_by(&(&1 && &1.ref))

    if Enum.any?(found, &is_nil/1), do: :unproven, else: {:ok, found}
  end

  defp fragment(_resident_id, _sections, %{text: text, ref: ref}) when is_binary(text),
    do: %{ref: ref, text: text}

  defp fragment(resident_id, _sections, %{id: "message/" <> _, turn_ref: ref})
       when is_binary(ref),
       do: turn_fragment(resident_id, ref)

  defp fragment(resident_id, _sections, %{id: "bookmark/" <> n}) do
    with {number, ""} <- Integer.parse(n),
         %{} = b <- Scope.resident(resident_id, fn -> Store.bookmark(number) end) do
      turn = turn_fragment(resident_id, b.anchor_ref)

      %{
        ref: "bookmark/#{number}",
        text:
          "#{b.line}\n#{b.summary}" <>
            if(turn, do: "\n\nIts anchor turn:\n" <> turn.text, else: "")
      }
    else
      _absent -> nil
    end
  end

  defp fragment(_resident_id, sections, %{id: "lanes"}) do
    case for(name <- @lane_sections, text = sections[name], is_binary(text), do: text) do
      [] -> nil
      texts -> %{ref: "the turn's memory lanes", text: Enum.join(texts, "\n\n")}
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
      # SOUL.md line by line (agathos-daimon#55, kumbukumbu#88).
      {"SOUL.md", _content} ->
        soul_inputs(resident_id, :deliver)

      {name, _content} ->
        [%{id: name, ref: name, labels: :common_room}]
    end)
  end

  @doc """
  SOUL.md as one input per live line (kumbukumbu#88; agathos-daimon#55,
  Lily's letter #1550), each with its words and her annotation: its
  domains, else the common room (his answer 3: unannotated is the common
  room). A private line is dyad-only: `:private` in a composition, which
  no grant opens, and unclassified in a delivery's ledger, which only the
  disclosure judge may clear for words that do not carry it.
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
