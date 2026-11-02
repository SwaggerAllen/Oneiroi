defmodule Oneiroi.Xenia.Correspondence do
  @moduledoc """
  The correspondence aggregate on `xenia-<resident_id>` (spec §6.6, F23).
  Pure: it holds what was received (by its dedupe key, so an adapter may
  send the same message twice), each message's state, the trusted
  identities and each reply's state, and decides who may do what:

  - an inbound adapter or the witness delivers; only the witness reads
    a message through, trusts a sender, or approves a reply;
  - only the resident marks a message read or drafts a reply;
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
    trusted: MapSet.new(),
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

  @doc "Whether a platform's name is well formed: a lowercase slug of at most 32."
  @spec platform_ok?(term()) :: boolean()
  def platform_ok?(p), do: is_binary(p) and Regex.match?(@platform, p)

  @doc "An identity as it is compared: trimmed and lowercased."
  @spec identity(String.t()) :: String.t()
  def identity(s) when is_binary(s), do: s |> String.trim() |> String.downcase()

  # ---- inbound ----

  def execute(%__MODULE__{} = s, %Commands.ReceiveMessage{} = c) do
    key = {c.platform, c.account, c.external_id}

    cond do
      not deliverer?(c.actor) ->
        {:error, Error.new(:xenia_not_allowed, :xenia_receive_actor, actor: c.actor.kind)}

      not received_ok?(c) ->
        {:error, Error.new(:xenia_message_invalid, :xenia_receive_invalid, limit: @text_bytes)}

      Map.has_key?(s.received, key) ->
        []

      true ->
        sender = identity(c.sender)

        %Events.CorrespondenceReceived{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: map_size(s.messages) + 1,
          platform: c.platform,
          account: c.account,
          external_id: c.external_id,
          sender: sender,
          sender_name: c.sender_name,
          verified: c.verified == true,
          thread: c.thread,
          subject: c.subject,
          text: c.text,
          sent_at: c.sent_at,
          trusted: c.verified == true and MapSet.member?(s.trusted, {c.platform, sender})
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.DecideMessage{} = c) do
    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:xenia_not_allowed, :xenia_decide_message_actor, actor: c.actor.kind)}

      not Map.has_key?(s.messages, c.number) ->
        {:error,
         Error.new(:xenia_no_such_message, :xenia_decide_message_absent, number: c.number)}

      s.messages[c.number].state != :pending ->
        {:error,
         Error.new(:xenia_already_decided, :xenia_decide_message_decided, number: c.number)}

      c.approve == true ->
        %Events.CorrespondenceApproved{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: c.number
        }

      true ->
        %Events.CorrespondenceRejected{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: c.number
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.MarkMessages{} = c) do
    fresh =
      c.numbers
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.filter(fn n -> match?(%{state: :approved, read: false}, s.messages[n]) end)

    cond do
      c.actor.kind != :resident ->
        {:error, Error.new(:xenia_not_allowed, :xenia_mark_actor, actor: c.actor.kind)}

      fresh == [] ->
        []

      true ->
        %Events.CorrespondenceMarked{actor: c.actor, at: c.at, id: c.id, numbers: fresh}
    end
  end

  # ---- trust ----

  def execute(%__MODULE__{} = s, %Commands.TrustCorrespondent{} = c) do
    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:xenia_not_allowed, :xenia_trust_actor, actor: c.actor.kind)}

      not platform_ok?(c.platform) or not line?(c.identity, @identity_limit) ->
        {:error, Error.new(:xenia_correspondent_invalid, :xenia_trust_invalid)}

      MapSet.member?(s.trusted, {c.platform, identity(c.identity)}) ->
        []

      true ->
        %Events.CorrespondentTrusted{
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

  def execute(%__MODULE__{} = s, %Commands.DistrustCorrespondent{} = c) do
    cond do
      c.actor.kind != :witness ->
        {:error, Error.new(:xenia_not_allowed, :xenia_distrust_actor, actor: c.actor.kind)}

      not is_binary(c.identity) or
          not MapSet.member?(s.trusted, {c.platform, identity(c.identity)}) ->
        {:error, Error.new(:xenia_no_such_correspondent, :xenia_distrust_absent)}

      true ->
        %Events.CorrespondentDistrusted{
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

      c.in_reply_to != nil and not match?(%{state: :approved}, origin) ->
        {:error,
         Error.new(:xenia_no_such_message, :xenia_draft_reply_absent, number: c.in_reply_to)}

      not (is_binary(c.text) and String.trim(c.text) != "" and
               String.length(c.text) <= @reply_limit) ->
        {:error, Error.new(:xenia_reply_invalid, :xenia_draft_text, limit: @reply_limit)}

      true ->
        draft(s, c, origin)
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

  def apply(%__MODULE__{} = s, %Events.CorrespondenceReceived{} = e) do
    state = if e.trusted, do: :approved, else: :pending

    %{
      s
      | id: e.id,
        received: Map.put(s.received, {e.platform, e.account, e.external_id}, e.number),
        messages:
          Map.put(s.messages, e.number, %{
            state: state,
            read: false,
            platform: e.platform,
            account: e.account,
            thread: e.thread,
            sender: e.sender
          })
    }
  end

  def apply(%__MODULE__{} = s, %Events.CorrespondenceApproved{} = e),
    do: put_message(s, e.number, state: :approved)

  def apply(%__MODULE__{} = s, %Events.CorrespondenceRejected{} = e),
    do: put_message(s, e.number, state: :rejected)

  def apply(%__MODULE__{} = s, %Events.CorrespondenceMarked{} = e),
    do: Enum.reduce(e.numbers, s, &put_message(&2, &1, read: true))

  def apply(%__MODULE__{} = s, %Events.CorrespondentTrusted{} = e),
    do: %{s | id: e.id, trusted: MapSet.put(s.trusted, {e.platform, e.identity})}

  def apply(%__MODULE__{} = s, %Events.CorrespondentDistrusted{} = e),
    do: %{s | trusted: MapSet.delete(s.trusted, {e.platform, e.identity})}

  def apply(%__MODULE__{} = s, %Events.ReplyDrafted{} = e),
    do: %{s | id: e.id, replies: Map.put(s.replies, e.number, :drafted)}

  def apply(%__MODULE__{} = s, %Events.ReplyApproved{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :approved)}

  def apply(%__MODULE__{} = s, %Events.ReplyDeclined{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :declined)}

  def apply(%__MODULE__{} = s, %Events.ReplyMarkedSent{} = e),
    do: %{s | replies: Map.put(s.replies, e.number, :sent)}

  # ---- helpers ----

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
