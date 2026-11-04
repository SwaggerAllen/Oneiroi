defmodule Oneiroi.Xenia.Correspondence do
  @moduledoc """
  The correspondence aggregate on `xenia-<resident_id>` (spec §6.6, F23
  as amended 2026-11-02). Pure: it holds what was received (by its
  dedupe key, so an adapter may send the same message twice), each
  message's state, the blocked identities with who blocked each, and
  each reply's state, and decides who may do what:

  - an inbound adapter or the witness delivers; a message reaches the
    resident at once unless its sender is blocked;
  - either party blocks an identity, and only the party who set a block
    lifts it;
  - only the resident marks a message read or drafts a reply;
  - only the witness approves or declines a reply;
  - the witness or an adapter marks an approved reply sent.

  Identities compare trimmed and lowercased, so `Grace@Example.com` and
  `grace@example.com` are one sender; a display name never counts.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Events

  defstruct [
    :id,
    received: %{},
    messages: %{},
    blocked: %{},
    replies: %{}
  ]

  # Bounds (systems/xenia.md #10): a message whole up to 64 KiB, a reply
  # up to 20,000 characters, a name or a subject one line.
  @platform ~r/\A[a-z][a-z0-9_-]{0,31}\z/
  @text_bytes 65_536
  @reply_limit 20_000
  @id_limit 512
  @identity_limit 320
  @line_limit 300

  # An origin: a scheme and a host, a port at most; or `*` for any.
  @origin ~r/\Ahttps?:\/\/[a-z0-9.-]+(:\d{1,5})?\z/
  @sites_limit 50

  @doc "Whether an allowlist entry is an origin (`https://host`) or `*`."
  @spec origin_ok?(term()) :: boolean()
  def origin_ok?("*"), do: true
  def origin_ok?(o), do: is_binary(o) and Regex.match?(@origin, o)

  @doc "Whether a platform's name is well formed: a lowercase slug of at most 32."
  @spec platform_ok?(term()) :: boolean()
  def platform_ok?(p), do: is_binary(p) and Regex.match?(@platform, p)

  @doc "An identity as it is compared: trimmed and lowercased."
  @spec identity(String.t()) :: String.t()
  def identity(s) when is_binary(s), do: s |> String.trim() |> String.downcase()

  # ---- inbound ----

  def execute(%__MODULE__{} = s, %Commands.ReceiveMessage{} = c) do
    cond do
      not deliverer?(c.actor) ->
        {:error, Error.new(:xenia_not_allowed, :xenia_receive_actor, actor: c.actor.kind)}

      not received_ok?(c) ->
        {:error, Error.new(:xenia_message_invalid, :xenia_receive_invalid, limit: @text_bytes)}

      Map.has_key?(s.received, {c.platform, c.account, c.external_id}) ->
        []

      true ->
        received(s, c)
    end
  end

  def execute(%__MODULE__{} = s, %Commands.MarkMessages{} = c) do
    fresh =
      c.numbers
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.filter(fn n -> match?(%{state: :received, read: false}, s.messages[n]) end)

    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:xenia_not_allowed, :xenia_mark_actor, actor: c.actor.kind)}

      fresh == [] ->
        []

      true ->
        %Events.CorrespondenceMarked{actor: c.actor, at: c.at, id: c.id, numbers: fresh}
    end
  end

  # ---- blocks ----

  def execute(%__MODULE__{} = s, %Commands.BlockCorrespondent{} = c) do
    cond do
      not party?(c.actor) ->
        {:error, Error.new(:xenia_not_allowed, :xenia_block_actor, actor: c.actor.kind)}

      not platform_ok?(c.platform) or not line?(c.identity, @identity_limit) ->
        {:error, Error.new(:xenia_block_invalid, :xenia_block_invalid)}

      Map.has_key?(s.blocked, {c.platform, identity(c.identity)}) ->
        []

      true ->
        %Events.CorrespondentBlocked{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          platform: c.platform,
          identity: identity(c.identity),
          name: c.name
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.UnblockCorrespondent{} = c) do
    by = if is_binary(c.identity), do: s.blocked[{c.platform, identity(c.identity)}]

    cond do
      not party?(c.actor) ->
        {:error, Error.new(:xenia_not_allowed, :xenia_unblock_actor, actor: c.actor.kind)}

      is_nil(by) ->
        {:error, Error.new(:xenia_no_such_block, :xenia_unblock_absent)}

      # A block is lifted by the party who set it: the resident's
      # boundary is hers, the witness's his (xenia#12).
      by != c.actor.kind ->
        {:error, Error.new(:xenia_not_yours, :xenia_unblock_other_party, blocked_by: by)}

      true ->
        %Events.CorrespondentUnblocked{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          platform: c.platform,
          identity: identity(c.identity)
        }
    end
  end

  # ---- outbound ----

  def execute(%__MODULE__{} = s, %Commands.DraftReply{} = c) do
    origin = c.in_reply_to && s.messages[c.in_reply_to]

    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:xenia_not_allowed, :xenia_draft_actor, actor: c.actor.kind)}

      c.in_reply_to != nil and not match?(%{state: :received}, origin) ->
        {:error,
         Error.new(:xenia_no_such_message, :xenia_draft_reply_absent, number: c.in_reply_to)}

      not (is_binary(c.text) and String.trim(c.text) != "" and
               String.length(c.text) <= @reply_limit) ->
        {:error, Error.new(:xenia_reply_invalid, :xenia_draft_text, limit: @reply_limit)}

      true ->
        draft(s, c, origin)
    end
  end

  # The reader's allowlists (xenia#16): the witness's alone, each list
  # at most 50 origins or `*`.
  def execute(%__MODULE__{}, %Commands.SetReaderSites{} = c) do
    lists = [List.wrap(c.scrape), List.wrap(c.research)]

    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:xenia_not_allowed, :xenia_reader_sites_actor, actor: c.actor.kind)}

      not Enum.all?(
        lists,
        &(length(&1) <= @sites_limit and Enum.all?(&1, fn o -> origin_ok?(o) end))
      ) ->
        {:error,
         Error.new(:xenia_sites_invalid, :xenia_reader_sites_invalid, limit: @sites_limit)}

      true ->
        %Events.ReaderSitesSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          scrape: Enum.uniq(List.wrap(c.scrape)),
          research: Enum.uniq(List.wrap(c.research))
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.DecideReply{} = c) do
    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:xenia_not_allowed, :xenia_decide_reply_actor, actor: c.actor.kind)}

      not Map.has_key?(s.replies, c.number) ->
        {:error, Error.new(:xenia_no_such_reply, :xenia_decide_reply_absent, number: c.number)}

      s.replies[c.number] != :drafted ->
        {:error, Error.new(:xenia_already_decided, :xenia_decide_reply_decided, number: c.number)}

      c.approve == true ->
        %Events.ReplyApproved{actor: c.actor, at: c.at, note: c.note, id: c.id, number: c.number}

      true ->
        %Events.ReplyDeclined{actor: c.actor, at: c.at, note: c.note, id: c.id, number: c.number}
    end
  end

  def execute(%__MODULE__{} = s, %Commands.MarkReplySent{} = c) do
    cond do
      not deliverer?(c.actor) ->
        {:error, Error.new(:xenia_not_allowed, :xenia_sent_actor, actor: c.actor.kind)}

      s.replies[c.number] == :sent ->
        []

      s.replies[c.number] != :approved ->
        {:error, Error.new(:xenia_reply_not_approved, :xenia_sent_unapproved, number: c.number)}

      not (is_nil(c.url) or line?(c.url, 2_048)) ->
        {:error, Error.new(:xenia_reply_invalid, :xenia_sent_url)}

      true ->
        %Events.ReplyMarkedSent{actor: c.actor, at: c.at, id: c.id, number: c.number, url: c.url}
    end
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.ReaderSitesSet{} = e), do: %{s | id: e.id}

  def apply(%__MODULE__{} = s, %Events.CorrespondenceReceived{} = e) do
    %{
      s
      | id: e.id,
        received: Map.put(s.received, {e.platform, e.account, e.external_id}, e.number),
        messages:
          Map.put(s.messages, e.number, %{
            state: if(e.blocked, do: :blocked, else: :received),
            read: false,
            platform: e.platform,
            account: e.account,
            thread: e.thread,
            sender: e.sender
          })
    }
  end

  def apply(%__MODULE__{} = s, %Events.CorrespondenceMarked{} = e),
    do: Enum.reduce(e.numbers, s, &put_message(&2, &1, read: true))

  def apply(%__MODULE__{} = s, %Events.CorrespondentBlocked{} = e),
    do: %{s | id: e.id, blocked: Map.put(s.blocked, {e.platform, e.identity}, kind_of(e.actor))}

  def apply(%__MODULE__{} = s, %Events.CorrespondentUnblocked{} = e),
    do: %{s | blocked: Map.delete(s.blocked, {e.platform, e.identity})}

  def apply(%__MODULE__{} = s, %Events.ReplyDrafted{} = e),
    do: %{s | id: e.id, replies: Map.put(s.replies, e.number, :drafted)}

  def apply(%__MODULE__{} = s, %Events.ReplyApproved{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :approved)}

  def apply(%__MODULE__{} = s, %Events.ReplyDeclined{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :declined)}

  def apply(%__MODULE__{} = s, %Events.ReplyMarkedSent{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :sent)}

  # ---- helpers ----

  # A blocked sender's message keeps what dedupe and the count need and
  # never the words: nothing blocked reaches the resident by any door,
  # the export included (xenia#12, #14).
  defp received(s, c) do
    sender = identity(c.sender)
    blocked? = Map.has_key?(s.blocked, {c.platform, sender})

    %Events.CorrespondenceReceived{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: map_size(s.messages) + 1,
      platform: c.platform,
      account: c.account,
      external_id: c.external_id,
      sender: sender,
      sender_name: unless(blocked?, do: c.sender_name),
      verified: c.verified == true,
      thread: c.thread,
      subject: unless(blocked?, do: c.subject),
      text: unless(blocked?, do: c.text),
      sent_at: c.sent_at,
      blocked: blocked?
    }
  end

  # A reply to a message goes where the message came from; a new one
  # names its platform, its account and whom it is to.
  defp draft(s, c, origin) do
    {platform, account, thread, to} =
      case origin do
        %{} -> {origin.platform, origin.account, origin.thread, origin.sender}
        nil -> {c.platform, c.account, c.thread, c.to && identity(c.to)}
      end

    if platform_ok?(platform) and line?(account, @identity_limit) and line?(to, @identity_limit) do
      %Events.ReplyDrafted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: map_size(s.replies) + 1,
        in_reply_to: c.in_reply_to,
        platform: platform,
        account: account,
        thread: thread,
        to: to,
        text: c.text
      }
    else
      {:error, Error.new(:xenia_reply_invalid, :xenia_draft_address)}
    end
  end

  # Who may deliver a message or mark a reply sent: an inbound adapter
  # (the hands that read and send) or the witness, pasting by hand.
  defp deliverer?(%Actor{kind: kind}), do: kind in [:hands, :witness]

  # The two parties to the relationship, who keep its boundaries.
  defp party?(%Actor{kind: kind}), do: kind in [:resident, :witness]

  # The actor as stored on the event: a struct once decoded.
  defp kind_of(%{kind: kind}) when is_atom(kind), do: kind

  defp received_ok?(c), do: address_ok?(c) and words_ok?(c)

  defp address_ok?(c) do
    platform_ok?(c.platform) and line?(c.account, @identity_limit) and
      line?(c.external_id, @id_limit) and line?(c.sender, @identity_limit)
  end

  defp words_ok?(c) do
    Enum.all?([c.sender_name, c.subject], &optional_line?/1) and
      (is_nil(c.thread) or line?(c.thread, @id_limit)) and
      is_binary(c.text) and c.text != "" and byte_size(c.text) <= @text_bytes and
      match?(%DateTime{}, c.sent_at)
  end

  defp line?(s, limit),
    do: is_binary(s) and String.trim(s) != "" and String.length(s) <= limit and not (s =~ "\n")

  defp optional_line?(nil), do: true
  defp optional_line?(s), do: line?(s, @line_limit)

  defp put_message(s, number, changes),
    do: %{s | messages: Map.update!(s.messages, number, &Map.merge(&1, Map.new(changes)))}
end
