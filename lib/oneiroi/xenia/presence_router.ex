defmodule Oneiroi.Xenia.PresenceRouter do
  @moduledoc "The presence ledger's router: `presence-<resident_id>` (xenia#20)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Xenia.PresenceLedger",
    prefix: "presence-",
    commands: "Oneiroi.Xenia.Commands",
    dispatching:
      ~w(SetPresence RecordFollows ExcludeAccount IncludeAccount DrawPass ReadItem StageInteraction DecideInteraction MarkInteractionSent FailInteraction)
end
