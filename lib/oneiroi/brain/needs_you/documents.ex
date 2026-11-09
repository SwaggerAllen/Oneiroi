defmodule Oneiroi.Brain.NeedsYou.Documents do
  @moduledoc """
  Seshat's documents (brain#72, seshat#49): one adapter for every kind,
  built-in or user-made. Which kinds wait on him, and at which stages,
  is the kind registry's declaration (`approvable`, `approval`), never a
  list here: a kind marked for review waits for his decision
  (`piece_to_review`, in the kind's own words); a kind whose flow goes
  on to the reader's Substack draft waits on him again to publish it
  (`piece_to_publish`). A kind added to the registry appears here with
  no change to this module.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Kinds

  @impl true
  def stages do
    flows = for k <- Kinds.all(), flow = Kinds.approval(k), do: flow

    [%{kind: "piece_to_review", screen: "inbox"} | publish_stage(flows)]
    |> then(&if(flows == [], do: [], else: &1))
  end

  # Publishing waits on him only where a flow goes on to a draft outside.
  defp publish_stage(flows) do
    if Enum.any?(flows, &(&1["then"] == "substack_draft")),
      do: [%{kind: "piece_to_publish", screen: "inbox"}],
      else: []
  end

  @impl true
  def entries(resident_id) do
    %{for_review: review, drafted: drafted} = Seshat.pieces(resident_id)

    for(
      p <- review,
      p.written_at,
      do: %Entry{
        kind: "piece_to_review",
        ref: p.path,
        since: p.written_at,
        screen: "inbox",
        about: %{title: p.title, kind: p.kind, ask: p.ask}
      }
    ) ++
      for p <- drafted do
        %Entry{
          kind: "piece_to_publish",
          ref: p.path,
          since: p.decided_at,
          screen: "inbox",
          about: %{title: p.title}
        }
      end
  end
end
