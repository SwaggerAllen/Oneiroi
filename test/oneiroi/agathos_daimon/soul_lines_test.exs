defmodule Oneiroi.AgathosDaimon.SoulLinesTest do
  @moduledoc "The soul file as rows, pure: the split, the marker, the render and the diff."
  use ExUnit.Case, async: true

  alias Oneiroi.AgathosDaimon.SoulLines

  test "paragraphs are the lines: trimmed, blanks and headings dropped, markers read and stripped" do
    text = "# Soul\n\n  [soul/3] A.\n\n\nB, two\nlines.\n \n## Part\n\n[soul/1]C.\n"
    assert ["A.", "B, two\nlines.", "C."] = SoulLines.paragraphs(text)
    assert [{3, "A."}, {nil, "B, two\nlines."}, {1, "C."}] = SoulLines.marked(text)
    assert [] = SoulLines.paragraphs(nil)
    assert [] = SoulLines.paragraphs("# Only a heading\n\n   \n")
  end

  test "strip removes the markers and nothing else" do
    text = "# Soul\n\n[soul/1] A.\n\n  [soul/22] B.\n\nC [soul/3] not at the start.\n"
    assert SoulLines.strip(text) == "# Soul\n\nA.\n\n  B.\n\nC [soul/3] not at the start.\n"
    assert SoulLines.strip(nil) == nil
  end

  test "render deals the markers out in order, byte for byte, and leaves an unmatched text bare" do
    lines = [%{number: 4, text: "A."}, %{number: 2, text: "B."}]
    content = "# Soul\n\n  A.\n\n\nB.\n"
    assert SoulLines.render(content, lines) == "# Soul\n\n  [soul/4] A.\n\n\n[soul/2] B.\n"
    assert SoulLines.paragraphs(SoulLines.render(content, lines)) == ["A.", "B."]
    assert SoulLines.strip(SoulLines.render(content, lines)) == content
    assert SoulLines.render("# Soul\n\nA.\n\nX.", lines) == "# Soul\n\nA.\n\nX."
    assert SoulLines.render("", []) == ""
  end

  test "the diff: a marker claims its line, equal words keep one, a marker-less text pairs in order, the rest is written and the unclaimed retired" do
    lines = [{1, "A."}, {2, "B."}, {3, "C."}]

    # Marked: the claim wins, the unmarked new paragraph is new, the unclaimed line retires.
    assert %{
             order: [{:kept, 3}, {:reworded, 1, "A, again."}, {:kept, 2}, {:written, "D."}],
             retired: []
           } = SoulLines.diff(lines, [{3, "C."}, {1, "A, again."}, {nil, "B."}, {nil, "D."}])

    assert %{order: [{:reworded, 2, "Bee."}, {:written, "D."}], retired: [1, 3]} =
             SoulLines.diff(lines, [{2, "Bee."}, {nil, "D."}])

    # A claim on a number not live, or claimed twice, is no claim.
    assert %{order: [{:written, "Z."}, {:kept, 1}, {:written, "A?"}], retired: [2, 3]} =
             SoulLines.diff(lines, [{9, "Z."}, {1, "A."}, {1, "A?"}])

    # Unmarked throughout: equal words keep, then pairing in order, then writing, then retiring.
    assert %{order: [{:kept, 2}], retired: [1, 3]} = SoulLines.diff(lines, [{nil, "B."}])
    assert %{order: [], retired: [1, 2, 3]} = SoulLines.diff(lines, [])
    assert %{order: [{:written, "A."}], retired: []} = SoulLines.diff([], [{nil, "A."}])

    assert %{
             order: [{:reworded, 1, "X."}, {:reworded, 2, "Y."}, {:reworded, 3, "Z."}],
             retired: []
           } = SoulLines.diff(lines, [{nil, "X."}, {nil, "Y."}, {nil, "Z."}])

    assert %{
             order: [{:kept, 2}, {:reworded, 1, "X."}, {:reworded, 3, "Y."}, {:written, "W."}],
             retired: []
           } = SoulLines.diff(lines, [{nil, "B."}, {nil, "X."}, {nil, "Y."}, {nil, "W."}])
  end
end
