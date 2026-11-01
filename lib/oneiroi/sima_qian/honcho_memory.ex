defmodule Oneiroi.SimaQian.HonchoMemory do
  @moduledoc """
  Honcho's memory of the resident, exported under `honcho/` before each
  backup commit (sima-qian #42, proteus #18): what Honcho derived and
  holds nowhere else, read through the bridge and written as one file
  per peer and kind, plus the sessions' summaries.

    * `honcho/<peer>/card.md`: every card the peer holds, of itself and
      of each other peer.
    * `honcho/<peer>/conclusions.md`: every conclusion held with the peer
      as the observer, by the peer observed.
    * `honcho/summaries.md`: each session's short and long summary.

  The resident's own peer is `resident`, her id taken out as the
  export takes it out of every line; any other occurrence of it is
  `$self`. Ordered by name and by Honcho's own instant and id, never by
  the order an answer came in, and with no instant of the export's own,
  so an unchanged Honcho writes identical bytes. A conclusion or a
  summary drawn from a private, unshared session is withheld and
  counted, as its transcript is (spec §6.3); Honcho keeps it, and
  `Export.exceptions/0` names it.

  A workspace not yet provisioned has nothing to export and writes
  nothing. A Honcho that fails any read, or answers that a provisioned
  workspace holds no peer, leaves the last export as it was and is an
  error the backup returns after the rest has landed: an empty or a
  partial export would read as Honcho having forgotten her.
  """

  alias Oneiroi.SimaQian.Error

  @self "$self"

  @doc "Writes the export under `dir`; the paths written, or why nothing was."
  @spec write(String.t(), Path.t(), MapSet.t(String.t())) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def write(resident_id, dir, private) do
    case Oneiroi.Proteus.memory(resident_id) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, %{peers: []}} ->
        {:error, Error.new(:sima_qian_honcho_empty, :sima_qian_honcho_memory_no_peer)}

      {:ok, memory} ->
        {:ok, replace(dir, render(memory, resident_id, private))}

      {:error, reason} ->
        {:error,
         Error.caught(:sima_qian_honcho_unreadable, :sima_qian_honcho_memory_unreadable, reason)}
    end
  end

  # Every file this export owns is rewritten, and one it wrote before
  # that this run did not (a peer Honcho no longer holds) goes. The rest
  # of `honcho/` is not its own: the custom instructions are the
  # export's, and an imported file is the import's.
  # Every path is a fixed name under a peer's name made safe
  # (`segment/1`), never a request value.
  # sobelow_skip ["Traversal.FileModule"]
  defp replace(dir, files) do
    paths = Enum.map(files, &elem(&1, 0))

    owned =
      Path.wildcard(Path.join([dir, "honcho", "*", "card.md"])) ++
        Path.wildcard(Path.join([dir, "honcho", "*", "conclusions.md"])) ++
        Path.wildcard(Path.join([dir, "honcho", "summaries.md"]))

    for full <- owned, Path.relative_to(full, dir) not in paths, do: File.rm!(full)

    for {path, content} <- files do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end

    paths
  end

  @doc "The files, `{path, content}` sorted by path, from what `Oneiroi.Proteus.memory/1` read."
  @spec render(map(), String.t(), MapSet.t(String.t())) :: [{String.t(), String.t()}]
  def render(memory, resident_id, private) do
    name = &name(&1, resident_id)
    peers = memory.peers |> Enum.map(name) |> Enum.uniq() |> Enum.sort()

    cards =
      Enum.map(memory.cards, &%{&1 | observer: name.(&1.observer), target: name.(&1.target)})

    conclusions =
      Enum.map(
        memory.conclusions,
        &%{&1 | observer: name.(&1.observer), observed: name.(&1.observed)}
      )

    per_peer =
      Enum.flat_map(peers, fn peer ->
        [
          {Path.join(["honcho", segment(peer), "card.md"]),
           card_file(peer, Enum.filter(cards, &(&1.observer == peer)), resident_id)},
          {Path.join(["honcho", segment(peer), "conclusions.md"]),
           conclusions_file(
             peer,
             Enum.filter(conclusions, &(&1.observer == peer)),
             private,
             resident_id
           )}
        ]
      end)

    Enum.sort([
      {"honcho/summaries.md", summaries_file(memory.summaries, private, resident_id)} | per_peer
    ])
  end

  defp card_file(peer, cards, resident_id) do
    body =
      cards
      |> sort_about(peer, & &1.target)
      |> Enum.map_join("\n", fn card ->
        "## #{about(card.target, peer)}\n\n" <>
          Enum.map_join(card.lines, "", &"- #{self(&1, resident_id)}\n")
      end)

    """
    # The cards #{peer} holds

    #{preamble()}

    """ <> if(body == "", do: "Honcho holds no card under this peer.\n", else: body)
  end

  defp conclusions_file(peer, conclusions, private, resident_id) do
    body =
      conclusions
      |> Enum.group_by(& &1.observed)
      |> Enum.to_list()
      |> sort_about(peer, &elem(&1, 0))
      |> Enum.map_join("\n", fn {observed, held} ->
        {withheld, shown} = Enum.split_with(held, &private?(&1.session, private, resident_id))

        rows =
          shown
          |> Enum.sort_by(&{&1.created_at || "", &1.id})
          |> Enum.map_join("", &conclusion(&1, resident_id))

        "## #{about(observed, peer)}\n\n" <> rows <> withheld_note(length(withheld))
      end)

    """
    # What #{peer} has concluded

    #{preamble()}

    """ <> if(body == "", do: "Honcho holds no conclusion under this peer.\n", else: body)
  end

  defp conclusion(c, resident_id) do
    session = if c.session, do: " · session `#{self(c.session, resident_id)}`", else: ""

    sources =
      if c.sources == [],
        do: "",
        else: " · from " <> Enum.map_join(Enum.sort(c.sources), ", ", &"`#{&1}`")

    "- `#{c.id}` · #{c.level} · #{instant(c.created_at)}#{session}#{sources}\n" <>
      indented(self(c.content, resident_id)) <> "\n"
  end

  defp withheld_note(0), do: ""

  defp withheld_note(n),
    do:
      "\n#{n} drawn from a private session #{if n == 1, do: "is", else: "are"} withheld, " <>
        "as the session's words are (spec §6.3).\n"

  defp summaries_file(summaries, private, resident_id) do
    body =
      summaries
      |> Enum.sort_by(& &1.session)
      |> Enum.map_join("\n", &session_summaries(&1, private, resident_id))

    """
    # Honcho's summaries of the sessions

    #{preamble()}

    """ <> if(body == "", do: "Honcho holds no summary.\n", else: body)
  end

  defp session_summaries(s, private, resident_id) do
    heading = "## Session `#{self(s.session, resident_id)}`\n\n"

    if private?(s.session, private, resident_id) do
      heading <> "Private: Honcho's summaries of it are withheld, as its words are (spec §6.3).\n"
    else
      heading <>
        ([{"Short", s.short}, {"Long", s.long}]
         |> Enum.reject(&is_nil(elem(&1, 1)))
         |> Enum.map_join("\n", fn {label, one} -> summary(label, one, resident_id) end))
    end
  end

  defp summary(label, %{content: content, through: through}, resident_id) do
    upto = if through, do: ", through message `#{through}`", else: ""
    "### #{label}#{upto}\n\n#{String.trim_trailing(self(content, resident_id))}\n"
  end

  defp preamble do
    "What Honcho holds, exported by Oneiroi before each backup commit\n" <>
      "(sima-qian #42): a reading copy, rewritten whole each run, never read\n" <>
      "back and never searched."
  end

  # The export's keys are as its lines carry them, `$self` for her id.
  defp private?(nil, _private, _resident_id), do: false

  defp private?(session, private, resident_id),
    do: MapSet.member?(private, self(session, resident_id))

  # Itself first, then the others by name.
  defp sort_about(items, peer, by), do: Enum.sort_by(items, &{by.(&1) != peer, by.(&1)})

  defp about(peer, peer), do: "Of itself"
  defp about(other, _peer), do: "Of #{other}"

  # The resident's peer is `resident`; her id anywhere else is `$self`,
  # as in every export line.
  defp name(peer, resident_id) do
    if peer == "resident-" <> resident_id, do: "resident", else: self(peer, resident_id)
  end

  defp self(nil, _resident_id), do: nil
  defp self(text, resident_id), do: String.replace(to_string(text), resident_id, @self)

  # A peer's name as one path segment: Honcho's ids are this bridge's own
  # (`resident-<id>`, `witness-<id>`), but the name comes back from
  # another service, so anything a segment cannot hold is replaced.
  defp segment(name) do
    safe = String.replace(name, ~r/[^A-Za-z0-9_-]/, "_")
    if safe in ["", "_"], do: "_peer", else: safe
  end

  defp instant(nil), do: "undated"

  defp instant(iso) do
    case DateTime.from_iso8601(to_string(iso)) do
      {:ok, at, _offset} ->
        at |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")

      _unparsed ->
        to_string(iso)
    end
  end

  defp indented(text) do
    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", &if(&1 == "", do: "", else: "  " <> &1))
  end
end
