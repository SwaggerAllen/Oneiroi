defmodule Oneiroi.SimaQian.WalkPlanTest do
  @moduledoc "The walk's plan (sima-qian#48): the mirror through the reviewed table, mechanical eras at half the walking model's context, and an estimate that says it is one."
  use ExUnit.Case, async: true

  alias Oneiroi.SimaQian.WalkPlan

  @catalog [
    %{
      id: "openai/gpt-4o",
      context_length: 1_000,
      prompt_nanos: 2_500.0,
      completion_nanos: 10_000.0
    },
    %{id: "z-ai/glm-5.3", context_length: 2_000, prompt_nanos: 600.0, completion_nanos: 2_200.0}
  ]

  defp conversation(id, model, bytes, day) do
    %{
      id: id,
      title: "conv #{id}",
      created_at: DateTime.new!(Date.new!(2025, 1, day), ~T[12:00:00], "Etc/UTC"),
      messages: [
        %{role: :user, text: String.duplicate("a", div(bytes, 2)), model: nil},
        %{role: :assistant, text: String.duplicate("b", div(bytes, 2)), model: model}
      ]
    }
  end

  test "the mirror finds the twin, substitutes and says why, and never guesses" do
    offered = Enum.map(@catalog, & &1.id)
    assert {:mirror, "openai/gpt-4o"} = WalkPlan.mirror("gpt-4o", offered, "z-ai/glm-5.3")

    assert {:substitute, "z-ai/glm-5.3", "auto names no model anyone can call"} =
             WalkPlan.mirror("auto", offered, "z-ai/glm-5.3")

    assert {:substitute, _, "gpt-4's twin openai/gpt-4 is not in the catalogue"} =
             WalkPlan.mirror("gpt-4", offered, "z-ai/glm-5.3")

    assert {:substitute, _, "gpt-9 is not in the reviewed table"} =
             WalkPlan.mirror("gpt-9", offered, "z-ai/glm-5.3")
  end

  test "eras pack whole conversations to half the model's context, break where the model changes, and an oversized one walks alone" do
    # gpt-4o's half is 500 tokens (2,000 bytes); glm's is 1,000 tokens.
    conversations = [
      conversation("a", "gpt-4o", 800, 1),
      conversation("b", "gpt-4o", 800, 2),
      conversation("c", "gpt-4o", 800, 3),
      conversation("d", "auto", 800, 4),
      conversation("e", "gpt-4o", 4_000, 5),
      conversation("f", "gpt-9", 400, 6)
    ]

    %{eras: eras, substitutions: subs, gaps: gaps} =
      WalkPlan.plan(conversations, :mirror, @catalog)

    assert [
             %{number: 1, model: "openai/gpt-4o", conversations: ["a", "b"], tokens: 400},
             %{number: 2, model: "openai/gpt-4o", conversations: ["c"]},
             %{number: 3, model: "z-ai/glm-5.3", conversations: ["d"]},
             %{number: 4, model: "openai/gpt-4o", conversations: ["e"], oversized: true},
             %{number: 5, model: "z-ai/glm-5.3", conversations: ["f"]}
           ] = eras

    assert [%{lived: "auto", walked: "z-ai/glm-5.3"}, %{lived: "gpt-9"}] = subs
    assert [%{kind: :unmapped_model, where: "conv f"}] = gaps
  end

  test "one model for the whole walk, and an estimate that says it is one" do
    conversations = [conversation("a", "gpt-4o", 800, 1), conversation("b", "auto", 800, 2)]

    %{eras: eras, substitutions: []} =
      WalkPlan.plan(conversations, {:one, "z-ai/glm-5.3"}, @catalog)

    assert [%{model: "z-ai/glm-5.3", conversations: ["a", "b"]}] = eras

    estimate = WalkPlan.estimate(eras, @catalog)
    assert %{eras: 1, nanos: nanos, assumptions: "an estimate, never a quote" <> _} = estimate
    assert nanos > 0
  end
end
