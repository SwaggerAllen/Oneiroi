defmodule Oneiroi.Brain.Plugins.Character do
  @moduledoc """
  The trigger lane (spec §6.17, ethos#16). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4, trial_reads: 1]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "character",
      name: "How I act",
      about: "the habits this situation matches, and the seeds near it",
      place: :turn,
      reads: ~w(habits seeds)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, ctx) do
    acting = how_i_act(turn, ctx.text)

    section(
      "character",
      acting.text,
      # Under 255 characters: the injection row's description column
      # is that wide, and a longer one took the conversations
      # projector down on the first turn the lane ran.
      "the trigger lane (spec §6.17): #{acting.count} habits matched by the witness's words, the conversation's tags or the time of day, #{length(acting.near)} by the vector lane's nearness, with scores and cited turns; #{acting.seeds} open seeds counted, #{length(acting.near_seeds)} named as near, never loaded whole",
      %{refs: acting.numbers}
    )
  end

  # Retrieval is memory's and choice is the brain's (kumbukumbu#11): the
  # situation is the witness's words, the conversation's tags and the
  # time of day, matched with no model call; with the resident's actor
  # the vector lane adds what sits near the words, one embedding billed
  # to the dyad under the embeddings purpose (ethos#16).
  defp how_i_act(turn, text) do
    tags =
      turn.resident_id
      |> Kumbukumbu.taggings("conversation", turn.session_key)
      |> Enum.map(& &1.tag)

    Oneiroi.Ethos.how_i_act(
      turn.resident_id,
      Map.merge(
        %{
          text: text,
          tags: tags,
          at: Clock.now(),
          session_key: turn.session_key,
          actor: lane_actor(turn)
        },
        trial_reads(turn)
      )
    )
  end

  # The vector lane runs only for a query somebody is billed for; a
  # preview bills nobody, so its lane is the trigger lane alone (brain#41).
  defp lane_actor(%{preview?: true}), do: nil

  defp lane_actor(turn), do: Map.get(turn, :resident)
end
