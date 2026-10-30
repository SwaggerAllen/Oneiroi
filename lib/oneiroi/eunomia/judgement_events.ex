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
    # Version 2 adds `criteria`: the hash of the judge's prompt file as
    # shipped when the verdict was asked for, so a criterion is on the log
    # before it can be invoked (spec §6.4, P12). A version-1 line carries
    # none and reads as nil, which is the truth about it.
    use Oneiroi.Event,
      version: 2,
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
        :judge_model,
        :criteria
      ]
  end

  defimpl Commanded.Event.Upcaster, for: DisputeChecked do
    def upcast(event, _metadata), do: event
  end

  defmodule DisputeSettled do
    # Conceded or held, by the resident on a live check and by the judge's
    # reading on a nightly one; a decision, so it carries its note.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref, :outcome]
  end

  defmodule NightJudged do
    # One per day: how much the judge read, what it found, under which
    # model. A quiet day is recorded with no messages and no model.
    # Version 2 adds `criteria` as `DisputeChecked` does; a quiet day,
    # judged by nobody, carries none. Version 3 adds `movements` (spec
    # §6.4, P34): the day's threads that moved, each string-keyed with
    # `numbers`, `turn_ref`, `happened`, `stance`, `intention` and
    # `resume`, so the record keeps what changed and not only what
    # stood; the store restarts for v0.2, so the upcaster is identity.
    use Oneiroi.Event,
      version: 3,
      fields: [
        :id,
        :day,
        :messages,
        :chars,
        :found,
        :judge_model,
        :summary,
        :criteria,
        :movements
      ]
  end

  defimpl Commanded.Event.Upcaster, for: NightJudged do
    def upcast(event, _metadata), do: event
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
    # Version 2 adds `criteria` as `DisputeChecked` does.
    use Oneiroi.Event,
      version: 2,
      fields: [:id, :ref, :conclusions, :flagged, :judge_model, :summary, :criteria]
  end

  defimpl Commanded.Event.Upcaster, for: AuditRun do
    def upcast(event, _metadata), do: event
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

  defmodule WashRun do
    # The weekly wash pass (spec §6.13, P18, Kael: "a defensive sentence
    # can't be seen from the inside"): how many entries of the identity
    # files the judge read, how many it flagged, under which model and
    # which prompt (`criteria`, as the other verdicts carry).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ref, :entries, :flagged, :judge_model, :summary, :criteria]
  end

  defmodule WashFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :ref, :reason]
  end

  defmodule WashFlagRaised do
    # One entry the judge reads as expired, a contradiction, tense or
    # defensive; a proposal, never a clearing: the resident decides.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :ref, :wash_ref, :file, :entry, :kind, :reason]
  end

  defmodule WashFlagResolved do
    # The resident's decision on a flag, keep or edit, with its note
    # (the edit itself is a soul edit, the resident's own write).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref, :decision]
  end

  defmodule JudgeModelChanged do
    # So the ratio chart marks it (spec §6.4).
    use Oneiroi.Event, version: 1, fields: [:id, :model, :previous]
  end
end
