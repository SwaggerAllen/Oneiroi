defmodule Oneiroi.Brain.NeedsYouTest do
  @moduledoc """
  brain#72 (the queue abstraction, the witness's sign-off 2026-11-09):
  one projection over registered sources, each declaring the stages it
  holds for him and returning entries in one contract; which document
  kinds wait on him is the kind registry's declaration alone.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Brain.NeedsYou.Documents
  alias Oneiroi.Brain.NeedsYou.Source
  alias Oneiroi.Seshat.Kinds

  test "every registered source keeps the contract and declares its stages" do
    for source <- NeedsYou.sources() do
      behaviours =
        source.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert Source in behaviours

      assert [_ | _] = source.stages()
      assert Enum.all?(source.stages(), &(is_binary(&1.kind) and is_binary(&1.screen)))
    end

    kinds = for s <- NeedsYou.sources(), st <- s.stages(), do: st.kind
    assert Enum.uniq(kinds) == kinds
  end

  test "an entry is a struct with every field, or it does not compile" do
    assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
      Code.eval_string("%Oneiroi.Brain.NeedsYou.Entry{kind: \"ask\", ref: 1}")
    end
  end

  # The #16 case, ready for kinds-as-data: the documents adapter names no
  # kind; every approvable kind in the registry is covered by its stages,
  # and a flow that goes outside adds the publishing stage, read from the
  # registry, so a kind added there appears with no change here.
  test "which document kinds wait on him is the registry's alone" do
    source = File.read!("lib/oneiroi/brain/needs_you/documents.ex")

    for k <- Kinds.all() do
      refute source =~ ~s("#{k.kind}"), "the documents adapter names the kind #{k.kind}"
    end

    assert Enum.any?(Kinds.all(), &Kinds.approvable?/1)
    stages = Enum.map(Documents.stages(), & &1.kind)
    assert "piece_to_review" in stages

    outside = Enum.any?(Kinds.all(), &match?(%{"then" => "substack_draft"}, Kinds.approval(&1)))
    assert "piece_to_publish" in stages == outside
  end
end
