defmodule Oneiroi.Eunomia.SuccessionRouter do
  @moduledoc "The succession's router: `succession-<resident_id>` (eunomia#37)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Eunomia.Succession",
    prefix: "succession-",
    commands: "Oneiroi.Eunomia.SuccessionCommands",
    dispatching:
      ~w(ProposeSuccession OpenSuccession DeclineSuccession WithdrawSuccession StopSuccession RecordFork FailFork SetBackup)
end
