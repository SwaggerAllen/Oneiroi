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
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
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
      Store,
      Store.Pool,
      Store.Question,
      Store.Item,
      Store.Ready,
      Store.Packet,
      Store.ToolUse,
      Store.Succession
    ]

  alias Oneiroi.Janus.ForkWorker
  alias Oneiroi.Janus.Successions

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def oban_queues do
    [
      # A succession's fork copy, off her yes (janus#4).
      {:janus_fork, []},
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
      {Oneiroi.Janus.Events.PacketDrafted, 1}
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
end
