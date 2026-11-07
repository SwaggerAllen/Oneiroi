defmodule Oneiroi.Brain.Plugins.Exploration do
  @moduledoc """
  The exploration (F11, brain#68): bookmarks drawn at random from
  outside the ranked set, fresh each turn, against character
  metastasising and for spontaneity. Its own slot since the witness's
  call that every memory slot is a plugin, with its own lines and token
  budget (`KUMBUKUMBU_EXPLORE_LINES`, `KUMBUKUMBU_EXPLORE_TOKENS`); the
  draw itself is made beside the ranking, which never returns what was
  drawn. A draw is returned and never ranked, so it teaches the learned
  edges nothing until it is used. A first-party plugin: code that
  entered by review, under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "exploration",
      name: "Drawn at random",
      about: "bookmarks drawn at random, for what you might not think to look for",
      place: :turn,
      reads: ~w(bookmarks)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(_turn, %{index: index}) do
    section(
      "exploration",
      Map.get(index, :exploration, ""),
      "the exploration (F11, brain#68): #{length(index.explored)} drawn at random from outside the ranked set, fresh this turn",
      %{text: Map.get(index, :exploration, ""), refs: index.explored}
    )
  end
end
