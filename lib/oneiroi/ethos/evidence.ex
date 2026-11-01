defmodule Oneiroi.Ethos.Evidence do
  @moduledoc """
  Tags as citations (spec §6.17, P39): a moment or a bookmark is tagged
  by the tree node it evidences, a soul line, a habit or a seed, rather
  than by a label, so the resident's own tree is the vocabulary. The
  habit's and the seed's citations are theirs (`Habits`, `Seeds`); this
  is the soul line's, by either party, and the read memory takes through
  its tree port (`Oneiroi.Kumbukumbu.Tree`) to show a moment's tree tags
  beside its closed-set ones. A pin naming a soul line is leaf-evidence
  of it: the pin records the line and the line cites the bookmark, one
  call (`pin_as_evidence/4`).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Edge
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope

  @doc "A soul line cites a moment that evidenced it: a turn by ref or a bookmark by number, by the resident or its witness, with what the moment changed (P34) or nil; the line must be live."
  def cite_soul_line(resident_id, number, kind, target_id, %Actor{} = actor, movement \\ nil)
      when is_integer(number) do
    with :ok <- party(actor),
         :ok <- Edge.target_exists(resident_id, "soul", number),
         :ok <- Edge.target_exists(resident_id, kind, target_id),
         {:ok, movement} <- Edge.movement(movement) do
      command = %Commands.CiteSoulLine{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        target_kind: kind,
        target_id: to_string(target_id),
        movement: movement
      }

      with {:ok, _} <- Edge.dispatch(command), do: :ok
    end
  end

  @doc "Pins a bookmark as evidence of a soul line: the pin carries the line and the line cites the bookmark."
  def pin_as_evidence(resident_id, bookmark, soul_line, %Actor{} = actor)
      when is_integer(bookmark) and is_integer(soul_line) do
    with :ok <- party(actor),
         :ok <- Edge.target_exists(resident_id, "soul", soul_line),
         :ok <- Kumbukumbu.pin_bookmark(resident_id, bookmark, %{evidences: soul_line}, actor) do
      cite_soul_line(resident_id, soul_line, "bookmark", bookmark, actor)
    end
  end

  @doc "The citations of one soul line, newest first."
  def soul_line_citations(resident_id, number) do
    Scope.resident(resident_id, fn ->
      Enum.filter(Store.citations("soul"), &(&1.number == number))
    end)
  end

  @doc "Every soul line's citations, newest first."
  def soul_evidence(resident_id),
    do: Scope.resident(resident_id, fn -> Store.citations("soul") end)

  @doc """
  The tree's tags on moments, for memory's port: each target id named
  to the nodes citing it, as `kind/number` (`soul/3`, `habit/2`,
  `seed/1`), sorted. A moment nothing cites is absent.
  """
  @spec tags_of(String.t(), String.t(), [String.t()]) :: %{String.t() => [String.t()]}
  def tags_of(_resident_id, _target_kind, []), do: %{}

  def tags_of(resident_id, target_kind, target_ids) do
    Scope.resident(resident_id, fn ->
      target_kind
      |> Store.citations_of(Enum.map(target_ids, &to_string/1))
      |> Enum.group_by(& &1.target_id, &"#{&1.kind}/#{&1.number}")
      |> Map.new(fn {id, tags} -> {id, Enum.sort(tags)} end)
    end)
  end

  defp party(%Actor{kind: kind}) when kind in [:resident, :witness], do: :ok
  defp party(%Actor{}), do: {:error, Error.new(:ethos_not_a_party, :ethos_evidence_party_only)}
end
