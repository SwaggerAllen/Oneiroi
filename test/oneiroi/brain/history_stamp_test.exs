defmodule Oneiroi.Brain.HistoryStampTest do
  use ExUnit.Case, async: false

  alias Oneiroi.Brain.History

  @at ~U[2026-11-06 18:54:07Z]
  @zone "America/Los_Angeles"

  test "every message the resident reads carries when it was said, inline, in her zone" do
    rows = [
      %{role: "user", content: "hello", sent_at: @at},
      %{role: "tool", content: "a(x) -> 1", sent_at: @at},
      %{role: "assistant", content: "hi", sent_at: @at}
    ]

    assert [
             %{role: :user, content: "[2026-11-06 10:54 PST] hello"},
             %{role: :assistant, content: "", tool_calls: [_]},
             %{role: :tool, content: "[2026-11-06 10:54 PST] 1"},
             %{role: :assistant, content: "[2026-11-06 10:54 PST] hi"}
           ] = History.messages(rows, @zone)

    assert [_, %{content: "[2026-11-06 10:54 PST] a(x) -> 1"}, _] = History.words(rows, @zone)
  end

  test "an inferred instant is never shown as a time" do
    rows = [%{role: "user", content: "old", sent_at: @at, instant_inferred: true}]
    assert [%{content: "[time unknown] old"}] = History.messages(rows, @zone)
  end

  test "with no zone, nothing is stamped" do
    assert [%{content: "hello"}] =
             History.messages([%{role: "user", content: "hello", sent_at: @at}])
  end

  test "a stamp the model copied onto its reply is taken off, once, at the head" do
    assert History.unstamp("[2026-11-06 10:54 PST] hi") == "hi"
    assert History.unstamp("[time unknown]  hi") == "hi"
    assert History.unstamp("hi [2026-11-06 10:54 PST] there") == "hi [2026-11-06 10:54 PST] there"
    assert History.unstamp(nil) == nil
  end

  describe "BRAIN_HISTORY_STAMPS (brain#59)" do
    setup do
      values = :persistent_term.get({Oneiroi.Config, :values})
      on_exit(fn -> :persistent_term.put({Oneiroi.Config, :values}, values) end)
      {:ok, values: values}
    end

    test "off by default: no zone, no stamps, and the prompt says nothing of them" do
      assert History.zone("any") == nil
      assert History.stamps_line() == ""

      assert [%{content: "hello"}] =
               History.messages(
                 [%{role: "user", content: "hello", sent_at: @at}],
                 History.zone("any")
               )
    end

    test "on: the prompt names the stamps", %{values: values} do
      :persistent_term.put(
        {Oneiroi.Config, :values},
        Map.put(values, {:brain, :history_stamps}, true)
      )

      assert History.stamps_line() =~ "[2026-11-06 10:54 PST]"
    end
  end
end
