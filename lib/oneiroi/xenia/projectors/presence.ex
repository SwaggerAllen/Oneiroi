defmodule Oneiroi.Xenia.Projectors.Presence do
  @moduledoc """
  Folds the presence stream (xenia#20): the switch, the follow list
  (accounts gone from a new fetch kept and marked unfollowed, so their
  history stays), the mask, each pass with its reads and the cursor it
  leaves, and every interaction's way to being sent.
  """
  use Oneiroi.Projection, name: "xenia_presence"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Xenia.Events

  alias Oneiroi.Xenia.Store.{
    Presence,
    PresenceAccount,
    PresenceInteraction,
    PresencePass,
    PresenceRead
  }

  fold(%Events.PresenceSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :presence,
      %Presence{resident_id: e.id, enabled: e.enabled, handle: e.handle, set_at: e.at},
      on_conflict: {:replace, [:enabled, :handle, :set_at]},
      conflict_target: [:resident_id]
    )
  end)

  fold(%Events.FollowsRecorded{} = e, _metadata, fn multi ->
    accounts = Enum.map(e.accounts, &string_keyed/1)
    keys = Enum.map(accounts, & &1["key"])

    rows =
      for a <- accounts do
        %{
          resident_id: e.id,
          key: a["key"],
          name: a["name"],
          host: a["host"],
          publication_id: a["publication_id"],
          author_id: a["author_id"],
          first_seen_at: e.at,
          followed: true
        }
      end

    multi
    |> Multi.insert(
      :presence,
      %Presence{resident_id: e.id, follows_at: e.at, visible: e.visible},
      on_conflict: {:replace, [:follows_at, :visible]},
      conflict_target: [:resident_id]
    )
    |> Multi.insert_all(:accounts, PresenceAccount, rows,
      on_conflict: {:replace, [:name, :host, :publication_id, :author_id, :followed]},
      conflict_target: [:resident_id, :key]
    )
    |> Multi.update_all(
      :unfollowed,
      from(a in PresenceAccount, where: a.resident_id == ^e.id and a.key not in ^keys),
      set: [followed: false]
    )
  end)

  fold(%Events.AccountExcluded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :account,
      from(a in PresenceAccount, where: a.resident_id == ^e.id and a.key == ^e.key),
      set: [excluded: true, excluded_at: e.at, reason: e.note]
    )
  end)

  fold(%Events.AccountIncluded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :account,
      from(a in PresenceAccount, where: a.resident_id == ^e.id and a.key == ^e.key),
      set: [excluded: false, excluded_at: nil, reason: nil]
    )
  end)

  fold(%Events.PassDrawn{} = e, _metadata, fn multi ->
    accounts = Enum.map(e.accounts, &to_string/1)

    reads =
      for r <- Enum.map(e.reads, &string_keyed/1) do
        %{
          resident_id: e.id,
          pass: e.number,
          item: r["key"],
          account: r["account"],
          kind: r["kind"],
          title: r["title"],
          url: r["url"],
          published_at: instant(r["at"]),
          likes: r["likes"] || 0,
          comments: r["comments"] || 0,
          restacks: r["restacks"] || 0,
          score: r["score"] || 0,
          cut: r["cut"],
          excerpt: r["excerpt"]
        }
      end

    multi
    |> Multi.insert(
      :pass,
      %PresencePass{
        resident_id: e.id,
        number: e.number,
        day: e.day,
        accounts: accounts,
        pool: e.pool,
        ranked: e.ranked,
        serendipity: e.serendipity,
        cap: e.cap,
        drawn_at: e.at
      },
      on_conflict: :nothing
    )
    |> Multi.insert_all(:reads, PresenceRead, reads, on_conflict: :nothing)
    |> Multi.update_all(
      :sampled,
      from(a in PresenceAccount, where: a.resident_id == ^e.id and a.key in ^accounts),
      set: [last_sampled_at: e.at]
    )
    |> Multi.insert(
      :cursor,
      %Presence{resident_id: e.id, cursor: List.last(accounts)},
      on_conflict: {:replace, [:cursor]},
      conflict_target: [:resident_id]
    )
  end)

  fold(%Events.ItemRead{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :read,
      from(r in PresenceRead,
        where: r.resident_id == ^e.id and r.pass == ^e.pass and r.item == ^e.item
      ),
      set: [read_at: e.at]
    )
  end)

  fold(%Events.InteractionStaged{} = e, _metadata, fn multi ->
    multi =
      Multi.insert(
        multi,
        :interaction,
        %PresenceInteraction{
          resident_id: e.id,
          number: e.number,
          pass: e.pass,
          item: e.item,
          account: e.account,
          kind: e.kind,
          text: e.text,
          supersedes: e.supersedes,
          state: "staged",
          staged_at: e.at
        },
        on_conflict: :nothing
      )

    if e.supersedes,
      do:
        Multi.update_all(
          multi,
          :superseded,
          interaction(e.id, e.supersedes),
          set: [state: "superseded", superseded_by: e.number]
        ),
      else: multi
  end)

  fold(%Events.InteractionDecided{} = e, _metadata, fn multi ->
    state =
      case e.decision do
        "approve" -> "approved"
        "revise" -> "revise"
        _pass -> "passed"
      end

    Multi.update_all(multi, :decided, interaction(e.id, e.number),
      set: [state: state, comment: e.comment, release_at: e.release_at, decided_at: e.at]
    )
  end)

  fold(%Events.InteractionSent{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :sent, interaction(e.id, e.number),
      set: [state: "sent", url: e.url, sent_at: e.at]
    )
  end)

  fold(%Events.InteractionFailed{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :failed, interaction(e.id, e.number),
      set: [state: "failed", reason: e.reason, sent_at: e.at]
    )
  end)

  defp interaction(id, number),
    do: from(i in PresenceInteraction, where: i.resident_id == ^id and i.number == ^number)

  defp string_keyed(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp instant(%DateTime{} = at), do: at

  defp instant(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _bad -> nil
    end
  end

  defp instant(_none), do: nil
end
