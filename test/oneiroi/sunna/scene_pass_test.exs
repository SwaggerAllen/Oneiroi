defmodule Oneiroi.Sunna.ScenePassTest do
  @moduledoc """
  The bedtime scene pass (sunna#34): a housekeeping turn before the
  scene slot, on the chat line, free time following its end; and the
  floor under a slot the free-time line cannot pay for.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Schedules

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    test = self()

    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})
        {:ok, "Done for now."}
      end,
      for: resident.id
    )

    {:ok, id: resident.id, actor: actor}
  end

  defp setting(slug, key, value) do
    values = :persistent_term.get({Oneiroi.Config, :values})
    on_exit(fn -> :persistent_term.put({Oneiroi.Config, :values}, values) end)
    :persistent_term.put({Oneiroi.Config, :values}, Map.put(values, {slug, key}, value))
  end

  defp jobs(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.FreeTimeWorker", select: j.args)
      )
    end)
    |> Enum.filter(&(&1["resident_id"] == id))
  end

  defp kinds(id), do: Kumbukumbu.sessions({:resident, id}) |> Enum.map(& &1.kind)

  test "at the scene slot the tick asks for the pass, not free time", ctx do
    setting(:sunna, :scene_slot, "12:00")
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)

    assert [%{"turn" => "scene", "slot" => "12:00", "n" => 1}] = jobs(ctx.id)
    refute "free_time" in kinds(ctx.id)
  end

  test "the pass is a housekeeping turn on the day of her chat, and free time follows it", ctx do
    {:ok, _main} =
      Kumbukumbu.main_session(ctx.id, ctx.actor.id, ctx.actor)

    day = Schedules.local_day(Schedules.local_now(ctx.id))
    assert :ok = Schedules.scene_pass(ctx.id, day, "22:30", nil, 1)

    assert_received {:asked, first}
    note = List.last(first).content
    assert note =~ "This is housekeeping, not free time: the bedtime scene pass for #{day}"
    assert note =~ "scenes/#{day}.md"

    assert "housekeeping" in kinds(ctx.id)
    assert "free_time" in kinds(ctx.id)
  end

  test "a slot the free-time line cannot pay for rests and says so", ctx do
    :ok = Nisaba.set_budget(ctx.id, :free_time, 5_000_000_000, :day, ctx.actor)
    day = Schedules.local_day(Schedules.local_now(ctx.id))
    :ok = Schedules.run_free_time(ctx.id, day, "12:00", ctx.actor)

    # The line now has next to nothing left.
    [%{spent_nanos: spent}] =
      Enum.filter(Nisaba.budgets(ctx.id, :witness), &(&1.purpose == :free_time))

    :ok = Nisaba.set_budget(ctx.id, :free_time, spent + 1, :day, ctx.actor)
    flush()

    assert :ok = Schedules.run_free_time(ctx.id, day, "13:00", ctx.actor)
    refute_received {:asked, _}

    assert %{outcome: "rested: not enough left tonight" <> _} =
             Enum.find(Sunna.free_time_history(ctx.id, 5), &(&1.slot == "13:00"))
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
