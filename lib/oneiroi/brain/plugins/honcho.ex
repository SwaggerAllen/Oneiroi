defmodule Oneiroi.Brain.Plugins.Honcho do
  @moduledoc """
  Honcho's context (spec §5). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.Config

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "honcho",
      name: "Honcho",
      about: "the background model's context on the person, when its switch is on",
      place: :turn,
      reads: ~w(background_model)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    section(
      "honcho",
      if(Oneiroi.AgathosDaimon.switch_on?(turn.resident_id, "background_model"),
        do: Oneiroi.Proteus.context(turn.resident_id),
        else: ""
      ),
      "Honcho's context on the person, in the resident's eyes, under #{Config.fetch!(:proteus, :context_tokens)} tokens (spec §5)"
    )
  end
end
