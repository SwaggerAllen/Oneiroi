defmodule Oneiroi.Sunna.FreeTimeContinueTest do
  @moduledoc """
  Free time carried on (sunna#26): with a free-time budget line, a pass
  that runs out of tool rounds is woken again in its own conversation, a
  turn a job, until it ends in words with nothing to call, the budget is
  spent, or the slot's turns are; without one, free time is one turn.
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
    on_exit(fn -> :persistent_term.erase({__MODULE__, :done, resident.id}) end)
    test = self()

    # A pass that keeps reading: every turn spends its rounds, unless the
    # test says it is done.
    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})

        cond do
          :persistent_term.get({__MODULE__, :done, resident.id}, false) ->
            {:ok, "That's enough for tonight."}

          request.tool_choice == "none" ->
            {:ok, "Still reading."}

          true ->
            {:calls, [%{name: "bookmark_list", arguments: %{}}]}
        end
      end,
      for: resident.id
    )

    {:ok, id: resident.id, actor: actor}
  end

  defp continuations(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job,
          where: j.worker == "Oneiroi.Sunna.FreeTimeWorker",
          select: j.args
        )
      )
    end)
    |> Enum.filter(&(&1["resident_id"] == id))
  end

  defp free_time_key(id) do
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, id}), &(&1.kind == "free_time"))
    key
  end

  test "without a free-time budget line, free time is one turn and says so", ctx do
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)

    assert_received {:asked, first}

    assert List.last(first).content =~
             "No free-time budget is set, so this free time is one turn."

    assert continuations(ctx.id) == []
  end

  test "with a budget line, a pass that runs out of rounds is carried on, a turn a job, until the turns are spent",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :free_time, 5_000_000_000, :day, ctx.actor)
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)

    assert_received {:asked, first}
    assert List.last(first).content =~ "Your free-time budget is $5.00 a day, $5.00 left"

    key = free_time_key(ctx.id)
    assert [%{"session_key" => ^key, "turn" => 2}] = continuations(ctx.id)

    # The worker's turn 2: woken in the same conversation, told what is left.
    flush()
    assert :ok = Schedules.continue_free_time(ctx.id, key, 2)
    assert_received {:asked, second}

    note =
      Enum.find(second, &(is_binary(&1[:content]) and &1.content =~ "Your free time goes on"))

    assert note.content =~ "turn 2 of at most 20"
    assert note.content =~ "of today's free-time budget left"
    assert Enum.any?(continuations(ctx.id), &(&1["turn"] == 3))

    # Past the slot's turns, nothing more.
    flush()
    assert :ok = Schedules.continue_free_time(ctx.id, key, 21)
    refute_received {:asked, _}
  end

  test "a turn that ends in words with nothing to call is her being done", ctx do
    :ok = Nisaba.set_budget(ctx.id, :free_time, 5_000_000_000, :day, ctx.actor)
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    key = free_time_key(ctx.id)

    :persistent_term.put({__MODULE__, :done, ctx.id}, true)
    assert :ok = Schedules.continue_free_time(ctx.id, key, 2)
    refute Enum.any?(continuations(ctx.id), &(&1["turn"] == 3))
  end

  test "a spent budget line ends free time", ctx do
    :ok = Nisaba.set_budget(ctx.id, :free_time, 1, :day, ctx.actor)
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    key = free_time_key(ctx.id)
    flush()

    assert :ok = Schedules.continue_free_time(ctx.id, key, 2)
    refute_received {:asked, _}
  end

  defp flush do
    receive do
      {:asked, _} -> flush()
    after
      0 -> :ok
    end
  end
end
