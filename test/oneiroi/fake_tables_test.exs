defmodule Oneiroi.FakeTablesTest do
  # The fakes' shared tables outlive the process that first used them.
  # Owned by that process, a table went when it exited, and a later
  # test's on_exit clear raised on a table that was gone (CI on PR #45).
  # (The memory fake went with Honcho, proteus#20.)
  use ExUnit.Case, async: true

  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  test "the model fake's table is owned by neither its first user nor this test" do
    first = Task.async(fn -> Model.clear(for: "first-user") end)

    Task.await(first)
    refute Process.alive?(first.pid)

    owner = :ets.info(:nisaba_fake_scripts, :owner)
    assert is_pid(owner) and Process.alive?(owner)
    refute owner in [self(), first.pid]

    assert :ok = Model.clear(for: "after")
  end
end
