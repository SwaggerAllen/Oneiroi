defmodule Oneiroi.Eunomia.Events.Judgement do
  @moduledoc """
  The judgement stream's events, version 1 (spec §3.1, §6.4):
  `judgement-<resident_id>`, one per resident: positions and their
  chains, disputes live and nightly, predictions, the nights, and the
  judge. Every verdict carries the judge's model (F41). These are the
  resident's record and export like any other (spec §6.10 lists them),
  unlike the regression suite's.
  """

  defmodule PositionTaken do
    # A position is a statement the resident holds, in its words, at a
    # moment in a conversation; the number is minted by the resident
    # aggregate so `<slug>:position/7` survives a rebuild.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :statement, :session_key, :turn_ref]
  end

  defmodule PositionReplaced do
    # `number` is the new position; `replaces` the one it supersedes. A
    # chain cannot fork: only the head of a chain may be replaced.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :replaces, :statement, :session_key, :turn_ref]
  end

  defmodule DisputeChecked do
    # A live check (`source: live`) is the resident asking the judge
    # before answering; `timed_out` is unjudged, not failed (spec §6.4).
    # A nightly one (`source: night`) is the judge reading the day and
    # finding a disagreement settled in conversation.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :ref,
        :source,
        :position_number,
        :claim,
        :stance,
        :session_key,
        :turn_ref,
        :outcome,
        :advice,
        :advice_text,
        :judge_model
      ]
  end

  defmodule DisputeSettled do
    # Conceded or held, by the resident on a live check and by the judge's
    # reading on a nightly one; a decision, so it carries its note.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref, :outcome]
  end

  defmodule NightJudged do
    # One per day: how much the judge read, what it found, under which
    # model. A quiet day is recorded with no messages and no model.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :day, :messages, :chars, :found, :judge_model, :summary]
  end

  defmodule NightFailed do
    # A reply naming a message it was not shown fails the night rather
    # than being guessed at (spec §6.4); the night may run again.
    use Oneiroi.Event, version: 1, fields: [:id, :day, :reason]
  end

  defmodule PredictionLogged do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :statement, :due, :session_key, :turn_ref],
      instants: [:due]
  end

  defmodule PredictionResolved do
    # Right, wrong or void: the witness's alone (F17), with a note.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number, :outcome]
  end

  defmodule AuditRun do
    # The weekly memory audit (F15): how many of Honcho's conclusions the
    # judge read, how many it flagged, under which model.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ref, :conclusions, :flagged, :judge_model, :summary]
  end

  defmodule AuditFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :ref, :reason]
  end

  defmodule AuditFlagRaised do
    # One conclusion the judge reads as drift from the resident's stated
    # positions or soul; the witness approves the flag (the conclusion
    # goes) or deletes it (the conclusion stays).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ref, :audit_ref, :conclusion_id, :conclusion, :reason]
  end

  defmodule AuditFlagApproved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule AuditFlagDeleted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule JudgeModelChanged do
    # So the ratio chart marks it (spec §6.4).
    use Oneiroi.Event, version: 1, fields: [:id, :model, :previous]
  end
end
