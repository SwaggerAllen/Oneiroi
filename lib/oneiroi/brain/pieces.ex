defmodule Oneiroi.Brain.Pieces do
  @moduledoc """
  A section's pieces (kumbukumbu#111; the witness, 2026-11-25: "we need
  to make the domains carried by sections more granular, that means that
  each journal row gets its own domains"): each line of a section that
  stands for one record, its exact words and that record's labels, so a
  delivery is held only by a piece in a conflicting domain, and a judge
  is shown that piece alone.

  A piece is `%{ref, labels, text}`, its text an exact span of the
  section's words. Labels are read as they stand, a domain the agreement
  does not declare read as the common room: an undeclared domain has no
  rule to hold anything by.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu

  @common %{"kind" => "common_room"}
  @unclassified %{"kind" => "unclassified"}

  @doc "Records' labels as a piece carries them: undeclared domains the common room; none kept, unclassified."
  def labels(resident_id, labels), do: normalize(labels, declared(resident_id))

  @doc "Pieces of bookmark lines: `[{number, text}]`, each labelled by its bookmark's anchor turn."
  def bookmarks(_resident_id, []), do: []

  def bookmarks(resident_id, lines) do
    found = Kumbukumbu.bookmark_labels(resident_id, Enum.map(lines, &elem(&1, 0)))

    for {n, text} <- lines,
        do: %{ref: "bookmark/#{n}", labels: Map.get(found, n, [@unclassified]), text: text}
  end

  @doc "A section's bookmark lines, those that open `#<number> `: `[{number, line}]`."
  def numbered_lines(text) when is_binary(text) do
    for line <- String.split(text, "\n"),
        [_, n] <- [Regex.run(~r/^#(\d+)\s/, line)],
        do: {String.to_integer(n), line}
  end

  def numbered_lines(_text), do: []

  @doc "Pieces of rows that keep labels: `[%{ref, labels, text}]`, their labels as they stand."
  def rows(resident_id, rows) do
    declared = declared(resident_id)
    for r <- rows, do: %{r | labels: normalize(r.labels, declared)}
  end

  @doc "A section with its pieces, so the turn's ledger and its audience read them (kumbukumbu#111)."
  def put([section], pieces), do: [Map.put(section, :pieces, pieces)]
  def put([], _pieces), do: []

  defp declared(resident_id),
    do: MapSet.new(AgathosDaimon.declared_domains(resident_id), &{&1.person, &1.domain})

  defp normalize(labels, _declared) when labels in [nil, []], do: [@unclassified]

  defp normalize(labels, declared) do
    labels
    |> Enum.map(fn l ->
      person = l["person"] || l[:person]
      domain = l["domain"] || l[:domain]
      kind = l["kind"] || l[:kind]

      cond do
        is_binary(domain) and {person, domain} in declared ->
          %{"person" => person, "domain" => domain}

        is_binary(domain) ->
          @common

        to_string(kind) == "unclassified" ->
          @unclassified

        true ->
          @common
      end
    end)
    |> Enum.uniq()
  end
end
