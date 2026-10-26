defmodule Oneiroi.DataCase do
  @moduledoc """
  Sandbox-checked-out database tests (conventions §9). Async by default;
  a test that drives Commanded's projectors, which write from their own
  processes, takes `async: false` and the shared sandbox so the
  projector's connection is the test's.

  Every test runs under a scope, because an unscoped query is refused
  (`Oneiroi.Repo`): the platform scope by default, which sees every row,
  so a test that asserts tenancy sets the narrower scope it means.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Oneiroi.Repo
      import Oneiroi.DataCase
      import Oneiroi.StatementBudget, only: [assert_statements: 2, count_statements: 1]
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
