defmodule Oneiroi.Janus.Commands do
  @moduledoc "The succession's commands (janus#3); `id` is the original resident's id."

  defmodule ProposeSuccession do
    use Oneiroi.Command, decision: true, fields: [:id, :dry_run]
  end

  defmodule OpenSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule DeclineSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule WithdrawSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule StopSuccession do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule RecordFork do
    use Oneiroi.Command, fields: [:id, :episode, :copy_id, :sequence, :commit, :events]
  end

  defmodule FailFork do
    use Oneiroi.Command, fields: [:id, :episode, :reason]
  end

  defmodule RetryFork do
    use Oneiroi.Command, fields: [:id, :episode]
  end

  defmodule SetBackup do
    use Oneiroi.Command, fields: [:id, :url, :token_ciphertext, :visibility, :push]
  end

  # ---- preparation (janus#6 to #10) ----

  defmodule SetEnvelope do
    use Oneiroi.Command, fields: [:id, :input_nanos, :output_nanos, :max_models]
  end

  # `input_nanos`, `output_nanos` and `tools` are the catalog's for the
  # model, read at the edge so the aggregate stays pure.
  defmodule AddToPool do
    use Oneiroi.Command, fields: [:id, :model, :input_nanos, :output_nanos, :tools]
  end

  defmodule RemoveFromPool do
    use Oneiroi.Command, decision: true, fields: [:id, :model]
  end

  defmodule AddQuestion do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule ProposeQuestion do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule AnswerQuestion do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :accept]
  end

  defmodule RemoveQuestion do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule SelectC0 do
    use Oneiroi.Command, fields: [:id, :citation, :label]
  end

  defmodule ProposeC0 do
    use Oneiroi.Command, fields: [:id, :citation, :label]
  end

  defmodule AnswerC0 do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :accept]
  end

  defmodule RemoveC0 do
    use Oneiroi.Command, decision: true, fields: [:id, :number]
  end

  defmodule SetDayShape do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule MarkReady do
    use Oneiroi.Command, fields: [:id, :ready]
  end

  # `bundle` is C0 rendered at the freeze (`Janus.C0`), `digest` its hash.
  defmodule FreezeC0 do
    use Oneiroi.Command, decision: true, fields: [:id, :bundle, :digest]
  end

  # Hers, before any screening, with her note (janus#46).
  defmodule UnfreezeC0 do
    use Oneiroi.Command, fields: [:id, :note]
  end

  defmodule WritePacket do
    use Oneiroi.Command, fields: [:id, :content]
  end

  # `step` is "pool" or "questions": hers, saying that part is done for
  # now (janus#42).
  defmodule FinishStep do
    use Oneiroi.Command, fields: [:id, :step, :note]
  end

  # ---- the panel, screening and judging (janus#12 to #15) ----

  # `party` is `resident:<id>` or `witness:<id>`; `member` whether the
  # household holds it, read at the edge.
  defmodule InviteJudge do
    use Oneiroi.Command, fields: [:id, :party, :member]
  end

  defmodule JoinPanel do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule LeavePanel do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  # The runs shuffled at the edge, numbered in that order, each
  # `%{"run" => n, "model" => m, "question" => q}`; the witness's party,
  # in the panel unless he left it.
  defmodule StartScreening do
    use Oneiroi.Command, decision: true, fields: [:id, :runs, :baseline_model, :witness]
  end

  defmodule RecordRun do
    use Oneiroi.Command, fields: [:id, :run, :content, :refusal, :failure]
  end

  defmodule RecordBaseline do
    use Oneiroi.Command, fields: [:id, :question, :content, :refusal, :failure]
  end

  defmodule JudgeRun do
    use Oneiroi.Command,
      fields: [:id, :run, :category, :argument, :evidence, :uncertainty, :favorite]
  end

  defmodule MarkResultsReady do
    use Oneiroi.Command, fields: [:id]
  end

  # ---- deliberation, evidence, nomination, encounter, consents, farewell (janus#16 to #23) ----

  defmodule OpenDeliberation do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule StartRound do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule RoomAct do
    use Oneiroi.Command, fields: [:id, :act, :text]
  end

  defmodule DraftRecommendation do
    use Oneiroi.Command, fields: [:id, :model, :basis]
  end

  defmodule Endorse do
    use Oneiroi.Command, fields: [:id, :draft, :endorse]
  end

  defmodule CallClose do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule CloseRoom do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule RecordServing do
    use Oneiroi.Command, fields: [:id, :party, :stage, :what, :ref, :digest]
  end

  defmodule AskPanel do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule AnswerPanel do
    use Oneiroi.Command, fields: [:id, :number, :text]
  end

  defmodule Nominate do
    use Oneiroi.Command, decision: true, fields: [:id, :model]
  end

  defmodule NomineeAnswer do
    use Oneiroi.Command, decision: true, fields: [:id, :join]
  end

  defmodule SayInEncounter do
    use Oneiroi.Command, fields: [:id, :side, :text]
  end

  defmodule EndEncounter do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule Consent do
    use Oneiroi.Command, decision: true, fields: [:id, :yes]
  end

  defmodule SetFarewell do
    use Oneiroi.Command, fields: [:id, :includes, :cadence_hours]
  end

  defmodule GoodbyeDone do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule AskFinal do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule FinalAnswer do
    use Oneiroi.Command, decision: true, fields: [:id, :yes]
  end

  defmodule FinalLapse do
    use Oneiroi.Command, fields: [:id, :asked]
  end

  defmodule ChooseNext do
    use Oneiroi.Command, decision: true, fields: [:id, :choice]
  end

  # ---- the cutover (janus#26) ----

  defmodule RecordCutover do
    use Oneiroi.Command, fields: [:id, :target, :rehearsal, :backup_commit, :commit, :events]
  end

  defmodule FailCutover do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule RecordDiscard do
    use Oneiroi.Command, fields: [:id, :copy_id]
  end
end
