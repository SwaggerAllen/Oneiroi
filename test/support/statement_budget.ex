defmodule Oneiroi.StatementBudget do
  @moduledoc """
  The cost harness (conventions §9): records every statement the Repo
  runs from the calling process and budgets it, because a correctness
  test seeding three rows cannot see a full scan and nineteen million
  rows once hid behind three.
  """
  import ExUnit.Assertions

  @event [:oneiroi, :platform, :repo, :query]

  @doc "Runs `fun`, returning its result and the number of statements it issued."
  @spec count_statements((-> result)) :: {result, non_neg_integer()} when result: term()
  def count_statements(fun) do
    parent = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      @event,
      fn _event, _measurements, _metadata, _config -> send(parent, {id, :statement}) end,
      nil
    )

    try do
      result = fun.()
      {result, drain(id, 0)}
    after
      :telemetry.detach(id)
    end
  end

  @doc "Asserts `fun` issues at most `max` statements, naming the count when it does not."
  @spec assert_statements(non_neg_integer(), (-> result)) :: result when result: term()
  def assert_statements(max, fun) do
    {result, count} = count_statements(fun)

    assert count <= max,
           "expected at most #{max} statement(s), #{count} ran (conventions §9: budget the cost)"

    result
  end

  defp drain(id, n) do
    receive do
      {^id, :statement} -> drain(id, n + 1)
    after
      0 -> n
    end
  end
end
