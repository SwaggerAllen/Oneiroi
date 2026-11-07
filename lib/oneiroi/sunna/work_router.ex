defmodule Oneiroi.Sunna.WorkRouter do
  @moduledoc "The work queue aggregate's router (sunna#33): `work-<resident_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Sunna.Work",
    prefix: "work-",
    commands: "Oneiroi.Sunna.Commands",
    dispatching:
      ~w(AddWork MoveWork OrderWork WrapWork StartWork EndWork RestWork ArmWork DisarmWork)
end
