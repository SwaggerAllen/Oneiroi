defmodule Oneiroi.Xenia.Router do
  @moduledoc "The correspondence aggregate's router: `xenia-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Xenia.Correspondence",
    prefix: "xenia-",
    commands: "Oneiroi.Xenia.Commands",
    dispatching:
      ~w(ReceiveMessage BlockCorrespondent UnblockCorrespondent MarkMessages DraftReply DecideReply MarkReplySent SetReaderSites)
end
