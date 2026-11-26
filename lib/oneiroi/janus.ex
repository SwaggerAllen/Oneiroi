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
      Oneiroi.SimaQian,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
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
      Events.Proposed,
      Events.Opened,
      Events.Declined,
      Events.Withdrawn,
      Events.Stopped,
      Events.Forked,
      Events.ForkFailed,
      Events.BackupSet,
      Store,
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
      {:janus_fork, []}
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
      {Oneiroi.Janus.Events.BackupSet, 1}
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
end
