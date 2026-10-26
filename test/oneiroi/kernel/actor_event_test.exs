defmodule Oneiroi.ActorEventTest do
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Commanded.Middleware.Actor, as: Middleware
  alias Oneiroi.Event.Codec
  alias Oneiroi.Test.PlainEvent, as: Plain

  defmodule Decided do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule Undecided do
    use Oneiroi.Command, fields: [:id]
  end

  @at ~U[2026-10-26 12:00:00.000000Z]

  test "an actor is one of the platform's parties and nothing else" do
    assert Actor.valid?(Actor.new(:steward, "a1"))
    assert Actor.valid?(Actor.new(:resident, "r1", "openai/gpt-5"))
    refute Actor.valid?(%{kind: :steward})
    assert_raise FunctionClauseError, fn -> Actor.new(:someone, "x") end
  end

  test "an event round-trips the log's JSON with its actor and instant restored" do
    event = %Plain{actor: Actor.new(:resident, "r1", "m"), at: @at, name: "x"}
    json = Jason.encode!(event)
    decoded = Jason.decode!(json)

    restored =
      Codec.restore(
        struct(Plain, Map.new(decoded, fn {k, v} -> {String.to_existing_atom(k), v} end))
      )

    assert restored == event
    assert Plain.__version__() == 1
    refute Plain.__decision__?()
  end

  test "the middleware refuses a command without an actor, an instant, or a decision's note" do
    assert Middleware.problems(%Undecided{actor: Actor.platform(), at: @at, id: "x"}) == []
    assert Middleware.problems(%Undecided{actor: nil, at: @at, id: "x"}) == [:actor_required]

    assert Middleware.problems(%Undecided{actor: Actor.platform(), at: nil, id: "x"}) == [
             :at_required
           ]

    assert Middleware.problems(%Decided{actor: Actor.platform(), at: @at, id: "x", note: "  "}) ==
             [:note_required]

    assert Middleware.problems(%Decided{
             actor: Actor.platform(),
             at: @at,
             id: "x",
             note: "because"
           }) ==
             []
  end
end
