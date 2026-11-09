defmodule Oneiroi.Brain.NeedsYou do
  @moduledoc """
  `needs_you` (spec §5, brain#65): everything waiting on the witness's
  decision across the systems, one list, oldest first, each entry
  naming the screen its decision is made on. The replies to approve and
  the approved ones to send (Xenia), the open asks (AgathosDaimon), the
  pieces for review and the drafted ones to publish (Seshat), and the
  work items blocked (Sunna).

  It only shows. Nothing here decides, sends or approves, on a timeout
  or otherwise: an entry past `long_hours/0` is marked `long`, and the
  mark is all that happens (Lily's rule for it: the queue shows, the
  click is his, always).
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna
  alias Oneiroi.Xenia

  # Past this an entry is marked as having waited long. A mark only.
  @long_hours 48

  @doc "The hours past which an entry is marked long."
  @spec long_hours() :: pos_integer()
  def long_hours, do: @long_hours

  @doc "Every entry waiting on the witness, oldest first."
  @spec list(String.t()) :: [map()]
  def list(resident_id) do
    now = Clock.now()

    (replies(resident_id) ++
       asks(resident_id) ++
       pieces(resident_id) ++
       work(resident_id) ++
       plugins(resident_id))
    |> Enum.sort_by(& &1.since, DateTime)
    |> Enum.map(&Map.put(&1, :long, DateTime.diff(now, &1.since, :hour) >= @long_hours))
  end

  defp replies(resident_id) do
    for r <- Xenia.replies(resident_id, nil), r.state in ["drafted", "approved"] do
      %{
        kind: if(r.state == "drafted", do: "reply_to_approve", else: "reply_to_send"),
        ref: r.number,
        since: if(r.state == "drafted", do: r.drafted_at, else: r.decided_at || r.drafted_at),
        screen: "inbox",
        about: %{to: r.to, platform: r.platform, account: r.account}
      }
    end
  end

  defp asks(resident_id) do
    for a <- AgathosDaimon.asks(resident_id), is_nil(a.decision) do
      %{
        kind: "ask",
        ref: a.number,
        since: a.asked_at,
        screen: "inbox",
        about: %{subject: a.subject, ask: a.kind}
      }
    end
  end

  defp pieces(resident_id) do
    %{for_review: review, drafted: drafted} = Seshat.pieces(resident_id)

    for(
      p <- review,
      p.written_at,
      do: %{
        kind: "piece_to_review",
        ref: p.path,
        since: p.written_at,
        screen: "inbox",
        # The ask in the kind's own words (seshat#49): a piece to review,
        # a design to read and sign off.
        about: %{title: p.title, kind: p.kind, ask: p.ask}
      }
    ) ++
      for p <- drafted do
        %{
          kind: "piece_to_publish",
          ref: p.path,
          since: p.decided_at,
          screen: "inbox",
          about: %{title: p.title}
        }
      end
  end

  # Her plugin proposals waiting for his answer (brain#68).
  defp plugins(resident_id) do
    for p <- Oneiroi.AgathosDaimon.plugin_proposals(resident_id),
        is_nil(p.answered_at),
        p.proposed_by == "resident" do
      %{
        kind: "plugin_proposal",
        ref: p.number,
        since: p.proposed_at,
        screen: "agreement",
        about: %{key: p.key, change: p.change, note: p.note}
      }
    end
  end

  # Blocked work (sunna#42) waits on other work and is the queue's, not
  # his: only an item blocked before the rule, its blocker a line of
  # words rather than an item's number, still shows here, since what it
  # waited on was mostly him, until it is triaged.
  defp work(resident_id) do
    for w <- Sunna.work_queue(resident_id).items,
        w.status == "blocked",
        not item_ref?(w.blocked_on) do
      %{
        kind: "work_blocked",
        ref: w.number,
        since: w.moved_at || w.added_at,
        screen: "work",
        about: %{what: w.what, blocked_on: w.blocked_on}
      }
    end
  end

  defp item_ref?(on), do: is_binary(on) and Regex.match?(~r/\A#\d+\z/, on)
end
