defmodule Oneiroi.Brain.NeedsYou.Plugins do
  @moduledoc "AgathosDaimon's plugin proposals (brain#72, brain#68): hers, waiting for his answer."
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry

  @impl true
  def stages, do: [%{kind: "plugin_proposal", screen: "agreement"}]

  @impl true
  def entries(resident_id) do
    for p <- AgathosDaimon.plugin_proposals(resident_id),
        is_nil(p.answered_at),
        p.proposed_by == "resident" do
      %Entry{
        kind: "plugin_proposal",
        ref: p.number,
        since: p.proposed_at,
        screen: "agreement",
        about: %{key: p.key, change: p.change, note: p.note}
      }
    end
  end
end
