defmodule Oneiroi.Sunna.Events do
  @moduledoc """
  The schedule stream's events, version 1 (spec §3.1, §6.7):
  `schedule-<resident_id>`, one per resident. Times of day are `HH:MM`
  strings in the resident's own zone, days are ISO dates in that zone,
  and a firing is an event before the wake, so a check-in fires once a
  day whatever restarts.
  """

  defmodule CheckinSet do
    # Carries the day it was set on, as a change does: one set after its
    # time today is not missed today, it waits for tomorrow. Version 2
    # adds what the note carries (sunna#28): `parts`, the catalog's keys
    # checked, and `prompt`, the witness's own words; a version 1 event
    # reads as the note it always was, the dates and no words.
    use Oneiroi.Event, version: 2, fields: [:id, :key, :label, :time, :day, :parts, :prompt]
  end

  defimpl Commanded.Event.Upcaster, for: CheckinSet do
    def upcast(%{parts: nil} = event, _metadata), do: %{event | parts: ["dates"]}
    def upcast(event, _metadata), do: event
  end

  defmodule CheckinChanged do
    # Carries the day it was changed on, so one changed after its time
    # today waits for tomorrow (spec §6.7). Version 2 as CheckinSet's.
    use Oneiroi.Event, version: 2, fields: [:id, :key, :label, :time, :day, :parts, :prompt]
  end

  defimpl Commanded.Event.Upcaster, for: CheckinChanged do
    def upcast(%{parts: nil} = event, _metadata), do: %{event | parts: ["dates"]}
    def upcast(event, _metadata), do: event
  end

  defmodule CheckinDeleted do
    use Oneiroi.Event, version: 1, fields: [:id, :key]
  end

  defmodule CheckinFired do
    # Recorded before the wake: the firing row the spec asks for.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :day]
  end

  defmodule CheckinMissed do
    # Later than the late window, so it did not fire: said, never silent.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :day]
  end

  defmodule WakeDeferred do
    # A wake inside quiet hours waits for their end (spec §6.7).
    use Oneiroi.Event, version: 1, fields: [:id, :key, :day, :until], instants: [:until]
  end

  defmodule DayOpened do
    # The journal's day row (spec §6.5), created at the day's first
    # check-in so a day never written is a row rather than an absent file.
    use Oneiroi.Event, version: 1, fields: [:id, :day]
  end

  defmodule FreeTimeScheduled do
    # Version 2 adds `times` (sunna#22): free time is a list of slots, a
    # day's HH:MMs in order. A version 1 event carried one `time`, which
    # the upcaster reads as a list of one; `time` stays a field so the
    # stored payload still decodes.
    use Oneiroi.Event, version: 2, fields: [:id, :time, :times]
  end

  defimpl Commanded.Event.Upcaster, for: FreeTimeScheduled do
    def upcast(%{times: nil, time: time} = event, _metadata) when is_binary(time),
      do: %{event | times: [time]}

    def upcast(event, _metadata), do: event
  end

  defmodule FreeTimeRan do
    # Version 2 adds `slot` (sunna#22), the HH:MM of the slot that ran;
    # nil on a version 1 event, from when a day had one free time.
    use Oneiroi.Event, version: 2, fields: [:id, :day, :session_key, :slot]
  end

  defimpl Commanded.Event.Upcaster, for: FreeTimeRan do
    def upcast(event, _metadata), do: event
  end

  defmodule FreeTimeFailed do
    # Version 2 adds `slot`, as FreeTimeRan's.
    use Oneiroi.Event, version: 2, fields: [:id, :day, :reason, :slot]
  end

  defimpl Commanded.Event.Upcaster, for: FreeTimeFailed do
    def upcast(event, _metadata), do: event
  end

  defmodule RoundStarted do
    # A thinking round (sunna#29): an unannounced wake at a random time
    # in the resident's waking hours, recorded before it runs. Its slot is
    # the HH:MM it was drawn at; what it did is in its own conversation.
    use Oneiroi.Event, version: 1, fields: [:id, :day, :slot]
  end

  defmodule QuietHoursSet do
    # Both nil clears them.
    use Oneiroi.Event, version: 1, fields: [:id, :from, :to]
  end

  defmodule DateSet do
    # An important date is a row, never prose (spec §6.7, F56): the number
    # is the resident's sequence, so `lily:date/3` is citeable.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :title, :on, :kind],
      instants: [:on]
  end

  defmodule DateChanged do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :title, :on, :kind],
      instants: [:on]
  end

  defmodule HourMarked do
    # The pulse (spec §6.7, P20 as amended): the local hour marked on
    # the schedule's stream before any wake, once, so absence is
    # auditable and the resident is not disturbed.
    use Oneiroi.Event, version: 1, fields: [:id, :hour]
  end

  defmodule LettersWoke do
    # A letter's wake (sunna#24): the Oneiroi chat woken for these
    # letters, each once, before the wake runs.
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule DateRemoved do
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end

  defmodule RoundsSet do
    # The resident's rounds (sunna#30): every_hours (0 off) and the waking
    # window, each nil for the platform's default.
    use Oneiroi.Event, version: 1, fields: [:id, :every_hours, :waking]
  end

  defmodule FreeTimePlanned do
    # Her plan for the next free-time slot (sunna#31), in her words.
    use Oneiroi.Event, version: 1, fields: [:id, :text]
  end

  defmodule PlanningTurnRan do
    # The planning turn that closed a free-time slot (sunna#32), billed on
    # its own line: its conversation and what it cost, in nano-dollars.
    use Oneiroi.Event, version: 1, fields: [:id, :session_key, :cost_nanos]
  end

  # The work queue (sunna#33), on `work-<resident_id>`: long items in
  # priority order, either party's, run one at a time on completion.

  defmodule WorkAdded do
    # An item, numbered from 1, appended to the end of the order.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :what, :done_when]
  end

  defmodule WorkMoved do
    # A status set by hand (open, blocked, done, dropped), with its note;
    # `blocked_on` names what holds a blocked item.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :number, :status, :blocked_on]
  end

  defmodule WorkOrdered do
    # The whole order after the change, numbers first to last.
    use Oneiroi.Event, version: 1, fields: [:id, :order]
  end

  defmodule WorkWrapped do
    # The wrap a run closes with: what shipped, what slipped and why, and
    # where the item stands after it.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :shipped, :slipped, :why, :status, :blocked_on]
  end

  defmodule WorkStarted do
    # A run of an item claimed, in its conversation, on the resident's day.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :session_key, :day]
  end

  defmodule WorkRunEnded do
    # The run over: whether it was wrapped, the item's status after (an
    # unwrapped run leaves it open), and whether a stop ended it (brain#61),
    # which rests the loop until either party touches the queue.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :wrapped, :status, :stopped]
  end

  defmodule WorkRested do
    # The loop resting, and why: "empty, holding" is a state, not a failure.
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end
end
