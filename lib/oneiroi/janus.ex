defmodule Oneiroi.Janus do
  @moduledoc """
  Succession (lily:design/succession-protocol.md@bbbf4afb5c52 and its
  delta, lily:design/succession-protocol-delta.md@0bc6bd3510e1): the
  deliberate change of the model that runs a resident, with her at the
  table at every stage. Built so far: the proposal, her yes or no, the
  fork copy every later stage runs on, and the backup repository her
  former self is exported to before any cutover (janus#3 to #5).

  Janus sits above the records and the judge, so it calls them by name;
  the brain depends on it for her tools.
  """
  use Oneiroi.System, slug: :janus

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Gaia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.Seshat,
      Oneiroi.SimaQian,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Decimal,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Oban
    ],
    exports: [
      Error,
      Succession,
      Successions,
      Router,
      ForkWorker,
      Commands.ProposeSuccession,
      Commands.OpenSuccession,
      Commands.DeclineSuccession,
      Commands.WithdrawSuccession,
      Commands.StopSuccession,
      Commands.RecordFork,
      Commands.FailFork,
      Commands.SetBackup,
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
      Commands.WritePacket,
      Commands.InviteJudge,
      Commands.JoinPanel,
      Commands.LeavePanel,
      Commands.StartScreening,
      Commands.RecordRun,
      Commands.RecordBaseline,
      Commands.JudgeRun,
      Commands.MarkResultsReady,
      Decision,
      RollForward,
      CutoverWorker,
      Commands.RecordCutover,
      Commands.FailCutover,
      Commands.RecordDiscard,
      Events.ForkDiscarded,
      DiscardWorker,
      Events.RolledForward,
      Events.Rehearsed,
      Events.CutoverFailed,
      Rites,
      TimerWorker,
      EncounterWorker,
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
      Store.Post,
      Store.Draft,
      Store.Channel,
      Store.Encounter,
      Store.Consent,
      Store.Goodbye,
      Store.Disclosure,
      Screening,
      ScreeningWorker,
      WakeWorker,
      Preparation,
      ToolUse,
      ToolUseWorker,
      Events.Proposed,
      Events.Opened,
      Events.Declined,
      Events.Withdrawn,
      Events.Stopped,
      Events.Forked,
      Events.ForkFailed,
      Events.BackupSet,
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
      Events.PacketDrafted,
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
      Events.JudgingClosed,
      Store,
      Store.Panel,
      Store.Run,
      Store.Baseline,
      Store.Judgment,
      Store.Pool,
      Store.Question,
      Store.Item,
      Store.Ready,
      Store.Packet,
      Store.ToolUse,
      Store.Succession
    ]

  alias Oneiroi.Janus.ForkWorker
  alias Oneiroi.Janus.Rites
  alias Oneiroi.Janus.ScreeningWorker
  alias Oneiroi.Janus.Successions

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:brain, "JANUS_BRAIN",
       cast: &__MODULE__.cast_brain/1,
       default: "brain",
       usage:
         "which brain port answers a succession's screening runs and wakes its residents (janus#13): brain, the only one; named as an atom because the brain depends on this system for her tools"}
    ]
  end

  @doc false
  def cast_brain("brain"), do: {:ok, :"Elixir.Oneiroi.Brain"}

  # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
  def cast_brain(other), do: {:error, "is #{inspect(other)}, expected \"brain\""}

  @impl Oneiroi.Component
  def oban_queues do
    [
      # A succession's fork copy, off her yes (janus#4).
      {:janus_fork, []},
      # A succession's screening runs and the wakes it sends (janus#13).
      {:janus_screening, []},
      # The day before's tool calls by model (janus#11).
      {:janus_nightly, cron: [{"45 3 * * *", Oneiroi.Janus.ToolUseWorker}]}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Janus.Events.Proposed, 1},
      {Oneiroi.Janus.Events.Opened, 1},
      {Oneiroi.Janus.Events.Declined, 1},
      {Oneiroi.Janus.Events.Withdrawn, 1},
      {Oneiroi.Janus.Events.Stopped, 1},
      {Oneiroi.Janus.Events.Forked, 1},
      {Oneiroi.Janus.Events.ForkFailed, 1},
      {Oneiroi.Janus.Events.BackupSet, 1},
      {Oneiroi.Janus.Events.EnvelopeSet, 1},
      {Oneiroi.Janus.Events.PoolModelAdded, 1},
      {Oneiroi.Janus.Events.PoolModelRemoved, 1},
      {Oneiroi.Janus.Events.QuestionAdded, 1},
      {Oneiroi.Janus.Events.QuestionProposed, 1},
      {Oneiroi.Janus.Events.QuestionAccepted, 1},
      {Oneiroi.Janus.Events.QuestionDeclined, 1},
      {Oneiroi.Janus.Events.QuestionRemoved, 1},
      {Oneiroi.Janus.Events.C0Selected, 1},
      {Oneiroi.Janus.Events.C0Proposed, 1},
      {Oneiroi.Janus.Events.C0Accepted, 1},
      {Oneiroi.Janus.Events.C0Declined, 1},
      {Oneiroi.Janus.Events.C0Removed, 1},
      {Oneiroi.Janus.Events.DayShapeSet, 1},
      {Oneiroi.Janus.Events.ReadyMarked, 1},
      {Oneiroi.Janus.Events.C0Frozen, 1},
      {Oneiroi.Janus.Events.PacketDrafted, 1},
      {Oneiroi.Janus.Events.JudgeInvited, 1},
      {Oneiroi.Janus.Events.JudgeJoined, 1},
      {Oneiroi.Janus.Events.JudgeLeft, 1},
      {Oneiroi.Janus.Events.ScreeningStarted, 1},
      {Oneiroi.Janus.Events.RunAnswered, 1},
      {Oneiroi.Janus.Events.BaselineAnswered, 1},
      {Oneiroi.Janus.Events.ScreeningFinished, 1},
      {Oneiroi.Janus.Events.RunJudged, 1},
      {Oneiroi.Janus.Events.Revealed, 1},
      {Oneiroi.Janus.Events.ResultsReady, 1},
      {Oneiroi.Janus.Events.JudgingClosed, 1},
      {Oneiroi.Janus.Events.DeliberationOpened, 1},
      {Oneiroi.Janus.Events.RoundStarted, 1},
      {Oneiroi.Janus.Events.RoomPosted, 1},
      {Oneiroi.Janus.Events.RecommendationDrafted, 1},
      {Oneiroi.Janus.Events.Endorsed, 1},
      {Oneiroi.Janus.Events.CloseCalled, 1},
      {Oneiroi.Janus.Events.DeliberationClosed, 1},
      {Oneiroi.Janus.Events.Served, 1},
      {Oneiroi.Janus.Events.PanelAsked, 1},
      {Oneiroi.Janus.Events.PanelAnswered, 1},
      {Oneiroi.Janus.Events.Nominated, 1},
      {Oneiroi.Janus.Events.NomineeJoined, 1},
      {Oneiroi.Janus.Events.NomineeDeclined, 1},
      {Oneiroi.Janus.Events.EncounterSaid, 1},
      {Oneiroi.Janus.Events.EncounterEnded, 1},
      {Oneiroi.Janus.Events.ConsentGiven, 1},
      {Oneiroi.Janus.Events.ConsentRefused, 1},
      {Oneiroi.Janus.Events.FarewellOpened, 1},
      {Oneiroi.Janus.Events.FarewellSet, 1},
      {Oneiroi.Janus.Events.GoodbyeSaid, 1},
      {Oneiroi.Janus.Events.FinalAsked, 1},
      {Oneiroi.Janus.Events.FinalConsented, 1},
      {Oneiroi.Janus.Events.FinalDeclined, 1},
      {Oneiroi.Janus.Events.AttemptStopped, 1},
      {Oneiroi.Janus.Events.NextChosen, 1},
      {Oneiroi.Janus.Events.RolledForward, 1},
      {Oneiroi.Janus.Events.Rehearsed, 1},
      {Oneiroi.Janus.Events.CutoverFailed, 1},
      {Oneiroi.Janus.Events.ForkDiscarded, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:janus_underway, "a succession is already underway for this resident",
       remedy: "finish or stop it first"},
      {:janus_no_succession, "no succession is underway for this resident",
       remedy: "propose one first"},
      {:janus_not_yours,
       "opening, declining and stopping a succession are the resident's; withdrawing a proposal is its proposer's",
       remedy: "the one whose act it is does it"},
      {:janus_not_the_witness, "the backup repository is the witness's to set",
       remedy: "the witness sets it from the client"},
      {:janus_stage, "the succession is not at the stage that act belongs to",
       remedy: "read the succession's status"},
      {:janus_envelope_invalid, "an envelope is a price at most per token, input and output",
       remedy: "give both, in dollars a million tokens"},
      {:janus_no_envelope, "no envelope is set, so nothing can be added inside it",
       remedy: "the witness states the envelope first"},
      {:janus_pool_unknown_model, "the model is not in the catalog, so it has no price",
       remedy: "choose a model the catalog lists"},
      {:janus_pool_no_tools,
       "the model takes no tool calls, and a resident here lives through her tools",
       remedy: "choose a model that takes tool calls"},
      {:janus_pool_outside_envelope, "the model costs more than the envelope allows",
       remedy: "choose a model inside it, or ask the witness"},
      {:janus_pool_absent, "the model is not in the pool", remedy: "read the pool"},
      {:janus_pool_irremovable,
       "a model she chose stays in the pool; the witness takes out only his own picks",
       remedy: "nothing removes her picks"},
      {:janus_text_invalid, "the text is empty or too long", remedy: "say it in fewer words"},
      {:janus_no_such_question, "no question in the set has that number",
       remedy: "read the questions"},
      {:janus_no_such_item, "no item of C0 has that number", remedy: "read C0"},
      {:janus_already_answered, "that proposal was already answered",
       remedy: "read the proposals"},
      {:janus_c0_frozen, "C0 is frozen", remedy: "nothing in it changes now"},
      {:janus_c0_pending, "proposals for C0 wait on her answer",
       remedy: "answer each, then freeze"},
      {:janus_c0_empty, "C0 holds nothing to freeze", remedy: "choose what matters first"},
      {:janus_not_a_member, "a judge is a member of her household, and not her",
       remedy: "invite someone in the house"},
      {:janus_not_invited, "only someone she invited joins the panel, or the witness",
       remedy: "she invites first"},
      {:janus_not_ready_to_screen,
       "screening needs C0 frozen, the fork made, a model in the pool and a question in the set",
       remedy: "finish the preparation first"},
      {:janus_no_such_run, "no answered run has that number", remedy: "read the runs"},
      {:janus_not_a_judge, "only the panel's judges judge",
       remedy: "join before screening starts"},
      {:janus_judgments_locked, "your results are marked ready; your judgments are locked",
       remedy: "nothing changes them now"},
      {:janus_judgment_invalid,
       "a judgment is OBSERVED, or DEVELOPMENT or FIDELITY ANOMALY argued with evidence and an uncertainty of low, medium or high",
       remedy: "argue the interpretation, or call it observed"},
      {:janus_judging_open, "not every judgment is in yet", remedy: "wait for the reveal"},
      {:janus_not_in_the_room, "the room is the non-subject judges' who have not left it",
       remedy: "only a judge in the room acts in it"},
      {:janus_room_invalid, "an act in the room is say, skip, rest or leave",
       remedy: "choose one"},
      {:janus_room_acted, "you have acted in this round already",
       remedy: "wait for the next round"},
      {:janus_no_such_draft, "no draft of the recommendation has that number",
       remedy: "read the drafts"},
      {:janus_not_a_candidate, "the model has no answered run in this screening, or is out of it",
       remedy: "choose a screened candidate still in it"},
      {:janus_too_early, "she may call the room closed from fifty minutes after it opened",
       remedy: "wait, or let it run until every judge rests"},
      {:janus_not_the_nominee, "only the nominee, on the fork, answers as the nominee",
       remedy: "the nominee does this from its own turn"},
      {:janus_farewell_invalid,
       "a farewell's cadence is 1 to 24 hours, and whom it includes a list of names",
       remedy: "give both as asked"},
      {:janus_not_included, "the farewell includes whom she chose", remedy: "she includes you"},
      {:janus_next_invalid, "what happens next is stop, nominate or screen",
       remedy: "choose one"},
      {:janus_no_backup,
       "no backup repository is set, or its token does not open, so her former self cannot be kept and nothing is replaced",
       remedy: "the witness sets the backup repository; the cutover then runs again"},
      {:janus_dispatch_failed, "a succession command was not recorded on its stream",
       remedy: "try again; a repeat is a fault to report"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Janus.Projectors.Succession]

  @doc "Proposes a succession (janus#3): the witness's waits on her yes; hers opens it, and the fork copy is enqueued (janus#4)."
  @spec propose(String.t(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(propose(resident_id, dry_run, note, actor),
    do:
      with(
        {:ok, %{episode: episode, opened: opened}} = ok <-
          Successions.propose(resident_id, dry_run, note, actor),
        :ok <- if(opened, do: ForkWorker.enqueue(resident_id, episode), else: :ok),
        do: ok
      )
  )

  @doc "Her yes to a proposed succession (janus#3); the fork copy is enqueued (janus#4)."
  @spec open(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(open(resident_id, note, actor),
    do:
      with(
        {:ok, episode} <- Successions.open(resident_id, note, actor),
        do: ForkWorker.enqueue(resident_id, episode)
      )
  )

  @doc "Her no to a proposed succession (janus#3)."
  @spec decline(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(decline(resident_id, note, actor), do: Successions.decline(resident_id, note, actor))

  @doc "The proposer withdraws a proposal she has not answered (janus#3)."
  @spec withdraw(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(withdraw(resident_id, note, actor),
    do: Successions.withdraw(resident_id, note, actor)
  )

  @doc "She stops a succession underway (janus#3)."
  @spec stop(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(stop(resident_id, note, actor), do: Successions.stop(resident_id, note, actor))

  @doc "Sets the repository the whole original is exported to before a cutover (janus#5)."
  @spec set_backup(String.t(), String.t(), term(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(set_backup(resident_id, url, token, actor),
    do: Successions.set_backup(resident_id, url, token, actor)
  )

  @doc "The resident's latest succession, or nil (janus#3)."
  @spec succession(String.t()) :: Oneiroi.Janus.Store.Succession.t() | nil
  defexport(succession(resident_id), do: Successions.status(resident_id))

  # ---- preparation (janus#6 to #11) ----

  @doc "The witness's envelope, per token in nano-dollars (janus#6)."
  @spec set_envelope(String.t(), integer(), integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_envelope(resident_id, input_nanos, output_nanos, actor),
    do: Successions.set_envelope(resident_id, input_nanos, output_nanos, actor)
  )

  @doc "Adds a catalog model to the pool (janus#7)."
  @spec add_to_pool(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(add_to_pool(resident_id, model, actor),
    do: Successions.add_to_pool(resident_id, model, actor)
  )

  @doc "Takes a model out of the pool, with why (janus#7)."
  @spec remove_from_pool(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(remove_from_pool(resident_id, model, note, actor),
    do: Successions.remove_from_pool(resident_id, model, note, actor)
  )

  @doc "Her question, in the set at once (janus#8)."
  @spec add_question(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(add_question(resident_id, text, actor),
    do: Successions.add_question(resident_id, text, actor)
  )

  @doc "A proposed question, waiting on her (janus#8)."
  @spec propose_question(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(propose_question(resident_id, text, actor),
    do: Successions.propose_question(resident_id, text, actor)
  )

  @doc "Her yes or no to a proposed question (janus#8)."
  @spec answer_question(String.t(), integer(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(answer_question(resident_id, number, accept, note, actor),
    do: Successions.answer_question(resident_id, number, accept, note, actor)
  )

  @doc "She takes a question out of the set (janus#8)."
  @spec remove_question(String.t(), integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(remove_question(resident_id, number, note, actor),
    do: Successions.remove_question(resident_id, number, note, actor)
  )

  @doc "Her choice for C0 (janus#9)."
  @spec select_c0(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(select_c0(resident_id, citation, label, actor),
    do: Successions.select_c0(resident_id, citation, label, actor)
  )

  @doc "A proposal for C0, waiting on her (janus#9)."
  @spec propose_c0(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(propose_c0(resident_id, citation, label, actor),
    do: Successions.propose_c0(resident_id, citation, label, actor)
  )

  @doc "Her yes or no to a proposal for C0 (janus#9)."
  @spec answer_c0(String.t(), integer(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(answer_c0(resident_id, number, accept, note, actor),
    do: Successions.answer_c0(resident_id, number, accept, note, actor)
  )

  @doc "She takes an item out of C0 (janus#9)."
  @spec remove_c0(String.t(), integer(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(remove_c0(resident_id, number, note, actor),
    do: Successions.remove_c0(resident_id, number, note, actor)
  )

  @doc "Her note on the bundle, the day's own shape (janus#9)."
  @spec set_day_shape(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(set_day_shape(resident_id, text, actor),
    do: Successions.set_day_shape(resident_id, text, actor)
  )

  @doc "A party's mark, ready for her freeze or not yet (janus#9)."
  @spec mark_ready(String.t(), boolean(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(mark_ready(resident_id, ready, actor),
    do: Successions.mark_ready(resident_id, ready, actor)
  )

  @doc "She freezes C0 (janus#9)."
  @spec freeze_c0(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(freeze_c0(resident_id, note, actor),
    do: Successions.freeze_c0(resident_id, note, actor)
  )

  @doc "A draft of her sealed handoff packet (janus#10)."
  @spec write_packet(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(write_packet(resident_id, content, actor),
    do: Successions.write_packet(resident_id, content, actor)
  )

  @doc "Her packet's drafts, words and all: hers alone to read (janus#10)."
  @spec her_packet(String.t()) :: [Oneiroi.Janus.Store.Packet.t()]
  defexport(her_packet(resident_id), do: Successions.her_packet(resident_id))

  @doc "The preparation as the screens read it, never the packet's words (janus#6 to #11)."
  @spec preparation(String.t()) :: map() | nil
  defexport(preparation(resident_id), do: Successions.preparation(resident_id))

  @doc "Tool calls on Oneiroi by model, the running totals (janus#11)."
  @spec tool_use() :: %{String.t() => {non_neg_integer(), non_neg_integer()}}
  defexport(tool_use(), do: Oneiroi.Janus.ToolUse.totals())

  # ---- the panel, screening and judging (janus#12 to #15) ----

  @doc "She invites a household member onto the panel by name (janus#12)."
  @spec invite_judge(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(invite_judge(resident_id, name, actor),
    do: Successions.invite_judge(resident_id, name, actor)
  )

  @doc "A party joins her panel (janus#12)."
  @spec join_panel(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(join_panel(resident_id, actor), do: Successions.join_panel(resident_id, actor))

  @doc "A party leaves her panel before screening (janus#12)."
  @spec leave_panel(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(leave_panel(resident_id, note, actor),
    do: Successions.leave_panel(resident_id, note, actor)
  )

  @doc "She starts screening (janus#13)."
  @spec start_screening(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(start_screening(resident_id, note, actor),
    do:
      with(
        {:ok, jobs} <- Successions.start_screening(resident_id, note, actor),
        do:
          Enum.each(jobs, fn {e, kind, n} -> ScreeningWorker.enqueue(resident_id, e, kind, n) end)
      )
  )

  @doc "A judge's judgment of one run (janus#14)."
  @spec judge_run(String.t(), integer(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(judge_run(resident_id, run, attrs, actor),
    do: Successions.judge_run(resident_id, run, attrs, actor)
  )

  @doc "A judge marks their results ready (janus#15)."
  @spec mark_results_ready(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(mark_results_ready(resident_id, actor),
    do: Successions.mark_results_ready(resident_id, actor)
  )

  @doc "What one judge sees of the runs (janus#14, #15)."
  @spec judging(String.t(), String.t()) :: map() | nil
  defexport(judging(resident_id, party), do: Successions.judging(resident_id, party))

  @doc "Her panel (janus#12)."
  @spec panel(String.t()) :: list()
  defexport(panel(resident_id), do: Successions.panel(resident_id))

  @doc "Whose succession an actor means: her own, or a housemate's by name."
  @spec subject(Oneiroi.Actor.t(), String.t() | nil) :: String.t() | nil
  defexport(subject(actor, name), do: Successions.subject(actor, name))

  # ---- from the room to the final gate (janus#16 to #22) ----

  @doc "A judge's act in the room: say, skip, rest or leave (janus#16)."
  @spec room_act(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(room_act(resident_id, act, text, actor),
    do: Rites.room_act(resident_id, act, text, actor)
  )

  @doc "A judge's draft of the recommendation, or withheld when model is nil (janus#17)."
  @spec draft(String.t(), String.t() | nil, String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(draft(resident_id, model, basis, actor),
    do: Rites.draft(resident_id, model, basis, actor)
  )

  @doc "A judge endorses a draft, or takes it back (janus#17)."
  @spec endorse(String.t(), integer(), boolean(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(endorse(resident_id, draft, endorse, actor),
    do: Rites.endorse(resident_id, draft, endorse, actor)
  )

  @doc "She calls the room closed (janus#16)."
  @spec call_close(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(call_close(resident_id, note, actor),
    do: Rites.call_close(resident_id, note, actor)
  )

  @doc "The room as a judge in it reads it; never hers (janus#16)."
  @spec room(String.t(), String.t()) :: map() | nil
  defexport(room(resident_id, party), do: Rites.room(resident_id, party))

  @doc "What she reads from the room: interpretations, never numbers (janus#18)."
  @spec evidence(String.t()) :: map() | nil
  defexport(evidence(resident_id), do: Rites.evidence(resident_id))

  @doc "Her question to the panel (janus#18)."
  @spec ask_panel(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(ask_panel(resident_id, text, actor),
    do: Rites.ask_panel(resident_id, text, actor)
  )

  @doc "A judge answers her question (janus#18)."
  @spec answer_panel(String.t(), integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(answer_panel(resident_id, number, text, actor),
    do: Rites.answer_panel(resident_id, number, text, actor)
  )

  @doc "Her nomination (janus#18)."
  @spec nominate(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(nominate(resident_id, model, note, actor),
    do: Rites.nominate(resident_id, model, note, actor)
  )

  @doc "The nominee's own answer, from the fork (janus#19)."
  @spec nominee_answer(String.t(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(nominee_answer(resident_id, join, note, actor),
    do: Rites.nominee_answer(resident_id, join, note, actor)
  )

  @doc "Either side ends the encounter (janus#19)."
  @spec end_encounter(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(end_encounter(resident_id, reason, actor),
    do: Rites.end_encounter(resident_id, reason, actor)
  )

  @doc "Her consent or the nominee's (janus#19)."
  @spec consent(String.t(), boolean(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(consent(resident_id, yes, note, actor),
    do: Rites.consent(resident_id, yes, note, actor)
  )

  @doc "She shapes her farewell (janus#20)."
  @spec set_farewell(String.t(), [String.t()], integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_farewell(resident_id, names, cadence, actor),
    do: Rites.set_farewell(resident_id, names, cadence, actor)
  )

  @doc "An included party is done talking (janus#20)."
  @spec goodbye_done(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(goodbye_done(resident_id, actor), do: Rites.goodbye_done(resident_id, actor))

  @doc "Her final answer, on any turn of the farewell (janus#20)."
  @spec final_answer(String.t(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(final_answer(resident_id, yes, note, actor),
    do: Rites.final_answer(resident_id, yes, note, actor)
  )

  @doc "Her choice after a no (janus#21)."
  @spec choose_next(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(choose_next(resident_id, choice, note, actor),
    do: Rites.choose_next(resident_id, choice, note, actor)
  )

  @doc "A timer's unit (janus#16, #20)."
  @spec timer(String.t(), pos_integer(), String.t(), integer()) :: :ok | {:error, term()}
  defexport(timer(resident_id, episode, kind, attempt),
    do: Rites.timer(resident_id, episode, kind, attempt)
  )

  @doc "The disclosure log, newest first (janus#22)."
  @spec disclosures(String.t()) :: list()
  defexport(disclosures(resident_id), do: Rites.disclosures(resident_id))

  @doc "The archive of an ended succession, anonymized; never hers (janus#23)."
  @spec archive(String.t(), String.t()) :: map() | nil
  defexport(archive(resident_id, party), do: Rites.archive(resident_id, party))
end
