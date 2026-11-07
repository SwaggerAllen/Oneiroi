defmodule Oneiroi.Gaia.BootsTest do
  @moduledoc """
  The platform's boots (gaia#21) and the notice every conversation gets
  of them (brain#63): any restart, same commit or changed, told once.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia.Boots
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, key: key, actor: actor}
  end

  defp tick(seconds), do: Clock.Fake.advance(seconds)

  test "each boot is recorded with the commit before and whether it changed" do
    # A stream of its own: the event store outlives the test.
    Process.put(Oneiroi.Gaia.Door, "boots-test-" <> Kumbukumbu.turn_ref())
    :ok = Boots.record("aaaaaaa1")
    :ok = Boots.record("aaaaaaa1")
    :ok = Boots.record("bbbbbbb2")

    assert [third, second, first] = Boots.latest(5)
    assert %{number: 1, commit: "aaaaaaa1", previous: nil, changed: false} = first
    assert %{number: 2, previous: "aaaaaaa1", changed: false} = second
    assert %{number: 3, previous: "aaaaaaa1", commit: "bbbbbbb2", changed: true} = third

    assert Boots.line(second, "x") == "The platform restarted at x, same commit (aaaaaaa)."
    assert Boots.line(third, "x") =~ "commit aaaaaaa → bbbbbbb, changed. The diff: "
    assert Boots.line(third, "x") =~ "/compare/aaaaaaa1...bbbbbbb2"
  end

  test "a conversation is told of the restarts since it last spoke, once", ctx do
    test = self()

    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})
        {:ok, "noted"}
      end,
      for: ctx.id
    )

    {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "before", ctx.actor)

    # The turn's process keeps the suite's fixed instant, so the boot is
    # placed after it, from here.
    tick(60)
    :ok = Boots.record("ccccccc3")

    {:ok, %{messages: messages}} = Oneiroi.Brain.turn(ctx.id, ctx.key, "after", ctx.actor)

    assert Enum.any?(
             messages,
             &(&1.role == :system and &1.content =~ "Since this conversation last spoke" and
                 &1.content =~ "ccccccc")
           )

    # Once the conversation has spoken after the boot, it is not told again.
    tick(60)

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        Kumbukumbu.turn_ref(),
        Clock.now(),
        [
          %{role: :user, content: "later", sent_at: Clock.now(), actor: ctx.actor}
        ],
        ctx.actor
      )

    {:ok, %{messages: again}} = Oneiroi.Brain.turn(ctx.id, ctx.key, "and again", ctx.actor)

    refute Enum.any?(
             again,
             &(&1.role == :system and &1.content =~ "Since this conversation last spoke")
           )
  end
end
