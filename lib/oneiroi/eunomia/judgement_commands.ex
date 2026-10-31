defmodule Oneiroi.Eunomia.JudgementCommands do
  @moduledoc "The judgement aggregate's commands; `id` is the resident's id."

  # `imported` (eunomia #29): a record carried from another platform is
  # held to the shape and not the length limit, because its words are
  # what they were; nothing but the import sets it.
  defmodule TakePosition do
    use Oneiroi.Command, fields: [:id, :number, :statement, :session_key, :turn_ref, :imported]
  end

  defmodule ReplacePosition do
    use Oneiroi.Command,
      fields: [:id, :number, :replaces, :statement, :session_key, :turn_ref, :imported]
  end

  defmodule CheckDispute do
    use Oneiroi.Command,
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

  defmodule SettleDispute do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :outcome]
  end

  defmodule RecordNight do
    use Oneiroi.Command,
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

  defmodule FailNight do
    use Oneiroi.Command, fields: [:id, :day, :reason]
  end

  defmodule LogPrediction do
    use Oneiroi.Command,
      fields: [:id, :number, :statement, :due, :session_key, :turn_ref, :imported]
  end

  defmodule ResolvePrediction do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :outcome]
  end

  defmodule RunAudit do
    use Oneiroi.Command,
      fields: [:id, :ref, :conclusions, :flagged, :judge_model, :summary, :criteria]
  end

  defmodule FailAudit do
    use Oneiroi.Command, fields: [:id, :ref, :reason]
  end

  defmodule RaiseAuditFlag do
    use Oneiroi.Command, fields: [:id, :ref, :audit_ref, :conclusion_id, :conclusion, :reason]
  end

  defmodule ApproveAuditFlag do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  defmodule DeleteAuditFlag do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  # The wash pass (spec §6.13, P18): a run over the identity files'
  # entries, its flags, and the resident's decision on each.
  defmodule RunWash do
    use Oneiroi.Command,
      fields: [:id, :ref, :entries, :flagged, :judge_model, :summary, :criteria]
  end

  defmodule FailWash do
    use Oneiroi.Command, fields: [:id, :ref, :reason]
  end

  defmodule RaiseWashFlag do
    use Oneiroi.Command, fields: [:id, :ref, :wash_ref, :file, :entry, :kind, :reason]
  end

  defmodule ResolveWashFlag do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :decision]
  end

  defmodule SetJudgeModel do
    use Oneiroi.Command, fields: [:id, :model]
  end
end
