defmodule Oneiroi.Sunna.WorkRouter do
  @moduledoc "The work line aggregate's router (sunna#33, #102): `work-<resident_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Sunna.Work",
    prefix: "work-",
    commands: "Oneiroi.Sunna.Commands",
    dispatching:
      ~w(RestWork ResetWorkRuns ResetActivityRuns SkipCareWait ResumeWork StartActivityRun EndActivityRun)
end
