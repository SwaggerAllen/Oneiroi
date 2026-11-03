defmodule Oneiroi.FakeTablesTest do
  # The fakes' shared tables outlive the process that first used them.
  # Owned by that process, a table went when it exited, and a later
  # test's on_exit clear raised on a table that was gone (CI on PR #45).
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  test "the model fake's and the memory fake's tables are owned by neither their first user nor this test" do
    first =
      Task.async(fn ->
        Model.clear(for: "first-user")
        Honcho.clear(for: "first-user")
      end)

    Task.await(first)
    refute Process.alive?(first.pid)

    for table <- [:nisaba_fake_scripts, :proteus_honcho_fake] do
      owner = :ets.info(table, :owner)
      assert is_pid(owner) and Process.alive?(owner)
      refute owner in [self(), first.pid]
    end

    assert :ok = Model.clear(for: "after")
    assert :ok = Honcho.clear(for: "after")
  end
end
