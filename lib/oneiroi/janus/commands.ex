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

  defmodule SetBackup do
    use Oneiroi.Command, fields: [:id, :url, :token_ciphertext, :visibility, :push]
  end

  # ---- preparation (janus#6 to #10) ----

  defmodule SetEnvelope do
    use Oneiroi.Command, fields: [:id, :input_nanos, :output_nanos]
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

  defmodule FreezeC0 do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule WritePacket do
    use Oneiroi.Command, fields: [:id, :content]
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
end
