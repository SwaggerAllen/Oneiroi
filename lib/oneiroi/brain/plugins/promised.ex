defmodule Oneiroi.Brain.Plugins.Promised do
  @moduledoc """
  What the resident has promised (spec §3.1, P19). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "promised",
      name: "What I have promised",
      about: "your open commitments, every turn",
      place: :turn,
      reads: ~w(commitments)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    promised = Oneiroi.Ethos.promised(turn.resident_id)

    section(
      "promised",
      promised.text,
      "what the resident has promised and not yet kept or been released from (spec §3.1, P19): #{length(promised.numbers)} open commitments named, loaded every turn because a promise that has to be retrieved is one that can be lost",
      %{text: promised.text, refs: promised.numbers}
    )
  end
end
