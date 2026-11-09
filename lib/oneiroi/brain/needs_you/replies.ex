defmodule Oneiroi.Brain.NeedsYou.Replies do
  @moduledoc """
  Xenia's replies (brain#72): drafted, his to approve; approved, his to
  send (the reader holds the sending, and he marks it sent).
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Xenia

  @impl true
  def stages,
    do: [
      %{kind: "reply_to_approve", screen: "inbox"},
      %{kind: "reply_to_send", screen: "inbox"}
    ]

  @impl true
  def entries(resident_id) do
    for r <- Xenia.replies(resident_id, nil), r.state in ["drafted", "approved"] do
      %Entry{
        kind: if(r.state == "drafted", do: "reply_to_approve", else: "reply_to_send"),
        ref: r.number,
        since: if(r.state == "drafted", do: r.drafted_at, else: r.decided_at || r.drafted_at),
        screen: "inbox",
        about: %{to: r.to, platform: r.platform, account: r.account}
      }
    end
  end
end
