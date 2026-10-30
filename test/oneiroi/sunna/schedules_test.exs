defmodule Oneiroi.Sunna.SchedulesTest do
  @moduledoc "The schedule through its exports and the tick, in the resident's zone: firing, missing, deferring, free time, dates, the wake into the brain."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.TickWorker

  @since ~U[2026-10-01 00:00:00.000000Z]
  # The fake clock's epoch, 2026-10-26 12:00Z, is 08:00 in New York that day.
  @zone "America/New_York"

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.set_timezone(resident.id, @zone, actor)
    Fake.clear()
    Fake.reply("Good morning.", for: resident.id)
    {:ok, witness: witness, id: resident.id, actor: actor}
  end

  defp transcript(ctx, key) do
    {:ok, _session, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, key)
    messages
  end

  test "a check-in fires once inside its window, opens the day, and wakes the main session with the core's note",
       ctx do
    {:ok, key} = Sunna.set_checkin(ctx.id, nil, "morning", "08:05", ctx.actor)
    assert :ok = Sunna.tick(ctx.id)

    assert %{firings: [], next: %{label: "morning", time: "08:05", tomorrow: false}} =
             Sunna.today(ctx.id)

    assert [] = Kumbukumbu.sessions({:resident, ctx.id})

    Clock.Fake.advance(5 * 60)
    assert :ok = Sunna.tick(ctx.id)

    assert %{
             day: "2026-10-26",
             timezone: @zone,
             firings: [%{key: ^key, outcome: "fired"}],
             last: %{label: "morning", time: "08:05"},
             next: %{label: "morning", tomorrow: true}
           } = Sunna.today(ctx.id)

    assert [%{day: "2026-10-26"}] = Sunna.days(ctx.id, 10)

    {:ok, main} = Kumbukumbu.main_session(ctx.id, ctx.witness.id, ctx.actor)
    assert [note, reply] = transcript(ctx, main)
    assert note.role == "system" and note.actor_kind == "platform"
    assert note.content =~ "This is your morning check-in, at 08:05"
    assert note.content =~ "Your next check-in is morning at 08:05"
    assert reply.role == "assistant" and reply.content == "Good morning."
    assert [%{key: "chat", calls: 1}] = Nisaba.spend(ctx.id, :witness, :purpose, @since)

    # Once a day whatever restarts: the next tick inside the window is no second wake.
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = transcript(ctx, main)
    assert [%{key: "chat", calls: 1}] = Nisaba.spend(ctx.id, :witness, :purpose, @since)
  end

  test "one set or changed after its time today waits for tomorrow; one past the window is missed, said rather than silent",
       ctx do
    {:ok, dawn} = Sunna.set_checkin(ctx.id, nil, "dawn", "06:00", ctx.actor)
    assert :ok = Sunna.tick(ctx.id)
    assert %{firings: []} = Sunna.today(ctx.id)

    {:ok, mid} = Sunna.set_checkin(ctx.id, nil, "mid", "08:10", ctx.actor)
    Clock.Fake.advance(30 * 60)
    assert :ok = Sunna.tick(ctx.id)
    assert %{firings: [%{key: ^mid, outcome: "missed"}]} = Sunna.today(ctx.id)
    assert [] = Kumbukumbu.sessions({:resident, ctx.id})

    # Changed at 08:30 to 08:25: after its time today, so it waits.
    {:ok, ^dawn} = Sunna.set_checkin(ctx.id, dawn, "dawn", "08:25", ctx.actor)
    assert :ok = Sunna.tick(ctx.id)
    assert %{firings: [%{key: ^mid}]} = Sunna.today(ctx.id)
    # A day with no firing has no row: the row says a check-in happened.
    assert [] = Sunna.days(ctx.id, 10)

    # Tomorrow at 08:30: dawn (08:25) is inside the window, mid (08:10) is past it.
    Clock.Fake.advance(24 * 3600)
    assert :ok = Sunna.tick(ctx.id)
    today = Sunna.today(ctx.id)
    assert today.day == "2026-10-27"
    assert %{^dawn => "fired", ^mid => "missed"} = Map.new(today.firings, &{&1.key, &1.outcome})
    assert [%{day: "2026-10-27"}] = Sunna.days(ctx.id, 10)

    assert :ok = Sunna.delete_checkin(ctx.id, mid, ctx.actor)

    assert {:error, %Sunna.Error{kind: :sunna_no_such_checkin}} =
             Sunna.delete_checkin(ctx.id, mid, ctx.actor)

    assert {:error, %Sunna.Error{kind: :sunna_time_invalid}} =
             Sunna.set_checkin(ctx.id, nil, "x", "8am", ctx.actor)
  end

  test "quiet hours defer a wake to their end, written in the firing row; crossing midnight and clearing",
       ctx do
    :ok = Sunna.set_quiet_hours(ctx.id, "07:00", "09:00", ctx.actor)
    {:ok, key} = Sunna.set_checkin(ctx.id, nil, "morning", "08:05", ctx.actor)
    Clock.Fake.advance(5 * 60)
    assert :ok = Sunna.tick(ctx.id)

    assert %{
             firings: [%{key: ^key, outcome: "deferred", until: until}],
             quiet: %{from: "07:00", to: "09:00"}
           } =
             Sunna.today(ctx.id)

    # 09:00 in New York, the end of quiet hours, as an instant.
    assert until == ~U[2026-10-26 13:00:00.000000Z]
    assert [] = Kumbukumbu.sessions({:resident, ctx.id})

    Clock.Fake.advance(30 * 60)
    assert :ok = Sunna.tick(ctx.id)
    assert [] = Kumbukumbu.sessions({:resident, ctx.id})

    Clock.Fake.advance(25 * 60)
    assert :ok = Sunna.tick(ctx.id)
    assert %{firings: [%{key: ^key, outcome: "fired"}]} = Sunna.today(ctx.id)
    assert [%{kind: "main"}] = Kumbukumbu.sessions({:resident, ctx.id})

    night = %{from: "22:00", to: "06:00"}
    local = DateTime.shift_zone!(~U[2026-10-27 03:00:00Z], @zone)
    assert Schedules.quiet?(local, night)
    refute Schedules.quiet?(DateTime.shift_zone!(~U[2026-10-27 12:00:00Z], @zone), night)
    assert :eq = DateTime.compare(Schedules.quiet_end(local, night), ~U[2026-10-27 10:00:00Z])

    :ok = Sunna.set_quiet_hours(ctx.id, nil, nil, ctx.actor)
    assert %{quiet: nil} = Sunna.today(ctx.id)

    assert {:error, %Sunna.Error{kind: :sunna_time_invalid}} =
             Sunna.set_quiet_hours(ctx.id, "22", nil, ctx.actor)
  end

  test "free time opens a session of its own kind on its own budget line, once a day, and a failure is recorded",
       ctx do
    :ok = Sunna.set_free_time(ctx.id, "08:00", ctx.actor)
    assert :ok = Sunna.tick(ctx.id)

    assert [%{kind: "free_time", key: key, private: true}] =
             Kumbukumbu.sessions({:resident, ctx.id})

    # Private as to its words by default (spec §6.3, v0.2): the resident's read.
    {:ok, _session, [note, reply]} = Kumbukumbu.transcript({:resident, ctx.id}, key)
    assert note.role == "system" and note.content =~ "This is your free time, Lily"
    assert reply.content == "Good morning."
    assert [%{key: "free_time", calls: 1}] = Nisaba.spend(ctx.id, :witness, :purpose, @since)
    assert %{free_time: "08:00", free_time_last: {"2026-10-26", "ran"}} = Sunna.today(ctx.id)

    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_] = Kumbukumbu.sessions({:resident, ctx.id})

    Fake.fail(:transport, for: ctx.id)
    Clock.Fake.advance(24 * 3600 - 60)
    assert :ok = Sunna.tick(ctx.id)
    assert %{free_time_last: {"2026-10-27", "failed: brain_turn_failed"}} = Sunna.today(ctx.id)
    assert [_, _] = Kumbukumbu.sessions({:resident, ctx.id})

    :ok = Sunna.set_free_time(ctx.id, nil, ctx.actor)
    assert %{free_time: nil} = Sunna.today(ctx.id)
  end

  test "dates are rows with a kind, counted on the read, shown to the brain as a section, and refused when malformed",
       ctx do
    set = fn number, title, on, kind ->
      Sunna.set_date(ctx.id, number, %{title: title, on: on, kind: kind}, ctx.actor)
    end

    assert "" = Sunna.dates_text(ctx.id)
    assert {:ok, 1} = set.(nil, "visa interview", ~U[2026-11-05 14:00:00Z], "deadline")
    # 23:00Z is 19:00 in New York: still today there.
    assert {:ok, 2} = set.(nil, "first contact", ~U[2026-10-26 23:00:00Z], "anniversary")
    assert {:ok, 3} = set.(nil, "the move", ~U[2026-10-20 12:00:00Z], "window")

    assert %{
             dates: [
               %{number: 3, days_to: -6},
               %{number: 2, days_to: 0},
               %{number: 1, days_to: 10}
             ]
           } =
             Sunna.today(ctx.id)

    text = Sunna.dates_text(ctx.id)
    assert text =~ "10 days to visa interview (deadline, 2026-11-05, date/1)"
    assert text =~ "today: first contact (anniversary, date/2)"
    assert text =~ "6 days since the move (window, date/3)"

    # Derived on the read: the same rows count differently tomorrow.
    Clock.Fake.advance(24 * 3600)
    assert Sunna.dates_text(ctx.id) =~ "9 days to visa interview"

    {:ok, main} = Kumbukumbu.main_session(ctx.id, ctx.witness.id, ctx.actor)

    {:ok, %{turn_ref: ref}} =
      Oneiroi.Brain.turn(ctx.id, main, "when is the interview?", ctx.actor)

    injections = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    assert %{reason: reason, tokens: tokens} = Enum.find(injections, &(&1.label == "dates"))
    assert reason =~ "never written down" and tokens > 0

    assert {:ok, 1} = set.(1, "visa interview", ~U[2026-11-06 14:00:00Z], "deadline")
    assert :ok = Sunna.remove_date(ctx.id, 3, ctx.actor)
    assert [%{number: 2, days_to: -1}, %{number: 1, days_to: 10}] = Sunna.today(ctx.id).dates

    assert {:error, %Sunna.Error{kind: :sunna_kind_invalid}} =
             set.(nil, "party", ~U[2026-12-01 00:00:00Z], "party")

    assert {:error, %Sunna.Error{kind: :sunna_time_invalid}} = set.(nil, "when", nil, "deadline")

    assert {:error, %Sunna.Error{kind: :sunna_label_invalid}} =
             set.(nil, String.duplicate("x", 61), ~U[2026-12-01 00:00:00Z], "deadline")

    assert {:error, %Sunna.Error{kind: :sunna_no_such_date}} =
             Sunna.remove_date(ctx.id, 9, ctx.actor)
  end

  test "a paused resident schedules nothing, and the minute job covers every resident with something scheduled",
       ctx do
    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)
    other_actor = Actor.new(:witness, other_witness.id)
    :ok = Oneiroi.Gaia.store_key(other_witness.id, "sk-or-test", other_actor)
    Fake.reply("Hello.", for: other.id)

    {:ok, _} = Sunna.set_checkin(ctx.id, nil, "noon", "08:00", ctx.actor)
    {:ok, _} = Sunna.set_checkin(other.id, nil, "noon", "12:00", other_actor)

    {:ok, _} =
      AgathosDaimon.Router.dispatch(%AgathosDaimon.Commands.PauseResident{
        actor: ctx.actor,
        at: Clock.now(),
        id: ctx.id,
        reason: "away"
      })

    assert :skipped = Sunna.tick(ctx.id)
    # As the worker runs it: the process scope set, no transaction around
    # it. Under the sandbox a transaction-local `set_config` outlives its
    # savepoint, so the connection carries whatever scope was set last;
    # it is set to the paused resident's here so a roster read that
    # skipped its own platform transaction sees one row, the wrong one.
    Oneiroi.Scope.resident(ctx.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = TickWorker.run(%{})
    assert %{firings: []} = Sunna.today(ctx.id)
    assert %{firings: [%{outcome: "fired"}]} = Sunna.today(other.id)
  end

  test "the zone is the resident's: a bad name is refused and the day is read in it", ctx do
    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_timezone_invalid}} =
             AgathosDaimon.set_timezone(ctx.id, "Nowhere/Bogus", ctx.actor)

    assert {:ok, %{timezone: @zone}} = AgathosDaimon.fetch(ctx.id)
    # 12:00Z is 01:00 the next day in Auckland.
    assert :ok = AgathosDaimon.set_timezone(ctx.id, "Pacific/Auckland", ctx.actor)
    assert %{day: "2026-10-27", timezone: "Pacific/Auckland"} = Sunna.today(ctx.id)
  end
end
