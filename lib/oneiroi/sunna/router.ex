defmodule Oneiroi.Sunna.Router do
  @moduledoc "The schedule aggregate's router: `schedule-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Sunna.Schedule",
    prefix: "schedule-",
    commands: "Oneiroi.Sunna.Commands",
    dispatching:
      ~w(SetCheckin DeleteCheckin FireCheckin MissCheckin DeferWake OpenDay SetFreeTime RecordFreeTime SetQuietHours SetDate RemoveDate)
end
