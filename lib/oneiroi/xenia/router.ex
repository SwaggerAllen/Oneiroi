defmodule Oneiroi.Xenia.Router do
  @moduledoc "The correspondence aggregate's router: `xenia-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Xenia.Correspondence",
    prefix: "xenia-",
    commands: "Oneiroi.Xenia.Commands",
    dispatching:
      ~w(ReceiveMessage DecideMessage TrustCorrespondent DistrustCorrespondent MarkMessages DraftReply DecideReply MarkReplySent)
end
