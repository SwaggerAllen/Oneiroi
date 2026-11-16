defmodule Oneiroi.Brain.NeedsYou.Contracts do
  @moduledoc """
  A version of the agreement the resident proposed, waiting on the
  witness's answer (the witness, 2026-11-16: proposals passed silently in
  both directions). Answered on the agreement screen, agreed or declined
  with a note; his own proposals wait on her, on her side of the bell.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry

  @impl true
  def stages, do: [%{kind: "contract_to_answer", screen: "agreement"}]

  @impl true
  def entries(resident_id) do
    case AgathosDaimon.contract(resident_id) do
      %{open: %{proposed_by: "resident"} = c} ->
        [
          %Entry{
            kind: "contract_to_answer",
            ref: c.version,
            since: c.proposed_at,
            screen: "agreement",
            about: %{note: c.note}
          }
        ]

      _none ->
        []
    end
  end
end
