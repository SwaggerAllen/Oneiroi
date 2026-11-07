defmodule Oneiroi.Xenia.Projectors.Correspondence do
  @moduledoc "Folds the correspondence streams into messages, blocks and replies."
  use Oneiroi.Projection, name: "xenia_correspondence"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Xenia.Events
  alias Oneiroi.Xenia.Store.{Block, Message, ReaderSites, Reply}

  fold(%Events.CorrespondenceReceived{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :message,
      %Message{
        resident_id: e.id,
        number: e.number,
        platform: e.platform,
        account: e.account,
        external_id: e.external_id,
        sender: e.sender,
        sender_name: e.sender_name,
        verified: e.verified,
        thread: e.thread,
        subject: e.subject,
        text: e.text,
        sent_at: e.sent_at,
        received_at: e.at,
        received_by: actor_kind(e.actor),
        state: if(e.blocked, do: "blocked", else: "received")
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.CorrespondenceMarked{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :marked,
      from(m in Message,
        where: m.resident_id == ^e.id and m.number in ^e.numbers and is_nil(m.read_at)
      ),
      set: [read_at: e.at]
    )
  end)

  fold(%Events.ReaderSitesSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :reader_sites,
      %ReaderSites{
        resident_id: e.id,
        scrape: e.scrape || [],
        research: e.research || [],
        set_at: e.at
      },
      on_conflict: {:replace, [:scrape, :research, :set_at]},
      conflict_target: [:resident_id]
    )
  end)

  fold(%Events.CorrespondentBlocked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :block,
      %Block{
        resident_id: e.id,
        platform: e.platform,
        identity: e.identity,
        name: e.name,
        note: e.note,
        blocked_by: actor_kind(e.actor),
        blocked_at: e.at
      },
      on_conflict: {:replace, [:name, :note, :blocked_by, :blocked_at]},
      conflict_target: [:resident_id, :platform, :identity]
    )
  end)

  fold(%Events.CorrespondentUnblocked{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :unblocked,
      from(b in Block,
        where: b.resident_id == ^e.id and b.platform == ^e.platform and b.identity == ^e.identity
      )
    )
  end)

  fold(%Events.ReplyDrafted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :reply,
      %Reply{
        resident_id: e.id,
        number: e.number,
        in_reply_to: e.in_reply_to,
        platform: e.platform,
        account: e.account,
        thread: e.thread,
        to: e.to,
        text: e.text,
        state: "drafted",
        drafted_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.ReplySuperseded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :superseded,
      from(r in Reply, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [state: "superseded", superseded_by: e.by, decided_at: e.at]
    )
  end)

  fold(%Events.ReplyApproved{} = e, _metadata, fn multi ->
    decide(multi, Reply, e, "approved")
  end)

  fold(%Events.ReplyDeclined{} = e, _metadata, fn multi ->
    decide(multi, Reply, e, "declined")
  end)

  fold(%Events.ReplyMarkedSent{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :sent,
      from(r in Reply, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [state: "sent", sent_at: e.at, sent_by: actor_kind(e.actor), url: e.url]
    )
  end)

  defp decide(multi, schema, e, state) do
    Multi.update_all(
      multi,
      :decided,
      from(r in schema, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [state: state, note: e.note, decided_at: e.at]
    )
  end

  defp actor_kind(%{} = actor), do: to_string(Map.get(actor, :kind) || Map.get(actor, "kind"))
  defp actor_kind(_other), do: nil
end
