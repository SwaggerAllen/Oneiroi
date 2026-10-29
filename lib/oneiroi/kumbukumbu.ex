defmodule Oneiroi.Kumbukumbu do
  @moduledoc """
  Memory (spec §6.3): transcripts first, in this slice. One conversation
  stream per session holds the turns captured there and what was put in
  front of the brain for each; the sessions, messages, capture failures
  and context injections are its projections, scoped by the resident and
  by the account party to the session, which is the visibility rule as a
  row policy rather than a check in a client.

  Bookmarks, tags and taggings live on the memory stream,
  `memory-<resident_id>` (#19), with the bookmark index built from them
  under a token budget and the compaction summary on the session; the
  behaviours (Ethos) arrive in the next slice.
  """
  use Oneiroi.System, slug: :kumbukumbu

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      # For the bookmark numbers: minted by the resident aggregate so a
      # citation survives a rebuild (agathos-daimon #4).
      Oneiroi.AgathosDaimon,
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
      Memory,
      Memories,
      MemoryRouter,
      Index,
      MemoryCommands.AddBookmark,
      MemoryCommands.ExtendBookmark,
      MemoryCommands.PinBookmark,
      MemoryCommands.UnpinBookmark,
      MemoryCommands.ProposeBookmark,
      MemoryCommands.DeclineBookmarkProposal,
      MemoryCommands.ProposeTag,
      MemoryCommands.ApproveTag,
      MemoryCommands.RejectTag,
      MemoryCommands.CreateTag,
      MemoryCommands.RetireTag,
      MemoryCommands.ApplyTag,
      MemoryCommands.RemoveTagging,
      Events.Memory.BookmarkAdded,
      Events.Memory.BookmarkExtended,
      Events.Memory.BookmarkPinned,
      Events.Memory.BookmarkUnpinned,
      Events.Memory.BookmarkProposed,
      Events.Memory.BookmarkProposalDeclined,
      Events.Memory.TagProposed,
      Events.Memory.TagApproved,
      Events.Memory.TagRejected,
      Events.Memory.TagCreated,
      Events.Memory.TagRetired,
      Events.Memory.TagApplied,
      Events.Memory.TaggingRemoved,
      Commands.CompactSession,
      Events.Compacted,
      Store.Bookmark,
      Store.BookmarkProposal,
      Store.Tag,
      Store.Tagging,
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
  alias Oneiroi.Kumbukumbu.Memories

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:index_tokens, "KUMBUKUMBU_INDEX_TOKENS",
       cast: :integer,
       default: "1500",
       tag: :bound,
       usage:
         "the token budget the bookmark index is built under every turn (F7); the plan's guess, never measured against a model's attention"}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Kumbukumbu.Events.SessionOpened, 1},
      {Oneiroi.Kumbukumbu.Events.TurnStarted, 1},
      {Oneiroi.Kumbukumbu.Events.TurnCaptured, 1},
      {Oneiroi.Kumbukumbu.Events.ContextAssembled, 1},
      {Oneiroi.Kumbukumbu.Events.Compacted, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailed, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailureResolved, 1},
      {Oneiroi.Kumbukumbu.Events.SessionShared, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkAdded, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkExtended, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkPinned, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkUnpinned, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkProposed, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkProposalDeclined, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagProposed, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagApproved, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagRejected, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagCreated, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagRetired, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TagApplied, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.TaggingRemoved, 1}
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
       remedy: "read the open failures; one already resolved is resolved"},
      {:kumbukumbu_no_such_turn, "no captured turn in the session has that ref",
       remedy: "anchor on a captured turn, or pass anchor_at for one still in flight"},
      {:kumbukumbu_summary_empty, "a compaction needs a summary with words in it",
       remedy: "a model that returned nothing has not compacted; try on the next turn"},
      {:kumbukumbu_not_the_resident, "bookmarks are the resident's words (spec §6.3)",
       remedy: "a steward proposes a bookmark and the resident writes or accepts it"},
      {:kumbukumbu_not_the_steward, "the tag set is the steward's to decide (spec §6.3)",
       remedy: "propose the tag; the steward approves or rejects it"},
      {:kumbukumbu_line_invalid, "a bookmark's line is at most 120 characters and not blank",
       remedy: "say it in a line; the summary holds the rest"},
      {:kumbukumbu_no_such_bookmark, "no bookmark has that number", remedy: "read the index"},
      {:kumbukumbu_span_not_grown, "a span is at least one turn and only ever grows",
       remedy: "extend with more turns back than the bookmark has"},
      {:kumbukumbu_no_such_proposal, "no open proposal has that ref",
       remedy: "one accepted or declined is decided; read the open proposals"},
      {:kumbukumbu_slug_invalid,
       "a tag is a slug: lowercase letters, digits and hyphens, 40 at most",
       remedy: "spell it as a slug"},
      {:kumbukumbu_tag_exists, "the tag is already in the set, or already proposed",
       remedy: "apply it, or wait for the decision on the proposal"},
      {:kumbukumbu_tag_not_active,
       "only an active tag applies; this one is proposed, retired or unknown",
       remedy: "read the tag set; propose the tag if it is missing"},
      {:kumbukumbu_no_such_tag, "no active tag has that slug", remedy: "read the tag set"},
      {:kumbukumbu_target_invalid,
       "a tagging targets a bookmark, a conversation or a turn that exists",
       remedy: "bookmark by number, conversation by session key, turn by ref"}
    ]
  end

  @impl Oneiroi.Component
  def children,
    do: [Oneiroi.Kumbukumbu.Projectors.Conversations, Oneiroi.Kumbukumbu.Projectors.Memory]

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

  @doc "Records a compaction of a session: a summary through a store sequence (spec §5)."
  @spec compact(
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(compact(resident_id, key, turn_ref, through_sequence, summary, actor),
    do: Conversations.compact(resident_id, key, turn_ref, through_sequence, summary, actor)
  )

  @doc "The session and the count of its messages compaction has not covered."
  @spec uncompacted(String.t(), String.t()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), non_neg_integer()} | {:error, term()}
  defexport(uncompacted(resident_id, key), do: Conversations.uncompacted(resident_id, key))

  @doc "Every message of a session after its compaction, in order."
  @spec since_compaction(String.t(), String.t()) :: [Oneiroi.Kumbukumbu.Store.Message.t()]
  defexport(since_compaction(resident_id, key),
    do: Conversations.since_compaction(resident_id, key)
  )

  # ---- bookmarks, tags, taggings (spec §6.3) ----

  @doc "The resident bookmarks a moment; returns its number. Attrs: session_key, anchor_ref, line, summary, turns_back, proposal_ref, anchor_at."
  @spec add_bookmark(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(add_bookmark(resident_id, attrs, actor),
    do: Memories.add_bookmark(resident_id, attrs, actor)
  )

  @doc "Grows a bookmark's span to `turns_back` turns."
  @spec extend_bookmark(String.t(), pos_integer(), pos_integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(extend_bookmark(resident_id, number, turns_back, actor),
    do: Memories.extend_bookmark(resident_id, number, turns_back, actor)
  )

  @doc "Pins a bookmark: a decision, by either party."
  @spec pin_bookmark(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(pin_bookmark(resident_id, number, actor),
    do: Memories.pin_bookmark(resident_id, number, actor)
  )

  @doc "Unpins a bookmark."
  @spec unpin_bookmark(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(unpin_bookmark(resident_id, number, actor),
    do: Memories.unpin_bookmark(resident_id, number, actor)
  )

  @doc "The steward proposes a bookmark with a suggested line and a note; returns the proposal's ref."
  @spec propose_bookmark(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Oneiroi.Actor.t()
        ) ::
          {:ok, String.t()} | {:error, term()}
  defexport(propose_bookmark(resident_id, session_key, anchor_ref, line, note, actor),
    do: Memories.propose_bookmark(resident_id, session_key, anchor_ref, line, note, actor)
  )

  @doc "The resident declines a proposed bookmark, with a note."
  @spec decline_proposal(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decline_proposal(resident_id, ref, note, actor),
    do: Memories.decline_proposal(resident_id, ref, note, actor)
  )

  @doc "Either party proposes a tag for the closed set, with a note."
  @spec propose_tag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(propose_tag(resident_id, slug, note, actor),
    do: Memories.propose_tag(resident_id, slug, note, actor)
  )

  @doc "The steward approves a proposed tag, with a note."
  @spec approve_tag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(approve_tag(resident_id, slug, note, actor),
    do: Memories.approve_tag(resident_id, slug, note, actor)
  )

  @doc "The steward rejects a proposed tag, with a note."
  @spec reject_tag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(reject_tag(resident_id, slug, note, actor),
    do: Memories.reject_tag(resident_id, slug, note, actor)
  )

  @doc "The steward adds a tag to the set."
  @spec create_tag(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(create_tag(resident_id, slug, actor),
    do: Memories.create_tag(resident_id, slug, actor)
  )

  @doc "The steward retires a tag; its taggings stay."
  @spec retire_tag(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(retire_tag(resident_id, slug, actor),
    do: Memories.retire_tag(resident_id, slug, actor)
  )

  @doc "Applies an active tag to a bookmark (by number), a conversation (by key) or a turn (by ref)."
  @spec apply_tag(
          String.t(),
          String.t(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(apply_tag(resident_id, slug, kind, target_id, actor),
    do: Memories.apply_tag(resident_id, slug, kind, target_id, actor)
  )

  @doc "Removes a tagging."
  @spec remove_tagging(
          String.t(),
          String.t(),
          String.t(),
          String.t() | pos_integer(),
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(remove_tagging(resident_id, slug, kind, target_id, actor),
    do: Memories.remove_tagging(resident_id, slug, kind, target_id, actor)
  )

  @doc "The resident's bookmarks, newest first, with their tags."
  @spec bookmarks(String.t()) :: [Oneiroi.Kumbukumbu.Store.Bookmark.t()]
  defexport(bookmarks(resident_id), do: Memories.bookmarks(resident_id))

  @doc "One bookmark and the messages of its span."
  @spec bookmark(String.t(), pos_integer()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Bookmark.t(), [Oneiroi.Kumbukumbu.Store.Message.t()]}
          | {:error, term()}
  defexport(bookmark(resident_id, number), do: Memories.bookmark(resident_id, number))

  @doc "The open bookmark proposals, oldest first."
  @spec proposals(String.t()) :: [Oneiroi.Kumbukumbu.Store.BookmarkProposal.t()]
  defexport(proposals(resident_id), do: Memories.proposals(resident_id))

  @doc "The tag set, every state."
  @spec tags(String.t()) :: [Oneiroi.Kumbukumbu.Store.Tag.t()]
  defexport(tags(resident_id), do: Memories.tags(resident_id))

  @doc "The taggings on one target."
  @spec taggings(String.t(), String.t(), String.t() | pos_integer()) ::
          [Oneiroi.Kumbukumbu.Store.Tagging.t()]
  defexport(taggings(resident_id, kind, target_id),
    do: Memories.taggings(resident_id, kind, target_id)
  )

  @doc "Everything carrying a tag, across every record kind."
  @spec tagged(String.t(), String.t()) :: [Oneiroi.Kumbukumbu.Store.Tagging.t()]
  defexport(tagged(resident_id, slug), do: Memories.tagged(resident_id, slug))

  @doc "The bookmark index for this turn: text, the numbers it lists, how many it left out, its tokens."
  @spec index(String.t()) :: Oneiroi.Kumbukumbu.Index.built()
  defexport(index(resident_id), do: Memories.index(resident_id))
end
