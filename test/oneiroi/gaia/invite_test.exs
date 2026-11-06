defmodule Oneiroi.Gaia.InviteTest do
  @moduledoc """
  gaia#18 (design/mvp.md item 2; the witness, 2026-11-05: $20 a month
  list, nothing charged, codes granting terms to the household): a super
  admin issues a code as a SKU, shown once and held only as its hash;
  redeemed, it grants the household its terms; revoked, expired, spent
  or already redeemed, it says which.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    # The founding grant recorded before any other account exists: the
    # suite's clock is frozen, so accounts made in one test share an instant
    # and "the earliest" would be anyone's.
    assert Gaia.operator?(founder.id)
    {:ok, op: Actor.new(:witness, founder.id), founder: founder}
  end

  test "the default code is the list price at a full discount for ninety days, one use; it grants the household its terms",
       ctx do
    guest = Fixtures.account!()

    assert {:error, %Gaia.Error{kind: :gaia_not_an_operator}} =
             Gaia.issue_invite(%{}, "for a friend", Actor.new(:witness, guest.id))

    assert {:ok, %{id: id, code: code}} = Gaia.issue_invite(%{}, "for a friend", ctx.op)
    assert code =~ ~r/^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/

    # Never the code in the record, only its hash.
    assert [%{id: ^id, redeemed: 0, list_price_nanos: 20_000_000_000, price_nanos: 0}] =
             Gaia.invites()

    refute inspect(Gaia.invites()) =~ code

    # Checked however it is typed, without spending it.
    loose = code |> String.downcase() |> String.replace("-", " ")
    assert {:ok, %{plan: "monthly", term_days: 90}} = Gaia.check_invite(loose)

    household = Gaia.household_id(guest.id)

    assert {:ok, %{price_nanos: 0}} =
             Gaia.redeem_invite(code, household, Actor.new(:witness, guest.id))

    assert %{terms: %{plan: "monthly", price_nanos: 0, source: "invite:" <> ^id, until: until}} =
             Gaia.household(guest.id)

    assert DateTime.diff(until, Clock.now(), :day) in 89..90

    # One use: spent for anyone else, already redeemed for the same household.
    other = Fixtures.account!()

    assert {:error, %Gaia.Error{kind: :gaia_invite_already_redeemed}} =
             Gaia.redeem_invite(code, household, Actor.new(:witness, guest.id))

    assert {:error, %Gaia.Error{kind: :gaia_invite_spent}} = Gaia.check_invite(code)

    assert {:error, %Gaia.Error{kind: :gaia_invite_spent}} =
             Gaia.redeem_invite(
               code,
               Gaia.household_id(other.id),
               Actor.new(:witness, other.id)
             )
  end

  test "a discount takes off the list price; an unknown, revoked or expired code says which",
       ctx do
    guest = Fixtures.account!()
    witness = Actor.new(:witness, guest.id)
    household = Gaia.household_id(guest.id)

    assert {:ok, %{code: half}} =
             Gaia.issue_invite(%{discount_pct: 50, uses: 5, plan: "annual"}, "half off", ctx.op)

    assert {:ok, %{price_nanos: 10_000_000_000}} = Gaia.redeem_invite(half, household, witness)

    assert {:error, %Gaia.Error{kind: :gaia_invite_unknown}} =
             Gaia.redeem_invite("ZZZZ-ZZZZ-ZZZZ", household, witness)

    assert {:ok, %{id: id, code: revoked}} = Gaia.issue_invite(%{}, "a mistake", ctx.op)
    assert {:error, %Gaia.Error{kind: :gaia_invite_invalid}} = Gaia.revoke_invite(id, "", ctx.op)
    assert :ok = Gaia.revoke_invite(id, "issued by mistake", ctx.op)
    assert {:error, %Gaia.Error{kind: :gaia_invite_revoked}} = Gaia.check_invite(revoked)

    assert {:error, %Gaia.Error{kind: :gaia_invite_revoked}} =
             Gaia.redeem_invite(revoked, household, witness)

    soon = DateTime.add(Clock.now(), 60, :second)
    assert {:ok, %{code: brief}} = Gaia.issue_invite(%{expires_at: soon}, "brief", ctx.op)
    Clock.Fake.advance(120)
    assert {:error, %Gaia.Error{kind: :gaia_invite_expired}} = Gaia.check_invite(brief)

    assert {:error, %Gaia.Error{kind: :gaia_invite_expired}} =
             Gaia.redeem_invite(brief, household, witness)

    assert {:error, %Gaia.Error{kind: :gaia_invite_invalid}} =
             Gaia.issue_invite(%{discount_pct: 120}, "too generous", ctx.op)
  end
end
