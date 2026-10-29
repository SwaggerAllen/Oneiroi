defmodule Oneiroi.StatementBudget do
  @moduledoc """
  The cost harness (conventions §9): records every statement the Repo
  runs from the calling process and budgets it, because a correctness
  test seeding three rows cannot see a full scan and nineteen million
  rows once hid behind three.
  """
  import ExUnit.Assertions

  @event [:oneiroi, :apsu, :repo, :query]

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

  @doc """
  Runs `fun`, returning its result and the statements it issued, in
  order, less the scope's own `set_config` and the transaction markers:
  what a test reads when the question is which statements ran, not how
  many.
  """
  @spec statements((-> result)) :: {result, [String.t()]} when result: term()
  def statements(fun) do
    parent = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      @event,
      fn _event, _measurements, %{query: query}, _config -> send(parent, {id, query}) end,
      nil
    )

    try do
      result = fun.()

      {result,
       id
       |> drain_queries([])
       |> Enum.reject(&(&1 =~ "set_config" or &1 in ~w(begin commit rollback)))}
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

  defp drain_queries(id, acc) do
    receive do
      {^id, query} -> drain_queries(id, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp drain(id, n) do
    receive do
      {^id, :statement} -> drain(id, n + 1)
    after
      0 -> n
    end
  end
end
