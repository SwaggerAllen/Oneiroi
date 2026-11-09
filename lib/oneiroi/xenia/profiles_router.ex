defmodule Oneiroi.Xenia.ProfilesRouter do
  @moduledoc "The profiles ledger's router: `profiles-<resident_id>` (xenia#19)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Xenia.ProfilesLedger",
    prefix: "profiles-",
    commands: "Oneiroi.Xenia.Commands",
    dispatching: ~w(SetProfile RevokeProfile RestoreProfile)
end
