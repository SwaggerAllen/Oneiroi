defmodule Oneiroi.Kumbukumbu.IndexTest do
  @moduledoc "The index under its budget: pins first and at most half, the rest by weight then recency, the left-out count said."
  use ExUnit.Case, async: true

  alias Oneiroi.Kumbukumbu.Index

  @at ~U[2026-10-29 12:00:00.000000Z]

  defp bookmark(number, extra \\ []) do
    Map.merge(
      %{
        number: number,
        anchor_at: @at,
        line: "line #{number} " <> String.duplicate("w", 20),
        tags: [],
        pinned_at: nil,
        weight: 1.0
      },
      Map.new(extra)
    )
  end

  test "the near-miss record names every bookmark ranked and not taken, with the reason it lost" do
    pinned = for n <- 1..4, do: bookmark(n, pinned_at: @at)
    rest = [bookmark(5, weight: 3.0), bookmark(6, weight: 2.0), bookmark(7, weight: 1.0)]
    # A pinned line costs 13 tokens and a plain one 11: the pins' half of
    # 56 holds two, and the 30 left hold two of the rest.
    built = Index.build(pinned ++ rest, 56)
    assert built.included == [4, 3, 5, 6]
    assert built.left_out == 3

    assert [
             %{number: 2, reason: "pinned, but the pins' half of the budget was spent"},
             %{number: 1, reason: "pinned, but the pins' half of the budget was spent"},
             %{number: 7, reason: "ranked at weight 1.0 below what the budget held"}
           ] = built.near_misses

    assert Enum.all?(built.near_misses, &String.starts_with?(&1.line, "##{&1.number} "))
    assert %{near_misses: []} = Index.build(rest, 100)
  end

  test "an empty memory says so" do
    assert %{text: "Every bookmark is listed.", included: [], left_out: 0} = Index.build([], 100)
  end

  test "pins lead, newest first, and take at most half the budget" do
    pinned = for n <- 1..6, do: bookmark(n, pinned_at: @at)
    rest = for n <- 7..9, do: bookmark(n)
    # One line costs about 12 tokens; 60 tokens hold five lines in all.
    built = Index.build(Enum.shuffle(pinned ++ rest), 60)

    pinned_included = Enum.filter(built.included, &(&1 <= 6))
    assert pinned_included == Enum.sort(pinned_included, :desc)
    assert length(pinned_included) <= 2
    assert built.left_out == 9 - length(built.included)
    assert built.text =~ "#{built.left_out} more not shown"

    assert built.tokens <=
             60 +
               Index.tokens(
                 "99 more not shown; bookmark_open(number) reads any, and transcript_search reaches past the index."
               )
  end

  test "the rest rank by weight, then by recency" do
    rows = [bookmark(1, weight: 0.5), bookmark(2, weight: 2.0), bookmark(3, weight: 0.5)]
    assert %{included: [2, 3, 1], left_out: 0} = Index.build(rows, 1_000)
  end

  test "a line carries the number, the day, the pin and the tags" do
    line = Index.line(bookmark(42, tags: ["haven", "care"], pinned_at: @at))

    assert line =~ "#42 2026-10-29 (pinned) [care, haven]" or
             line =~ "#42 2026-10-29 (pinned) [haven, care]"
  end
end
