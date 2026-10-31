defmodule Oneiroi.Glitnir.Projectors.Reports do
  @moduledoc "Folds the governance streams into reports, their steps and the strikes."
  use Oneiroi.Projection, name: "glitnir_reports"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Glitnir.Events
  alias Oneiroi.Glitnir.Store.{Report, Step, Strike}

  fold(%Events.ReportFiled{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :report,
      %Report{
        resident_id: e.id,
        number: e.number,
        by_kind: actor_field(e.actor, :kind),
        by_id: actor_field(e.actor, :id),
        text: e.text,
        filed_at: e.at,
        state: "open"
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  # Keyed on the store's position (huginn-muninn's lesson): two steps in
  # one instant are two rows.
  fold(%Events.InvestigationStepRecorded{} = e, metadata, fn multi ->
    Multi.insert(
      multi,
      :step,
      %Step{
        resident_id: e.id,
        number: e.number,
        sequence: Map.get(metadata, :event_number, 0),
        at: e.at,
        reason: e.note,
        by_id: actor_field(e.actor, :id)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number, :sequence]
    )
  end)

  fold(%Events.ReportResolved{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :resolved,
      from(r in Report, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [
        state: "resolved",
        outcome: e.outcome,
        resolved_at: e.at,
        resolution_note: e.note,
        resolved_by_id: actor_field(e.actor, :id)
      ]
    )
  end)

  fold(%Events.StrikeIssued{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :strike,
      %Strike{
        resident_id: e.id,
        number: e.number,
        report: e.report,
        witness_account_id: e.witness_account_id,
        consequence: e.consequence,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  defp actor_field(%{} = actor, key) do
    case Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp actor_field(_other, _key), do: nil
end
