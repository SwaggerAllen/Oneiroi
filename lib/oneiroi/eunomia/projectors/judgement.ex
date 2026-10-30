defmodule Oneiroi.Eunomia.Projectors.Judgement do
  @moduledoc "Folds the judgement streams into positions, disputes, predictions, nights and judge changes."
  use Oneiroi.Projection, name: "eunomia_judgement"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Eunomia.Events.Judgement, as: Events

  alias Oneiroi.Eunomia.Store.{
    Audit,
    AuditFlag,
    Dispute,
    JudgeChange,
    Night,
    Position,
    Prediction
  }

  fold(%Events.PositionTaken{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :position,
      %Position{
        resident_id: e.id,
        number: e.number,
        statement: e.statement,
        session_key: e.session_key,
        turn_ref: e.turn_ref,
        taken_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.PositionReplaced{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :position,
      %Position{
        resident_id: e.id,
        number: e.number,
        statement: e.statement,
        session_key: e.session_key,
        turn_ref: e.turn_ref,
        replaces: e.replaces,
        taken_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
    |> Multi.update_all(:replaced, from(p in Position, where: p.number == ^e.replaces),
      set: [replaced_by: e.number, replaced_at: e.at]
    )
  end)

  fold(%Events.DisputeChecked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :dispute,
      %Dispute{
        resident_id: e.id,
        ref: e.ref,
        source: e.source,
        position_number: e.position_number,
        claim: e.claim,
        stance: e.stance,
        session_key: e.session_key,
        turn_ref: e.turn_ref,
        outcome: e.outcome,
        advice: e.advice,
        advice_text: e.advice_text,
        judge_model: e.judge_model,
        criteria: e.criteria,
        checked_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.DisputeSettled{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :settled, from(d in Dispute, where: d.ref == ^e.ref),
      set: [
        settlement: e.outcome,
        settled_note: e.note,
        settled_by_kind: actor_kind(e.actor),
        settled_at: e.at
      ]
    )
  end)

  fold(%Events.NightJudged{} = e, _metadata, fn multi ->
    Multi.insert(multi, :night, %Night{
      resident_id: e.id,
      day: e.day,
      at: e.at,
      outcome: "judged",
      messages: e.messages,
      chars: e.chars,
      found: e.found,
      judge_model: e.judge_model,
      criteria: e.criteria,
      summary: e.summary
    })
  end)

  fold(%Events.NightFailed{} = e, _metadata, fn multi ->
    Multi.insert(multi, :night, %Night{
      resident_id: e.id,
      day: e.day,
      at: e.at,
      outcome: "failed",
      reason: e.reason
    })
  end)

  fold(%Events.PredictionLogged{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :prediction,
      %Prediction{
        resident_id: e.id,
        number: e.number,
        statement: e.statement,
        due: e.due,
        session_key: e.session_key,
        turn_ref: e.turn_ref,
        logged_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.PredictionResolved{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :resolved, from(p in Prediction, where: p.number == ^e.number),
      set: [outcome: e.outcome, note: e.note, resolved_at: e.at]
    )
  end)

  fold(%Events.AuditRun{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :audit,
      %Audit{
        resident_id: e.id,
        ref: e.ref,
        outcome: "run",
        conclusions: e.conclusions,
        flagged: e.flagged,
        judge_model: e.judge_model,
        criteria: e.criteria,
        summary: e.summary,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.AuditFailed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :audit,
      %Audit{resident_id: e.id, ref: e.ref, outcome: "failed", reason: e.reason, at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.AuditFlagRaised{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :flag,
      %AuditFlag{
        resident_id: e.id,
        ref: e.ref,
        audit_ref: e.audit_ref,
        conclusion_id: e.conclusion_id,
        conclusion: e.conclusion,
        reason: e.reason,
        raised_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.AuditFlagApproved{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :flag, from(f in AuditFlag, where: f.ref == ^e.ref),
      set: [decision: "approved", note: e.note, decided_at: e.at]
    )
  end)

  fold(%Events.AuditFlagDeleted{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :flag, from(f in AuditFlag, where: f.ref == ^e.ref),
      set: [decision: "deleted", note: e.note, decided_at: e.at]
    )
  end)

  fold(%Events.JudgeModelChanged{} = e, _metadata, fn multi ->
    Multi.insert(multi, :change, %JudgeChange{
      resident_id: e.id,
      at: e.at,
      model: e.model,
      previous: e.previous
    })
  end)

  defp actor_kind(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp actor_kind(%{kind: kind}) when is_binary(kind), do: kind
  defp actor_kind(_actor), do: nil
end
