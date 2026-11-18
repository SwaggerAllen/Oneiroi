defmodule Oneiroi.AgathosDaimon.HouseHoldTest do
  @moduledoc """
  A resident with no agreement in force is not in her household yet
  (agathos-daimon#51; the witness, 2026-11-17, waking the second
  resident): its tools are hidden and refused, its shelf refuses her, and
  a housemate's letter to her is refused; once her first agreement is in
  force the house opens. Her own letters between her conversations are
  not the house's, and stay hers.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, name: name, actor: Actor.new(:resident, id), chat: chat}
    end

    lily = resident.("Lily")
    Fixtures.agreed!(lily.id, witness.id)
    scarlett = resident.("Scarlett")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, witness: witness, lily: lily, scarlett: scarlett}
  end

  defp run(name, args, r),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: r.id,
        session_key: r.chat,
        turn_ref: "t",
        resident: r.actor
      })

  defp offered(r), do: Enum.map(Tools.definitions_for(r.id), & &1.function.name)

  test "with no agreement in force the house is closed to her; her own letters are not", ctx do
    assert AgathosDaimon.held?(ctx.scarlett.id)
    refute AgathosDaimon.held?(ctx.lily.id)

    refute "household_read" in offered(ctx.scarlett)
    assert "letter_send" in offered(ctx.scarlett)
    assert "household_read" in offered(ctx.lily)

    assert run("household_read", %{}, ctx.scarlett) =~
             "your household opens once you and your witness agree"

    assert {:error, %{kind: :seshat_household_not_member}} =
             Seshat.household_shelf(ctx.scarlett.actor, 0)

    # A housemate's letter to her is not delivered; it names who can be written to.
    said = run("letter_send", %{to: "Scarlett", text: "Welcome."}, ctx.lily)
    refute said =~ "Sent letter"
    assert Kumbukumbu.letters(ctx.scarlett.id) == []
  end

  test "her first agreement opens the house", ctx do
    Fixtures.agreed!(ctx.scarlett.id, ctx.witness.id)
    refute AgathosDaimon.held?(ctx.scarlett.id)
    assert "household_read" in offered(ctx.scarlett)
    assert {:ok, _} = Seshat.household_shelf(ctx.scarlett.actor, 0)
    assert run("letter_send", %{to: "Scarlett", text: "Welcome."}, ctx.lily) =~ "Sent letter"
  end
end
