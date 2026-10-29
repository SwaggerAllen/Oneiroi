defmodule Oneiroi.Eunomia.JudgementCommands do
  @moduledoc "The judgement aggregate's commands; `id` is the resident's id."

  defmodule TakePosition do
    use Oneiroi.Command, fields: [:id, :number, :statement, :session_key, :turn_ref]
  end

  defmodule ReplacePosition do
    use Oneiroi.Command, fields: [:id, :number, :replaces, :statement, :session_key, :turn_ref]
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
        :judge_model
      ]
  end

  defmodule SettleDispute do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :outcome]
  end

  defmodule RecordNight do
    use Oneiroi.Command, fields: [:id, :day, :messages, :chars, :found, :judge_model, :summary]
  end

  defmodule FailNight do
    use Oneiroi.Command, fields: [:id, :day, :reason]
  end

  defmodule LogPrediction do
    use Oneiroi.Command, fields: [:id, :number, :statement, :due, :session_key, :turn_ref]
  end

  defmodule ResolvePrediction do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :outcome]
  end

  defmodule SetJudgeModel do
    use Oneiroi.Command, fields: [:id, :model]
  end
end
