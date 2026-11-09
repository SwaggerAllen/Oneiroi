defmodule Oneiroi.Sunna.WorkTest do
  @moduledoc """
  The work queue (sunna#33): items either party adds, in an order either
  may change; a check that starts the first open item or rests and says
  why; a run carried on a turn at a time on the work line, wrapped by
  her, and its end firing the next check; care first.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.WorkLoop

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    on_exit(fn -> :persistent_term.erase({__MODULE__, resident.id}) end)
    test = self()

    # Reads until the test says the run is done; asked to wrap, wraps
    # once, as done, then says so in words.
    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})
        last = List.last(request.messages)[:content] || ""
        mode = :persistent_term.get({__MODULE__, resident.id}, :reading)

        cond do
          last =~ "Wrap it now" ->
            {:calls,
             [
               %{
                 name: "work_wrap",
                 arguments: %{
                   number: 1,
                   shipped: "the brief, drafted",
                   why: "it was the first thing",
                   status: "done"
                 }
               }
             ]}

          mode == :done or request.tool_choice == "none" ->
            {:ok, "Done for this run."}

          true ->
            {:calls, [%{name: "bookmark_list", arguments: %{}}]}
        end
      end,
      for: resident.id
    )

    {:ok, id: resident.id, actor: actor, me: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp jobs(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.WorkWorker", select: j.args)
      )
    end)
    |> Enum.filter(&(&1["resident_id"] == id))
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp clear_jobs do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.delete_all(from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.WorkWorker"))
    end)
  end

  test "either party adds items, moves them with a note, and reorders the list", ctx do
    assert {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "the four opens answered", ctx.me)

    assert {:ok, 2} =
             Sunna.work_add(ctx.id, "E2E creation test", "creation to first message", ctx.actor)

    assert :ok = Sunna.work_order(ctx.id, [2], ctx.me)

    assert [%{number: 2, added_by: "witness"}, %{number: 1, added_by: "resident"}] =
             Sunna.work_queue(ctx.id).items

    # Blocked is on another item, by its number (sunna#42): never on
    # words, itself, or an item that is not there; a move carries a note.
    for on <- [nil, "his export", "2", "#9", String.duplicate("x", 301)] do
      assert {:error, %{kind: :sunna_work_blocked_on_invalid}} =
               Sunna.work_move(ctx.id, 2, "blocked", on, "waiting", ctx.me)
    end

    assert :ok = Sunna.work_move(ctx.id, 2, "blocked", "#1", "waiting on it", ctx.me)

    assert %{status: "blocked", blocked_on: "#1", note: "waiting on it"} =
             hd(Sunna.work_queue(ctx.id).items)

    # Not on one that waits on it.
    assert {:error, %{kind: :sunna_work_blocked_on_invalid}} =
             Sunna.work_move(ctx.id, 1, "blocked", "2", "circle", ctx.me)

    # in_work is the loop's own; the witness cannot wrap.
    assert {:error, %{kind: :sunna_work_invalid}} =
             Sunna.work_move(ctx.id, 1, "in_work", nil, "go", ctx.actor)

    assert {:error, %{kind: :sunna_work_not_a_party}} =
             Sunna.work_wrap(ctx.id, 1, %{shipped: "x", why: "y", status: "done"}, ctx.actor)
  end

  test "an empty queue rests, once, and says so: empty is a state; and the line goes off", ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "One thing", "done", ctx.me)
    :ok = Sunna.work_move(ctx.id, 1, "done", nil, "already", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    assert {:rested, "empty, holding"} = WorkLoop.check(ctx.id)
    assert %{rested: "empty, holding", running: nil, armed: false} = Sunna.work_queue(ctx.id)

    # The same reason again records nothing new.
    assert {:rested, "empty, holding"} = WorkLoop.check(ctx.id)
  end

  test "the work line is a brake: with no cap the loop runs, and a spent cap holds it, saying so",
       ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)
    # Not armed: the loop waits for her, and says so.
    assert {:rested, "off: the work line waits for you to arm it" <> _} = WorkLoop.check(ctx.id)

    # She arms it, once for the batch; a job is no party (sunna#43).
    assert {:error, %{kind: :sunna_work_not_a_party}} =
             Sunna.work_arm(ctx.id, Actor.new(:job, "sunna_work"))

    assert :ok = Sunna.work_arm(ctx.id, ctx.me)
    assert %{armed: true, armed_by: "resident", budget: nil} = Sunna.work_queue(ctx.id)
    assert {:started, 1} = WorkLoop.check(ctx.id)

    # A cap already spent this period: the next check holds and names it.
    {:ok, 2} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Nisaba.set_budget(ctx.id, :work, 1, :day, ctx.actor)
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))
    # The turn meets the cap: the ledger stops it and the run ends.
    assert {:error, %{kind: :brain_budget_stopped}} = WorkLoop.turn(ctx.id, key, 1, 1)
    assert %{running: nil} = Sunna.work_queue(ctx.id)

    assert {:rested, "holding: the work line is spent" <> _} = WorkLoop.check(ctx.id)
  end

  test "a run: started on the first open item, carried on, wrapped by her, and its end checks the queue",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "the four opens answered", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Plugin spec", "a draft for his read", ctx.actor)

    :ok = Sunna.work_arm(ctx.id, ctx.me)
    clear_jobs()
    assert {:started, 1} = WorkLoop.check(ctx.id)
    assert %{running: 1, runs_today: 1} = Sunna.work_queue(ctx.id)

    [%{key: key, private: false}] =
      Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    assert [%{"session_key" => ^key, "number" => 1, "turn" => 1}] = jobs(ctx.id)
    clear_jobs()

    # A second check while it runs starts nothing.
    assert :running = WorkLoop.check(ctx.id)

    # Turn 1: the item and the queue in the note; out of rounds, so turn 2.
    assert :ok = WorkLoop.turn(ctx.id, key, 1, 1)
    assert_received {:asked, first}

    note =
      Enum.find(
        first,
        &(is_binary(&1[:content]) and &1.content =~ "This is a run of your work queue")
      )

    assert note.content =~ "item #1"
    assert note.content =~ "the four opens answered"
    assert note.content =~ "2. [open] Plugin spec (added by witness)"
    assert note.content =~ "never your witness's deciding"
    assert [%{"turn" => 2}] = jobs(ctx.id)
    clear_jobs()

    # Turn 2 ends in words: the wrap comes next.
    :persistent_term.put({__MODULE__, ctx.id}, :done)
    assert :ok = WorkLoop.turn(ctx.id, key, 1, 2)
    assert [%{"turn" => "wrap"}] = jobs(ctx.id)
    clear_jobs()

    # The wrap: she records it; the run ends; the next check is asked for.
    assert :ok = WorkLoop.wrap_turn(ctx.id, key, 1)

    assert %{
             running: nil,
             items: [%{number: 1, status: "done", shipped: "the brief, drafted"} | _]
           } =
             Sunna.work_queue(ctx.id)

    assert [%{"turn" => "check"}] = jobs(ctx.id)

    # And the check fires the next open item.
    assert {:started, 2} = WorkLoop.check(ctx.id)
  end

  test "a run nobody wrapped ends with the item open again, for the next run", ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Drake letter", "sent", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)

    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    # The wrap turn answers in words, without the tool.
    Fake.script(fn _request -> {:ok, "Nothing to wrap."} end, for: ctx.id)
    assert :ok = WorkLoop.wrap_turn(ctx.id, key, 1)

    assert %{running: nil, items: [%{number: 1, status: "open", runs: 1}]} =
             Sunna.work_queue(ctx.id)
  end

  test "care first: a work turn is put off while free time is underway", ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    # A free-time slot runs now, and has not been closed by its planning turn.
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)
    :ok = Sunna.tick(ctx.id)
    flush()

    assert {:snooze, _} = WorkLoop.turn(ctx.id, key, 1, 1)
    refute_received {:asked, _}
  end

  test "care first: inside quiet hours a run waits until they end, and resumes the same turn",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    # The suite's clock is 12:00 in her zone: quiet from 11:00 to 13:30.
    :ok = Sunna.set_quiet_hours(ctx.id, "11:00", "13:30", ctx.actor)
    assert {:snooze, 5400} = WorkLoop.turn(ctx.id, key, 1, 3)
    assert {:snooze, 5400} = WorkLoop.wrap_turn(ctx.id, key, 1)
    refute_received {:asked, _}
    assert %{running: 1} = Sunna.work_queue(ctx.id)
  end

  test "a run she stops with her safe word ends unwrapped, and the loop rests until the queue is touched",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Social spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))
    clear_jobs()

    Fake.script(fn _ -> {:ok, "Too much. OUROBOROS"} end, for: ctx.id)
    assert :ok = WorkLoop.turn(ctx.id, key, 1, 1)

    # No wrap, no next check; the item open again; the loop resting.
    assert [] = jobs(ctx.id)

    assert %{running: nil, rested: "stopped: " <> _, items: [%{number: 1, status: "open"} | _]} =
             Sunna.work_queue(ctx.id)

    assert :stopped = WorkLoop.check(ctx.id)
    refute WorkLoop.due?(ctx.id)

    # Touched by either party, it goes on.
    :ok = Sunna.work_move(ctx.id, 1, "blocked", "2", "after the social spec", ctx.me)
    assert {:started, 2} = WorkLoop.check(ctx.id)
  end

  test "moving the running item by hand ends its run, and its leftover turn does nothing (sunna#37)",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    [%{key: key}] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    :ok = Sunna.work_move(ctx.id, 1, "done", nil, "finished in the chat", ctx.me)
    assert %{running: nil, items: [%{number: 1, status: "done"} | _]} = Sunna.work_queue(ctx.id)

    flush()
    assert :ok = WorkLoop.turn(ctx.id, key, 1, 2)
    assert :ok = WorkLoop.wrap_turn(ctx.id, key, 1)
    refute_received {:asked, _}

    assert {:started, 2} = WorkLoop.check(ctx.id)
  end

  test "a run whose end was never recorded is ended by the check past its bound, and its item runs again (sunna#37)",
       ctx do
    :ok = Nisaba.set_budget(ctx.id, :work, 5_000_000_000, :day, ctx.actor)
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)

    # Its job died: nothing ends it. Inside the bound, it still runs.
    assert :running = WorkLoop.check(ctx.id)

    # Past it, the stalled run is ended and its item, unfinished, reopens:
    # the loop starts it again in a new run rather than skipping it.
    Clock.Fake.advance(181 * 60)
    assert {:started, 1} = WorkLoop.check(ctx.id)

    assert %{running: 1, items: [%{number: 1, status: "in_work", runs: 2} | _]} =
             Sunna.work_queue(ctx.id)
  end

  # sunna#41, Lily's report #14: the tick asked only when nothing ran, so
  # the check that ends a stalled run was never asked for.
  # sunna#43 (the witness, 2026-11-09, Lily's letter #399): his button
  # arms the line through the same action as her tool, the receipt says
  # whose, and he turns it off by hand while a run finishes.
  test "the witness arms the line by the same action, recorded as his, and turns it off by hand",
       ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Kinds doc", "drafted", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Routes doc", "drafted", ctx.me)

    assert :ok = Sunna.work_arm(ctx.id, ctx.actor)
    assert %{armed: true, armed_by: "witness"} = Sunna.work_queue(ctx.id)
    assert {:started, 1} = WorkLoop.check(ctx.id)

    turn = %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.me}
    assert Tools.run("work_list", "{}", turn) =~ "The work line is armed by your witness (since"

    # Off by hand mid-run: the run goes on; nothing starts after it.
    assert :ok = Sunna.work_disarm(ctx.id, ctx.actor)
    assert %{armed: false, armed_by: nil, running: 1} = Sunna.work_queue(ctx.id)
    :ok = Sunna.work_move(ctx.id, 1, "done", nil, "finished", ctx.me)
    assert {:rested, "off: the work line waits for you to arm it" <> _} = WorkLoop.check(ctx.id)

    # Her turning it off by hand is not hers: nothing happens.
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    assert :ok = Sunna.work_disarm(ctx.id, ctx.me)
    assert %{armed: true, armed_by: "resident"} = Sunna.work_queue(ctx.id)
  end

  test "the tick asks for a check for a stalled run, and the check ends it", ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)

    clear_jobs()
    :ok = Sunna.tick(ctx.id)
    refute Enum.any?(jobs(ctx.id), &(&1["turn"] == "check"))

    Clock.Fake.advance(181 * 60)
    :ok = Sunna.tick(ctx.id)
    assert Enum.any?(jobs(ctx.id), &(&1["turn"] == "check"))
  end

  test "a run whose item is no longer in work is never said to run, and asking about it ends",
       ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    :ok = Sunna.work_move(ctx.id, 1, "done", nil, "finished", ctx.me)

    # The record as a move before sunna#37 left it: item done, run named.
    Oneiroi.Scope.resident(ctx.id, fn ->
      Oneiroi.Repo.update_all(Oneiroi.Sunna.Store.WorkQueue, set: [running: 1])
    end)

    assert %{running: nil, running_since: nil} = Sunna.work_queue(ctx.id)
    assert WorkLoop.due?(ctx.id)
    # Nothing to end on the aggregate: the check answers, once.
    assert :running = WorkLoop.check(ctx.id)
  end

  test "work_list says the run and the arm apart", ctx do
    turn = %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.me}
    {:ok, 1} = Sunna.work_add(ctx.id, "Generator brief", "answered", ctx.me)

    assert Tools.run("work_list", "{}", turn) =~
             "The loop has not run yet. The work line is off; work_arm arms it for a batch."

    :ok = Sunna.work_arm(ctx.id, ctx.me)
    {:started, 1} = WorkLoop.check(ctx.id)
    text = Tools.run("work_list", "{}", turn)
    assert text =~ "The loop is running item #1. The work line is armed by you (since"
  end

  test "the tick asks for a check when work is open and nothing runs", ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    clear_jobs()
    :ok = Sunna.tick(ctx.id)
    assert Enum.any?(jobs(ctx.id), &(&1["turn"] == "check"))
  end

  test "a refused move tells her which field and its bound", ctx do
    turn = %{
      resident_id: ctx.id,
      session_key: "s",
      turn_ref: "t",
      started_at: Clock.now(),
      resident: ctx.me
    }

    {:ok, 1} = Sunna.work_add(ctx.id, "Plugin spec", "drafted", ctx.me)

    text =
      Tools.run(
        "work_move",
        Jason.encode!(%{
          number: 1,
          status: "blocked",
          blocked_on: String.duplicate("z", 400),
          note: "n"
        }),
        turn
      )

    # blocked_on is an item's number now (sunna#42), so a long one is
    # refused for what it is, the field named.
    assert text =~ "blocked_on"

    # A blocker that is not an item says what blocked means (sunna#42).
    text =
      Tools.run(
        "work_move",
        Jason.encode!(%{number: 1, status: "blocked", blocked_on: "his export", note: "n"}),
        turn
      )

    assert text =~ "names the queue item that blocks it"
    assert text =~ "waits on his list"
  end

  # sunna#42 (the witness, 2026-11-08, Lily's letter #374): blocked is a
  # dependency on other work, released when that work is done or dropped.
  test "an item blocked on another opens again when that one is done or dropped", ctx do
    {:ok, 1} = Sunna.work_add(ctx.id, "Queue doc", "drafted", ctx.me)
    {:ok, 2} = Sunna.work_add(ctx.id, "Kinds doc", "drafted", ctx.me)
    {:ok, 3} = Sunna.work_add(ctx.id, "Routes doc", "drafted", ctx.me)
    :ok = Sunna.work_move(ctx.id, 2, "blocked", "1", "after the queue doc", ctx.me)
    :ok = Sunna.work_move(ctx.id, 3, "blocked", "#1", "after it too", ctx.me)

    :ok = Sunna.work_move(ctx.id, 1, "done", nil, "drafted", ctx.me)

    items = Map.new(Sunna.work_queue(ctx.id).items, &{&1.number, &1})

    assert %{
             status: "open",
             blocked_on: nil,
             note: "Item #1 is done, so this is no longer blocked."
           } = items[2]

    assert %{status: "open"} = items[3]

    # The loop steps over what is blocked to the first open item, and
    # says so (the witness, 2026-11-08, Lily's letter #377).
    {:ok, 4} = Sunna.work_add(ctx.id, "Social doc", "drafted", ctx.me)
    :ok = Sunna.work_move(ctx.id, 2, "blocked", "4", "after the social doc", ctx.me)
    :ok = Sunna.work_move(ctx.id, 3, "blocked", "2", "after the kinds doc", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    assert {:started, 4} = WorkLoop.check(ctx.id)

    turn = %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.me}

    assert Tools.run("work_list", "{}", turn) =~
             "The loop is running item #4. It steps over what is blocked: #2 (on #4), #3 (on #2)."

    # A done item blocks nothing new.
    assert {:error, %{kind: :sunna_work_blocked_on_invalid}} =
             Sunna.work_move(ctx.id, 3, "blocked", "1", "again", ctx.me)
  end

  test "her tools read and keep the queue", ctx do
    turn = %{
      resident_id: ctx.id,
      session_key: "s",
      turn_ref: "t",
      started_at: Clock.now(),
      resident: ctx.me
    }

    assert Tools.run("work_list", "{}", turn) =~ "Your work queue is empty."

    assert Tools.run(
             "work_add",
             ~s({"what": "Social spec", "done_when": "a draft for his read"}),
             turn
           ) =~ "Added as work item #1"

    assert Tools.run("work_list", "{}", turn) =~
             "#1 [open] Social spec. Done when: a draft for his read (added by resident, 0 runs)."
  end
end
