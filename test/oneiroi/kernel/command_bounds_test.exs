defmodule Oneiroi.CommandBoundsTest do
  @moduledoc """
  A name is bounded on its command and refused at dispatch, before any
  event exists (2026-11-03); free text is never bounded.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Commanded.Middleware.Actor, as: Middleware
  alias Oneiroi.Gaia.Commands.IssueToken
  alias Oneiroi.Kumbukumbu.MemoryCommands.AddBookmark
  alias Oneiroi.Kumbukumbu.MemoryCommands.CreateTag

  defmodule Labelled do
    use Oneiroi.Command, fields: [:key, :label, :words], bounds: [key: 8, label: 12]
  end

  @at ~U[2026-11-03 12:00:00.000000Z]

  defp command(fields), do: struct!(Labelled, [actor: Actor.platform(), at: @at] ++ fields)

  test "a name within its bound passes; free text of any length passes" do
    words = String.duplicate("long words ", 10_000)
    assert Middleware.problems(command(key: "tea", label: "Tea count", words: words)) == []
    assert Middleware.problems(command(key: nil, label: nil)) == []
  end

  test "each name past its bound is refused by name, counted in characters" do
    assert Middleware.problems(command(key: "much-too-long", label: "fine")) == [:key_too_long]

    assert Middleware.problems(command(key: "much-too-long", label: String.duplicate("é", 13))) ==
             [:key_too_long, :label_too_long]

    assert Middleware.problems(command(key: "ééééé", label: String.duplicate("é", 12))) == []
  end

  test "a value that is not text is not called too long" do
    assert Middleware.problems(command(key: 12_345_678_901, label: "x")) == []
  end

  test "a bound on a field the command does not have, or no positive bound, is a compile error" do
    assert_raise ArgumentError, ~r/not a field/, fn ->
      Code.compile_string("""
      defmodule Oneiroi.CommandBoundsTest.Bad do
        use Oneiroi.Command, fields: [:a], bounds: [b: 3]
      end
      """)
    end

    assert_raise ArgumentError, ~r/bound/, fn ->
      Code.compile_string("""
      defmodule Oneiroi.CommandBoundsTest.Bad2 do
        use Oneiroi.Command, fields: [:a], bounds: [a: 0]
      end
      """)
    end
  end

  test "the platform's names are bounded where they are made" do
    assert {:slug, 64, :slug_too_long} in CreateTag.__bounds__()
    assert {:label, 120, :label_too_long} in IssueToken.__bounds__()
    assert AddBookmark.__bounds__() == []
  end
end
