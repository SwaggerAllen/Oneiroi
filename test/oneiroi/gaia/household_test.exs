defmodule Oneiroi.Gaia.HouseholdTest do
  @moduledoc """
  gaia#17 (the witness, 2026-11-05: the household is the billing owner
  from day one, with two join tables, one for its witnesses and one for
  its residents; never neither): every account founds a household when it
  is created, every resident joins its witness's, a solo witness is a
  household of one pair, custody moves a resident between households,
  and terms are granted by the platform or a super admin, with a note.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    :ok
  end

  test "an account founds its household; its resident joins it; a solo witness is a household of one pair" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)

    assert Gaia.household_id(witness.id) == witness.id

    assert %{id: id, witnesses: [w], residents: [r], terms: nil} = Gaia.household(witness.id)
    assert id == witness.id
    assert w == witness.id
    assert r == resident.id
  end

  test "custody to another account moves the resident to that account's household" do
    old = Fixtures.account!()
    new = Fixtures.account!()
    resident = Fixtures.resident!(old)

    assert :ok =
             AgathosDaimon.propose_custody(
               resident.id,
               new.id,
               "take her",
               Actor.new(:witness, old.id)
             )

    assert :ok = AgathosDaimon.accept_custody(resident.id, "mine", Actor.new(:witness, new.id))

    assert %{residents: []} = Gaia.household(old.id)
    assert %{residents: [moved]} = Gaia.household(new.id)
    assert moved == resident.id
  end

  test "terms are granted by the platform or a super admin, with a note; never by a stranger" do
    founder = Fixtures.account!()
    stranger = Fixtures.account!()
    until = DateTime.add(Clock.now(), 90 * 86_400, :second)
    terms = %{plan: "monthly", price_nanos: 20_000_000_000, until: until, source: "invite:abc"}

    assert {:error, %Gaia.Error{kind: :gaia_not_an_operator}} =
             Gaia.grant_household_terms(
               stranger.id,
               terms,
               "mine",
               Actor.new(:witness, stranger.id)
             )

    assert {:error, %Gaia.Error{kind: :gaia_household_invalid}} =
             Gaia.grant_household_terms(stranger.id, terms, " ", Actor.platform())

    assert :ok =
             Gaia.grant_household_terms(
               stranger.id,
               terms,
               "an invite redeemed",
               Actor.platform()
             )

    assert %{terms: %{plan: "monthly", price_nanos: 20_000_000_000, source: "invite:abc"}} =
             Gaia.household(stranger.id)

    assert :ok =
             Gaia.grant_household_terms(
               stranger.id,
               %{terms | plan: "annual"},
               "the operator's",
               Actor.new(:witness, founder.id)
             )

    assert %{terms: %{plan: "annual"}} = Gaia.household(stranger.id)
  end
end
