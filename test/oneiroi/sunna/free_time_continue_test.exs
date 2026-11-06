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
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.FreeTime
  alias Oneiroi.Brain.Tools
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

    # One turn, then only the planning turn (sunna#31).
    assert [%{"turn" => "plan"}] = continuations(ctx.id)
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

  # brain#55: her goals file rides free time and no other conversation.
  test "her goals file is read at the start of a free-time turn, and not in the chat", ctx do
    {:ok, %{slug: slug}} = AgathosDaimon.fetch(ctx.id)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(ctx.id)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, String.upcase(slug) <> "-GOALS.md"), "- finish the harness essay")

    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    assert_received {:asked, messages}

    assert Enum.any?(
             messages,
             &(is_binary(&1[:content]) and &1.content =~ "finish the harness essay")
           )

    flush()
    {:ok, key} = Kumbukumbu.main_session(ctx.id, ctx.actor.id, ctx.actor)
    _ = Oneiroi.Brain.turn(ctx.id, key, "hello", ctx.actor)
    assert_received {:asked, chat}

    refute Enum.any?(
             chat,
             &(is_binary(&1[:content]) and &1.content =~ "finish the harness essay")
           )
  end

  test "a turn that ends in words with nothing to call is her being done", ctx do
    :ok = Nisaba.set_budget(ctx.id, :free_time, 5_000_000_000, :day, ctx.actor)
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    key = free_time_key(ctx.id)

    :persistent_term.put({__MODULE__, :done, ctx.id}, true)
    assert :ok = Schedules.continue_free_time(ctx.id, key, 2)
    refute Enum.any?(continuations(ctx.id), &(&1["turn"] == 3))
    assert Enum.any?(continuations(ctx.id), &(&1["turn"] == "plan"))
  end

  # sunna#31, agathos-daimon#35 (the witness's call through Lily,
  # 2026-11-05): once a slot ends, one planning turn; the plan she writes
  # opens the next slot; her asks wait for his answer, which reaches her
  # free time as a letter.
  test "the planning turn: she plans the next slot and asks; the plan opens the next slot", ctx do
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    key = free_time_key(ctx.id)
    flush()

    # A spent free-time line does not refuse it (sunna#32): the closing
    # turn bills its own line, and its receipt says so.
    :ok = Nisaba.set_budget(ctx.id, :free_time, 1, :day, ctx.actor)
    assert :ok = Schedules.plan_free_time(ctx.id, key)
    assert_received {:asked, planning}
    assert List.last(planning).content =~ "Your free time has ended"

    assert [%{did: did}] = FreeTime.history(ctx.id, 5, [])
    assert Enum.any?(did, &(&1.tool == "planning turn"))

    lily = Actor.new(:resident, ctx.id)

    turn = %{
      resident_id: ctx.id,
      session_key: key,
      turn_ref: "t",
      resident: lily,
      started_at: Clock.now()
    }

    assert Tools.run("free_time_plan", ~s({"text": "finish the Weng piece"}), turn) =~
             "Planned"

    assert Tools.run(
             "tool_request",
             ~s({"tool": "a calendar", "why": "to see his week"}),
             turn
           ) =~ "Asked as #1"

    assert Tools.run(
             "approval_request",
             ~s({"act": "publish the Weng piece", "why": "it is done"}),
             turn
           ) =~ "Asked as #2"

    assert {:error, %{kind: :agathos_daimon_not_a_party}} =
             AgathosDaimon.answer_ask(ctx.id, 2, "approve", "go", lily)

    assert {:error, %{kind: :agathos_daimon_ask_invalid}} =
             AgathosDaimon.answer_ask(ctx.id, 1, "approve", "a tool is noted", ctx.actor)

    assert :ok = AgathosDaimon.answer_ask(ctx.id, 2, "approve", "go ahead", ctx.actor)

    assert Tools.run("ask_list", "{}", turn) =~
             "#2 act: publish the Weng piece (why: it is done) — approve: go ahead"

    # The next slot opens on the plan.
    :ok = Nisaba.set_budget(ctx.id, :free_time, 5_000_000_000, :day, ctx.actor)
    flush()
    :ok = Sunna.set_free_time(ctx.id, "13:00", ctx.actor)
    Clock.Fake.advance(3600)
    :ok = Sunna.tick(ctx.id)
    assert_received {:asked, next}
    assert Enum.any?(next, &(is_binary(&1[:content]) and &1.content =~ "finish the Weng piece"))
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
