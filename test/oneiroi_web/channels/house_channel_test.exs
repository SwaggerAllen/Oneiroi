defmodule OneiroiWeb.HouseChannelTest do
  @moduledoc "The house queue's notices (sunna#80): a member joins the household's channel and hears a queue change as a notice, so the Work page never polls; a stranger cannot join."
  use OneiroiWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias OneiroiWeb.UserSocket

  setup do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, witness: witness, resident: resident}
  end

  defp join_as(account_id, household_id) do
    {:ok, socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, account_id)})

    subscribe_and_join(socket, OneiroiWeb.HouseChannel, "house:#{household_id}", %{})
  end

  test "a member hears a queue change, whoever made it", ctx do
    {:ok, _reply, _socket} = join_as(ctx.witness.id, ctx.witness.id)
    lily = Actor.new(:resident, ctx.resident.id)

    :ok = Oneiroi.Sunna.queue_open_project(ctx.witness.id, %{slug: "p", name: "P"}, lily)

    assert_push "notice", %{stream: "queue", kind: "ProjectOpened"}, 5_000
  end

  # The witness, 2026-11-26: pages are pushed to, not polled; the
  # charter's page hears its household's own stream.
  test "`house:mine` is the caller's household, and its charter's changes arrive", ctx do
    {:ok, _reply, _socket} = join_as(ctx.witness.id, "mine")
    andrew = Actor.new(:witness, ctx.witness.id)

    {:ok, _} =
      Oneiroi.Seshat.household_propose_contract(andrew, "We share this house.", "founding")

    assert_push "notice", %{stream: "household"}, 5_000
  end

  # apsu#35: the join names the client build served, nil where none is
  # built (as here), so a page compares nothing.
  test "the join names the client build it serves", ctx do
    assert {:ok, %{build: build}, _socket} = join_as(ctx.witness.id, ctx.witness.id)
    assert build == OneiroiWeb.ClientBuild.id()
  end

  test "a stranger cannot join another household's channel", ctx do
    stranger = Fixtures.account!()
    assert {:error, %{reason: "not a member"}} = join_as(stranger.id, ctx.witness.id)
  end
end
