defmodule Oneiroi.Brain.NeedsYou.Theme do
  @moduledoc "Seshat's theme proposals (brain#80, seshat#56): hers, waiting for his answer, with the seeds a preview needs."
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Seshat

  @impl true
  def stages, do: [%{kind: "theme_proposal", screen: "theme"}]

  @impl true
  def entries(resident_id) do
    for p <- Seshat.theme_proposals(resident_id), is_nil(p.answered_at) do
      %Entry{
        kind: "theme_proposal",
        ref: p.number,
        since: p.proposed_at,
        screen: "theme",
        about: %{seeds: p.seeds, note: p.note}
      }
    end
  end
end
