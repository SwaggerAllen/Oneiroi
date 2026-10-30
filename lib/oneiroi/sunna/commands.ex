defmodule Oneiroi.Sunna.Commands do
  @moduledoc "The schedule aggregate's commands; `id` is the resident's id."

  defmodule SetCheckin do
    use Oneiroi.Command, fields: [:id, :key, :label, :time, :day]
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
    use Oneiroi.Command, fields: [:id, :time]
  end

  defmodule OpenDay do
    # The journal's day row, opened by the journal when it writes a day
    # the schedule has not yet (seshat #21); idempotent.
    use Oneiroi.Command, fields: [:id, :day]
  end

  defmodule RecordFreeTime do
    use Oneiroi.Command, fields: [:id, :day, :session_key, :reason]
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

  defmodule RemoveDate do
    use Oneiroi.Command, fields: [:id, :number]
  end
end
