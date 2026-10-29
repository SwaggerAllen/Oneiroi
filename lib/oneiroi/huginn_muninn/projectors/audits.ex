defmodule Oneiroi.HuginnMuninn.Projectors.Audits do
  @moduledoc "Folds the audits streams into counters with their increments, the steward's audits, and the runs."
  use Oneiroi.Projection, name: "huginn_muninn_audits"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.HuginnMuninn.Events
  alias Oneiroi.HuginnMuninn.Store.{Audit, Counter, Increment, Run}

  fold(%Events.CounterDefined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :counter,
      %Counter{resident_id: e.id, key: e.key, label: e.label, defined_at: e.at},
      on_conflict: [set: [label: e.label, retired_at: nil, defined_at: e.at]],
      conflict_target: [:resident_id, :key]
    )
  end)

  # Keyed on the store's position, never the instant: two increments in
  # one microsecond (a tool loop, or the suite's fixed clock) are two
  # rows in the audit log, which the first version collapsed into one
  # while the value counted both. The test that lists them found it.
  fold(%Events.CounterIncremented{} = e, metadata, fn multi ->
    multi
    |> Multi.insert(
      :increment,
      %Increment{
        resident_id: e.id,
        key: e.key,
        sequence: Map.get(metadata, :event_number, 0),
        at: e.at,
        by: e.by,
        note: e.note,
        actor_kind: actor_kind(e.actor),
        actor_id: actor_id(e.actor)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key, :sequence]
    )
    |> Multi.update_all(:value, from(c in Counter, where: c.key == ^e.key),
      inc: [value: e.by, increments: 1],
      set: [last_at: e.at, last_by_kind: actor_kind(e.actor)]
    )
  end)

  fold(%Events.CounterRetired{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :retired, from(c in Counter, where: c.key == ^e.key),
      set: [retired_at: e.at]
    )
  end)

  fold(%Events.UserAuditDefined{} = e, _metadata, fn multi ->
    fields = [
      label: e.label,
      figure: e.figure,
      op: e.op,
      value: e.value,
      tone: e.tone,
      counts: e.counts
    ]

    Multi.insert(
      multi,
      :audit,
      struct!(Audit, [resident_id: e.id, key: e.key, defined_at: e.at] ++ fields),
      on_conflict: [set: fields ++ [retired_at: nil, defined_at: e.at]],
      conflict_target: [:resident_id, :key]
    )
  end)

  fold(%Events.UserAuditRetired{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :retired, from(a in Audit, where: a.key == ^e.key),
      set: [retired_at: e.at]
    )
  end)

  # Keyed and ordered on the store's position, as the increments are:
  # two runs in one instant were one row, and the light read the older.
  fold(%Events.AuditRun{} = e, metadata, fn multi ->
    Multi.insert(
      multi,
      :run,
      %Run{
        resident_id: e.id,
        key: e.key,
        sequence: Map.get(metadata, :event_number, 0),
        at: e.at,
        builtin: e.builtin,
        tone: e.tone,
        value: e.value,
        finding: e.finding
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key, :sequence]
    )
  end)

  defp actor_kind(%{} = actor), do: to_string(Map.get(actor, :kind) || Map.get(actor, "kind"))
  defp actor_kind(_other), do: nil

  defp actor_id(%{} = actor) do
    case Map.get(actor, :id) || Map.get(actor, "id") do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp actor_id(_other), do: nil
end
