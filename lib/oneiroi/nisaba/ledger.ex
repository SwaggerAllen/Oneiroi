defmodule Oneiroi.Nisaba.Ledger do
  @moduledoc """
  The ledger aggregate on `ledger-<resident_id>`. Pure (conventions §6):
  every instant arrives on the command, the period key is derived from
  it, and the only decision here is whether a recorded call crossed its
  line.

  Spend is tracked per purpose for the current period only, so the state
  stays a handful of counters however many calls the stream holds; the
  exact history is the projection's. Setting a line with a different
  period starts its tracking afresh from that moment, which the stop the
  aggregate writes is the only thing to depend on it.
  """

  alias Oneiroi.Nisaba.Commands
  alias Oneiroi.Nisaba.Events
  alias Oneiroi.Nisaba.Period

  defstruct [:id, budgets: %{}, spent: %{}, exceeded: %{}]

  @type t :: %__MODULE__{}

  @default_period :month

  # ---- execute ----

  def execute(%__MODULE__{}, %Commands.SetBudget{} = c) do
    %Events.BudgetSet{
      actor: c.actor,
      at: c.at,
      id: c.id,
      purpose: Atom.to_string(c.purpose),
      cap_nanos: c.cap_nanos,
      period: Atom.to_string(c.period)
    }
  end

  def execute(%__MODULE__{} = l, %Commands.RecordModelCall{} = c) do
    purpose = Atom.to_string(c.purpose)

    recorded = %Events.ModelCallRecorded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      ref: c.ref,
      purpose: purpose,
      model: c.model,
      prompt_tokens: c.prompt_tokens,
      completion_tokens: c.completion_tokens,
      cost_nanos: c.cost_nanos,
      estimated: c.estimated
    }

    [recorded | stop(l, purpose, c)]
  end

  # The stop is written on the call that crosses the cap, once per period.
  defp stop(%__MODULE__{} = l, purpose, c) do
    case Map.get(l.budgets, purpose) do
      %{cap_nanos: cap, period: period} when is_integer(cap) ->
        key = Period.key(period, c.at)
        spent = spent_after(l, purpose, period, key, c.cost_nanos)

        if spent > cap and Map.get(l.exceeded, purpose) != key do
          [
            %Events.BudgetExceeded{
              actor: c.actor,
              at: c.at,
              id: c.id,
              purpose: purpose,
              cap_nanos: cap,
              spent_nanos: spent,
              period: Atom.to_string(period),
              period_key: key
            }
          ]
        else
          []
        end

      _no_cap ->
        []
    end
  end

  defp spent_after(%__MODULE__{spent: spent}, purpose, _period, key, cost) do
    case Map.get(spent, purpose) do
      {^key, so_far} -> so_far + cost
      _other_period -> cost
    end
  end

  # ---- apply ----

  def apply(%__MODULE__{} = l, %Events.BudgetSet{} = e) do
    period = Period.parse(e.period) || @default_period
    previous = Map.get(l.budgets, e.purpose)

    spent =
      if previous && previous.period == period,
        do: l.spent,
        else: Map.delete(l.spent, e.purpose)

    %{
      l
      | id: e.id,
        budgets: Map.put(l.budgets, e.purpose, %{cap_nanos: e.cap_nanos, period: period}),
        spent: spent,
        exceeded: Map.delete(l.exceeded, e.purpose)
    }
  end

  def apply(%__MODULE__{} = l, %Events.ModelCallRecorded{} = e) do
    period = period_of(l, e.purpose)
    key = Period.key(period, e.at)

    spent =
      case Map.get(l.spent, e.purpose) do
        {^key, so_far} -> {key, so_far + e.cost_nanos}
        _other -> {key, e.cost_nanos}
      end

    %{l | id: e.id, spent: Map.put(l.spent, e.purpose, spent)}
  end

  def apply(%__MODULE__{} = l, %Events.BudgetExceeded{} = e),
    do: %{l | id: e.id, exceeded: Map.put(l.exceeded, e.purpose, e.period_key)}

  defp period_of(%__MODULE__{budgets: budgets}, purpose) do
    case Map.get(budgets, purpose) do
      %{period: period} -> period
      nil -> @default_period
    end
  end
end
