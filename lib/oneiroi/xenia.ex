defmodule Oneiroi.Xenia do
  @moduledoc """
  Inbound (spec §6.6): correspondence, for any platform and any
  resident. A third party's message arrives through an inbound adapter
  (a hands agent with the `reader` role, never the resident) or the
  witness's paste, and reaches the resident at once (F23 as amended
  2026-11-02), unless either party has blocked its sender, when it is
  counted and its words are never kept. The resident drafts replies; the
  witness approves or declines each with a note; an adapter or the
  witness sends an approved one and marks it sent, which is the receipt.
  The reader, mail, feeds and the digest of §6.6 are not built yet.
  """
  use Oneiroi.System, slug: :xenia

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      # Routes (xenia#19): a route lands in a kind of her library, and
      # its definition is written into her repository.
      Oneiroi.Seshat,
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
      Jason
    ],
    exports: [
      Error,
      Correspondence,
      Inbox,
      Router,
      RoutesRouter,
      ProfilesRouter,
      Commands.ReceiveMessage,
      Commands.BlockCorrespondent,
      Commands.UnblockCorrespondent,
      Commands.MarkMessages,
      Commands.DraftReply,
      Commands.DecideReply,
      Commands.MarkReplySent,
      Commands.SetReaderSites,
      Commands.DefineRoute,
      Commands.AskRoute,
      Commands.LandRoute,
      Commands.FailRoute,
      Commands.SetProfile,
      Commands.RevokeProfile,
      Commands.RestoreProfile,
      Events.CorrespondenceReceived,
      Events.CorrespondenceMarked,
      Events.CorrespondentBlocked,
      Events.CorrespondentUnblocked,
      Events.ReplyDrafted,
      Events.ReplySuperseded,
      Events.ReplyApproved,
      Events.ReplyDeclined,
      Events.ReplyMarkedSent,
      Events.ReaderSitesSet,
      Events.RouteDefined,
      Events.RouteChanged,
      Events.RouteAsked,
      Events.RouteLanded,
      Events.RouteFailed,
      Events.ProfileSet,
      Events.ProfileRevoked,
      Events.ProfileRestored,
      Store,
      Store.Message,
      Store.Block,
      Store.Reply,
      Store.ReaderSites,
      Store.Route,
      Store.RouteRun,
      Store.Profile
    ]

  alias Oneiroi.Xenia.Inbox
  alias Oneiroi.Xenia.Routing

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config, do: []

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Xenia.Events.CorrespondenceReceived, 1},
      {Oneiroi.Xenia.Events.CorrespondenceMarked, 1},
      {Oneiroi.Xenia.Events.CorrespondentBlocked, 1},
      {Oneiroi.Xenia.Events.CorrespondentUnblocked, 1},
      {Oneiroi.Xenia.Events.ReplyDrafted, 1},
      {Oneiroi.Xenia.Events.ReplySuperseded, 1},
      {Oneiroi.Xenia.Events.ReplyApproved, 1},
      {Oneiroi.Xenia.Events.ReplyDeclined, 1},
      {Oneiroi.Xenia.Events.ReplyMarkedSent, 1},
      {Oneiroi.Xenia.Events.ReaderSitesSet, 1},
      {Oneiroi.Xenia.Events.RouteDefined, 1},
      {Oneiroi.Xenia.Events.RouteChanged, 1},
      {Oneiroi.Xenia.Events.RouteAsked, 1},
      {Oneiroi.Xenia.Events.RouteLanded, 1},
      {Oneiroi.Xenia.Events.RouteFailed, 1},
      {Oneiroi.Xenia.Events.ProfileSet, 1},
      {Oneiroi.Xenia.Events.ProfileRevoked, 1},
      {Oneiroi.Xenia.Events.ProfileRestored, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:xenia_sites_invalid,
       "an allowlist is at most 50 entries, each an origin (https://host, a port at most) or *",
       remedy: "give origins without paths, or * for any site"},
      {:xenia_not_allowed,
       "the inbound adapter or the witness delivers; either party blocks; the resident marks and drafts; the witness approves replies",
       remedy: "do this as the party it belongs to"},
      {:xenia_message_invalid,
       "a message names its platform (a lowercase slug), the account, its id there, its sender and when it was sent, and carries words of at most 64 KiB",
       remedy: "send every field; one line each, the words whole"},
      {:xenia_batch_too_large, "a delivery carries at most 40 messages",
       remedy: "send the rest in another delivery"},
      {:xenia_no_such_message, "no message the resident can answer has that number",
       remedy: "read the correspondence; a blocked sender's message has nothing to answer"},
      {:xenia_already_decided, "the reply was already approved or declined",
       remedy: "read where it stands; a decision is not made twice"},
      {:xenia_block_invalid,
       "a block is a platform (a lowercase slug) and an identity on it, one line",
       remedy: "name the platform and the address or account"},
      {:xenia_no_such_block, "nobody is blocked with that identity on that platform",
       remedy: "read the blocks"},
      {:xenia_not_yours, "a block is lifted only by the party who set it",
       remedy: "ask them; their boundary is theirs to lift"},
      {:xenia_reply_invalid,
       "a reply is words of at most 20,000 characters to a message that reached the resident, or to a named platform, account and recipient",
       remedy: "say what to send, and where"},
      {:xenia_no_such_reply, "no reply has that number", remedy: "read the replies"},
      {:xenia_not_supersedable,
       "only a draft still waiting for the witness can be replaced by a newer one",
       remedy: "read the replies; an approved, declined or sent reply stands as it is"},
      {:xenia_reply_not_approved, "only an approved reply is sent",
       remedy: "the witness approves it first"},
      {:xenia_route_invalid,
       "a route of hers is a source, asked on request, with a key of 2 to 40 lowercase letters, digits or -, a prompt of at most 4,000 characters, bound to a profile that stands, landing in a kind she writes whose approval stays in the house",
       remedy:
         "a sink, a schedule, a new profile and a kind that leaves the house are the witness's to enable; name what exists"},
      {:xenia_route_unable, "the route cannot fire: its profile is revoked or gone",
       remedy: "the witness restores the profile, or the route is bound to one that stands"},
      {:xenia_no_such_route, "no route of hers, or no open run, has that name or number",
       remedy: "read the routes; a built-in is asked through its own tool"},
      {:xenia_profile_invalid,
       "a profile is a key of 2 to 40 lowercase letters, digits or -, and exactly one origin (https://host)",
       remedy: "name one origin; a profile never spans two"},
      {:xenia_dispatch_failed,
       "the command was not recorded: the command bus refused it or failed before the inbox decided",
       remedy:
         "refused is a command without its actor, instant or note, a bug in the caller; anything else is the event store's"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Xenia.Projectors.Correspondence, Oneiroi.Xenia.Projectors.Routes]

  @doc "Receives a delivery of messages; each answers `{:ok, number}` or `{:ok, :duplicate}` or its refusal."
  @spec receive_messages(String.t(), [map()], Oneiroi.Actor.t()) ::
          {:ok, [term()]} | {:error, term()}
  defexport(receive_messages(resident_id, list, actor),
    do: Inbox.receive_messages(resident_id, list, actor)
  )

  @doc "Either party blocks an identity on a platform, with a note: its messages are counted, never kept."
  @spec block(String.t(), String.t(), String.t(), String.t() | nil, String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(block(resident_id, platform, identity, name, note, actor),
    do: Inbox.block(resident_id, platform, identity, name, note, actor)
  )

  @doc "The party who set a block lifts it, with a note."
  @spec unblock(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(unblock(resident_id, platform, identity, note, actor),
    do: Inbox.unblock(resident_id, platform, identity, note, actor)
  )

  @doc "The resident marks messages read."
  @spec mark(String.t(), [pos_integer()], Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(mark(resident_id, numbers, actor), do: Inbox.mark(resident_id, numbers, actor))

  @doc "The resident drafts a reply, to a message by number or to a named platform, account and recipient; returns its number."
  @spec draft_reply(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(draft_reply(resident_id, attrs, actor),
    do: Inbox.draft_reply(resident_id, attrs, actor)
  )

  @doc "The witness approves (`true`) or declines a drafted reply, with a note."
  @spec decide_reply(String.t(), pos_integer(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decide_reply(resident_id, number, approve?, note, actor),
    do: Inbox.decide_reply(resident_id, number, approve?, note, actor)
  )

  @doc "An adapter or the witness marks an approved reply sent, with where it now is: the receipt."
  @spec mark_sent(String.t(), pos_integer(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(mark_sent(resident_id, number, url, actor),
    do: Inbox.mark_sent(resident_id, number, url, actor)
  )

  @doc "Messages, newest first; `state` narrows to received or blocked."
  @spec messages(String.t(), String.t() | nil) :: [map()]
  defexport(messages(resident_id, state), do: Inbox.messages(resident_id, state))

  @doc "One message by number, or nil."
  @spec message(String.t(), pos_integer()) :: map() | nil
  defexport(message(resident_id, number), do: Inbox.message(resident_id, number))

  @doc "The blocked identities, each with who blocked it and why."
  @spec blocks(String.t()) :: [map()]
  defexport(blocks(resident_id), do: Inbox.blocks(resident_id))

  @doc "Replies, newest first; `state` narrows to drafted, approved, declined or sent."
  @spec replies(String.t(), String.t() | nil) :: [map()]
  defexport(replies(resident_id, state), do: Inbox.replies(resident_id, state))

  @doc "The reader's two allowlists (xenia#16): the sites it may reach to read correspondence and to research, as the witness set them or the defaults."
  @spec reader_sites(String.t()) :: %{
          scrape: [String.t()],
          research: [String.t()],
          set_at: DateTime.t() | nil
        }
  defexport(reader_sites(resident_id), do: Inbox.reader_sites(resident_id))

  @doc "Sets the reader's two allowlists (xenia#16); the witness's alone."
  @spec set_reader_sites(String.t(), [String.t()], [String.t()], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_reader_sites(resident_id, scrape, research, actor),
    do: Inbox.set_reader_sites(resident_id, scrape, research, actor)
  )

  @doc "What waits on the witness here: the replies to approve."
  @spec needs_you(String.t()) :: %{replies: non_neg_integer()}
  defexport(needs_you(resident_id), do: Inbox.needs_you(resident_id))

  @doc "Every route of the house for the resident, the built-ins then hers, each with whether it can fire and why not (xenia#19)."
  @spec routes(String.t()) :: [map()]
  defexport(routes(resident_id), do: Routing.routes(resident_id))

  @doc "The kinds a route of hers may land in (xenia#19)."
  @spec route_landing_kinds(String.t()) :: [String.t()]
  defexport(route_landing_kinds(resident_id), do: Routing.landing_kinds(resident_id))

  @doc "Her routes' runs, newest first (xenia#19)."
  @spec route_runs(String.t()) :: [map()]
  defexport(route_runs(resident_id), do: Routing.runs(resident_id))

  @doc "Defines or rewrites a route of hers against the safe subset, either party (xenia#19)."
  @spec define_route(String.t(), map(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(define_route(resident_id, attrs, note, actor),
    do: Routing.define(resident_id, attrs, note, actor)
  )

  @doc "Asks a run of a route of hers, either party (xenia#19)."
  @spec ask_route(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(ask_route(resident_id, key, note, actor),
    do: Routing.ask(resident_id, key, note, actor)
  )

  @doc "A run's reading lands in its route's kind (xenia#19), the reader's or the witness's."
  @spec land_route(String.t(), pos_integer(), String.t() | nil, String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(land_route(resident_id, number, title, text, actor),
    do: Routing.land(resident_id, number, title, text, actor)
  )

  @doc "A run the reader could not do, and why (xenia#19)."
  @spec fail_route(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(fail_route(resident_id, number, reason, actor),
    do: Routing.fail(resident_id, number, reason, actor)
  )

  @doc "What the reader is given: every route with its runner, state and what waits, and the profiles (xenia#19)."
  @spec reader(String.t()) :: map()
  defexport(reader(resident_id), do: Routing.reader(resident_id))

  @doc "The profiles her routes read through, with the routes bound to each; never a credential (xenia#19)."
  @spec profiles(String.t()) :: [map()]
  defexport(profiles(resident_id), do: Routing.profiles(resident_id))

  @doc "The witness makes or names a profile (xenia#19)."
  @spec set_profile(String.t(), map(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_profile(resident_id, attrs, note, actor),
    do: Routing.set_profile(resident_id, attrs, note, actor)
  )

  @doc "The witness revokes a profile; its routes stay, unable to fire (xenia#19)."
  @spec revoke_profile(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(revoke_profile(resident_id, key, note, actor),
    do: Routing.revoke_profile(resident_id, key, note, actor)
  )

  @doc "The witness restores a revoked profile (xenia#19)."
  @spec restore_profile(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(restore_profile(resident_id, key, note, actor),
    do: Routing.restore_profile(resident_id, key, note, actor)
  )
end
