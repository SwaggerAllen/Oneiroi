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
  def first_party, do: prefix() ++ (layout() -- [:where, :summary])

  @doc """
  The catalog (agathos-daimon#37): every plugin a resident may hold,
  each manifest with its tier. Today the first-party slots alone;
  installable plugins join it with their sources.
  """
  @spec catalog() :: [map()]
  def catalog, do: Enum.map(first_party(), &Map.put(&1.manifest(), :tier, "first_party"))

  @doc "The catalog's entry for a key, or nil."
  @spec entry(String.t()) :: map() | nil
  def entry(key), do: Enum.find(catalog(), &(&1.key == key))

  # The memory slots that existed before plugins (brain#68), recorded as
  # carried over the first time a resident's plugins are read. Fixed: a
  # slot added after it is not carried over, and waits for both parties.
  @carried ~w(pins state budget timeline free_time_plan goals_between letters index exploration character promised self-conversation movement madeleine dates figures journal honcho)

  @doc "The keys carried over from before plugins."
  @spec carried() :: [String.t()]
  def carried, do: @carried

  @doc """
  Which of `plugins` the turn's resident has installed and on, in their
  order; the sealed sections always. A trial or a preview reads the
  state and records nothing, the carry-over included.
  """
  @spec active([module() | atom()], map()) :: [module() | atom()]
  def active(plugins, turn) do
    read_only? = Map.get(turn, :trial?, false) or Map.get(turn, :preview?, false)

    on =
      if read_only?,
        do: MapSet.new(Oneiroi.AgathosDaimon.plugins_on_read(turn.resident_id, @carried)),
        else: MapSet.new(Oneiroi.AgathosDaimon.plugins_on(turn.resident_id, @carried))

    Enum.filter(plugins, fn
      sealed when sealed in [:where, :summary] -> true
      plugin -> MapSet.member?(on, plugin.manifest().key)
    end)
  end
end
