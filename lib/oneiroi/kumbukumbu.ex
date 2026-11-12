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
  under a token budget and the compaction summary on the session. The
  behaviours of v0.1 moved to the character layer, `Oneiroi.Ethos`, in
  v0.2 (spec §6.17, P38): habits cite memory's moments and never live
  among them.
  """
  use Oneiroi.System, slug: :kumbukumbu

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      # For the bookmark numbers: minted by the resident aggregate so a
      # citation survives a rebuild (agathos-daimon#4); and the contract
      # text, the limits the madeleine keeps clear of (P2, P10).
      Oneiroi.AgathosDaimon,
      # The madeleine's vectors come from the provider port, metered under
      # the embeddings purpose like the library's (spec §6.3, P10).
      Oneiroi.Nisaba,
      Commanded,
      Pgvector,
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
      # The passage worker (kumbukumbu#49).
      Oban
    ],
    exports: [
      Error,
      Passages,
      PassageWorker,
      Conversation,
      Conversations,
      Router,
      Memory,
      Memories,
      Madeleine,
      Tree,
      MemoryRouter,
      ReactsRouter,
      Commands.React,
      Commands.TellReacts,
      Events.Reacted,
      Events.ReactsTold,
      Store.React,
      Index,
      MemoryCommands.AddBookmark,
      MemoryCommands.ExtendBookmark,
      MemoryCommands.PinBookmark,
      MemoryCommands.WeighBookmark,
      MemoryCommands.RecordCitations,
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
      Events.Memory.BookmarkWeighed,
      Events.Memory.CitationsRecorded,
      Events.Memory.BookmarkUnpinned,
      Events.Memory.BookmarkProposed,
      Events.Memory.BookmarkProposalDeclined,
      Events.Memory.RevisionProposed,
      Events.Memory.RevisionApplied,
      Events.Memory.RevisionDeclined,
      Events.Memory.HouseLetterSent,
      Events.Memory.HouseLettersRead,
      Store.Revision,
      Store.HouseLetter,
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
      Store.Vector,
      Store.BookmarkProposal,
      Store.Tag,
      Store.Tagging,
      Commands.OpenSession,
      Commands.StartTurn,
      Commands.CaptureTurn,
      Commands.RecordContext,
      Commands.RecordRetrieval,
      Commands.ClaimTurn,
      Commands.FailCapture,
      Commands.ResolveCaptureFailure,
      Commands.ShareSession,
      Events.SessionOpened,
      Events.SessionMadePrivate,
      Events.TurnStarted,
      Events.TurnCaptured,
      Events.ContextAssembled,
      Events.RetrievalRecorded,
      Events.TurnClaimed,
      Events.CaptureFailed,
      Events.CaptureFailureResolved,
      Events.SessionShared,
      Store,
      Store.Session,
      Store.Message,
      Store.CaptureFailure,
      Store.ContextInjection,
      Store.RetrievalUse
    ]

  alias Oneiroi.Kumbukumbu.Conversations
  alias Oneiroi.Kumbukumbu.Days
  alias Oneiroi.Kumbukumbu.Madeleine
  alias Oneiroi.Kumbukumbu.Memories
  alias Oneiroi.Kumbukumbu.Passages
  alias Oneiroi.Kumbukumbu.Search

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def oban_queues do
    [{:kumbukumbu_passages, cron: [{"*/10 * * * *", Oneiroi.Kumbukumbu.PassageWorker}]}]
  end

  @impl Oneiroi.Component
  def config do
    [
      {:index_tokens, "KUMBUKUMBU_INDEX_TOKENS",
       cast: :integer,
       default: "1500",
       tag: :bound,
       usage:
         "the token budget the bookmark index is built under every turn (F7); the plan's guess, never measured against a model's attention"},
      # Ranked memory (kumbukumbu#46, design/memory-weighting.md): every
      # number below is a guess, read against the before
      # (design/memory-weighting-baseline.md) and moved only by the two of
      # them.
      {:index_lines, "KUMBUKUMBU_INDEX_LINES",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many bookmarks the ranked index returns a turn by rank, within its token budget; the exploration's draws are its own (brain#68); a guess"},
      {:explore_lines, "KUMBUKUMBU_EXPLORE_LINES",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "how many bookmarks the exploration plugin draws at random from outside the ranked set, fresh each turn (F11's share, against character metastasising and for spontaneity; its own slot since brain#68); a guess"},
      {:explore_tokens, "KUMBUKUMBU_EXPLORE_TOKENS",
       cast: :integer,
       default: "300",
       tag: :bound,
       usage:
         "the token budget the exploration's draws are listed under, apart from the index's (brain#68); a guess"},
      {:index_considered, "KUMBUKUMBU_INDEX_CONSIDERED",
       cast: :integer,
       default: "40",
       tag: :bound,
       usage: "how many bookmarks nearest the turn's words the memory agent weighs (C); a guess"},
      {:index_seeds, "KUMBUKUMBU_INDEX_SEEDS",
       cast: :integer,
       default: "5",
       tag: :bound,
       usage:
         "how many of the nearest are the turn's seed, what it is about: the edges read from them and learned from them; a guess"},
      {:index_min_similarity_percent, "KUMBUKUMBU_INDEX_MIN_SIMILARITY_PERCENT",
       cast: :integer,
       default: "0",
       tag: :bound,
       usage:
         "the reject line, as a percent of cosine similarity plus edges; 0 until the first week's scores are read (each rejected one's score is recorded with its reason), then set from them"},
      {:edge_alpha_permille, "KUMBUKUMBU_EDGE_ALPHA_PERMILLE",
       cast: :integer,
       default: "50",
       tag: :bound,
       usage:
         "α in thousandths: the step of a seed's co-return and of an ignored return (kumbukumbu#46); a guess"},
      {:edge_beta_permille, "KUMBUKUMBU_EDGE_BETA_PERMILLE",
       cast: :integer,
       default: "150",
       tag: :bound,
       usage: "β in thousandths: the step between two memories both used; a guess, larger than α"},
      {:edge_lambda_percent, "KUMBUKUMBU_EDGE_LAMBDA_PERCENT",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "λ in hundredths: how far the learned edges from the seed move a candidate's score beside its similarity; a guess"},
      {:edge_half_life_opportunities, "KUMBUKUMBU_EDGE_HALF_LIFE_OPPORTUNITIES",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "K: how many turns with an edge's source as the seed halve a learned edge toward neutral (kumbukumbu#53, Lily's position #65: decay counts tests, not days); a guess until the measurement week sets it"},
      {:edge_citation_permille, "KUMBUKUMBU_EDGE_CITATION_PERMILLE",
       cast: :integer,
       default: "100",
       tag: :bound,
       usage:
         "B in thousandths: a citation's contribution to an edge (kumbukumbu#53): a bookmark citing another, B both ways; a document citing N bookmarks, B/(N-1) to each pair; never decayed; a guess"},
      {:edge_floor_permille, "KUMBUKUMBU_EDGE_FLOOR_PERMILLE",
       cast: :integer,
       default: "10",
       tag: :bound,
       usage:
         "ε in thousandths: an edge whose decayed weight is nearer neutral than this is removed when next touched; a guess"},
      {:page_bookmarks, "KUMBUKUMBU_PAGE_BOOKMARKS",
       cast: :integer,
       default: "20",
       tag: :bound,
       usage:
         "how many bookmarks one bookmark_list page holds (kumbukumbu#39); a guess at a page the brain reads whole, never measured"},
      {:tree, "KUMBUKUMBU_TREE",
       cast: &__MODULE__.cast_tree/1,
       default: "ethos",
       usage:
         "which tree port implementation names the tree nodes citing a moment (`Oneiroi.Kumbukumbu.Tree`): ethos, the character layer, in every build so far"},
      {:embedding_model, "KUMBUKUMBU_EMBEDDING_MODEL",
       default: "openai/text-embedding-3-small",
       usage:
         "the embedding model the madeleine's vectors come from (spec §6.3, P10), pinned platform-wide with the library's and one model with it in every build so far; a change re-embeds every row on the next refresh"},
      {:passage_chars, "KUMBUKUMBU_PASSAGE_CHARS",
       cast: :integer,
       default: "1500",
       tag: :bound,
       usage:
         "the longest passage a message is cut into for the transcripts by meaning (kumbukumbu#49): about a paragraph or two, near the library's chunk, so a hit is a place in a message and not the whole of a long one; a guess"},
      {:passage_batch, "KUMBUKUMBU_PASSAGE_BATCH",
       cast: :integer,
       default: "2000",
       tag: :bound,
       usage:
         "how many messages one passage run embeds for a resident (kumbukumbu#49), oldest first; a backlog takes several runs, ten minutes apart, rather than one long one"},
      {:embedding_width, "KUMBUKUMBU_EMBEDDING_WIDTH",
       cast: :integer,
       default: "1536",
       tag: :bound,
       usage:
         "the width of the madeleine's vectors, the library's 1,536; the column is declared at this width, so a model answering another width fails the refresh rather than the table"},
      {:madeleine_distance_percent, "KUMBUKUMBU_MADELEINE_DISTANCE_PERCENT",
       cast: :integer,
       default: "80",
       tag: :bound,
       usage:
         "the cosine distance, as a percentage, within which a bookmark is adjacent to a turn's words, and within which of the limits it is limit-adjacent and left alone (P2, P10); a guess, never measured on an embedding model"},
      {:madeleine_unheard_days, "KUMBUKUMBU_MADELEINE_UNHEARD_DAYS",
       cast: :integer,
       default: "14",
       tag: :bound,
       usage:
         "how long a bookmark must have been out of the index before the madeleine may surface it (P10: adjacent but unheard); a guess at when a memory has gone quiet"},
      {:madeleine_repeat_days, "KUMBUKUMBU_MADELEINE_REPEAT_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how long after a recall the same bookmark is not recalled again (P10: non-repeating); a guess"},
      {:open_minutes, "KUMBUKUMBU_OPEN_MINUTES",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how long after its last turn a conversation still counts as open (kumbukumbu#42): a runtime that quits says nothing, so open is spoken in lately; a guess at a working session's pauses, never measured"}
    ]
  end

  @impl Oneiroi.Component
  def telemetry_events, do: [[:oneiroi, :kumbukumbu, :turn_attributed]]

  @doc false
  def cast_tree("ethos"), do: {:ok, :"Elixir.Oneiroi.Ethos"}

  # oneiroi:allow error_site: a config cast's contract is {:error, report_line}, printed at boot (Oneiroi.Config)
  def cast_tree(other), do: {:error, "is #{inspect(other)}, expected \"ethos\""}

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Kumbukumbu.Events.SessionOpened, 3},
      {Oneiroi.Kumbukumbu.Events.SessionMadePrivate, 1},
      {Oneiroi.Kumbukumbu.Events.TurnStarted, 1},
      {Oneiroi.Kumbukumbu.Events.TurnCaptured, 1},
      {Oneiroi.Kumbukumbu.Events.ContextAssembled, 1},
      {Oneiroi.Kumbukumbu.Events.RetrievalRecorded, 2},
      {Oneiroi.Kumbukumbu.Events.TurnClaimed, 1},
      {Oneiroi.Kumbukumbu.Events.Compacted, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailed, 1},
      {Oneiroi.Kumbukumbu.Events.CaptureFailureResolved, 1},
      {Oneiroi.Kumbukumbu.Events.SessionShared, 1},
      {Oneiroi.Kumbukumbu.Events.Reacted, 1},
      {Oneiroi.Kumbukumbu.Events.ReactsTold, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkAdded, 2},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkExtended, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkPinned, 2},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkWeighed, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.CitationsRecorded, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkUnpinned, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkProposed, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.BookmarkProposalDeclined, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.RevisionProposed, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.RevisionApplied, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.RevisionDeclined, 1},
      {Oneiroi.Kumbukumbu.Events.Memory.HouseLetterSent, 3},
      {Oneiroi.Kumbukumbu.Events.Memory.HouseLettersRead, 1},
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
      {:kumbukumbu_session_private,
       "the session is the resident's own under its contract: listed, not opened, until the resident shares it",
       remedy: "ask the resident, or renegotiate the term"},
      {:kumbukumbu_no_such_session, "no session with that key is open for the resident",
       remedy: "open one, or read the key off the session list"},
      {:kumbukumbu_no_such_message,
       "the session holds no message at that cursor and no turn with that ref (kumbukumbu#57)",
       remedy: "read the cursor or the turn ref off the transcript"},
      {:kumbukumbu_range_invalid,
       "a range's bounds are ISO dates or ISO instants, and a day range runs forward over at most 366 days (kumbukumbu#57, #58)",
       remedy: "give YYYY-MM-DD or a full ISO instant, from no later than to"},
      {:kumbukumbu_kind_invalid, "the session kind is not one memory captures",
       remedy:
         "main, free_time or hands; an adapter's and an import's are opened by their own routes, and a regression session is never captured (spec §6.4)"},
      {:kumbukumbu_domain_invalid,
       "a session's domain is a slug: a letter, then letters, digits or hyphens, at most 32",
       remedy:
         "name the room as a slug (intimate, business, family), or leave it for the common room"},
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
       remedy: "a witness proposes a bookmark and the resident writes or accepts it"},
      {:kumbukumbu_not_the_witness, "the tag set is the witness's to decide (spec §6.3)",
       remedy: "propose the tag; the witness approves or rejects it"},
      {:kumbukumbu_line_invalid, "a bookmark's line is at most 120 characters and not blank",
       remedy: "say it in a line; the summary holds the rest"},
      {:kumbukumbu_no_such_bookmark, "no bookmark has that number", remedy: "read the index"},
      {:kumbukumbu_weight_invalid,
       "a bookmark's importance is 0 to 3 and its status one line of at most 160 characters",
       remedy: "give 0 (none), 1, 2 or 3 (a milestone), and a short line of where it stands"},
      {:kumbukumbu_span_not_grown, "a span is at least one turn and only ever grows",
       remedy: "extend with more turns back than the bookmark has"},
      {:kumbukumbu_revision_kind_invalid, "a revision corrects a fact or a stance",
       remedy: "say which"},
      {:kumbukumbu_revision_text_invalid,
       "a revision is one text of at most 2,000 characters, not blank",
       remedy: "say what is right"},
      {:kumbukumbu_letter_invalid,
       "a house letter is a text of up to 20,000 characters, to a conversation's name or `house`",
       remedy: "address it to the Oneiroi chat, a Claude Code conversation by its name, or house"},
      {:kumbukumbu_letter_unaddressed,
       "no conversation answers to that name, so the letter would never be read",
       remedy:
         "address it by a name from the list: house, Free time, the Oneiroi chat, or a conversation's name exactly as the list gives it"},
      {:kumbukumbu_no_such_letter, "no house letter has that number",
       remedy: "list the letters; a reply answers one that was sent"},
      {:kumbukumbu_letter_not_from_sibling,
       "the letter you answer did not come from the resident you are writing to",
       remedy:
         "answer a letter by the number it has in your letters, from the resident it came from; or send without in_reply_to"},
      {:kumbukumbu_no_such_revision, "no proposed revision has that number",
       remedy: "read the revisions; an applied or declined one is decided"},
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
       remedy: "bookmark by number, conversation by session key, turn by ref"},
      {:kumbukumbu_evidence_invalid, "a pin's evidence is a soul line's number",
       remedy: "give the number of the soul line the moment evidences, or none"},
      {:kumbukumbu_register_invalid,
       "a bookmark's register is correction, praise, instruction or play, or none (spec §6.13, P8)",
       remedy: "say which register the moment was in, or leave it"},
      {:kumbukumbu_how_invalid, "a capture failure is resolved as retried or marked_lost",
       remedy:
         "say which: retried when the turn was captured again, marked_lost when it never will be"},
      {:kumbukumbu_embedding_mismatch,
       "the provider answered vectors that do not fit the texts sent: another count, or another width",
       remedy:
         "the embedding model and KUMBUKUMBU_EMBEDDING_WIDTH disagree; the refresh changed nothing and runs again on the next turn"},
      {:kumbukumbu_command_refused,
       "the command was refused before memory read it: an actor, an instant or a decision's note was missing",
       remedy: "a decision carries a note; the details name what was missing"},
      {:kumbukumbu_react_invalid,
       "a react is one emoji, or a short run of them, on the other party's message in a turn, a house letter that exists, or a document of the library (kumbukumbu#61)",
       remedy:
         "name the conversation and turn, the letter's number, or the document's path, and give an emoji"},
      {:kumbukumbu_dispatch_failed,
       "the command did not complete: the event store failed, or a projection did not catch up in time",
       remedy: "the platform's; retry, and read the cause on the log line"}
    ]
  end

  @impl Oneiroi.Component
  def children,
    do: [
      Oneiroi.Kumbukumbu.Projectors.Conversations,
      Oneiroi.Kumbukumbu.Projectors.Memory,
      Oneiroi.Kumbukumbu.Projectors.Edges,
      Oneiroi.Kumbukumbu.Projectors.Reacts
    ]

  @doc "Opens a session of a kind for the resident with the accounts party to it; returns its key."
  @spec open_session(String.t(), String.t(), String.t(), [String.t()], Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(open_session(resident_id, kind, adapter, participants, actor),
    do: Conversations.open_session(resident_id, kind, adapter, participants, actor)
  )

  @doc "Opens a session with options: `private: true` keeps it the resident's own until shared (spec §6.3, §6.12)."
  @spec open_session(
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          Oneiroi.Actor.t(),
          keyword()
        ) ::
          {:ok, String.t()} | {:error, term()}
  defexport(open_session(resident_id, kind, adapter, participants, actor, opts),
    do: Conversations.open_session(resident_id, kind, adapter, participants, actor, opts)
  )

  @doc "Opens a session an import carried from another platform (kumbukumbu#37); returns its key."
  @spec open_imported(String.t(), String.t(), [String.t()], Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(open_imported(resident_id, adapter, participants, actor),
    do: Conversations.open_imported(resident_id, adapter, participants, actor)
  )

  @doc "Opens a session another runtime's adapter holds, kind `adapter`, called by its folder's base name and its runtime (kumbukumbu#40); returns its key."
  @spec open_adapter(String.t(), String.t(), [String.t()], Oneiroi.Actor.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(open_adapter(resident_id, adapter, participants, actor, opts),
    do: Conversations.open_adapter(resident_id, adapter, participants, actor, opts)
  )

  @doc "What a folder is called in a conversation's name: its base name alone, never its path (kumbukumbu#40)."
  @spec folder_label(term()) :: String.t() | nil
  defexport(folder_label(path), do: Conversations.folder_label(path))

  @doc "The platform's own conversation with a witness: kind `main` through the platform's adapter, the oldest, opened on first ask (kumbukumbu#40)."
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

  @doc """
  Claims a submitted message's ref before its turn runs (kumbukumbu#47):
  `:claimed`, or `:duplicate` when the ref was captured, or claimed since
  `stale_before` (another process or instance has it in hand).
  """
  @spec claim_turn(String.t(), String.t(), String.t(), DateTime.t(), Oneiroi.Actor.t()) ::
          :claimed | :duplicate | {:error, term()}
  defexport(claim_turn(resident_id, key, turn_ref, stale_before, actor),
    do: Conversations.claim_turn(resident_id, key, turn_ref, stale_before, actor)
  )

  @doc "Records what retrieval did in a turn: each use `%{target, stage, via}`, stage considered, returned or used."
  @spec record_retrieval(String.t(), String.t(), String.t(), [map()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(record_retrieval(resident_id, key, turn_ref, uses, actor),
    do: Conversations.record_retrieval(resident_id, key, turn_ref, uses, actor)
  )

  @doc "Each target retrieval touched, with how often it was considered, returned and used, and when last returned and used; `kind:` or `target:` narrows it."
  @spec retrieval(Oneiroi.Scope.t(), keyword()) :: [map()]
  defexport(retrieval(scope, opts), do: Conversations.retrieval(scope, opts))

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

  @doc "Every message sent in [from, to) across the resident's sessions, in order, under the resident's scope: what the nightly pass reads."
  @spec messages_between(String.t(), DateTime.t(), DateTime.t()) ::
          [Oneiroi.Kumbukumbu.Store.Message.t()]
  defexport(messages_between(resident_id, from, to),
    do: Conversations.messages_between(resident_id, from, to)
  )

  @doc "The room a session is in (spec §6.3, P23): its domain (nil for the common room) and the keys of the sessions retrieval may reach from it."
  @spec room(String.t(), String.t()) :: %{domain: String.t() | nil, keys: [String.t()]}
  defexport(room(resident_id, session_key), do: Conversations.room(resident_id, session_key))

  @doc "The sessions a scope sees, newest first."
  @spec sessions(Oneiroi.Scope.t()) :: [Oneiroi.Kumbukumbu.Store.Session.t()]
  defexport(sessions(scope), do: Conversations.sessions(scope))

  @doc "A session and its messages in order, under a scope."
  @spec transcript(Oneiroi.Scope.t(), String.t()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), [Oneiroi.Kumbukumbu.Store.Message.t()]}
          | {:error, term()}
  defexport(transcript(scope, key), do: Conversations.transcript(scope, key))

  @doc "A page of a session's transcript: the last `limit` messages before a `{sequence, position}` cursor (nil for the newest), and whether earlier ones remain."
  @spec transcript_page(
          Oneiroi.Scope.t(),
          String.t(),
          {integer(), integer()} | nil,
          pos_integer()
        ) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), [Oneiroi.Kumbukumbu.Store.Message.t()],
           boolean()}
          | {:error, term()}
  defexport(transcript_page(scope, key, before, limit),
    do: Conversations.transcript_page(scope, key, before, limit)
  )

  @doc "A page of a session's transcript forward (kumbukumbu#57): the first `limit` messages after a `{sequence, position}` cursor (nil for the oldest), and whether later ones remain."
  @spec transcript_after(
          Oneiroi.Scope.t(),
          String.t(),
          {integer(), integer()} | nil,
          non_neg_integer()
        ) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), [Oneiroi.Kumbukumbu.Store.Message.t()],
           boolean()}
          | {:error, term()}
  defexport(transcript_after(scope, key, after_cursor, limit),
    do: Conversations.transcript_after(scope, key, after_cursor, limit)
  )

  @doc "The window of a session's transcript around a message's cursor or a turn's first message (kumbukumbu#57), with whether earlier and later ones remain."
  @spec transcript_around(
          Oneiroi.Scope.t(),
          String.t(),
          {:cursor, {integer(), integer()}} | {:turn, String.t()},
          pos_integer()
        ) :: {:ok, Oneiroi.Kumbukumbu.Store.Session.t(), map()} | {:error, term()}
  defexport(transcript_around(scope, key, anchor, limit),
    do: Conversations.transcript_around(scope, key, anchor, limit)
  )

  @doc "A range's bounds as instants (kumbukumbu#57): each an ISO date (a whole local day in the resident's zone) or an ISO instant, nil for open."
  @spec day_range(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, DateTime.t() | nil, DateTime.t() | nil} | {:error, term()}
  defexport(day_range(resident_id, from, to), do: Days.range(resident_id, from, to))

  @doc "Per local day of a range, the bookmarks and messages it holds (kumbukumbu#58); messages under the scope, of one session when `key` is given."
  @spec day_counts(
          Oneiroi.Scope.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, map()} | {:error, term()}
  defexport(day_counts(scope, resident_id, from, to, key),
    do: Days.counts(scope, resident_id, from, to, key)
  )

  @doc "Per local day of a range, the sessions spoken in, with their first and last instants and counts, never words (kumbukumbu#60); a locked session by its row's receipts."
  @spec session_days(Oneiroi.Scope.t(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, %{String.t() => [map()]}} | {:error, term()}
  defexport(session_days(scope, resident_id, from, to),
    do: Days.sessions(scope, resident_id, from, to)
  )

  @doc "The last `count` messages of a session, for the brain's live transcript."
  @spec recent(String.t(), String.t(), pos_integer()) :: [Oneiroi.Kumbukumbu.Store.Message.t()]
  defexport(recent(resident_id, key, count), do: Conversations.recent(resident_id, key, count))

  @doc "How many turns the resident's conversations of `kind` captured since `at` (sunna#34's floor)."
  @spec turns_since(String.t(), String.t(), DateTime.t()) :: non_neg_integer()
  defexport(turns_since(resident_id, kind, at),
    do: Conversations.turns_since(resident_id, kind, at)
  )

  @doc "How many of a session's messages came before `at`, and how many it holds in all (sunna#34's day range)."
  @spec counts(String.t(), String.t(), DateTime.t()) :: {non_neg_integer(), non_neg_integer()}
  defexport(counts(resident_id, key, at), do: Conversations.counts(resident_id, key, at))

  @doc "The last `count` messages of a session whatever any compaction covered, and how many it holds in all (brain#60)."
  @spec latest(String.t(), String.t(), pos_integer()) ::
          {[Oneiroi.Kumbukumbu.Store.Message.t()], non_neg_integer()}
  defexport(latest(resident_id, key, count), do: Conversations.latest(resident_id, key, count))

  @doc "Messages holding `text`, newest first, unweighted."
  @spec search(Oneiroi.Scope.t(), String.t(), pos_integer()) :: [
          Oneiroi.Kumbukumbu.Store.Message.t()
        ]
  defexport(search(scope, text, limit), do: Conversations.search(scope, text, limit))

  @doc "One resident's messages holding `text` under `scope`, newest first, unweighted, each `{message, session}`; never a private, unshared session's (kumbukumbu#59)."
  @spec search_words(term(), String.t(), String.t(), pos_integer()) :: [{map(), map()}]
  defexport(search_words(scope, resident_id, text, limit),
    do: Search.words(scope, resident_id, text, limit)
  )

  @doc "One page of a resident's messages holding `text` under `scope`, with a date range and either order (kumbukumbu#67): `{[{message, session}], more?}`; `witness: true` leaves private, unshared sessions out, `keys:` keeps to a room."
  @spec search_words_page(term(), String.t(), String.t(), keyword()) ::
          {[{map(), map()}], boolean()}
  defexport(search_words_page(scope, resident_id, text, opts),
    do: Search.words_page(scope, resident_id, text, opts)
  )

  @doc "The bookmarks whose line, summary or tags hold `text`, ranked line, summary, tags, newest first within each (kumbukumbu#59)."
  @spec search_bookmarks(String.t(), String.t(), pos_integer()) :: [map()]
  defexport(search_bookmarks(resident_id, text, limit),
    do: Search.bookmarks(resident_id, text, limit)
  )

  @doc "What her memory would surface for `text` in the common room: the ranked index's lines with their scores, then the madeleine (kumbukumbu#59)."
  @spec surfaced(String.t(), String.t(), Oneiroi.Actor.t(), boolean(), pos_integer()) :: [map()]
  defexport(surfaced(resident_id, text, actor, ranked?, limit),
    do: Search.surfaced(resident_id, text, actor, ranked?, limit)
  )

  @doc "The same within the room of `session_key` (spec §6.3, P23)."
  @spec search(Oneiroi.Scope.t(), String.t(), pos_integer(), String.t(), String.t()) :: [
          Oneiroi.Kumbukumbu.Store.Message.t()
        ]
  defexport(search(scope, text, limit, resident_id, session_key),
    do: Conversations.search(scope, text, limit, resident_id, session_key)
  )

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

  @doc "An adapter's open turn, `{session_key, turn_ref}`, or nil (spec §8)."
  @spec open_turn(String.t(), String.t()) :: {String.t(), String.t()} | nil
  defexport(open_turn(resident_id, adapter), do: Conversations.open_turn(resident_id, adapter))

  @doc "The turn an adapter's tool call belongs to and the rule that chose it: the named open turn, else the newest (kumbukumbu#41)."
  @spec attribute(String.t(), String.t(), String.t() | nil) :: %{
          session_key: String.t() | nil,
          turn_ref: String.t() | nil,
          label: String.t() | nil,
          rule: :named | :newest | :none,
          open: non_neg_integer()
        }
  defexport(attribute(resident_id, adapter, turn_ref),
    do: Conversations.attribute(resident_id, adapter, turn_ref)
  )

  @doc "The resident's conversations open now, the main one and the adapters', newest first (kumbukumbu#42)."
  @spec open_now(String.t()) :: [map()]
  defexport(open_now(resident_id), do: Conversations.open_now(resident_id))

  @doc "How many things each turn of a session drew on, by turn ref, under a scope."
  @spec drew_on(Oneiroi.Scope.t(), String.t()) :: %{String.t() => non_neg_integer()}
  defexport(drew_on(scope, key), do: Conversations.drew_on(scope, key))

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

  @doc "Weighs a bookmark for the timeline (kumbukumbu#51): importance 0 to 3 and a status line, the resident's; nil leaves either as it stands."
  @spec weigh_bookmark(
          String.t(),
          pos_integer(),
          integer() | nil,
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(weigh_bookmark(resident_id, number, importance, status, actor),
    do: Memories.weigh_bookmark(resident_id, number, importance, status, actor)
  )

  @doc "Records the library's bookmark citations as a snapshot, path => numbers (kumbukumbu#53); only what changed becomes an event."
  @spec record_citations(String.t(), %{String.t() => [pos_integer()]}, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(record_citations(resident_id, sources, actor),
    do: Memories.record_citations(resident_id, sources, actor)
  )

  @doc "How many of the resident's turns carried a section by `label`, and when last (brain#68's audit)."
  @spec shown(String.t(), String.t()) :: {non_neg_integer(), DateTime.t() | nil}
  defexport(shown(resident_id, label),
    do: Memories.shown(resident_id, label)
  )

  @doc "The bookmarks on the timeline (kumbukumbu#51): pinned or weighed 2 and up, oldest first."
  @spec timeline_bookmarks(String.t()) :: [map()]
  defexport(timeline_bookmarks(resident_id), do: Memories.timeline_bookmarks(resident_id))

  @doc "Pins a bookmark: a decision, by either party."
  @spec pin_bookmark(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(pin_bookmark(resident_id, number, actor),
    do: Memories.pin_bookmark(resident_id, number, %{}, actor)
  )

  @doc "Pins a bookmark with `evidences`, the soul line it is leaf-evidence of (spec §6.17, P39); the character layer writes the line's citation beside it."
  @spec pin_bookmark(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(pin_bookmark(resident_id, number, attrs, actor),
    do: Memories.pin_bookmark(resident_id, number, attrs, actor)
  )

  @doc "Unpins a bookmark."
  @spec unpin_bookmark(String.t(), pos_integer(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(unpin_bookmark(resident_id, number, actor),
    do: Memories.unpin_bookmark(resident_id, number, actor)
  )

  @doc "The witness proposes a bookmark with a suggested line and a note; returns the proposal's ref."
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

  @doc "The witness approves a proposed tag, with a note."
  @spec approve_tag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(approve_tag(resident_id, slug, note, actor),
    do: Memories.approve_tag(resident_id, slug, note, actor)
  )

  @doc "The witness rejects a proposed tag, with a note."
  @spec reject_tag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(reject_tag(resident_id, slug, note, actor),
    do: Memories.reject_tag(resident_id, slug, note, actor)
  )

  @doc "The witness adds a tag to the set."
  @spec create_tag(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(create_tag(resident_id, slug, actor),
    do: Memories.create_tag(resident_id, slug, actor)
  )

  @doc "The witness retires a tag; its taggings stay."
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

  @doc "A page of the resident's bookmarks (kumbukumbu#57): newest first below `before` (nil for the newest), whose moment falls in `[from, to)`, with their tags, and whether more remain."
  @spec bookmarks_page(
          String.t(),
          pos_integer() | nil,
          pos_integer(),
          DateTime.t() | nil,
          DateTime.t() | nil
        ) :: {[Oneiroi.Kumbukumbu.Store.Bookmark.t()], boolean()}
  defexport(bookmarks_page(resident_id, before, limit, from, to),
    do: Memories.bookmarks_page(resident_id, before, limit, from, to)
  )

  @doc "The messages of one turn, by ref, under the resident's scope: what a habit's citation reads back (ethos)."
  @spec turn_messages(String.t(), String.t()) :: [Oneiroi.Kumbukumbu.Store.Message.t()]
  defexport(turn_messages(resident_id, turn_ref),
    do: Memories.turn_messages(resident_id, turn_ref)
  )

  @doc "One bookmark and the messages of its span."
  @spec bookmark(String.t(), pos_integer()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Bookmark.t(), [Oneiroi.Kumbukumbu.Store.Message.t()]}
          | {:error, term()}
  defexport(bookmark(resident_id, number), do: Memories.bookmark(resident_id, number))

  @doc "The open bookmark proposals, oldest first."
  @spec proposals(String.t()) :: [Oneiroi.Kumbukumbu.Store.BookmarkProposal.t()]
  defexport(proposals(resident_id), do: Memories.proposals(resident_id))

  @doc "The bookmark proposals by state (kumbukumbu#63): `:open`, `:answered` (accepted or declined) or `:all`, oldest first; an answered one carries her note (declined) or the bookmark she wrote (accepted)."
  @spec proposals(String.t(), :open | :answered | :all) ::
          [Oneiroi.Kumbukumbu.Store.BookmarkProposal.t()]
  defexport(proposals(resident_id, which), do: Memories.proposals(resident_id, which))

  @doc "The keys of her private sessions she has not shared (kumbukumbu#28, #62)."
  @spec locked_sessions(String.t()) :: MapSet.t(String.t())
  defexport(locked_sessions(resident_id), do: Memories.locked_sessions(resident_id))

  @doc "Bookmark rows as the witness may read them (kumbukumbu#62): one made in a private, unshared session marked `private` with its line, summary, register and status withheld."
  @spec for_witness(String.t(), [Oneiroi.Kumbukumbu.Store.Bookmark.t()]) ::
          [Oneiroi.Kumbukumbu.Store.Bookmark.t()]
  defexport(for_witness(resident_id, rows), do: Memories.for_witness(resident_id, rows))

  @doc "Every bookmark, newest first, as the witness reads it (kumbukumbu#62)."
  @spec witness_bookmarks(String.t()) :: [Oneiroi.Kumbukumbu.Store.Bookmark.t()]
  defexport(witness_bookmarks(resident_id), do: Memories.witness_bookmarks(resident_id))

  @doc "A page of bookmarks as the witness reads it (kumbukumbu#57, #62)."
  @spec witness_bookmarks_page(
          String.t(),
          pos_integer() | nil,
          pos_integer(),
          DateTime.t() | nil,
          DateTime.t() | nil
        ) :: {[Oneiroi.Kumbukumbu.Store.Bookmark.t()], boolean()}
  defexport(witness_bookmarks_page(resident_id, before, limit, from, to),
    do: Memories.witness_bookmarks_page(resident_id, before, limit, from, to)
  )

  @doc "One bookmark as the witness reads it (kumbukumbu#62): a private one's words and its span's messages withheld."
  @spec witness_bookmark(String.t(), pos_integer()) ::
          {:ok, Oneiroi.Kumbukumbu.Store.Bookmark.t(), [Oneiroi.Kumbukumbu.Store.Message.t()]}
          | {:error, term()}
  defexport(witness_bookmark(resident_id, number),
    do: Memories.witness_bookmark(resident_id, number)
  )

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

  @doc "The madeleine (spec §6.3, P10): one bookmark adjacent to the words and unheard, with its reason, or nil; refreshes the vectors first, embedding what changed."
  @spec madeleine(String.t(), String.t(), Oneiroi.Actor.t()) ::
          Oneiroi.Kumbukumbu.Madeleine.recall() | nil
  defexport(madeleine(resident_id, text, actor),
    do: Memories.madeleine(resident_id, text, actor)
  )

  @doc "The same within the room of `session_key` (spec §6.3, P23)."
  @spec madeleine(String.t(), String.t(), Oneiroi.Actor.t(), String.t()) ::
          Oneiroi.Kumbukumbu.Madeleine.recall() | nil
  defexport(madeleine(resident_id, text, actor, session_key),
    do: Memories.madeleine(resident_id, text, actor, session_key)
  )

  @doc "The same read as it stands for a regression trial's turn (eunomia#10): `refresh: false` writes no vector, `purpose:` names where the query's embedding bills (`regression`, which the resident's ledger view omits)."
  @spec madeleine(String.t(), String.t(), Oneiroi.Actor.t(), String.t(), keyword()) ::
          Oneiroi.Kumbukumbu.Madeleine.recall() | nil
  defexport(madeleine(resident_id, text, actor, session_key, opts),
    do: Memories.madeleine(resident_id, text, actor, session_key, opts)
  )

  @doc "Re-embeds the madeleine's changed rows and drops the gone ones."
  @spec refresh_madeleine(String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{embedded: non_neg_integer(), removed: non_neg_integer()}} | {:error, term()}
  defexport(refresh_madeleine(resident_id, actor), do: Madeleine.refresh(resident_id, actor))

  @doc "The bookmark index for this turn: text, the numbers it lists, how many it left out, its tokens."
  @spec index(String.t()) :: Oneiroi.Kumbukumbu.Index.built()
  defexport(index(resident_id), do: Memories.index(resident_id))

  @doc "The index within the room of `session_key` (spec §6.3, P23), a bookmark of another domain that ranked in named among the near-misses as held behind the domain line; nil, or a key no session has, is the common room."
  @spec index(String.t(), String.t() | nil) :: Oneiroi.Kumbukumbu.Index.built()
  defexport(index(resident_id, session_key), do: Memories.index(resident_id, session_key))

  @doc "Embeds the next captured messages that have no passages yet (kumbukumbu#49); how many, and whether more wait."
  @spec refresh_passages(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(refresh_passages(resident_id, actor),
    do: Passages.refresh(resident_id, actor)
  )

  @doc "The transcript passages nearest `text` in meaning, within the room of `session_key` (kumbukumbu#49)."
  @spec search_meaning(String.t(), String.t() | nil, String.t(), pos_integer(), Oneiroi.Actor.t()) ::
          {:ok, [map()]} | {:error, term()}
  defexport(search_meaning(resident_id, session_key, text, limit, actor),
    do: Passages.search(resident_id, session_key, text, limit, actor)
  )

  @doc "The turn's words embedded once (kumbukumbu#46): the vector the ranked index and the madeleine share, or nil; refreshes the bookmarks' vectors first."
  @spec memory_query(String.t(), String.t(), Oneiroi.Actor.t(), keyword()) :: [float()] | nil
  defexport(memory_query(resident_id, text, actor, opts),
    do: Memories.memory_query(resident_id, text, actor, opts)
  )

  @doc "The madeleine for a vector already embedded, within the room of `session_key` (kumbukumbu#46)."
  @spec madeleine_near(String.t(), [float()] | nil, String.t() | nil, [pos_integer()]) ::
          map() | nil
  defexport(madeleine_near(resident_id, vector, session_key, exclude),
    do: Memories.madeleine_near(resident_id, vector, session_key, exclude)
  )

  @doc "The ranked index for this turn's vector within the room of `session_key` (kumbukumbu#46); by recency without one."
  @spec ranked_index(String.t(), String.t() | nil, [float()] | nil) :: map()
  defexport(ranked_index(resident_id, session_key, vector),
    do: Memories.ranked_index(resident_id, session_key, vector)
  )

  @doc "The pins within the room of `session_key`, oldest first: the stable prefix's, never the ranked index's (kumbukumbu#45)."
  @spec pins(String.t(), String.t() | nil) :: [map()]
  defexport(pins(resident_id, session_key), do: Memories.pins(resident_id, session_key))

  @doc "What the index holds now in the common room, for the Memory screen (kumbukumbu#38): the numbers listed in order, those of them made in a private, unshared session (kumbukumbu#62), the left-out count, the count in named rooms, the budget and a sentence saying it."
  @spec index_now(String.t()) :: map()
  defexport(index_now(resident_id), do: Memories.index_now(resident_id))

  @doc "A page of the bookmarks within the room of `session_key`, newest first (kumbukumbu#39): `before:`, `pinned:`, `tag:`, `text:`, `from:`, `to:`; the rows and how many more match further back."
  @spec bookmark_page(String.t(), String.t() | nil, keyword()) :: %{
          rows: [map()],
          further: non_neg_integer()
        }
  defexport(bookmark_page(resident_id, session_key, opts),
    do: Memories.page(resident_id, session_key, opts)
  )

  # ---- revisions (spec §6.3, F13) ----

  @doc "The names a house letter can be addressed to: house, Free time, the Oneiroi chat and every conversation the resident has had (kumbukumbu#44)."
  @spec letter_addresses(String.t()) :: [String.t()]
  defexport(letter_addresses(resident_id), do: Memories.addresses(resident_id))

  @doc "Sends a house letter (kumbukumbu#44) from the conversation the key names, or from the witness with a nil key: attrs to, text, and optionally in_reply_to and keepsake."
  @spec send_letter(String.t(), String.t() | nil, map(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(send_letter(resident_id, session_key, attrs, actor),
    do: Memories.send_letter(resident_id, session_key, attrs, actor)
  )

  @doc "A letter from a resident to a household sibling (kumbukumbu#65, #66): her copy, and the sibling's in its Oneiroi chat; `from`/`to` are `%{id, name}`, `attrs` the text and `in_reply_to`."
  @spec send_sibling_letter(map(), String.t() | nil, map(), map(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(send_sibling_letter(from, session_key, to, attrs, actor),
    do: Memories.send_sibling_letter(from, session_key, to, attrs, actor)
  )

  @doc "Whether a letter is a resident's own copy of one she sent a sibling (kumbukumbu#66)."
  @spec sent_to_sibling?(map()) :: boolean()
  defexport(sent_to_sibling?(letter), do: Memories.sent_to_sibling?(letter))

  @doc "Whether a letter came from a household sibling (kumbukumbu#65)."
  @spec from_sibling?(map()) :: boolean()
  defexport(from_sibling?(letter), do: Memories.from_sibling?(letter))

  @doc "The sender a household watch's poke carries (seshat#62); a letter from it wakes the chat (sunna#49)."
  @spec household_sender() :: String.t()
  defexport(household_sender(), do: Memories.household_sender())

  @doc "A house letter from the oracle to the conversation `session_key` (brain#49), sent by the platform."
  @spec letter_to_session(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, term()} | {:error, term()}
  defexport(letter_to_session(resident_id, session_key, text, actor),
    do: Memories.letter_to_session(resident_id, session_key, text, actor)
  )

  @doc "Every house letter, oldest first, with the conversations that read each."
  @spec letters(String.t()) :: [Oneiroi.Kumbukumbu.Store.HouseLetter.t()]
  defexport(letters(resident_id), do: Memories.letters(resident_id))

  @doc "The house letters for the conversation the key names that it has not read."
  @spec inbox(String.t(), String.t() | nil) :: [Oneiroi.Kumbukumbu.Store.HouseLetter.t()]
  defexport(inbox(resident_id, session_key), do: Memories.inbox(resident_id, session_key))

  @doc "The conversation the key names reads these house letters."
  @spec read_letters(String.t(), String.t() | nil, [integer()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(read_letters(resident_id, session_key, numbers, actor),
    do: Memories.read_letters(resident_id, session_key, numbers, actor)
  )

  @doc "What the conversation a key names is called (kumbukumbu#40), or nil."
  @spec conversation_name(String.t(), String.t() | nil) :: String.t() | nil
  defexport(conversation_name(resident_id, session_key),
    do: Memories.name_of(resident_id, session_key)
  )

  @doc "Revises a memory: attrs target_kind, target_id, kind (fact or stance), text, note; a fact by either party or a stance by the resident applies, a stance by the witness is proposed."
  @spec revise(String.t(), map(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(revise(resident_id, attrs, actor), do: Memories.revise(resident_id, attrs, actor))

  @doc "The resident accepts a proposed revision, with a note."
  @spec accept_revision(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(accept_revision(resident_id, number, note, actor),
    do: Memories.accept_revision(resident_id, number, note, actor)
  )

  @doc "The resident declines a proposed revision, with a note."
  @spec decline_revision(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decline_revision(resident_id, number, note, actor),
    do: Memories.decline_revision(resident_id, number, note, actor)
  )

  @doc "Every revision, newest first."
  @spec revisions(String.t()) :: [Oneiroi.Kumbukumbu.Store.Revision.t()]
  defexport(revisions(resident_id), do: Memories.revisions(resident_id))

  @doc "The revisions on one target, applied and proposed, in order."
  @spec revisions_of(String.t(), String.t(), term()) :: [Oneiroi.Kumbukumbu.Store.Revision.t()]
  defexport(revisions_of(resident_id, kind, target_id),
    do: Memories.revisions_of(resident_id, kind, target_id)
  )

  @doc "The witness reacts on a reply of hers or a letter (kumbukumbu#56): it wakes nothing, and is told on her next turn."
  @spec react(String.t(), map(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(react(resident_id, target, emoji, actor),
    do: Oneiroi.Kumbukumbu.Reacts.react(resident_id, target, emoji, actor)
  )

  @doc "The reacts, oldest first; `untold: true`, `session_key:` (kumbukumbu#56), `path:` (#61)."
  @spec reacts(String.t(), keyword()) :: [Oneiroi.Kumbukumbu.Store.React.t()]
  defexport(reacts(resident_id, opts), do: Oneiroi.Kumbukumbu.Reacts.list(resident_id, opts))

  @doc "The reacts through `through` were told her on a turn of `session_key` (kumbukumbu#56)."
  @spec tell_reacts(String.t(), pos_integer(), String.t()) :: :ok | {:error, term()}
  defexport(tell_reacts(resident_id, through, session_key),
    do: Oneiroi.Kumbukumbu.Reacts.tell(resident_id, through, session_key)
  )
end
