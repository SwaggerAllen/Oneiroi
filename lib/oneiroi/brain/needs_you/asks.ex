defmodule Oneiroi.Brain.NeedsYou.Asks do
  @moduledoc "AgathosDaimon's asks (brain#72, agathos-daimon#35): open until he answers."
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry

  @impl true
  def stages, do: [%{kind: "ask", screen: "inbox"}]

  @impl true
  def entries(resident_id) do
    for a <- AgathosDaimon.asks(resident_id), is_nil(a.decision) do
      %Entry{
        kind: "ask",
        ref: a.number,
        since: a.asked_at,
        screen: "inbox",
        about: %{subject: a.subject, ask: a.kind}
      }
    end
  end
end
