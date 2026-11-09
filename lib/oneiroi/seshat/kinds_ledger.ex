defmodule Oneiroi.Seshat.KindsLedger do
  @moduledoc """
  A resident's own kinds and the system kinds' gates (seshat#51), on
  `kinds-<resident_id>`. Either party defines or rewrites a kind of hers
  (the witness, 2026-11-08: "either should be able to edit the
  workspace"), the descriptor checked against the safe subset before it
  gets here. A system kind's approval gate is its own consent flow, never
  the contract's (the witness, 2026-11-09): either party turns it back on
  alone and at once; off is a proposal the other party answers.
  """

  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events

  @parties [:resident, :witness]

  defstruct kinds: MapSet.new(), gates: %{}, proposals: %{}, next: 1

  def execute(%__MODULE__{}, %{actor: %{kind: kind}}) when kind not in @parties,
    do: {:error, Error.new(:seshat_kind_not_a_party, :seshat_kinds_ledger_not_a_party)}

  def execute(%__MODULE__{kinds: kinds}, %Commands.DefineKind{} = c) do
    module = if MapSet.member?(kinds, c.kind), do: Events.KindChanged, else: Events.KindDefined

    struct!(module,
      actor: c.actor,
      at: c.at,
      id: c.id,
      kind: c.kind,
      descriptor: c.descriptor,
      note: c.note
    )
  end

  def execute(%__MODULE__{} = s, %Commands.ProposeKindGate{} = c) do
    current = Map.get(s.gates, c.kind, true)
    open? = Enum.any?(s.proposals, fn {_n, p} -> p.kind == c.kind and p.open end)

    cond do
      not is_boolean(c.approvable) ->
        {:error, Error.new(:seshat_kind_gate_invalid, :seshat_kinds_ledger_gate_value)}

      c.approvable == current ->
        []

      # Toward safety: either party, alone, at once.
      c.approvable ->
        %Events.KindGateMoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          kind: c.kind,
          approvable: true,
          number: nil
        }

      open? ->
        {:error, Error.new(:seshat_kind_gate_invalid, :seshat_kinds_ledger_gate_open)}

      true ->
        %Events.KindGateProposed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: s.next,
          kind: c.kind,
          approvable: false,
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{proposals: proposals}, %Commands.AnswerKindGate{} = c) do
    case Map.get(proposals, c.number) do
      %{open: true, by: by} = p when by != c.actor.kind ->
        answered = %Events.KindGateAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          agree: c.agree == true,
          note: c.note
        }

        if c.agree == true,
          do: [
            answered,
            %Events.KindGateMoved{
              actor: c.actor,
              at: c.at,
              id: c.id,
              kind: p.kind,
              approvable: p.approvable,
              number: c.number
            }
          ],
          else: answered

      %{open: true} ->
        {:error, Error.new(:seshat_kind_gate_invalid, :seshat_kinds_ledger_own_proposal)}

      _closed_or_none ->
        {:error, Error.new(:seshat_kind_gate_invalid, :seshat_kinds_ledger_no_proposal)}
    end
  end

  def apply(%__MODULE__{} = s, %Events.KindDefined{kind: k}),
    do: %{s | kinds: MapSet.put(s.kinds, k)}

  def apply(%__MODULE__{} = s, %Events.KindChanged{}), do: s

  def apply(%__MODULE__{} = s, %Events.KindGateProposed{} = e),
    do: %{
      s
      | next: e.number + 1,
        proposals:
          Map.put(s.proposals, e.number, %{
            kind: e.kind,
            approvable: e.approvable,
            by: actor_kind(e.actor),
            open: true
          })
    }

  def apply(%__MODULE__{} = s, %Events.KindGateAnswered{number: n}),
    do: %{s | proposals: Map.update!(s.proposals, n, &%{&1 | open: false})}

  def apply(%__MODULE__{} = s, %Events.KindGateMoved{kind: k, approvable: a}),
    do: %{s | gates: Map.put(s.gates, k, a)}

  defp actor_kind(%{kind: kind}) when is_atom(kind), do: kind
  defp actor_kind(%{kind: kind}) when is_binary(kind), do: String.to_existing_atom(kind)
  defp actor_kind(%{"kind" => kind}), do: String.to_existing_atom(kind)
end
