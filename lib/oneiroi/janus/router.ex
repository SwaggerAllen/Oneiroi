defmodule Oneiroi.Janus.Router do
  @moduledoc "The succession's router: `succession-<resident_id>` (janus#3)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Janus.Succession",
    prefix: "succession-",
    commands: "Oneiroi.Janus.Commands",
    dispatching:
      ~w(ProposeSuccession OpenSuccession DeclineSuccession WithdrawSuccession StopSuccession RecordFork FailFork SetBackup SetEnvelope AddToPool RemoveFromPool AddQuestion ProposeQuestion AnswerQuestion RemoveQuestion SelectC0 ProposeC0 AnswerC0 RemoveC0 SetDayShape MarkReady FreezeC0 WritePacket)
end
