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

  defmodule AddFreeTimeOnce do
    # A one-off free-time slot (sunna#45): a day and a time in her zone,
    # either party's, on top of the standing list.
    use Oneiroi.Command, fields: [:id, :day, :time]
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
  # The wake log (sunna#71): what a wake carried, and when it was read.
  defmodule ManifestWake do
    use Oneiroi.Command, fields: [:id, :wake_id, :channel, :causes, :household_id, :delivered]
  end

  defmodule ReadWake do
    use Oneiroi.Command, fields: [:id, :wake_id]
  end

  defmodule WakeForLetters do
    # `capped` false for a wake that carries no letter from another of her
    # conversations (sunna#72): only those can wake each other in a loop.
    # `spacing`: no two letter wakes closer than this many seconds
    # (sunna#73), the first after a quiet spell at once.
    use Oneiroi.Command, fields: [:id, :numbers, :limit, :capped, :spacing]
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

  # The work line (sunna#33, #86), on `work-<resident_id>`; the old
  # queue's item commands retired (sunna#102).

  # A run of a house queue activity on her work line (sunna#86): the
  # household, the task and the activity, in its conversation, on her day.
  defmodule StartActivityRun do
    use Oneiroi.Command, fields: [:id, :household, :task, :act, :session_key, :day]
  end

  defmodule EndActivityRun do
    use Oneiroi.Command, fields: [:id, :act, :stopped, :cut, :moved, :stopped_by]
  end

  defmodule ResetWorkRuns do
    use Oneiroi.Command, fields: [:id], decision: true
  end

  # One activity's runs given back, on its task (sunna#106).
  defmodule ResetActivityRuns do
    use Oneiroi.Command, fields: [:id, :act], decision: true
  end

  # A line rested by a stopped run taken up again (sunna#109), with a note.
  defmodule ResumeWork do
    use Oneiroi.Command, fields: [:id], decision: true
  end

  # The witness skips the free-time wait (sunna#76), with a note.
  defmodule SkipCareWait do
    use Oneiroi.Command, fields: [:id], decision: true
  end

  defmodule RestWork do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  # Her own words for a house check-in (sunna#65), by its key.
  defmodule SetHousePrompt do
    use Oneiroi.Command, fields: [:id, :key, :prompt, :parts], bounds: [key: 64, prompt: 4_000]
  end
end
