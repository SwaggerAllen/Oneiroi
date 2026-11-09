defmodule Oneiroi.Seshat.Projectors.Kinds do
  @moduledoc "Folds the kinds streams (seshat#51): her own kinds' descriptors, the system kinds' gates as hers, and the gate proposals."
  use Oneiroi.Projection, name: "seshat_kinds"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.KindGate
  alias Oneiroi.Seshat.Store.KindGateProposal
  alias Oneiroi.Seshat.Store.UserKind

  fold(%Events.KindDefined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :kind,
      %UserKind{
        resident_id: e.id,
        kind: e.kind,
        descriptor: e.descriptor,
        created_by: by(e.actor),
        updated_by: by(e.actor),
        created_at: e.at,
        updated_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.KindChanged{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :kind,
      from(k in UserKind, where: k.resident_id == ^e.id and k.kind == ^e.kind),
      set: [descriptor: e.descriptor, updated_by: by(e.actor), updated_at: e.at]
    )
  end)

  fold(%Events.KindGateProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :proposal,
      %KindGateProposal{
        resident_id: e.id,
        number: e.number,
        kind: e.kind,
        approvable: e.approvable,
        proposed_by: by(e.actor),
        note: e.note,
        proposed_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.KindGateAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :answer,
      from(p in KindGateProposal, where: p.resident_id == ^e.id and p.number == ^e.number),
      set: [agree: e.agree, answered_by: by(e.actor), answer_note: e.note, answered_at: e.at]
    )
  end)

  fold(%Events.KindGateMoved{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :gate,
      %KindGate{
        resident_id: e.id,
        kind: e.kind,
        approvable: e.approvable,
        moved_by: by(e.actor),
        moved_at: e.at
      },
      on_conflict: {:replace, [:approvable, :moved_by, :moved_at]},
      conflict_target: [:resident_id, :kind]
    )
  end)

  defp by(%{kind: kind}), do: to_string(kind)
  defp by(%{"kind" => kind}), do: to_string(kind)
  defp by(_none), do: nil
end
