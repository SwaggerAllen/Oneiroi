defmodule Oneiroi.Gaia.PlatformRouter do
  @moduledoc "The platform aggregate's router (gaia#16): `platform-platform`, the front door and the roles."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Platform",
    prefix: "platform-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching: ~w(SetGate SetTriageResident GrantRole RevokeRole RecordBoot)
end
