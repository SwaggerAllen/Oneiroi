defmodule OneiroiWeb.SessionChannelTest do
  @moduledoc "The streamed conversation: a witness joins their resident's session, sends, and gets deltas then the turn."
  use OneiroiWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias OneiroiWeb.UserSocket

  setup do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", Actor.new(:witness, witness.id))

    {:ok, key} =
      Oneiroi.Kumbukumbu.main_session(resident.id, witness.id, Actor.new(:witness, witness.id))

    Fake.clear()
    {:ok, witness: witness, resident: resident, key: key}
  end

  test "a socket token or an API token connects; a stranger's token does not", ctx do
    token = UserSocket.token(OneiroiWeb.Endpoint, ctx.witness.id)
    assert {:ok, socket} = connect(UserSocket, %{"token" => token})
    assert socket.assigns.principal.account_id == ctx.witness.id

    {:ok, raw, _hash} =
      Oneiroi.Gaia.issue_token(ctx.witness.id, "script", Actor.new(:witness, ctx.witness.id))

    assert {:ok, _socket} = connect(UserSocket, %{"token" => raw})

    assert :error = connect(UserSocket, %{"token" => "nonsense"})
    assert :error = connect(UserSocket, %{})
  end

  test "a witness joins their resident's session and a turn streams, and another account cannot join",
       ctx do
    {:ok, socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, ctx.witness.id)})

    {:ok, _reply, socket} =
      subscribe_and_join(
        socket,
        OneiroiWeb.SessionChannel,
        "session:#{ctx.resident.id}:#{ctx.key}"
      )

    ref = push(socket, "send", %{"text" => "hello channel"})
    assert_reply ref, :ok
    assert_push "turn_started", %{turn_ref: turn_ref}
    assert_push "delta", %{text: _}, 5_000

    assert_push "turn",
                %{
                  turn_ref: ^turn_ref,
                  messages: [_, %{content: "The fake provider heard: hello channel"}]
                },
                10_000

    other = Fixtures.account!()

    {:ok, other_socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, other.id)})

    assert {:error, %{reason: "not witnessed"}} =
             subscribe_and_join(
               other_socket,
               OneiroiWeb.SessionChannel,
               "session:#{ctx.resident.id}:#{ctx.key}"
             )
  end
end
