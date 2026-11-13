defmodule Oneiroi.Brain.NeedsYou do
  @moduledoc """
  `needs_you` (spec §5, brain#65, brain#72): everything waiting on the
  witness's decision across the systems, one list, oldest first, each
  entry naming the screen its decision is made on.

  One projection over registered sources (brain#72, the queue
  abstraction, design/queue-abstraction.md): each source declares the
  stages of its flow the witness holds and returns its entries in the
  common contract (`NeedsYou.Entry`); this module keeps only what is the
  queue's own: the registration, the check that every entry is of a
  stage its source declared, the order and the long mark. Which document
  kinds wait on him is the kind registry's declaration, read by the one
  documents adapter, so a new kind needs no change here; a new source is
  a module and one line below.

  It only shows. Nothing here decides, sends or approves, on a timeout
  or otherwise: an entry past `long_hours/0` is marked `long`, and the
  mark is all that happens (Lily's rule for it: the queue shows, the
  click is his, always).
  """

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou.Entry

  # The sources, registered once: replies (Xenia), asks and plugin
  # proposals (AgathosDaimon), documents and kind gate proposals
  # (Seshat), work (Sunna), theme proposals (Seshat, brain#80), and the
  # notifications question (Gaia's answer, brain#76), and the turns that
  # failed (Kumbukumbu's capture failures, brain#88).
  @sources [
    Oneiroi.Brain.NeedsYou.Replies,
    Oneiroi.Brain.NeedsYou.Asks,
    Oneiroi.Brain.NeedsYou.Documents,
    Oneiroi.Brain.NeedsYou.Work,
    Oneiroi.Brain.NeedsYou.Plugins,
    Oneiroi.Brain.NeedsYou.Kinds,
    Oneiroi.Brain.NeedsYou.Theme,
    Oneiroi.Brain.NeedsYou.Notifications,
    Oneiroi.Brain.NeedsYou.Failures
  ]

  # Past this an entry is marked as having waited long. A mark only.
  @long_hours 48

  @doc "The hours past which an entry is marked long."
  @spec long_hours() :: pos_integer()
  def long_hours, do: @long_hours

  @doc "The registered sources."
  @spec sources() :: [module()]
  def sources, do: @sources

  @doc "Every entry waiting on the witness, oldest first."
  @spec list(String.t()) :: [map()]
  def list(resident_id) do
    now = Clock.now()

    @sources
    |> Enum.flat_map(&from(&1, resident_id))
    |> Enum.sort_by(& &1.since, DateTime)
    |> Enum.map(
      &(&1
        |> Map.from_struct()
        |> Map.put(:long, DateTime.diff(now, &1.since, :hour) >= @long_hours))
    )
  end

  # A source's entries, each of a stage it declared: one that is not is
  # a broken adapter, said at once rather than shown wrong.
  defp from(source, resident_id) do
    declared = MapSet.new(source.stages(), &{&1.kind, &1.screen})

    for %Entry{} = e <- source.entries(resident_id) do
      if MapSet.member?(declared, {e.kind, e.screen}),
        do: e,
        else: raise(ArgumentError, "#{inspect(source)} returned an undeclared stage #{e.kind}")
    end
  end
end
