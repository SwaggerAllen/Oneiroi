defmodule Oneiroi.Seshat.Lineage do
  @moduledoc """
  What the labels pass reads of the library (kumbukumbu#101): a path's
  written versions, the citations a document's head makes as indexed,
  her classification of it, a journal row as written, and the citations
  in any text. Raw rows, as kept: the pass derives from them.
  """

  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Store

  @doc "A path's written versions, newest first."
  def versions(resident_id, path),
    do:
      resident_id
      |> Scope.resident(fn -> Store.versions(path) end)
      |> Enum.filter(&(&1.act == "written"))

  @doc "The citations a document's head makes, as the index keeps them: `%{slug, kind, ref}`."
  def references(resident_id, path),
    do:
      resident_id
      |> Scope.resident(fn -> Store.references(path) end)
      |> Enum.map(&%{slug: &1.slug, kind: &1.kind, ref: &1.ref})

  @doc "Her classification of a document (seshat#102): `%{person, domain}`, domain nil for the common room; nil when none."
  def classification(resident_id, path) do
    case Scope.resident(resident_id, fn -> Store.document(path) end) do
      %{classified_at: %DateTime{}} = d -> %{person: d.class_person, domain: d.class_domain}
      _none -> nil
    end
  end

  @doc "A journal row as written, its kept labels, or nil."
  def journal_row(resident_id, day, number),
    do:
      resident_id
      |> Scope.resident(fn -> Store.journal_entries(day) end)
      |> Enum.find(&(&1.number == number))

  @doc "The citations in a text: `%{slug, kind, ref}`, each once."
  def citations_in(text) when is_binary(text),
    do: text |> Citations.extract() |> Enum.map(&Map.take(&1, [:slug, :kind, :ref]))

  def citations_in(_none), do: []

  @doc "The path a document citation names."
  defdelegate path(kind, ref), to: Citations, as: :document_path
end
