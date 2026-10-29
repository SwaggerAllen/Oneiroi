defmodule OneiroiWeb.SessionChannelTest do
  @moduledoc "The streamed conversation: a steward joins their resident's session, sends, and gets deltas then the turn."
  use OneiroiWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias OneiroiWeb.UserSocket

  setup do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", Actor.new(:steward, steward.id))

    {:ok, key} =
      Oneiroi.Kumbukumbu.main_session(resident.id, steward.id, Actor.new(:steward, steward.id))

    Fake.clear()
    {:ok, steward: steward, resident: resident, key: key}
  end

  test "a socket token or an API token connects; a stranger's token does not", ctx do
    token = UserSocket.token(OneiroiWeb.Endpoint, ctx.steward.id)
    assert {:ok, socket} = connect(UserSocket, %{"token" => token})
    assert socket.assigns.principal.account_id == ctx.steward.id

    {:ok, raw, _hash} =
      Oneiroi.Gaia.issue_token(ctx.steward.id, "script", Actor.new(:steward, ctx.steward.id))

    assert {:ok, _socket} = connect(UserSocket, %{"token" => raw})

    assert :error = connect(UserSocket, %{"token" => "nonsense"})
    assert :error = connect(UserSocket, %{})
  end

  test "a steward joins their resident's session and a turn streams, and another account cannot join",
       ctx do
    {:ok, socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, ctx.steward.id)})

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

    assert {:error, %{reason: "not stewarded"}} =
             subscribe_and_join(
               other_socket,
               OneiroiWeb.SessionChannel,
               "session:#{ctx.resident.id}:#{ctx.key}"
             )
  end
end
