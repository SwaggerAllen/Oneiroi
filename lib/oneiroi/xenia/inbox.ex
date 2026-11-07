defmodule Oneiroi.Xenia.Inbox do
  @moduledoc """
  Correspondence's service functions (spec §6.6, F23): the command edge
  for receiving, blocking, marking, drafting, deciding
  and sending; and the reads the Inbox screen and the resident's tools
  take, each under the resident's scope.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Events
  alias Oneiroi.Xenia.Router
  alias Oneiroi.Xenia.Store

  # A delivery's bound (xenia#10): an adapter sends at most this many
  # messages in one request, as the spec's mail bound is 40 a morning.
  @batch 40

  @doc "The most messages one delivery carries."
  def batch, do: @batch

  @doc """
  Receives one message; `{:ok, number}` for a new one, `{:ok, :duplicate}`
  when its platform, account and external id were received before.
  """
  def receive_message(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    command = %Commands.ReceiveMessage{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      platform: attrs[:platform],
      account: attrs[:account],
      external_id: attrs[:external_id],
      sender: attrs[:sender],
      sender_name: attrs[:sender_name],
      verified: attrs[:verified] == true,
      thread: attrs[:thread],
      subject: attrs[:subject],
      text: attrs[:text],
      sent_at: attrs[:sent_at]
    }

    case dispatch(command) do
      {:ok, [%Events.CorrespondenceReceived{number: n}]} -> {:ok, n}
      {:ok, []} -> {:ok, :duplicate}
      other -> other
    end
  end

  @doc "Receives a delivery of messages, each answered in order; refused whole past the bound."
  def receive_messages(resident_id, list, %Actor{} = actor) when is_list(list) do
    if length(list) > @batch,
      do: {:error, Error.new(:xenia_batch_too_large, :xenia_receive_batch, bound: @batch)},
      else: {:ok, Enum.map(list, &receive_message(resident_id, &1, actor))}
  end

  def block(resident_id, platform, identity, name, note, %Actor{} = actor) do
    %Commands.BlockCorrespondent{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      platform: platform,
      identity: identity,
      name: name,
      note: note
    }
    |> dispatch()
    |> ok()
  end

  def unblock(resident_id, platform, identity, note, %Actor{} = actor) do
    %Commands.UnblockCorrespondent{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      platform: platform,
      identity: identity,
      note: note
    }
    |> dispatch()
    |> ok()
  end

  def mark(resident_id, numbers, %Actor{} = actor) do
    %Commands.MarkMessages{actor: actor, at: Clock.now(), id: resident_id, numbers: numbers}
    |> dispatch()
    |> ok()
  end

  def draft_reply(resident_id, attrs, %Actor{} = actor) when is_map(attrs) do
    command = %Commands.DraftReply{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      in_reply_to: attrs[:in_reply_to],
      platform: attrs[:platform],
      account: attrs[:account],
      thread: attrs[:thread],
      to: attrs[:to],
      text: attrs[:text],
      supersedes: attrs[:supersedes]
    }

    case dispatch(command) do
      {:ok, [%Events.ReplyDrafted{number: n} | _superseded]} -> {:ok, n}
      other -> other
    end
  end

  def decide_reply(resident_id, number, approve?, note, %Actor{} = actor) do
    %Commands.DecideReply{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      approve: approve?,
      note: note
    }
    |> dispatch()
    |> ok()
  end

  def mark_sent(resident_id, number, url, %Actor{} = actor) do
    %Commands.MarkReplySent{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      url: url
    }
    |> dispatch()
    |> ok()
  end

  # ---- reads ----

  def messages(resident_id, state \\ nil),
    do: Scope.resident(resident_id, fn -> Store.messages(state) end)

  def message(resident_id, number),
    do: Scope.resident(resident_id, fn -> Store.message(number) end)

  def blocks(resident_id), do: Scope.resident(resident_id, fn -> Store.blocks() end)

  # Before the witness sets them: Substack to read correspondence, and
  # nothing to research, which waits for the witness to name the sites.
  @default_scrape ["https://substack.com", "https://www.substack.com"]

  @doc "The reader's allowlists: as the witness set them, or the defaults (xenia#16)."
  def reader_sites(resident_id) do
    case Scope.resident(resident_id, fn -> Store.reader_sites() end) do
      nil -> %{scrape: @default_scrape, research: [], set_at: nil}
      s -> %{scrape: s.scrape, research: s.research, set_at: s.set_at}
    end
  end

  @doc "Sets the reader's allowlists; the witness's alone."
  def set_reader_sites(resident_id, scrape, research, %Actor{} = actor) do
    %Commands.SetReaderSites{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      scrape: scrape,
      research: research
    }
    |> dispatch()
    |> ok()
  end

  def replies(resident_id, state \\ nil),
    do: Scope.resident(resident_id, fn -> Store.replies(state) end)

  @doc "What waits on the witness here: the replies to approve (the `needs_you` share of spec §5)."
  def needs_you(resident_id), do: %{replies: length(replies(resident_id, "drafted"))}

  defp ok({:ok, _events}), do: :ok
  defp ok(other), do: other

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:xenia_dispatch_failed, :xenia_command_dispatch, reason)}
    end
  end
end
