defmodule Oneiroi.Brain.Plugins do
  @moduledoc """
  The plugins a turn's context is assembled from (brain#68), in the
  order the context gives them. The first-party plugins are every
  memory slot the platform had before plugins, carried over whole; the
  two sealed sections that sit among them, where this conversation is
  and a compaction summary, are named in the layout as `:where` and
  `:summary` and stay the turn's own.
  """

  alias Oneiroi.Brain.Plugins

  @doc "The plugins of the stable prefix, after the identity files and the contract."
  @spec prefix() :: [module()]
  def prefix, do: [Plugins.Pins]

  @doc "The turn's slots in order, the sealed sections among them by name."
  @spec layout() :: [module() | :where | :summary]
  def layout do
    [
      Plugins.State,
      Plugins.Budget,
      Plugins.Timeline,
      :where,
      Plugins.FreeTimePlan,
      Plugins.Goals,
      Plugins.Letters,
      Plugins.Index,
      Plugins.Exploration,
      Plugins.Character,
      Plugins.Promised,
      Plugins.SelfConversation,
      Plugins.Movement,
      Plugins.Madeleine,
      Plugins.Dates,
      Plugins.Figures,
      Plugins.Journal,
      Plugins.Honcho,
      :summary
    ]
  end

  @doc "Every first-party plugin, prefix first."
  @spec first_party() :: [module()]
  def first_party, do: prefix() ++ (Enum.filter(layout(), &is_atom/1) -- [:where, :summary])
end
