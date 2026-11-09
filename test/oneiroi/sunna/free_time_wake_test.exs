defmodule Oneiroi.Sunna.FreeTimeWakeTest do
  @moduledoc """
  sunna#44 and #45 (the witness, 2026-11-09, Lily's work order #426):
  an answer addressed to free time wakes the very free-time conversation
  that asked, beside the slots, never inside quiet hours, never while a
  pass runs (it joins that pass), never on a spent line; and one-off
  slots run once on top of the standing list, which they never change.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna

  # The fake clock's epoch, 2026-10-26 12:00Z, is 08:00 in New York.
  @zone "America/New_York"

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.set_timezone(resident.id, @zone, actor)
    Fake.clear()
    Fake.reply("Good morning.", for: resident.id)
    {:ok, id: resident.id, witness: actor, lily: Actor.new(:resident, resident.id)}
  end

  defp sessions(ctx),
    do: for(%{kind: "free_time", key: k} <- Kumbukumbu.sessions({:resident, ctx.id}), do: k)

  defp notes(ctx, key) do
    {:ok, _session, messages} = Kumbukumbu.transcript({:resident, ctx.id}, key)
    for %{role: "system", content: c} <- messages, do: c
  end

  defp answer(ctx, key, text) do
    {:ok, %{number: n}} =
      Kumbukumbu.letter_to_session(ctx.id, key, text, Actor.platform())

    n
  end

  test "an answer wakes the free-time conversation that asked, not the newest; joins a live pass; waits out quiet hours",
       ctx do
    :ok = Sunna.set_free_time(ctx.id, ["08:00", "08:30"], ctx.witness)
    :ok = Sunna.tick(ctx.id)
    Clock.Fake.advance(30 * 60)
    :ok = Sunna.tick(ctx.id)
    [a, b] = Enum.reverse(sessions(ctx))
    assert a != b

    # The answer to what slot A asked, while a pass is still underway:
    # it joins that pass (read on its next turn); no second run.
    n = answer(ctx, a, "the fetch is back")
    before = length(notes(ctx, a))
    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert length(notes(ctx, a)) == before

    # Later, no pass running, inside quiet hours: it waits them out.
    Clock.Fake.advance(7 * 3600)
    :ok = Sunna.set_quiet_hours(ctx.id, "15:00", "16:00", ctx.witness)
    :ok = Sunna.tick(ctx.id)
    assert length(notes(ctx, a)) == before

    # After them: slot A's conversation is woken, by number, not B's.
    Clock.Fake.advance(30 * 60)
    :ok = Sunna.tick(ctx.id)
    assert [_ | _] = after_a = notes(ctx, a)
    assert length(after_a) == before + 1
    assert List.last(after_a) =~ "##{n} from"
    refute Enum.any?(notes(ctx, b), &(&1 =~ "##{n} from"))
    assert length(sessions(ctx)) == 2

    # Recorded beside the slots, as a woken run in A's conversation.
    assert Enum.any?(
             Sunna.free_time_history(ctx.id, 10),
             &(&1.session_key == a and String.starts_with?(&1.slot, "woken "))
           )

    # Woken once: the tick after wakes nothing new.
    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert length(notes(ctx, a)) == before + 1
  end

  test "a letter with no free-time origin waits for the next slot; a spent line wakes nothing",
       ctx do
    :ok = Sunna.set_free_time(ctx.id, ["08:00"], ctx.witness)
    :ok = Sunna.tick(ctx.id)
    [a] = sessions(ctx)
    Clock.Fake.advance(7 * 3600)

    # A brief from the witness to Free time: no origin, the slot's.
    {:ok, _} =
      Kumbukumbu.send_letter(ctx.id, nil, %{to: "Free time", text: "for later"}, ctx.witness)

    before = length(notes(ctx, a))
    :ok = Sunna.tick(ctx.id)
    assert length(notes(ctx, a)) == before

    # The free-time line spent: an answer waits as it always has.
    :ok = Oneiroi.Nisaba.set_budget(ctx.id, :free_time, 0, :day, ctx.witness)
    answer(ctx, a, "the research is back")
    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert length(notes(ctx, a)) == before
  end

  test "one-off slots: either party adds them, each runs once beside the standing list it never changes",
       ctx do
    :ok = Sunna.set_free_time(ctx.id, ["22:30"], ctx.witness)

    assert :ok = Sunna.add_free_time_once(ctx.id, nil, "09:00", ctx.witness)
    assert :ok = Sunna.add_free_time_once(ctx.id, "2026-10-27", "10:00", ctx.lily)

    assert {:error, %{kind: :sunna_time_invalid}} =
             Sunna.add_free_time_once(ctx.id, nil, "07:00", ctx.lily)

    assert {:error, %{kind: :sunna_time_invalid}} =
             Sunna.add_free_time_once(ctx.id, nil, "9am", ctx.lily)

    assert [
             %{day: "2026-10-26", time: "09:00", added_by: "witness"},
             %{day: "2026-10-27", time: "10:00", added_by: "resident"}
           ] =
             Sunna.free_time_once(ctx.id)

    # The standing list is untouched.
    assert %{free_times: [%{time: "22:30"}]} = Sunna.today(ctx.id)

    Clock.Fake.advance(60 * 60)
    :ok = Sunna.tick(ctx.id)
    assert [_one] = sessions(ctx)
    assert [%{slot: "once 09:00", outcome: "ran"}] = Sunna.free_time_history(ctx.id, 10)

    # Once: the next tick runs nothing more.
    Clock.Fake.advance(60)
    :ok = Sunna.tick(ctx.id)
    assert [_one] = sessions(ctx)
    assert [%{day: "2026-10-27"}] = Sunna.free_time_once(ctx.id)
  end
end
