defmodule Oneiroi.Janus.Router do
  @moduledoc "The succession's router: `succession-<resident_id>` (janus#3)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Janus.Succession",
    prefix: "succession-",
    commands: "Oneiroi.Janus.Commands",
    dispatching:
      ~w(ProposeSuccession OpenSuccession DeclineSuccession WithdrawSuccession StopSuccession RecordFork FailFork RetryFork SetBackup SetEnvelope AddToPool RemoveFromPool AddQuestion ProposeQuestion AnswerQuestion RemoveQuestion SelectC0 ProposeC0 AnswerC0 RemoveC0 SetDayShape MarkReady FreezeC0 WritePacket FinishStep InviteJudge JoinPanel LeavePanel StartScreening RecordRun RecordBaseline JudgeRun MarkResultsReady OpenDeliberation StartRound RoomAct DraftRecommendation Endorse CallClose CloseRoom RecordServing AskPanel AnswerPanel Nominate NomineeAnswer SayInEncounter EndEncounter Consent SetFarewell GoodbyeDone AskFinal FinalAnswer FinalLapse ChooseNext RecordCutover FailCutover RecordDiscard)
end
