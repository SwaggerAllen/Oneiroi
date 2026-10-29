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
    # time today is not missed today, it waits for tomorrow.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :label, :time, :day]
  end

  defmodule CheckinChanged do
    # Carries the day it was changed on, so one changed after its time
    # today waits for tomorrow (spec §6.7).
    use Oneiroi.Event, version: 1, fields: [:id, :key, :label, :time, :day]
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
    use Oneiroi.Event, version: 1, fields: [:id, :time]
  end

  defmodule FreeTimeRan do
    use Oneiroi.Event, version: 1, fields: [:id, :day, :session_key]
  end

  defmodule FreeTimeFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :day, :reason]
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

  defmodule DateRemoved do
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end
end
