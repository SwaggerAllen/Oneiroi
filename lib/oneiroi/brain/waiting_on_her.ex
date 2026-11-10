defmodule Oneiroi.Brain.WaitingOnHer do
  @moduledoc """
  What waits on the resident (brain#76, the bell's second tab): the
  other side of `needs_you`. The witness's proposals she has not
  answered (a contract version, an edit to her identity files, a
  bookmark, a revision to a memory, a plugin change), his house letters
  no conversation of hers has read yet, and the files she is waiting to
  write while his edit lease holds them (seshat#55). Oldest first, each
  `{kind, ref, title, since, screen, long, about}`: the needs-you shape
  with a title, the few words that name it.

  Everything here is his own act or a fact about one, so nothing of a
  private session's words can reach it: a title is built from his words
  (his bookmark's line) or from names (a file, a path, a conversation's
  name), never from hers. It only shows: nothing here answers anything
  for her, and nothing reminds her.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  defmodule Entry do
    @moduledoc "One thing waiting on her: every field enforced, as `NeedsYou.Entry` is."
    @enforce_keys [:kind, :ref, :title, :since, :screen, :about]
    defstruct [:kind, :ref, :title, :since, :screen, :about]

    @type t :: %__MODULE__{
            kind: String.t(),
            ref: integer() | String.t(),
            title: String.t(),
            since: DateTime.t(),
            screen: String.t(),
            about: map()
          }
  end

  @kinds ~w(contract_proposal soul_edit bookmark_proposal revision plugin_proposal letter lease_wait)

  @doc "The entry kinds this list can hold."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Everything waiting on the resident, oldest first."
  @spec list(String.t()) :: [map()]
  def list(resident_id) do
    now = Clock.now()

    [
      &contracts/1,
      &soul_edits/1,
      &bookmarks/1,
      &revisions/1,
      &plugins/1,
      &letters/1,
      &leases/1
    ]
    |> Enum.flat_map(& &1.(resident_id))
    |> Enum.sort_by(& &1.since, DateTime)
    |> Enum.map(
      &(&1
        |> Map.from_struct()
        |> Map.put(:long, DateTime.diff(now, &1.since, :hour) >= NeedsYou.long_hours()))
    )
  end

  # The version he proposed and she has neither agreed nor declined.
  defp contracts(resident_id) do
    case AgathosDaimon.contract(resident_id) do
      %{open: %{proposed_by: "witness"} = c} ->
        [
          %Entry{
            kind: "contract_proposal",
            ref: c.version,
            title: "Contract version #{c.version}",
            since: c.proposed_at,
            screen: "agreement",
            about: %{note: c.note}
          }
        ]

      _none ->
        []
    end
  end

  defp soul_edits(resident_id) do
    for e <- AgathosDaimon.edit_proposals(resident_id), e.proposed_by_kind == "witness" do
      %Entry{
        kind: "soul_edit",
        ref: e.ref,
        title: "An edit to #{e.file}",
        since: e.proposed_at,
        screen: "soul",
        about: %{file: e.file, note: e.note}
      }
    end
  end

  defp bookmarks(resident_id) do
    for p <- Kumbukumbu.proposals(resident_id), p.proposed_by_kind == "witness" do
      %Entry{
        kind: "bookmark_proposal",
        ref: p.ref,
        title: p.line,
        since: p.proposed_at,
        screen: "memory",
        about: %{session_key: p.session_key, anchor_ref: p.anchor_ref}
      }
    end
  end

  defp revisions(resident_id) do
    for r <- Kumbukumbu.revisions(resident_id), r.state == "proposed", r.by_kind == "witness" do
      %Entry{
        kind: "revision",
        ref: r.number,
        title: "A #{r.kind} revision to #{r.target_kind} #{r.target_id}",
        since: r.at,
        screen: "memory",
        about: %{target_kind: r.target_kind, target_id: r.target_id, revision: r.kind}
      }
    end
  end

  defp plugins(resident_id) do
    for p <- AgathosDaimon.plugin_proposals(resident_id),
        is_nil(p.answered_at),
        p.proposed_by == "witness" do
      %Entry{
        kind: "plugin_proposal",
        ref: p.number,
        title: "#{String.capitalize(p.change)} #{p.key}",
        since: p.proposed_at,
        screen: "agreement",
        about: %{key: p.key, change: p.change, note: p.note}
      }
    end
  end

  # His house letters no conversation of hers has read: one to a
  # conversation until that conversation reads it, one to the house
  # until any does.
  defp letters(resident_id) do
    for l <- Kumbukumbu.letters(resident_id), l.by_kind == "witness", unread?(l) do
      %Entry{
        kind: "letter",
        ref: l.number,
        title: "Letter to #{l.to_name}",
        since: l.sent_at,
        screen: "chat",
        about: %{to: l.to_name}
      }
    end
  end

  defp unread?(%{to_name: "house", read_by: read_by}), do: read_by == []
  defp unread?(%{to_name: to, read_by: read_by}), do: to not in read_by

  # A file she tried to write while his lease held it (seshat#55): she
  # is waiting on it until he releases it or it goes idle and her next
  # write takes it.
  defp leases(resident_id) do
    for l <- Seshat.leases(resident_id), l.state == "held", l.waiting_at != nil do
      %Entry{
        kind: "lease_wait",
        ref: l.path,
        title: "Waiting to write #{l.path}",
        since: l.waiting_at,
        screen: "library",
        about: %{takeable_at: l.takeable_at, takeable: l.takeable}
      }
    end
  end
end
