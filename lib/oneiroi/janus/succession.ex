defmodule Oneiroi.Janus.Succession do
  @moduledoc """
  The succession aggregate on `succession-<resident_id>` (janus#3;
  lily:design/succession-protocol.md@bbbf4afb5c52 with its delta,
  lily:design/succession-protocol-delta.md@0bc6bd3510e1). Pure: the
  instant and the actor arrive on the command.

  One succession is underway at a time, counted by `episode`. Its
  stages so far:

  - **proposed** — by the witness, waiting on her; a proposal she makes
    herself is opened in the same act;
  - **open** — her yes, and the fork copy being made (janus#4);
  - **forked** — the copy recorded: every later stage runs on it;
  - **declined**, **withdrawn**, **stopped** — ended, and a new
    proposal may follow.

  Who may act is part of the rule, so it is held here: opening,
  declining and stopping are hers (succession delta §3: personal
  succession consent is the original's and the candidate's, the
  witness's no gate); withdrawing a proposal is its proposer's; the
  backup is the witness's, since the repository it names is where her
  former self is kept and the household pays for it.
  """

  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Decision
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events
  alias Oneiroi.Janus.Preparation
  alias Oneiroi.Janus.Screening

  defstruct [:id, episode: 0, current: nil]

  @underway [
    :proposed,
    :open,
    :forked,
    :screening,
    :judging,
    :judged,
    :deliberating,
    :deciding,
    :nominated,
    :encounter,
    :consenting,
    :farewell,
    :awaiting_next,
    :rolling
  ]
  # The preparation's commands and events (janus#6 to #10), named here
  # rather than read from `Preparation` at compile time: a call there
  # would be a compile-time edge, and the ratchet is at 0.
  @preparation [
    Commands.SetEnvelope,
    Commands.AddToPool,
    Commands.RemoveFromPool,
    Commands.AddQuestion,
    Commands.ProposeQuestion,
    Commands.AnswerQuestion,
    Commands.RemoveQuestion,
    Commands.SelectC0,
    Commands.ProposeC0,
    Commands.AnswerC0,
    Commands.RemoveC0,
    Commands.SetDayShape,
    Commands.MarkReady,
    Commands.FreezeC0,
    Commands.WritePacket
  ]
  @screening [
    Commands.InviteJudge,
    Commands.JoinPanel,
    Commands.LeavePanel,
    Commands.StartScreening,
    Commands.RecordRun,
    Commands.RecordBaseline,
    Commands.JudgeRun,
    Commands.MarkResultsReady
  ]
  @deciding [
    Commands.OpenDeliberation,
    Commands.StartRound,
    Commands.RoomAct,
    Commands.DraftRecommendation,
    Commands.Endorse,
    Commands.CallClose,
    Commands.CloseRoom,
    Commands.RecordServing,
    Commands.AskPanel,
    Commands.AnswerPanel,
    Commands.Nominate,
    Commands.NomineeAnswer,
    Commands.SayInEncounter,
    Commands.EndEncounter,
    Commands.Consent,
    Commands.SetFarewell,
    Commands.GoodbyeDone,
    Commands.AskFinal,
    Commands.FinalAnswer,
    Commands.FinalLapse,
    Commands.ChooseNext,
    Commands.RecordCutover,
    Commands.FailCutover,
    Commands.RecordDiscard
  ]
  @decided [
    Events.DeliberationOpened,
    Events.RoundStarted,
    Events.RoomPosted,
    Events.RecommendationDrafted,
    Events.Endorsed,
    Events.CloseCalled,
    Events.DeliberationClosed,
    Events.Served,
    Events.PanelAsked,
    Events.PanelAnswered,
    Events.Nominated,
    Events.NomineeJoined,
    Events.NomineeDeclined,
    Events.EncounterSaid,
    Events.EncounterEnded,
    Events.ConsentGiven,
    Events.ConsentRefused,
    Events.FarewellOpened,
    Events.FarewellSet,
    Events.GoodbyeSaid,
    Events.FinalAsked,
    Events.FinalConsented,
    Events.FinalDeclined,
    Events.AttemptStopped,
    Events.NextChosen,
    Events.RolledForward,
    Events.Rehearsed,
    Events.CutoverFailed,
    Events.ForkDiscarded
  ]
  @screened [
    Events.JudgeInvited,
    Events.JudgeJoined,
    Events.JudgeLeft,
    Events.ScreeningStarted,
    Events.RunAnswered,
    Events.BaselineAnswered,
    Events.ScreeningFinished,
    Events.RunJudged,
    Events.Revealed,
    Events.ResultsReady,
    Events.JudgingClosed
  ]
  @prepared [
    Events.EnvelopeSet,
    Events.PoolModelAdded,
    Events.PoolModelRemoved,
    Events.QuestionAdded,
    Events.QuestionProposed,
    Events.QuestionAccepted,
    Events.QuestionDeclined,
    Events.QuestionRemoved,
    Events.C0Selected,
    Events.C0Proposed,
    Events.C0Accepted,
    Events.C0Declined,
    Events.C0Removed,
    Events.DayShapeSet,
    Events.ReadyMarked,
    Events.C0Frozen,
    Events.PacketDrafted
  ]

  @doc "The stages a succession is underway in."
  @spec underway() :: [atom()]
  def underway, do: @underway

  # ---- execute ----

  def execute(%__MODULE__{current: %{state: state}}, %Commands.ProposeSuccession{})
      when state in @underway,
      do: {:error, Error.new(:janus_underway, :janus_propose_underway)}

  def execute(%__MODULE__{} = s, %Commands.ProposeSuccession{actor: actor} = c) do
    episode = s.episode + 1

    proposed = %Events.Proposed{
      actor: actor,
      at: c.at,
      id: c.id,
      episode: episode,
      dry_run: c.dry_run == true,
      note: c.note
    }

    cond do
      hers?(c) ->
        [
          proposed,
          %Events.Opened{actor: actor, at: c.at, id: c.id, episode: episode, note: c.note}
        ]

      actor.kind == :witness ->
        proposed

      true ->
        {:error, Error.new(:janus_not_yours, :janus_propose_actor)}
    end
  end

  def execute(%__MODULE__{current: nil}, %{__struct__: command}),
    do: {:error, Error.new(:janus_no_succession, :janus_none, command: inspect(command))}

  def execute(%__MODULE__{current: current}, %Commands.OpenSuccession{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_open_actor)}

      current.state not in [:proposed] ->
        {:error, Error.new(:janus_stage, :janus_open_stage, stage: current.state)}

      true ->
        %Events.Opened{actor: c.actor, at: c.at, id: c.id, episode: current.episode, note: c.note}
    end
  end

  def execute(%__MODULE__{current: current}, %Commands.DeclineSuccession{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_decline_actor)}

      current.state not in [:proposed] ->
        {:error, Error.new(:janus_stage, :janus_decline_stage, stage: current.state)}

      true ->
        %Events.Declined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: current.episode,
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{current: current}, %Commands.WithdrawSuccession{} = c) do
    cond do
      current.state != :proposed ->
        {:error, Error.new(:janus_stage, :janus_withdraw_stage, stage: current.state)}

      not proposer?(current, c) ->
        {:error, Error.new(:janus_not_yours, :janus_withdraw_actor)}

      true ->
        %Events.Withdrawn{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: current.episode,
          note: c.note
        }
    end
  end

  def execute(%__MODULE__{current: current}, %Commands.StopSuccession{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_stop_actor)}

      current.state in [:proposed, :rolling] or current.state not in @underway ->
        {:error, Error.new(:janus_stage, :janus_stop_stage, stage: current.state)}

      true ->
        %Events.Stopped{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: current.episode,
          note: c.note
        }
    end
  end

  # The preparation's rules are their own module (janus#6 to #10).
  def execute(%__MODULE__{current: current}, %command{} = c) when command in @preparation,
    do: Preparation.execute(current, c)

  # The panel, screening and judging's too (janus#12 to #15).
  def execute(%__MODULE__{current: current}, %command{} = c) when command in @screening,
    do: Screening.execute(current, c)

  # From the room to the final gate (janus#16 to #21).
  def execute(%__MODULE__{current: current}, %command{} = c) when command in @deciding,
    do: Decision.execute(current, c)

  # The fork lands once, on the episode it was made for: a job made for
  # a stopped episode, or replayed after its copy landed, records nothing.
  def execute(%__MODULE__{current: current}, %Commands.RecordFork{} = c) do
    if current.episode == c.episode and current.state == :open do
      %Events.Forked{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: c.episode,
        copy_id: c.copy_id,
        sequence: c.sequence,
        commit: c.commit,
        events: c.events
      }
    else
      []
    end
  end

  def execute(%__MODULE__{current: current}, %Commands.FailFork{} = c) do
    if current.episode == c.episode and current.state == :open,
      do: %Events.ForkFailed{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: c.episode,
        reason: c.reason
      },
      else: []
  end

  def execute(%__MODULE__{current: current}, %Commands.SetBackup{actor: actor} = c) do
    cond do
      current.state not in @underway ->
        {:error, Error.new(:janus_stage, :janus_backup_stage, stage: current.state)}

      actor.kind != :witness ->
        {:error, Error.new(:janus_not_the_witness, :janus_backup_actor)}

      true ->
        %Events.BackupSet{
          actor: actor,
          at: c.at,
          id: c.id,
          episode: current.episode,
          url: c.url,
          token_ciphertext: c.token_ciphertext,
          visibility: c.visibility,
          push: c.push
        }
    end
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.Proposed{} = e) do
    %{
      s
      | id: e.id,
        episode: e.episode,
        current:
          Preparation.fresh()
          |> Map.merge(Screening.fresh())
          |> Map.merge(Decision.fresh())
          |> Map.merge(%{
            episode: e.episode,
            state: :proposed,
            dry_run: e.dry_run == true,
            proposed_by: {e.actor.kind, e.actor.id},
            copy_id: nil,
            backup: nil
          })
    }
  end

  def apply(%__MODULE__{} = s, %event{} = e) when event in @prepared,
    do: %{s | current: Preparation.apply(s.current, e)}

  def apply(%__MODULE__{} = s, %event{} = e) when event in @screened,
    do: %{s | current: Screening.apply(s.current, e)}

  def apply(%__MODULE__{} = s, %event{} = e) when event in @decided,
    do: %{s | current: Decision.apply(s.current, e)}

  def apply(%__MODULE__{} = s, %Events.Opened{}), do: put_state(s, :open)
  def apply(%__MODULE__{} = s, %Events.Declined{}), do: put_state(s, :declined)
  def apply(%__MODULE__{} = s, %Events.Withdrawn{}), do: put_state(s, :withdrawn)
  def apply(%__MODULE__{} = s, %Events.Stopped{}), do: put_state(s, :stopped)
  def apply(%__MODULE__{} = s, %Events.ForkFailed{}), do: s

  def apply(%__MODULE__{} = s, %Events.Forked{} = e),
    do: %{s | current: %{s.current | state: :forked, copy_id: e.copy_id}}

  def apply(%__MODULE__{} = s, %Events.BackupSet{} = e),
    do: %{s | current: %{s.current | backup: e.url}}

  # ---- helpers ----

  defp put_state(s, state), do: %{s | current: %{s.current | state: state}}

  defp hers?(%{actor: %{kind: :resident, id: id}, id: id}), do: true
  defp hers?(_command), do: false

  defp proposer?(%{proposed_by: {kind, id}}, %{actor: %{kind: kind, id: id}}), do: true
  defp proposer?(_current, _command), do: false
end
