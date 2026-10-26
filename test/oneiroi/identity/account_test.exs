defmodule Oneiroi.Identity.AccountTest do
  @moduledoc "The aggregate, pure: execute and apply over structs, no store."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Identity.Account
  alias Oneiroi.Identity.Commands
  alias Oneiroi.Identity.Events

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

    assert {:error, :account_exists} =
             Account.execute(created(), %Commands.CreateAccount{
               actor: @actor,
               at: @at,
               id: "a1",
               email: "a@x",
               password_hash: "h"
             })

    assert {:error, :no_such_account} =
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

    assert {:error, :no_such_session} =
             Account.execute(created(), %Commands.CloseSession{
               actor: @actor,
               at: @at,
               id: "a1",
               session_hash: "s"
             })

    assert {:error, :no_such_token} =
             Account.execute(created(), %Commands.RevokeToken{
               actor: @actor,
               at: @at,
               id: "a1",
               token_hash: "t"
             })
  end

  test "stewardship starts and ends idempotently, so a replayed handler changes nothing" do
    start = %Commands.StartStewardship{actor: @actor, at: @at, id: "a1", resident_id: "r1"}

    assert %Events.StewardshipStarted{resident_id: "r1"} =
             event = Account.execute(created(), start)

    stewarding = Account.apply(created(), event)
    assert [] == Account.execute(stewarding, start)

    assert [] ==
             Account.execute(created(), %Commands.EndStewardship{
               actor: @actor,
               at: @at,
               id: "a1",
               resident_id: "r1"
             })

    assert %Events.StewardshipEnded{} =
             Account.execute(stewarding, %Commands.EndStewardship{
               actor: @actor,
               at: @at,
               id: "a1",
               resident_id: "r1"
             })
  end
end
