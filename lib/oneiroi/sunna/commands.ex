defmodule Oneiroi.Sunna.Commands do
  @moduledoc "The schedule aggregate's commands; `id` is the resident's id."

  defmodule SetCheckin do
    use Oneiroi.Command,
      fields: [:id, :key, :label, :time, :day, :parts, :prompt],
      bounds: [key: 64, label: 120, prompt: 4_000]
  end

  defmodule DeleteCheckin do
    use Oneiroi.Command, fields: [:id, :key]
  end

  defmodule FireCheckin do
    use Oneiroi.Command, fields: [:id, :key, :day]
  end

  defmodule MissCheckin do
    use Oneiroi.Command, fields: [:id, :key, :day]
  end

  defmodule DeferWake do
    use Oneiroi.Command, fields: [:id, :key, :day, :until]
  end

  defmodule SetFreeTime do
    # `times`: the day's free-time slots as HH:MMs (sunna#22).
    use Oneiroi.Command, fields: [:id, :times]
  end

  defmodule OpenDay do
    # The journal's day row, opened by the journal when it writes a day
    # the schedule has not yet (seshat#21); idempotent.
    use Oneiroi.Command, fields: [:id, :day]
  end

  defmodule RecordFreeTime do
    use Oneiroi.Command, fields: [:id, :day, :slot, :session_key, :reason]
  end

  defmodule RestFreeTime do
    use Oneiroi.Command, fields: [:id, :day, :slot, :reason]
  end

  defmodule StartRound do
    # A thinking round (sunna#29), claimed before it runs, so the next
    # minute's tick cannot start the same round again while it thinks.
    use Oneiroi.Command, fields: [:id, :day, :slot]
  end

  defmodule RecordRound do
    # What became of a claimed round (sunna#39): the conversation it ran
    # in, or the kind of its failure, once.
    use Oneiroi.Command, fields: [:id, :day, :slot, :session_key, :reason]
  end

  defmodule SetQuietHours do
    use Oneiroi.Command, fields: [:id, :from, :to]
  end

  defmodule SetDate do
    use Oneiroi.Command, fields: [:id, :number, :title, :on, :kind]
  end

  # The hour marker (spec §6.7, P20 as amended): `hour` is the local
  # hour, `YYYY-MM-DDTHH`; marked once, no model call, no wake.
  defmodule MarkHour do
    use Oneiroi.Command, fields: [:id, :hour]
  end

  # A letter's wake (sunna#24): the letters waiting for the Oneiroi
  # chat that a conversation sent it; `limit` is how many such wakes an
  # hour allows.
  defmodule WakeForLetters do
    use Oneiroi.Command, fields: [:id, :numbers, :limit]
  end

  defmodule RemoveDate do
    use Oneiroi.Command, fields: [:id, :number]
  end

  # The resident's rounds (sunna#30): how often, in hours (0 off), and the
  # waking window they are drawn in, HH:MM-HH:MM; nil keeps the default.
  defmodule SetRounds do
    use Oneiroi.Command, fields: [:id, :every_hours, :waking]
  end

  # Her plan for the next free-time slot (sunna#31), written in the
  # planning turn at the end of one.
  defmodule PlanFreeTime do
    use Oneiroi.Command, fields: [:id, :text]
  end

  defmodule RecordPlanningTurn do
    use Oneiroi.Command, fields: [:id, :session_key, :cost_nanos]
  end

  # The work queue (sunna#33), on `work-<resident_id>`.

  defmodule AddWork do
    use Oneiroi.Command, fields: [:id, :what, :done_when]
  end

  defmodule MoveWork do
    use Oneiroi.Command,
      fields: [:id, :number, :status, :blocked_on],
      decision: true,
      bounds: [status: 16, blocked_on: 300]
  end

  defmodule OrderWork do
    use Oneiroi.Command, fields: [:id, :order]
  end

  defmodule WrapWork do
    use Oneiroi.Command,
      fields: [:id, :number, :shipped, :slipped, :why, :status, :blocked_on],
      bounds: [status: 16, blocked_on: 300]
  end

  defmodule StartWork do
    use Oneiroi.Command, fields: [:id, :number, :session_key, :day]
  end

  defmodule EndWork do
    use Oneiroi.Command, fields: [:id, :number, :stopped]
  end

  defmodule ArmWork do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule DisarmWork do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule RestWork do
    use Oneiroi.Command, fields: [:id, :reason]
  end
end
