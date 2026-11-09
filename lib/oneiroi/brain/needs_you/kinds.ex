defmodule Oneiroi.Brain.NeedsYou.Kinds do
  @moduledoc "Seshat's kind gate proposals (brain#72, seshat#51): hers, waiting for his answer."
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Seshat

  @impl true
  def stages, do: [%{kind: "kind_gate_proposal", screen: "kinds"}]

  @impl true
  def entries(resident_id) do
    for p <- Seshat.user_kinds(resident_id).proposals,
        is_nil(p.answered_at),
        p.proposed_by == "resident" do
      %Entry{
        kind: "kind_gate_proposal",
        ref: p.number,
        since: p.proposed_at,
        screen: "kinds",
        about: %{kind: p.kind, approvable: p.approvable, note: p.note}
      }
    end
  end
end
