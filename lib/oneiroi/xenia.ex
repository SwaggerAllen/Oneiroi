defmodule Oneiroi.Xenia do
  @moduledoc """
  Inbound (spec §6.6): correspondence and its approval queue, for any
  platform and any resident. A third party's message arrives through an
  inbound adapter (a hands agent with the `reader` role, never the
  resident) or the witness's paste; it waits for the witness's reading
  (F23) unless its verified sender is one the witness trusts, and then it
  reaches the resident approved. The resident drafts replies; the
  witness approves or declines each with a note; an adapter or the
  witness sends an approved one and marks it sent, which is the receipt.
  The reader, mail, feeds and the digest of §6.6 are not built yet.
  """
  use Oneiroi.System, slug: :xenia

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
      Correspondence,
      Inbox,
      Router,
      Commands.ReceiveMessage,
      Commands.DecideMessage,
      Commands.TrustCorrespondent,
      Commands.DistrustCorrespondent,
      Commands.MarkMessages,
      Commands.DraftReply,
      Commands.DecideReply,
      Commands.MarkReplySent,
      Events.CorrespondenceReceived,
      Events.CorrespondenceApproved,
      Events.CorrespondenceRejected,
      Events.CorrespondenceMarked,
      Events.CorrespondentTrusted,
      Events.CorrespondentDistrusted,
      Events.ReplyDrafted,
      Events.ReplyApproved,
      Events.ReplyDeclined,
      Events.ReplyMarkedSent,
      Store,
      Store.Message,
      Store.Correspondent,
      Store.Reply
    ]

  alias Oneiroi.Xenia.Inbox

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config, do: []

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Xenia.Events.CorrespondenceReceived, 1},
      {Oneiroi.Xenia.Events.CorrespondenceApproved, 1},
      {Oneiroi.Xenia.Events.CorrespondenceRejected, 1},
      {Oneiroi.Xenia.Events.CorrespondenceMarked, 1},
      {Oneiroi.Xenia.Events.CorrespondentTrusted, 1},
      {Oneiroi.Xenia.Events.CorrespondentDistrusted, 1},
      {Oneiroi.Xenia.Events.ReplyDrafted, 1},
      {Oneiroi.Xenia.Events.ReplyApproved, 1},
      {Oneiroi.Xenia.Events.ReplyDeclined, 1},
      {Oneiroi.Xenia.Events.ReplyMarkedSent, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:xenia_not_allowed,
       "the inbound adapter or the witness delivers; the witness reads through, trusts and approves; the resident marks and drafts",
       remedy: "do this as the party it belongs to"},
      {:xenia_message_invalid,
       "a message names its platform (a lowercase slug), the account, its id there, its sender and when it was sent, and carries words of at most 64 KiB",
       remedy: "send every field; one line each, the words whole"},
      {:xenia_batch_too_large, "a delivery carries at most 40 messages",
       remedy: "send the rest in another delivery"},
      {:xenia_no_such_message, "no message the resident can answer has that number",
       remedy: "read the inbox; a reply answers an approved message"},
      {:xenia_already_decided, "it was already approved or declined",
       remedy: "read where it stands; a decision is not made twice"},
      {:xenia_correspondent_invalid,
       "a trusted correspondent is a platform (a lowercase slug) and an identity on it, one line",
       remedy: "name the platform and the address or account"},
      {:xenia_no_such_correspondent, "no one trusted has that identity on that platform",
       remedy: "read the trusted list"},
      {:xenia_reply_invalid,
       "a reply is words of at most 20,000 characters to an approved message, or to a named platform, account and recipient",
       remedy: "say what to send, and where"},
      {:xenia_no_such_reply, "no reply has that number", remedy: "read the replies"},
      {:xenia_reply_not_approved, "only an approved reply is sent",
       remedy: "the witness approves it first"},
      {:xenia_dispatch_failed,
       "the command was not recorded: the command bus refused it or failed before the inbox decided",
       remedy:
         "refused is a command without its actor, instant or note, a bug in the caller; anything else is the event store's"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Xenia.Projectors.Correspondence]

  @doc "Receives a delivery of messages; each answers `{:ok, number}` or `{:ok, :duplicate}` or its refusal."
  @spec receive_messages(String.t(), [map()], Oneiroi.Actor.t()) ::
          {:ok, [term()]} | {:error, term()}
  defexport(receive_messages(resident_id, list, actor),
    do: Inbox.receive_messages(resident_id, list, actor)
  )

  @doc "The witness approves (`true`) or rejects a waiting message, with a note the resident reads first."
  @spec decide_message(String.t(), pos_integer(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(decide_message(resident_id, number, approve?, note, actor),
    do: Inbox.decide_message(resident_id, number, approve?, note, actor)
  )

  @doc "The witness trusts a verified identity on a platform: its messages arrive approved."
  @spec trust(String.t(), String.t(), String.t(), String.t() | nil, String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(trust(resident_id, platform, identity, name, note, actor),
    do: Inbox.trust(resident_id, platform, identity, name, note, actor)
  )

  @doc "The witness withdraws trust from an identity."
  @spec distrust(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(distrust(resident_id, platform, identity, note, actor),
    do: Inbox.distrust(resident_id, platform, identity, note, actor)
  )

  @doc "The resident marks approved messages read."
  @spec mark(String.t(), [pos_integer()], Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(mark(resident_id, numbers, actor), do: Inbox.mark(resident_id, numbers, actor))

  @doc "The resident drafts a reply, to an approved message by number or to a named platform, account and recipient; returns its number."
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

  @doc "Messages, newest first; `state` narrows to pending, approved or rejected."
  @spec messages(String.t(), String.t() | nil) :: [map()]
  defexport(messages(resident_id, state), do: Inbox.messages(resident_id, state))

  @doc "One message by number, or nil."
  @spec message(String.t(), pos_integer()) :: map() | nil
  defexport(message(resident_id, number), do: Inbox.message(resident_id, number))

  @doc "The trusted correspondents."
  @spec correspondents(String.t()) :: [map()]
  defexport(correspondents(resident_id), do: Inbox.correspondents(resident_id))

  @doc "Replies, newest first; `state` narrows to drafted, approved, declined or sent."
  @spec replies(String.t(), String.t() | nil) :: [map()]
  defexport(replies(resident_id, state), do: Inbox.replies(resident_id, state))

  @doc "What waits on the witness here: messages to read through, replies to approve."
  @spec needs_you(String.t()) :: %{messages: non_neg_integer(), replies: non_neg_integer()}
  defexport(needs_you(resident_id), do: Inbox.needs_you(resident_id))
end
