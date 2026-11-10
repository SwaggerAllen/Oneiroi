defmodule OneiroiWeb.ResidentChannelTest do
  @moduledoc "Change notices (apsu#24): a witness joins their resident's channel and hears what changed, never the data."
  use OneiroiWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Notices
  alias Oneiroi.Fixtures
  alias Oneiroi.Sunna.Schedules
  alias OneiroiWeb.UserSocket

  setup do
    pid = Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, witness: witness, resident: resident, actor: Actor.new(:witness, witness.id)}
  end

  defp join_as(account_id, resident_id, params \\ %{}) do
    {:ok, socket} =
      connect(UserSocket, %{"token" => UserSocket.token(OneiroiWeb.Endpoint, account_id)})

    subscribe_and_join(socket, OneiroiWeb.ResidentChannel, "resident:#{resident_id}", params)
  end

  test "a witness joins with the head position and hears a projected change as a notice", ctx do
    assert {:ok, %{position: head}, _socket} = join_as(ctx.witness.id, ctx.resident.id)
    assert is_integer(head)

    :ok = Schedules.set_quiet_hours(ctx.resident.id, "23:00", "06:00", ctx.actor)

    assert_push "notice", %{stream: "schedule", kind: kind, position: position}, 5_000
    assert is_binary(kind)
    assert position > head
  end

  test "another account cannot join", ctx do
    other = Fixtures.account!()
    assert {:error, %{reason: "not witnessed"}} = join_as(other.id, ctx.resident.id)
  end

  test "a cursor replays what was missed, and only this resident's", ctx do
    {:ok, %{position: head}, _socket} = join_as(ctx.witness.id, ctx.resident.id)

    other = Fixtures.resident!(ctx.witness)
    :ok = Schedules.set_quiet_hours(other.id, "22:00", "07:00", ctx.actor)
    :ok = Schedules.set_quiet_hours(ctx.resident.id, "23:00", "06:00", ctx.actor)

    assert {:ok, %{position: _}, _socket} =
             join_as(ctx.witness.id, ctx.resident.id, %{"since" => head})

    assert_push "notices", %{notices: notices}, 5_000
    assert notices != []
    assert Enum.all?(notices, &(&1.position > head))
    assert Enum.any?(notices, &(&1.stream == "schedule"))

    assert {:ok, replayed} = Notices.since(other.id, head)
    assert Enum.any?(replayed, &(&1.stream == "schedule"))
  end

  test "owner/1 names a resident's stream and refuses the sealed and the platform's" do
    id = "6c2f8a50-1b2d-4e8f-9a0b-1c2d3e4f5a6b"
    assert {:ok, ^id, "memory"} = Notices.owner("memory-" <> id)
    assert {:ok, ^id, "conversation-main"} = Notices.owner("conversation-main-" <> id)
    assert :none = Notices.owner("regression-" <> id)
    assert :none = Notices.owner("platform")
  end
end
