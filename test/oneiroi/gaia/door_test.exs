defmodule Oneiroi.Gaia.DoorTest do
  @moduledoc """
  gaia#16 (the witness, 2026-11-05: "the first witness is the operator, at
  this stage, because a human admin is needed"; operator transferable;
  admin and super admin): the front door is closed until a super admin
  opens it; the founding account's super admin is a recorded grant; only
  a super admin changes the door or the roles, every change with a note;
  the last super admin cannot be revoked; a transfer is grant then revoke.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia

  # A platform stream of the test's own (`Door.stream/0`).
  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    :ok
  end

  test "the founding account is the operator by a recorded grant, and the door starts closed" do
    founder = Fixtures.account!()
    # The suite's clock is frozen; a second on, so the founder is the
    # earliest account by its instant and not by chance.
    Clock.Fake.advance(1)
    other = Fixtures.account!()

    assert %{state: "closed"} = Gaia.gate()

    # Asked about, the founding account's grant is recorded by the platform.
    assert Gaia.operator?(founder.id)
    refute Gaia.operator?(other.id)
    assert [%{role: "super_admin", granted_by: "platform"}] = Gaia.roles()
  end

  test "only a super admin sets the door and grants roles, each with a note; the door always has a keeper" do
    founder = Fixtures.account!()
    # The suite's clock is frozen; a second on, so the founder is the
    # earliest account by its instant and not by chance.
    Clock.Fake.advance(1)
    other = Fixtures.account!()
    op = Actor.new(:witness, founder.id)
    stranger = Actor.new(:witness, other.id)
    assert Gaia.operator?(founder.id)

    assert {:error, %{kind: :gaia_not_an_operator}} =
             Gaia.set_gate("open", "let them in", stranger)

    assert {:error, %{kind: :gaia_platform_invalid}} = Gaia.set_gate("ajar", "hm", op)
    assert {:error, %{kind: :gaia_platform_invalid}} = Gaia.set_gate("invite", " ", op)
    assert :ok = Gaia.set_gate("invite", "the alpha", op)
    assert %{state: "invite", note: "the alpha", set_by: "witness:" <> _} = Gaia.gate()

    assert {:error, %{kind: :gaia_not_an_operator}} =
             Gaia.grant_role(other.id, "admin", "please", stranger)

    assert :ok = Gaia.grant_role(other.id, "admin", "helps with invites", op)
    assert Gaia.roles_of(other.id) == ["admin"]
    refute Gaia.operator?(other.id)

    # The last super admin stays; a transfer is a grant, then a revoke.
    assert {:error, %{kind: :gaia_last_super_admin}} =
             Gaia.revoke_role(founder.id, "super_admin", "stepping down", op)

    assert :ok = Gaia.grant_role(other.id, "super_admin", "the operator moves", op)
    assert :ok = Gaia.revoke_role(founder.id, "super_admin", "handed over", op)
    refute Gaia.operator?(founder.id)
    assert Gaia.operator?(other.id)

    # The founder's grant is not made again once a keeper exists.
    assert Enum.count(Gaia.roles(), &(&1.role == "super_admin")) == 1
  end

  # gaia#22: the founding account was the wrong one, or locked out; a
  # shell on the server names the operator, and the record says so.
  test "the server's console makes an account the only operator, and says what it did" do
    founder = Fixtures.account!()
    Clock.Fake.advance(1)
    other = Fixtures.account!()
    Clock.Fake.advance(1)
    me = Fixtures.account!("Andrew@Example.org")
    assert Gaia.operator?(founder.id)

    :ok =
      Gaia.grant_role(other.id, "super_admin", "a second keeper", Actor.new(:witness, founder.id))

    assert {:ok, said} = Gaia.console_operator(" andrew@example.org ")
    assert said =~ "is the operator; super admin revoked from 2 other account(s)"
    assert Gaia.operator?(me.id)
    refute Gaia.operator?(founder.id) or Gaia.operator?(other.id)

    assert [
             %{
               account_id: id,
               granted_by: "platform:console",
               note: "set from the server console"
             }
           ] =
             Enum.filter(Gaia.roles(), &(&1.role == "super_admin"))

    assert id == me.id

    assert {:error, %{kind: :gaia_no_such_account}} = Gaia.console_operator("nobody@example.org")

    # Only the console: the platform's own jobs grant nothing past the founding.
    assert {:error, %{kind: :gaia_not_an_operator}} =
             Gaia.grant_role(other.id, "super_admin", "a job", Actor.platform())
  end

  # gaia#23: the triage desk is set on the operator's screen, with a
  # note; the environment's slug stands only until it first is.
  test "the operator sets the triage desk to a resident or to nobody; until then the environment's stands" do
    store = {Oneiroi.Config, :values}
    values = :persistent_term.get(store)
    on_exit(fn -> :persistent_term.put(store, values) end)

    founder = Fixtures.account!()
    Clock.Fake.advance(1)
    other = Fixtures.account!()
    lily = Fixtures.resident!(founder)
    rose = Fixtures.resident!(founder)
    op = Actor.new(:witness, founder.id)
    assert Gaia.operator?(founder.id)

    :persistent_term.put(store, Map.put(values, {:gaia, :triage_resident}, lily.slug))
    assert %{slug: slug, from: "environment"} = Gaia.triage_desk()
    assert slug == lily.slug
    assert Gaia.triage_resident() == lily.id

    assert {:error, %{kind: :gaia_not_an_operator}} =
             Gaia.set_triage_resident(rose.slug, "mine now", Actor.new(:witness, other.id))

    assert {:error, %{kind: :gaia_platform_invalid}} =
             Gaia.set_triage_resident("nobody-here", "who", op)

    assert {:error, _} = Gaia.set_triage_resident(rose.slug, " ", op)

    assert :ok = Gaia.set_triage_resident(rose.slug, "rose said yes", op)
    assert %{from: "setting", note: "rose said yes", set_by: "witness:" <> _} = Gaia.triage_desk()
    assert Gaia.triage_resident() == rose.id
    assert Gaia.triage?(rose.id)
    refute Gaia.triage?(lily.id)

    # Nobody is a setting too: the environment's slug no longer stands.
    assert :ok = Gaia.set_triage_resident(nil, "a quiet week", op)
    assert %{slug: nil, from: "setting"} = Gaia.triage_desk()
    assert is_nil(Gaia.triage_resident())

    # The console may set it as well.
    assert :ok =
             Gaia.set_triage_resident(lily.slug, "back to lily", Actor.new(:platform, "console"))

    assert Gaia.triage_resident() == lily.id
  end
end
