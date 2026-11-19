defmodule Oneiroi.Seshat.HouseWorkingTest do
  @moduledoc "Who in the house is working now (seshat#90): marked for a wake's run, moved by her reading a thread, gone after."
  use ExUnit.Case, async: false

  alias Oneiroi.Seshat.HouseWorking

  test "a wake marks her for its run, in its thread; reading a thread moves the mark; it ends with the wake" do
    house = "h-#{System.unique_integer([:positive])}"
    parent = self()

    HouseWorking.during(house, "lily", nil, fn ->
      assert [%{resident_id: "lily", thread: nil}] = HouseWorking.list(house)
      HouseWorking.reading(house, "lily", "threads/herons")
      send(parent, {:marked, HouseWorking.list(house)})
    end)

    assert_received {:marked, [%{thread: "threads/herons"}]}
    assert HouseWorking.list(house) == []

    # Reading outside a wake marks nobody.
    HouseWorking.reading(house, "scarlett", "threads/herons")
    assert HouseWorking.list(house) == []
  end

  test "the mark ends even when the wake raises" do
    house = "h-#{System.unique_integer([:positive])}"

    assert_raise RuntimeError, fn ->
      HouseWorking.during(house, "lily", "threads/x", fn -> raise "fell over" end)
    end

    assert HouseWorking.list(house) == []
  end
end
