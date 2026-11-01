defmodule OneiroiWeb.RegressionChannelTest do
  @moduledoc "A regression run as it answers (eunomia #30): a witness joins the run's channel and its cards arrive blind, then the end; a stranger and an adapter cannot join."
  use OneiroiWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias OneiroiWeb.UserSocket

  setup do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)

    {:ok, 1} =
      Eunomia.write_test(resident.id, %{prompt: "Hello?", passes_if: "y", fails_if: "n"}, actor)

    Fake.reply("hello back", for: resident.id)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, resident: resident, actor: actor}
  end

  defp socket_for(account_id) do
    {:ok, socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, account_id)})

    socket
  end

  test "a witness joins the run's channel; each card arrives blind as it is recorded, then the end",
       ctx do
    id = ctx.resident.id
    {:ok, ref} = Eunomia.run(id, ["m1", "m2"], :all, ctx.actor)

    {:ok, _reply, _socket} =
      subscribe_and_join(
        socket_for(ctx.witness.id),
        OneiroiWeb.RegressionChannel,
        "regression:#{id}:#{ref}"
      )

    # Another run's news is not this channel's.
    PubSub.broadcast(
      :eunomia,
      :regression,
      {id, "another", {:finished, %{state: "finished", cards: 0}}}
    )

    assert %{discard: 0, failure: 0, success: 1} =
             Oban.drain_queue(queue: :eunomia_regression, with_safety: false)

    assert_push "card", %{model: nil, test_number: 1, content: "hello back", card_ref: c1}
    assert_push "card", %{model: nil, test_number: 1, card_ref: c2}
    assert_push "finished", %{state: "finished", cards: 2}
    refute_push "finished", _

    {:ok, _run, cards, []} = Eunomia.run_detail(id, ref)
    assert Enum.sort([c1, c2]) == cards |> Enum.map(& &1.card_ref) |> Enum.sort()
  end

  test "an account that does not witness the resident cannot join", ctx do
    {:ok, ref} = Eunomia.run(ctx.resident.id, ["m1"], :all, ctx.actor)
    other = Fixtures.account!()

    assert {:error, %{reason: "not witnessed"}} =
             subscribe_and_join(
               socket_for(other.id),
               OneiroiWeb.RegressionChannel,
               "regression:#{ctx.resident.id}:#{ref}"
             )
  end

  test "an adapter's token opens no socket, and an adapter principal cannot join", ctx do
    id = ctx.resident.id
    {:ok, ref} = Eunomia.run(id, ["m1"], :all, ctx.actor)
    {:ok, token} = AgathosDaimon.register_adapter(id, "claude-code", "brain", ctx.actor)
    assert :error = connect(UserSocket, %{"token" => token})

    adapter = %AdapterPrincipal{resident_id: id, adapter: "claude-code", role: "brain"}

    assert {:error, %{reason: "not witnessed"}} =
             UserSocket
             |> socket("adapter", %{principal: adapter})
             |> subscribe_and_join(OneiroiWeb.RegressionChannel, "regression:#{id}:#{ref}")
  end
end
