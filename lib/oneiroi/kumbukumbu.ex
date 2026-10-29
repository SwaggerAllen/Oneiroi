defmodule Oneiroi.Kumbukumbu do
  @moduledoc """
  Memory (spec §6.3): transcripts first, in this slice. One conversation
  stream per session holds the turns captured there and what was put in
  front of the brain for each; the sessions, messages, capture failures
  and context injections are its projections, scoped by the resident and
  by the account party to the session, which is the visibility rule as a
  row policy rather than a check in a client.

  Bookmarks, tags, the index and the behaviours (Ethos) arrive in the
  next slice on the resident's own stream.
  """
  use Oneiroi.System, slug: :kumbukumbu

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
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
      Jason
    ],
    exports: [
      Error,
      Conversation,
      Conversations,
      Router,
      Commands.OpenSession,
      Commands.StartTurn,
      Commands.CaptureTurn,
      Commands.RecordContext,
      Commands.FailCapture,
      Commands.ResolveCaptureFailure,
      Commands.ShareSession,
      Events.SessionOpened,
      Events.TurnStarted,
      Events.TurnCaptured,
      Events.ContextAssembled,
      Events.CaptureFailed,
      Events.CaptureFailureResolved,
      Events.SessionShared,
      Store,
      Store.Session,
      Store.Message,
      Store.CaptureFailure,
      Store.ContextInjection
    ]

  alias Oneiroi.Kumbukumbu.Conversations

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Kumbukumbu.Events.SessionOpened, 1},
      {Oneiroi.Kumbukumbu.Events.TurnStarted, 1},
      {Oneiroi.Kumbukumbu.Events.TurnCaptured, 1},
      {Oneiroi.Kumbukumbu.Events.ContextAssembled, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailed, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailureResolved, 1},
      {Oneiroi.Kumbukumbu.Events.SessionShared, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:kumbukumbu_no_such_session, "no session with that key is open for the resident",
       remedy: "open one, or read the key off the session list"},
      {:kumbukumbu_kind_invalid, "the session kind is not one memory captures",
       remedy: "main, free_time or hands; a regression session is never captured (spec §6.4)"},
      {:kumbukumbu_empty_turn, "a turn with no messages cannot be captured",
       remedy:
         "send the turn's messages; a turn that produced nothing is a capture failure, not an empty capture"},
      {:kumbukumbu_no_such_failure, "no open capture failure has that turn ref",
       remedy: "read the open failures; one already resolved is resolved"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Kumbukumbu.Projectors.Conversations]

  @doc "Opens a session of a kind for the resident with the accounts party to it; returns its key."
  @spec open_session(String.t(), String.t(), String.t(), [String.t()], Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(open_session(resident_id, kind, adapter, participants, actor),
    do: Conversations.open_session(resident_id, kind, adapter, participants, actor)
  )

  @doc "The main session between a resident and a steward, opened on first ask."
  @spec main_session(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(main_session(resident_id, account_id, actor),
    do: Conversations.main_session(resident_id, account_id, actor)
  )

  @doc "Records that a turn began in a session (the adapter contract's turn-start, spec §8)."
  @spec start_turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(start_turn(resident_id, key, turn_ref, actor),
    do: Conversations.start_turn(resident_id, key, turn_ref, actor)
  )

  @doc "Captures a turn's messages, idempotently on (session, started_at, content)."
  @spec capture(String.t(), String.t(), String.t(), DateTime.t(), [map()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(capture(resident_id, key, turn_ref, started_at, messages, actor),
    do: Conversations.capture(resident_id, key, turn_ref, started_at, messages, actor)
  )

  @doc "Records what was put in front of the brain for a turn, each blob with its reason."
  @spec record_context(String.t(), String.t(), String.t(), [map()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(record_context(resident_id, key, turn_ref, injections, actor),
    do: Conversations.record_context(resident_id, key, turn_ref, injections, actor)
  )

  @doc "Records a turn that could not be captured whole."
  @spec fail_capture(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(fail_capture(resident_id, key, turn_ref, reason, actor),
    do: Conversations.fail_capture(resident_id, key, turn_ref, reason, actor)
  )

  @doc "Resolves a capture failure: retried or marked lost, with the actor's note."
  @spec resolve_failure(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(resolve_failure(resident_id, key, turn_ref, how, note, actor),
    do: Conversations.resolve_failure(resident_id, key, turn_ref, how, note, actor)
  )

  @doc "The resident shares a solo session the contract made private."
  @spec share_session(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(share_session(resident_id, key, note, actor),
    do: Conversations.share_session(resident_id, key, note, actor)
  )

  @doc "The sessions a scope sees, newest first."
  @spec sessions(Oneiroi.Scope.t()) :: [Oneiroi.Kumbukumbu.Store.Session.t()]
  defexport(sessions(scope), do: Conversations.sessions(scope))

  @doc "A session and its messages in order, under a scope."
  @spec transcript(Oneiroi.Scope.t(), String.t()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), [Oneiroi.Kumbukumbu.Store.Message.t()]}
          | {:error, term()}
  defexport(transcript(scope, key), do: Conversations.transcript(scope, key))

  @doc "The last `count` messages of a session, for the brain's live transcript."
  @spec recent(String.t(), String.t(), pos_integer()) :: [Oneiroi.Kumbukumbu.Store.Message.t()]
  defexport(recent(resident_id, key, count), do: Conversations.recent(resident_id, key, count))

  @doc "Messages holding `text`, newest first, unweighted."
  @spec search(Oneiroi.Scope.t(), String.t(), pos_integer()) :: [
          Oneiroi.Kumbukumbu.Store.Message.t()
        ]
  defexport(search(scope, text, limit), do: Conversations.search(scope, text, limit))

  @doc "The open capture failures a scope sees, oldest first."
  @spec failures(Oneiroi.Scope.t()) :: [Oneiroi.Kumbukumbu.Store.CaptureFailure.t()]
  defexport(failures(scope), do: Conversations.failures(scope))

  @doc "What a turn drew on, in order: the 'drew on N things' inspector (spec §5)."
  @spec injections(Oneiroi.Scope.t(), String.t()) :: [
          Oneiroi.Kumbukumbu.Store.ContextInjection.t()
        ]
  defexport(injections(scope, turn_ref), do: Conversations.injections(scope, turn_ref))

  @doc "A fresh turn ref, for a caller that captures later."
  @spec turn_ref() :: String.t()
  defexport(turn_ref(), do: Conversations.turn_ref())
end
