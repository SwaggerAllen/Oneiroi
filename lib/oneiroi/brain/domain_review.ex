defmodule Oneiroi.Brain.DomainReview do
  @moduledoc """
  What is left to recategorize (kumbukumbu#110; the witness, 2026-11-25:
  "We need to be able to retag things that have undeclared domains and
  unclassified memories via tool call"), as her `domain_review` tool
  reads it:

  - **undeclared domains:** each domain her messages are in that the
    agreement in force does not declare, whose life it is, how many
    messages and conversations, from when to when, and the first turns
    that named it. `domain_recategorize` moves one whole; `domain_tag`
    moves a turn at a time.
  - **records:** the records that keep labels (a journal row, a letter, a
    letter to her next self, a file she wrote) whose labels as they stand
    (her classification, else the labels pass's, else as kept) are
    unclassified or name an undeclared domain. `record_classify` sets a
    journal row's or a letter's; `document_classify` a file's.

  Ids, dates and domains only, never the words: a record's words would
  enter the reading turn's ledger, and every one of them is hers to open.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @epoch ~U[2000-01-01 00:00:00Z]
  @far ~U[2999-01-01 00:00:00Z]
  @tag_points 3

  @doc "The undeclared domains of her messages, oldest first, each with its first tag points."
  def domains(resident_id) do
    declared = declared(resident_id)

    for p <- Kumbukumbu.domain_pairs(resident_id),
        {p.person, p.domain} not in declared,
        do:
          Map.put(
            p,
            :tag_points,
            Kumbukumbu.tag_points_of(resident_id, p.person, p.domain, @tag_points)
          )
  end

  @doc """
  The records whose labels as they stand are unclassified or name an
  undeclared domain, oldest first: `%{kind, id, at, status}`, `status`
  `:unclassified` or `{:undeclared, [domain]}`.
  """
  def records(resident_id) do
    declared = declared(resident_id)

    (journal(resident_id) ++
       letters(resident_id) ++ self_letters(resident_id) ++ files(resident_id))
    |> Enum.map(&Map.put(&1, :status, status(&1.labels, declared)))
    |> Enum.reject(&(&1.status == :ok))
    |> Enum.sort_by(& &1.at, DateTime)
    |> Enum.map(&Map.delete(&1, :labels))
  end

  defp declared(resident_id),
    do: MapSet.new(AgathosDaimon.declared_domains(resident_id), &{&1.person, &1.domain})

  defp journal(resident_id) do
    rows = Seshat.written_between(resident_id, @epoch, @far).journal
    standing(resident_id, "journal", rows, &"#{&1.day}/#{&1.number}", & &1.at)
  end

  defp letters(resident_id) do
    rows = Kumbukumbu.letters(resident_id)
    standing(resident_id, "letter", rows, &to_string(&1.number), & &1.sent_at)
  end

  defp self_letters(resident_id) do
    rows = AgathosDaimon.self_letters(resident_id)
    standing(resident_id, "self_letter", rows, &to_string(&1.number), & &1.written_at)
  end

  # Each row's labels as they stand: her classification, else the labels
  # pass's, else as kept.
  defp standing(resident_id, kind, rows, id_of, at_of) do
    ids = Enum.map(rows, id_of)
    derived = Kumbukumbu.derived_labels(resident_id, kind, ids)

    for row <- rows, at = at_of.(row), not is_nil(at) do
      id = id_of.(row)
      %{kind: kind, id: id, at: at, labels: Map.get(derived, id, Map.get(row, :labels))}
    end
  end

  # The files she wrote: her classification where she made one, else the
  # head version's labels, derived again where they were.
  defp files(resident_id) do
    heads =
      Seshat.written_between(resident_id, @epoch, @far).versions
      |> Map.new(&{&1.path, &1})

    # Only the kinds she writes: a journal or scenes file is rendered from
    # its rows, which are classified as rows.
    writable =
      for k <- Seshat.kinds(resident_id),
          Map.get(k, :access) in [:resident, :keepsake],
          do: k.kind

    for d <- Seshat.documents(resident_id),
        d.written_by_kind == "resident",
        d.kind in writable,
        at = d.classified_at || (heads[d.path] && heads[d.path].at),
        not is_nil(at),
        do: %{
          kind: "file",
          id: d.path,
          at: at,
          labels: file_labels(resident_id, d, heads[d.path])
        }
  end

  defp file_labels(_resident_id, %{classified_at: %DateTime{}, class_domain: nil}, _head),
    do: [%{"kind" => "common_room"}]

  defp file_labels(_resident_id, %{classified_at: %DateTime{}} = d, _head),
    do: [%{"person" => d.class_person, "domain" => d.class_domain}]

  defp file_labels(resident_id, _d, %{} = head) do
    id = "#{head.path}@#{head.hash}"

    case Kumbukumbu.derived_labels(resident_id, "file", [id]) do
      %{^id => labels} -> labels
      _none -> Kumbukumbu.ledger_labels(head.ledger)
    end
  end

  defp file_labels(_resident_id, _d, nil), do: nil

  # `:ok`, `:unclassified`, or the undeclared domains a record names.
  defp status(labels, _declared) when labels in [nil, []], do: :unclassified

  defp status(labels, declared) do
    undeclared =
      for l <- labels,
          domain = get(l, "domain"),
          is_binary(domain),
          {get(l, "person"), domain} not in declared,
          uniq: true,
          do: domain

    cond do
      Enum.any?(labels, &(to_string(get(&1, "kind")) == "unclassified")) -> :unclassified
      undeclared != [] -> {:undeclared, undeclared}
      true -> :ok
    end
  end

  defp get(%{} = l, key), do: Map.get(l, key) || Map.get(l, String.to_existing_atom(key))
  defp get(_other, _key), do: nil
end
