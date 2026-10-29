defmodule Oneiroi.Nisaba.LedgerTest do
  @moduledoc "The aggregate, pure: execute and apply over structs, no store."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Nisaba.Commands
  alias Oneiroi.Nisaba.Events
  alias Oneiroi.Nisaba.Ledger
  alias Oneiroi.Nisaba.Period

  @at ~U[2026-10-29 12:00:00.000000Z]
  @actor Actor.new(:resident, "r1", "fake/model")

  defp budget(ledger, purpose, cap, period) do
    Ledger.apply(ledger, %Events.BudgetSet{
      actor: @actor,
      at: @at,
      id: "r1",
      purpose: purpose,
      cap_nanos: cap,
      period: period
    })
  end

  defp record(ledger, purpose, cost, at \\ @at) do
    events =
      List.wrap(
        Ledger.execute(ledger, %Commands.RecordModelCall{
          actor: @actor,
          at: at,
          id: "r1",
          ref: "ref-#{cost}",
          purpose: purpose,
          model: "fake/model",
          prompt_tokens: 1,
          completion_tokens: 1,
          cost_nanos: cost,
          estimated: false
        })
      )

    {Enum.reduce(events, ledger, &Ledger.apply(&2, &1)), events}
  end

  test "a budget line is set as an event carrying its purpose and period as strings" do
    assert %Events.BudgetSet{purpose: "chat", period: "week", cap_nanos: 5} =
             Ledger.execute(%Ledger{}, %Commands.SetBudget{
               actor: @actor,
               at: @at,
               id: "r1",
               purpose: :chat,
               cap_nanos: 5,
               period: :week
             })
  end

  test "the stop is written on the call that crosses the cap, once per period" do
    ledger = budget(%Ledger{}, "chat", 100, "month")

    {ledger, events} = record(ledger, :chat, 60)
    assert [%Events.ModelCallRecorded{}] = events

    {ledger, events} = record(ledger, :chat, 60)
    assert [%Events.ModelCallRecorded{}, %Events.BudgetExceeded{} = stop] = events
    assert stop.spent_nanos == 120 and stop.cap_nanos == 100 and stop.period_key == "2026-10"

    # Already stopped this period: the next call records and says nothing more.
    {ledger, events} = record(ledger, :chat, 1)
    assert [%Events.ModelCallRecorded{}] = events

    # A new period starts the count over, and the stop can be written again.
    {_ledger, events} = record(ledger, :chat, 101, ~U[2026-11-01 00:00:00.000000Z])
    assert [%Events.ModelCallRecorded{}, %Events.BudgetExceeded{period_key: "2026-11"}] = events
  end

  test "a purpose with no cap records and never stops" do
    {_ledger, events} = record(%Ledger{}, :judge, 1_000_000_000_000)
    assert [%Events.ModelCallRecorded{purpose: "judge"}] = events

    ledger = budget(%Ledger{}, "judge", nil, "day")
    {_ledger, events} = record(ledger, :judge, 1_000_000_000_000)
    assert [%Events.ModelCallRecorded{}] = events
  end

  test "resetting a line clears its stop, and a changed period starts its tracking afresh" do
    ledger = budget(%Ledger{}, "chat", 10, "month")
    {ledger, [_, %Events.BudgetExceeded{}]} = record(ledger, :chat, 11)
    assert ledger.exceeded == %{"chat" => "2026-10"}

    ledger = budget(ledger, "chat", 10, "month")
    assert ledger.exceeded == %{}
    assert ledger.spent == %{"chat" => {"2026-10", 11}}

    ledger = budget(ledger, "chat", 10, "day")
    assert ledger.spent == %{}
  end

  test "period keys and ranges are what the spend query reads" do
    assert Period.key(:day, @at) == "2026-10-29"
    assert Period.key(:week, @at) == "2026-W44"
    assert Period.key(:month, @at) == "2026-10"

    assert {~U[2026-10-26 00:00:00.000000Z], ~U[2026-11-02 00:00:00.000000Z]} =
             Period.range(:week, @at)

    assert {~U[2026-10-01 00:00:00.000000Z], ~U[2026-11-01 00:00:00.000000Z]} =
             Period.range(:month, @at)

    assert {~U[2026-10-29 00:00:00.000000Z], ~U[2026-10-30 00:00:00.000000Z]} =
             Period.range(:day, @at)
  end
end
