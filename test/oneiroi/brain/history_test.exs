defmodule Oneiroi.Brain.HistoryTest do
  @moduledoc "Stored rows as a model reads them again: a tool row is a call and its answer, or words."
  use ExUnit.Case, async: true

  alias Oneiroi.Brain.History

  test "a tool row splits at its first `) -> `, and its output keeps whatever follows" do
    rows = [%{role: "tool", content: ~s|t({"a":1}) -> x) -> y\nz|}]

    assert [
             %{role: :assistant, content: "", tool_calls: [%{id: id, function: f}]},
             %{role: :tool, tool_call_id: id, content: "x) -> y\nz"}
           ] = History.messages(rows)

    assert f == %{name: "t", arguments: ~s({"a":1})}
  end

  test "every call gets its own id, and a row that is not a tool's record goes back as words" do
    rows = [
      %{role: "user", content: "u"},
      %{role: "tool", content: "a() -> 1"},
      %{role: "tool", content: "b() -> 2"},
      %{role: "tool", content: "written by another hand"}
    ]

    assert [
             %{role: :user},
             %{tool_calls: [%{id: x}]},
             %{tool_call_id: x},
             %{tool_calls: [%{id: y}]},
             %{tool_call_id: y},
             %{role: :assistant, content: "written by another hand"} = last
           ] = History.messages(rows)

    assert x != y
    refute Map.has_key?(last, :tool_calls)
    assert [_, %{role: :assistant, content: "a() -> 1"} | _] = History.words(rows)
  end
end
