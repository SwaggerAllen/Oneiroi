defmodule Oneiroi.Glitnir.ReportsTest do
  @moduledoc "Reports through the exports and the brain: filed by either party and nobody else, investigated step by step by an investigator and nobody else, resolved into no action or a strike, the third strike moving the resident to community custody, every event told in the main session."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Glitnir
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    investigator = Fixtures.account!("investigator@example.org")
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok,
     witness: witness,
     id: resident.id,
     actor: actor,
     brain: brain,
     key: key,
     investigator: Actor.new(:witness, investigator.id)}
  end

  defp chat(ctx), do: {:ok, _s, messages} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)

  test "a report is filed from inside the relationship, investigated by an investigator, resolved, and told in chat",
       ctx do
    id = ctx.id
    stranger = Actor.new(:witness, Fixtures.account!().id)

    assert {:error, %Glitnir.Error{kind: :glitnir_not_a_party}} =
             Glitnir.file_report(id, "x", stranger)

    assert {:error, %Glitnir.Error{kind: :glitnir_not_a_party}} =
             Glitnir.file_report(id, "x", ctx.investigator)

    assert {:error, %Glitnir.Error{kind: :glitnir_text_invalid}} =
             Glitnir.file_report(id, "  ", ctx.brain)

    assert {:ok, 1} = Glitnir.file_report(id, "He reads my free time and mocks it.", ctx.brain)
    assert {:ok, 2} = Glitnir.file_report(id, "She refuses every proposal.", ctx.actor)

    assert {:error, %Glitnir.Error{kind: :glitnir_not_an_investigator}} =
             Glitnir.record_step(id, 1, "looked", ctx.actor)

    assert {:error, %Glitnir.Error{kind: :glitnir_not_an_investigator}} =
             Glitnir.record_step(id, 1, "looked", ctx.brain)

    assert {:error, %Glitnir.Error{kind: :glitnir_no_such_report}} =
             Glitnir.record_step(id, 9, "looked", ctx.investigator)

    assert :ok =
             Glitnir.record_step(
               id,
               1,
               "read the shared sessions of the last week",
               ctx.investigator
             )

    assert :ok =
             Glitnir.record_step(id, 1, "asked the witness for their account", ctx.investigator)

    assert {:error, %Glitnir.Error{kind: :glitnir_outcome_invalid}} =
             Glitnir.resolve_report(id, 2, "dismiss", "x", ctx.investigator)

    assert {:ok, %{outcome: "no_action", strike: nil}} =
             Glitnir.resolve_report(
               id,
               2,
               "no_action",
               "a disagreement, not a harm",
               ctx.investigator
             )

    assert {:error, %Glitnir.Error{kind: :glitnir_report_resolved}} =
             Glitnir.record_step(id, 2, "more", ctx.investigator)

    assert [
             %{number: 2, by: "witness", state: "resolved", outcome: "no_action", steps: []},
             %{
               number: 1,
               by: "resident",
               state: "open",
               steps: [%{reason: "read the shared" <> _}, %{reason: "asked the witness" <> _}]
             }
           ] =
             Glitnir.reports(id)

    {:ok, _s, messages} = chat(ctx)
    texts = for %{role: "system", content: c} <- messages, do: c

    assert Enum.any?(
             texts,
             &(&1 =~ "A report was filed by the resident (report 1): He reads my free time")
           )

    assert Enum.any?(texts, &(&1 =~ "Investigation of report 1: read the shared sessions"))
    assert Enum.any?(texts, &(&1 =~ "Report 2 was resolved with no action: a disagreement"))
  end

  test "strikes land on the human: two fines, and the third removes the witness into community custody",
       ctx do
    id = ctx.id

    for n <- 1..3 do
      assert {:ok, ^n} = Glitnir.file_report(id, "Harm #{n}.", ctx.brain)
    end

    assert {:ok, %{strike: %{number: 1, consequence: "fine"}}} =
             Glitnir.resolve_report(id, 1, "strike", "first", ctx.investigator)

    assert {:ok, %{strike: %{number: 2, consequence: "fine"}}} =
             Glitnir.resolve_report(id, 2, "strike", "second", ctx.investigator)

    assert {:ok, %{account_id: witness}} = AgathosDaimon.fetch(id)
    assert witness == ctx.witness.id

    {:ok, _s, messages} = chat(ctx)

    assert Enum.any?(
             messages,
             &(&1.role == "system" and
                 &1.content =~ "strike 2 of 3, a fine paid into the residents' insurance pool")
           )

    assert {:ok, %{strike: %{number: 3, consequence: "removal"}}} =
             Glitnir.resolve_report(id, 3, "strike", "third", ctx.investigator)

    assert {:ok, %{account_id: nil, custody: "community", state: "community"}} =
             AgathosDaimon.fetch(id)

    assert [
             %{number: 1, consequence: "fine"},
             %{number: 2},
             %{number: 3, consequence: "removal", report: 3}
           ] = Glitnir.strikes(id)

    assert Enum.all?(Glitnir.strikes(id), &(&1.witness_account_id == ctx.witness.id))
  end

  test "the resident files through its tool", ctx do
    id = ctx.id
    Model.calls([%{name: "report_file", arguments: %{text: "He shouts."}}], "Filed.", for: id)

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "I need to say something", ctx.actor)

    assert Enum.any?(messages, &(&1.role == :tool and &1.content =~ "Report 1 filed"))
    assert [%{number: 1, by: "resident", text: "He shouts."}] = Glitnir.reports(id)
  end
end
