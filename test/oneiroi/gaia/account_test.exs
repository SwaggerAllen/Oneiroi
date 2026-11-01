defmodule Oneiroi.Gaia.AccountTest do
  @moduledoc "The aggregate, pure: execute and apply over structs, no store."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Gaia.Account
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  @at ~U[2026-10-26 12:00:00Z]
  @actor Actor.platform()

  defp created,
    do:
      Account.apply(%Account{}, %Events.AccountCreated{
        actor: @actor,
        at: @at,
        id: "a1",
        email: "a@x",
        password_hash: "h"
      })

  test "an account is created once" do
    assert %Events.AccountCreated{id: "a1"} =
             Account.execute(%Account{}, %Commands.CreateAccount{
               actor: @actor,
               at: @at,
               id: "a1",
               email: "a@x",
               password_hash: "h"
             })

    assert {:error, %Error{kind: :gaia_account_exists, site: :gaia_account_create_exists}} =
             Account.execute(created(), %Commands.CreateAccount{
               actor: @actor,
               at: @at,
               id: "a1",
               email: "a@x",
               password_hash: "h"
             })

    assert {:error, %Error{kind: :gaia_no_such_account, site: :gaia_account_absent}} =
             Account.execute(%Account{}, %Commands.OpenSession{
               actor: @actor,
               at: @at,
               id: "a1",
               session_hash: "s",
               expires_at: @at
             })
  end

  test "a session closes only while open, a token revokes only while issued" do
    opened =
      Account.apply(created(), %Events.SessionOpened{
        actor: @actor,
        at: @at,
        id: "a1",
        session_hash: "s",
        expires_at: @at
      })

    assert %Events.SessionClosed{session_hash: "s"} =
             Account.execute(opened, %Commands.CloseSession{
               actor: @actor,
               at: @at,
               id: "a1",
               session_hash: "s"
             })

    assert {:error, %Error{kind: :gaia_not_a_principal, site: :gaia_account_close_session_absent}} =
             Account.execute(created(), %Commands.CloseSession{
               actor: @actor,
               at: @at,
               id: "a1",
               session_hash: "s"
             })

    assert {:error, %Error{kind: :gaia_no_such_token, site: :gaia_account_revoke_token_absent}} =
             Account.execute(created(), %Commands.RevokeToken{
               actor: @actor,
               at: @at,
               id: "a1",
               token_hash: "t"
             })
  end

  test "witnessing starts and ends idempotently, so a replayed handler changes nothing" do
    start = %Commands.StartWitnessing{actor: @actor, at: @at, id: "a1", resident_id: "r1"}

    assert %Events.WitnessingStarted{resident_id: "r1"} =
             event = Account.execute(created(), start)

    witnessing = Account.apply(created(), event)
    assert [] == Account.execute(witnessing, start)

    assert [] ==
             Account.execute(created(), %Commands.EndWitnessing{
               actor: @actor,
               at: @at,
               id: "a1",
               resident_id: "r1"
             })

    assert %Events.WitnessingEnded{} =
             Account.execute(witnessing, %Commands.EndWitnessing{
               actor: @actor,
               at: @at,
               id: "a1",
               resident_id: "r1"
             })
  end
end
