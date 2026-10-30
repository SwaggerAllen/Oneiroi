defmodule Oneiroi.HuginnMuninn.AuditsTest do
  @moduledoc "The audits aggregate, pure: a counter's value is the fold of its increments, a rule is validated, a run has a tone."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.HuginnMuninn.Audits
  alias Oneiroi.HuginnMuninn.Commands
  alias Oneiroi.HuginnMuninn.Events

  @actor Actor.new(:witness, "a")
  @at ~U[2026-10-26 12:00:00.000000Z]

  defp evolve(state \\ %Audits{}, events),
    do: Enum.reduce(List.wrap(events), state, &Audits.apply(&2, &1))

  defp cmd(module, fields),
    do: struct!(module, Map.merge(%{actor: @actor, at: @at, id: "r"}, Map.new(fields)))

  test "a counter is defined once, incremented by non-zero integers, folded, and retired" do
    define = cmd(Commands.DefineCounter, key: "tea", label: "Cups of tea")
    assert %Events.CounterDefined{key: "tea"} = Audits.execute(%Audits{}, define)
    s = evolve(Audits.execute(%Audits{}, define))
    assert [] = Audits.execute(s, define)
    assert {:error, :key_invalid} = Audits.execute(s, %{define | key: "Not A Key"})
    assert {:error, :label_invalid} = Audits.execute(s, %{define | key: "ok", label: ""})

    inc = cmd(Commands.IncrementCounter, key: "tea", by: 2, note: "two this morning")
    assert %Events.CounterIncremented{by: 2} = Audits.execute(s, inc)
    s = evolve(s, Audits.execute(s, inc))
    s = evolve(s, Audits.execute(s, %{inc | by: -1}))
    assert s.counters["tea"] == 1
    assert {:error, :increment_invalid} = Audits.execute(s, %{inc | by: 0})
    assert {:error, :no_such_counter} = Audits.execute(s, %{inc | key: "coffee"})

    assert %Events.CounterRetired{} = Audits.execute(s, cmd(Commands.RetireCounter, key: "tea"))
    s = evolve(s, Audits.execute(s, cmd(Commands.RetireCounter, key: "tea")))
    assert {:error, :no_such_counter} = Audits.execute(s, inc)
  end

  test "a witness's audit is a validated rule, the same rule twice is no event, and a run carries a tone" do
    define =
      cmd(Commands.DefineUserAudit,
        key: "tea-enough",
        label: "Enough tea",
        figure: "tea",
        op: ">=",
        value: 3,
        tone: "warn",
        counts: true
      )

    assert %Events.UserAuditDefined{counts: true} = Audits.execute(%Audits{}, define)
    s = evolve(Audits.execute(%Audits{}, define))
    assert [] = Audits.execute(s, define)
    assert %Events.UserAuditDefined{value: 4} = Audits.execute(s, %{define | value: 4})
    assert {:error, :rule_invalid} = Audits.execute(s, %{define | op: "~"})
    assert {:error, :rule_invalid} = Audits.execute(s, %{define | value: "three"})
    assert {:error, :rule_invalid} = Audits.execute(s, %{define | tone: "loud"})
    assert {:error, :no_such_audit} = Audits.execute(s, cmd(Commands.RetireUserAudit, key: "x"))

    assert %Events.UserAuditRetired{} =
             Audits.execute(s, cmd(Commands.RetireUserAudit, key: "tea-enough"))

    run =
      cmd(Commands.RecordRun,
        key: "attestation",
        builtin: true,
        tone: "silent",
        value: 0,
        finding: "nothing flagged: matched"
      )

    assert %Events.AuditRun{tone: "silent", builtin: true} = Audits.execute(s, run)
    assert {:error, :rule_invalid} = Audits.execute(s, %{run | tone: "ok"})
    assert {:error, :rule_invalid} = Audits.execute(s, %{run | tone: "fine"})
  end
end
