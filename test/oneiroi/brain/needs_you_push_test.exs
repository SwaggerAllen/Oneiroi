defmodule Oneiroi.Brain.NeedsYouPushTest do
  @moduledoc """
  brain#77, gaia#26: a content-free push when a needs-you entry first
  appears for the witness, once per entry ever, never inside her quiet
  hours (pushed at their end instead), and nothing recorded when no
  device could hear it.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYouPushWorker
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Account
  alias Oneiroi.Gaia.Events.NeedsYouPushed
  alias Oneiroi.Gaia.Push.Fake
  alias Oneiroi.Sunna

  @apple "https://web.push.apple.com/QGuQyavXutnMjhCkC"

  setup do
    Fake.clear()
    on_exit(&Fake.clear/0)
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    {:ok,
     id: resident.id,
     account: account.id,
     me: Actor.new(:witness, account.id),
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp eventually(read, tries \\ 50) do
    case read.() do
      [] when tries > 0 ->
        Process.sleep(20)
        eventually(read, tries - 1)

      value ->
        value
    end
  end

  defp hhmm(%DateTime{} = t),
    do: t |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)

  test "no device, nothing recorded; then one push per entry, ever", ctx do
    {:ok, 1} = AgathosDaimon.ask(ctx.id, "act", "Post the essay", "It is done.", ctx.lily)

    # No device: nothing sent, nothing marked told.
    assert {:ok, []} = NeedsYouPushWorker.push(ctx.id, ctx.account)

    :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.me)

    assert {:ok, [%{"kind" => "ask", "ref" => "1"}]} =
             NeedsYouPushWorker.push(ctx.id, ctx.account)

    assert eventually(&Fake.sent/0) == [@apple]

    # The same entry is never pushed again, by this run or the cron's.
    assert {:ok, []} = NeedsYouPushWorker.push(ctx.id, ctx.account)
    assert :ok = NeedsYouPushWorker.run(%{})
    Process.sleep(100)
    assert Fake.sent() == [@apple]

    # A new entry is: one push, for it alone.
    {:ok, 2} = AgathosDaimon.ask(ctx.id, "act", "And the next", "Ready.", ctx.lily)

    assert {:ok, [%{"kind" => "ask", "ref" => "2"}]} =
             NeedsYouPushWorker.push(ctx.id, ctx.account)

    assert eventually(fn -> if length(Fake.sent()) == 2, do: Fake.sent(), else: [] end) ==
             [@apple, @apple]
  end

  test "inside her quiet hours nothing is pushed or recorded; at their end it is, once", ctx do
    :ok = Gaia.subscribe_push(ctx.account, @apple, ctx.me)
    now = Clock.now()
    :ok = Sunna.set_quiet_hours(ctx.id, hhmm(now), hhmm(DateTime.add(now, 2, :hour)), ctx.me)
    {:ok, 1} = AgathosDaimon.ask(ctx.id, "act", "Post the essay", "It is done.", ctx.lily)

    assert Sunna.quiet_now?(ctx.id)
    assert {:ok, []} = NeedsYouPushWorker.push(ctx.id, ctx.account)
    Process.sleep(50)
    assert Fake.sent() == []

    Clock.Fake.advance(2 * 3600 + 60)
    refute Sunna.quiet_now?(ctx.id)
    assert {:ok, [%{"kind" => "ask"}]} = NeedsYouPushWorker.push(ctx.id, ctx.account)
    assert eventually(&Fake.sent/0) == [@apple]
  end

  test "an account rebuilt from its stream reads a pushed entry's keys either way (gaia#26)" do
    # Recorded with string keys; read back from the store with atom keys.
    # A rebuild that met the second crashed every command on the account,
    # sign-in included (2026-11-11).
    account = %Account{id: "a", pushed: MapSet.new()}

    for entries <- [
          [%{"kind" => "piece_to_review", "ref" => "design/key-recovery.md"}],
          [%{kind: "piece_to_review", ref: "design/key-recovery.md"}]
        ] do
      event = %NeedsYouPushed{
        actor: Actor.platform(),
        at: Clock.now(),
        id: "a",
        resident_id: "r",
        entries: entries
      }

      rebuilt = Account.apply(account, event)
      assert MapSet.member?(rebuilt.pushed, {"r", "piece_to_review", "design/key-recovery.md"})
    end
  end
end
