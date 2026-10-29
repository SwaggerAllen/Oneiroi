defmodule Oneiroi.Eunomia.JudgementRouter do
  @moduledoc "The judgement router: `judgement-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Eunomia.Judgement",
    prefix: "judgement-",
    commands: "Oneiroi.Eunomia.JudgementCommands",
    dispatching:
      ~w(TakePosition ReplacePosition CheckDispute SettleDispute RecordNight FailNight LogPrediction ResolvePrediction SetJudgeModel RunAudit FailAudit RaiseAuditFlag ApproveAuditFlag DeleteAuditFlag)
end
