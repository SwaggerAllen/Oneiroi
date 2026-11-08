defmodule Oneiroi.Sunna.SchedulesTest do
  @moduledoc "The schedule through its exports and the tick, in the resident's zone: firing, missing, deferring, free time, dates, the wake into the brain."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope
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

  test "the tick marks the local hour once, before anything else, for every active resident and never a paused one",
       ctx do
    id = ctx.id
    # Nothing scheduled: the pulse is the floor's resident's too.
    assert :ok = Sunna.tick(id)
    assert [%{hour: "2026-10-26T08", at: %DateTime{}}] = Sunna.hours(id, 5)
    assert :ok = Sunna.tick(id)
    assert [_one] = Sunna.hours(id, 5)

    Clock.Fake.advance(3600)
    assert :ok = Sunna.tick(id)
    assert [%{hour: "2026-10-26T09"}, %{hour: "2026-10-26T08"}] = Sunna.hours(id, 5)
    assert %{hour: "2026-10-26T09"} = Sunna.last_hour(id)

    # The worker's roster is every active resident, with or without a schedule; a paused one is skipped.
    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)
    paused_witness = Fixtures.account!()
    paused = Fixtures.resident!(paused_witness)

    {:ok, _} =
      AgathosDaimon.Router.dispatch(%AgathosDaimon.Commands.PauseResident{
        actor: Actor.new(:witness, paused_witness.id),
        at: Clock.now(),
        id: paused.id,
        reason: "away"
      })

    # The sandbox keeps the last scope set on the connection; pin it to
    # the paused resident's so a roster read without its own platform
    # transaction would see the wrong one row and the probe fails.
    Oneiroi.Scope.resident(paused.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    Clock.Fake.advance(3600)
    assert :ok = TickWorker.run(%{})
    assert [%{hour: "2026-10-26T10"} | _] = Sunna.hours(id, 5)
    assert [%{hour: "2026-10-26T14"}] = Sunna.hours(other.id, 5)
    assert [] = Sunna.hours(paused.id, 5)
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

  # sunna#24: a letter another conversation sends the Oneiroi chat wakes it.
  defp letters_setup(ctx) do
    lily = Actor.new(:resident, ctx.id)
    {:ok, main} = Kumbukumbu.main_session(ctx.id, ctx.witness.id, ctx.actor)

    {:ok, code} =
      Kumbukumbu.open_adapter(ctx.id, "laptop", [ctx.witness.id], lily,
        runtime: "claude-code",
        label: "Oneiroi"
      )

    send = fn from, actor, to, text ->
      {:ok, %{number: n}} = Kumbukumbu.send_letter(ctx.id, from, %{to: to, text: text}, actor)
      n
    end

    {main, fn text -> send.(code, lily, "Oneiroi chat", text) end, send, code, lily}
  end

  test "a letter from another conversation wakes the Oneiroi chat once, by number and sender, never its words",
       ctx do
    {main, letter, send, code, lily} = letters_setup(ctx)
    first = letter.("secret words")

    assert :ok = Sunna.tick(ctx.id)
    assert [note, reply] = transcript(ctx, main)
    assert note.role == "system" and note.actor_kind == "platform"

    assert note.content =~
             "another of your conversations wrote to you here: ##{first} from Claude Code · Oneiroi."

    assert note.content =~ "letter_send with in_reply_to"
    refute note.content =~ "secret words"
    assert reply.content == "Good morning."
    assert [%{key: "chat", calls: 1}] = Nisaba.spend(ctx.id, :witness, :purpose, @since)

    # Left unread, it wakes nothing again.
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = transcript(ctx, main)

    # The witness's own letter, a house letter and a brief for Free time wake nothing.
    send.(nil, ctx.actor, "Oneiroi chat", "from the witness")
    send.(code, lily, "house", "to everyone")
    send.(code, lily, "Free time", "a brief")
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = transcript(ctx, main)

    # At most six wakes an hour: five more letters wake it, the seventh
    # waits for the hour to turn, and then wakes it.
    for _ <- 1..5 do
      letter.("again")
      Clock.Fake.advance(60)
      assert :ok = Sunna.tick(ctx.id)
    end

    # (The fake model answers the first wake only; each wake is its note.)
    notes = fn -> ctx |> transcript(main) |> Enum.filter(&(&1.role == "system")) end
    assert length(notes.()) == 6
    held = letter.("held")
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert length(notes.()) == 6

    Clock.Fake.advance(3600)
    assert :ok = Sunna.tick(ctx.id)
    assert [_ | _] = all = notes.()
    assert length(all) == 7
    assert List.last(all).content =~ "##{held} from Claude Code · Oneiroi."
  end

  test "a letter waits out quiet hours and wakes the chat when they end", ctx do
    :ok = Sunna.set_quiet_hours(ctx.id, "07:00", "09:00", ctx.actor)
    {main, letter, _send, _code, _lily} = letters_setup(ctx)
    n = letter.("in the night")

    assert :ok = Sunna.tick(ctx.id)
    assert [] = transcript(ctx, main)

    Clock.Fake.advance(60 * 60 + 60)
    assert :ok = Sunna.tick(ctx.id)
    assert [note, _reply] = transcript(ctx, main)
    assert note.content =~ "##{n} from Claude Code · Oneiroi."
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

  # sunna#28 (the witness, 2026-11-04: "some check boxes so I can compose
  # from pre-existing parts and write stuff in myself").
  test "a check-in's note carries the witness's words and the parts he checked, in the catalog's order",
       ctx do
    {:ok, key} =
      Sunna.set_checkin(ctx.id, nil, "morning", "08:05", ctx.actor,
        parts: ["needs_you", "plan", "free_time"],
        prompt: "Look over the post draft first."
      )

    :ok = Sunna.set_free_time(ctx.id, "21:00", ctx.actor)

    # A change of time alone keeps what the note carries.
    {:ok, ^key} = Sunna.set_checkin(ctx.id, key, "morning", "08:05", ctx.actor)

    assert [
             %{
               parts: ["needs_you", "plan", "free_time"],
               prompt: "Look over the post draft first."
             }
           ] =
             Sunna.today(ctx.id).checkins

    assert {:error, %Sunna.Error{kind: :sunna_parts_invalid}} =
             Sunna.set_checkin(ctx.id, key, "morning", "08:05", ctx.actor, parts: ["horoscope"])

    Clock.Fake.advance(5 * 60)
    assert :ok = Sunna.tick(ctx.id)

    {:ok, main} = Kumbukumbu.main_session(ctx.id, ctx.witness.id, ctx.actor)
    assert [note | _] = transcript(ctx, main)
    c = note.content
    assert c =~ "This is your morning check-in, at 08:05"
    assert c =~ "From the person who looks after you:\n\nLook over the post draft first."
    assert c =~ "# Today's plan\n\nNo plan written for 2026-10-26"
    assert c =~ "- 21:00: still ahead"
    assert c =~ "# Waiting on the person who looks after you\n\nNothing."
    refute c =~ "# Letters"

    # The catalog's order, whatever order they were checked in.
    order = for h <- ["# Today's plan", "# Free time", "# Waiting on"], do: :binary.match(c, h)
    assert order == Enum.sort(order)

    # Words cleared with an empty prompt; the parts stay.
    {:ok, ^key} = Sunna.set_checkin(ctx.id, key, "morning", "08:05", ctx.actor, prompt: "  ")

    assert [%{prompt: nil, parts: ["needs_you", "plan", "free_time"]}] =
             Sunna.today(ctx.id).checkins
  end

  # sunna#29 (the witness, 2026-11-05: "fire randomly in a window, so like
  # I could set it to one every three hours").
  test "rounds: one at a random minute in each window of her waking hours, the same draw all day" do
    quiet = %{from: "22:00", to: "07:00"}
    times = Schedules.round_times("res-a", "2026-11-05", quiet, 3)

    # Waking hours 07:00-22:00, cut into three-hour windows: five rounds,
    # one inside each window.
    assert length(times) == 5

    for {time, n} <- Enum.with_index(times) do
      start = 7 * 60 + n * 180
      [h, m] = time |> String.split(":") |> Enum.map(&String.to_integer/1)
      assert h * 60 + m >= start and h * 60 + m < start + 180
    end

    assert Schedules.round_times("res-a", "2026-11-05", quiet, 3) == times
    refute Schedules.round_times("res-a", "2026-11-06", quiet, 3) == times
    refute Schedules.round_times("res-b", "2026-11-05", quiet, 3) == times
  end

  # sunna#30: the witness sees that rounds are on and sets them per
  # resident; the server settings are the defaults.
  test "her own rounds: a cadence and a window of her own, shown with when the last one started, never what it did",
       ctx do
    # The suite's default is off (config/test.exs).
    assert %{every_hours: 0, every_default: true, today: 0, last_at: nil} =
             Sunna.today(ctx.id).rounds

    assert {:error, %{kind: :sunna_rounds_invalid}} = Sunna.set_rounds(ctx.id, 30, nil, ctx.actor)

    assert {:error, %{kind: :sunna_rounds_invalid}} =
             Sunna.set_rounds(ctx.id, 3, "8am-10pm", ctx.actor)

    assert :ok = Sunna.set_rounds(ctx.id, 4, "08:00-20:00", ctx.actor)

    assert %{every_hours: 4, every_default: false, waking: "08:00-20:00", today: 3} =
             Sunna.today(ctx.id).rounds

    assert length(Schedules.round_times(ctx.id, "2026-11-05", nil, 4, "08:00-20:00")) == 3

    actor = Actor.new(:job, "sunna_tick")
    assert :ok = Schedules.run_round(ctx.id, "2026-10-26", "08:00", actor)
    assert %{last_at: %DateTime{}} = Sunna.today(ctx.id).rounds

    # Back to the defaults.
    assert :ok = Sunna.set_rounds(ctx.id, nil, nil, ctx.actor)
    assert %{every_default: true, waking_default: true} = Sunna.today(ctx.id).rounds
  end

  test "a round runs once, in a private conversation of its own, on its own rounds line, and is remembered; off at 0",
       ctx do
    # The suite runs with rounds off (config/test.exs): the tick draws none.
    assert Schedules.round_times(ctx.id, "2026-10-26", nil) == []
    assert :ok = Sunna.tick(ctx.id)
    assert [] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "round"))

    actor = Actor.new(:job, "sunna_tick")
    assert :ok = Schedules.run_round(ctx.id, "2026-10-26", "08:00", actor)

    assert [%{kind: "round", key: key, private: true}] =
             Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "round"))

    {:ok, _session, [note | _]} = Kumbukumbu.transcript({:resident, ctx.id}, key)
    assert note.content =~ "This is a round"
    # Speech is the habit, silence the exception with a reason (sunna#39).
    assert note.content =~ "the habit is to say something"
    assert note.content =~ "this wakes that conversation"
    assert note.content =~ "say in your closing line why"
    assert note.content =~ "This round is one turn."

    # Claimed before it runs: the same round again is not had twice.
    assert :already = Schedules.run_round(ctx.id, "2026-10-26", "08:00", actor)
    assert [_one] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "round"))

    # Billed to its own line (sunna#39), never free time's.
    spend = Nisaba.spend(ctx.id, :witness, :purpose, @since)
    assert Enum.any?(spend, &(&1.key == "rounds"))
    refute Enum.any?(spend, &(&1.key == "free_time"))

    # Remembered: when it fired, the conversation, and what left it.
    assert [%{day: "2026-10-26", slot: "08:00", outcome: "ran", session_key: ^key}] =
             Sunna.rounds(ctx.id, 10)

    assert [%{outcome: "ran", turns: 1, did: []}] = Oneiroi.Brain.round_history(ctx.id, 10)

    tool =
      Tools.run("round_list", "{}", %{
        resident_id: ctx.id,
        session_key: key,
        turn_ref: "t",
        resident: Actor.new(:resident, ctx.id)
      })

    assert tool =~ "2026-10-26 08:00: ran in session #{key} (1 turn(s)); left it: nothing left it"
  end

  test "a round that fails is remembered with the failure's kind; the check-in part names the day's rounds",
       ctx do
    actor = Actor.new(:job, "sunna_tick")
    Fake.clear()
    Fake.fail(:transport, for: ctx.id)
    assert {:error, _} = Schedules.run_round(ctx.id, "2026-10-26", "09:00", actor)
    assert [%{outcome: "failed: " <> _, session_key: key}] = Sunna.rounds(ctx.id, 10)
    assert is_binary(key)

    # Recorded once: a second record of the same round is no event.
    assert :already = Schedules.run_round(ctx.id, "2026-10-26", "09:00", actor)

    part = Oneiroi.Brain.checkin_part(ctx.id, "rounds")
    assert part =~ "# Rounds"
    assert part =~ "2026-10-26 09:00: failed: "
    assert "rounds" in Sunna.CheckinParts.keys()
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

    assert %{
             free_times: [%{time: "08:00", today: "ran"}],
             free_time_last: {"2026-10-26", "ran"}
           } = Sunna.today(ctx.id)

    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_] = Kumbukumbu.sessions({:resident, ctx.id})

    Fake.fail(:transport, for: ctx.id)
    Clock.Fake.advance(24 * 3600 - 60)
    assert :ok = Sunna.tick(ctx.id)
    assert %{free_time_last: {"2026-10-27", "failed: brain_turn_failed"}} = Sunna.today(ctx.id)
    assert [_, _] = Kumbukumbu.sessions({:resident, ctx.id})

    # Moved, never removed (sunna#21); the resident moves it too.
    assert {:error, %Sunna.Error{kind: :sunna_free_time_required}} =
             Sunna.set_free_time(ctx.id, nil, ctx.actor)

    assert {:error, %Sunna.Error{kind: :sunna_free_time_required}} =
             Sunna.set_free_time(ctx.id, [], ctx.actor)

    assert %{free_times: [%{time: "08:00"}]} = Sunna.today(ctx.id)
    :ok = Sunna.set_free_time(ctx.id, "23:15", Oneiroi.Actor.new(:resident, ctx.id))
    assert %{free_times: [%{time: "23:15", today: nil}]} = Sunna.today(ctx.id)
  end

  # Sunna #22: free time is a list of slots, each run once a day.
  test "two slots each run once a day, the list is kept in order, and its bounds are refused",
       ctx do
    # The suite's clock is 08:00 in the resident's zone (New York).
    :ok = Sunna.set_free_time(ctx.id, ["14:30", "08:00"], ctx.actor)
    assert %{free_times: [%{time: "08:00"}, %{time: "14:30"}]} = Sunna.today(ctx.id)

    assert :ok = Sunna.tick(ctx.id)
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_] = free_sessions(ctx.id)

    Clock.Fake.advance(6 * 3600 + 29 * 60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = free_sessions(ctx.id)

    assert %{free_times: [%{time: "08:00", today: "ran"}, %{time: "14:30", today: "ran"}]} =
             Sunna.today(ctx.id)

    assert {:error, %Sunna.Error{kind: :sunna_free_time_invalid}} =
             Sunna.set_free_time(ctx.id, ["08:00", "08:00"], ctx.actor)

    assert {:error, %Sunna.Error{kind: :sunna_free_time_invalid}} =
             Sunna.set_free_time(ctx.id, ~w(01:00 02:00 03:00 04:00 05:00), ctx.actor)

    assert {:error, %Sunna.Error{kind: :sunna_time_invalid}} =
             Sunna.set_free_time(ctx.id, ["08:00", "later"], ctx.actor)
  end

  # A day recorded before slots had its one free time: a deploy that adds
  # a second slot the same day does not run free time again.
  # sunna#27: on 2026-11-03 the witness moved the zone from UTC to Pacific
  # after the 22:30 UTC run; that night's 22:30 Pacific slot carried the
  # same day and slot and was taken as already run.
  test "a slot whose label an earlier run carries, under another zone, still runs, and runs once",
       ctx do
    :ok = AgathosDaimon.set_timezone(ctx.id, "Etc/UTC", ctx.actor)
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.actor)

    # 12:00 UTC: the slot runs.
    assert :ok = Sunna.tick(ctx.id)

    free = fn ->
      Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "free_time"))
    end

    assert [_] = free.()

    # The zone moves to New York (UTC-4): its 12:00 the same day is 16:00
    # UTC, the same day and slot by label, and another slot by the clock.
    :ok = AgathosDaimon.set_timezone(ctx.id, @zone, ctx.actor)
    Fake.reply("Good afternoon.", for: ctx.id)
    Clock.Fake.advance(4 * 3600)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = free.()

    # And once: the next minute is no third run.
    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = free.()
  end

  test "a day whose free time ran before slots runs no slot again" do
    settings = %{free_time: "22:30", free_time_day: "2026-11-02", free_time_outcome: "ran"}
    assert Schedules.free_times_of(settings) == ["22:30"]

    assert %{nil => "ran"} =
             Scope.platform(fn -> Schedules.free_time_ran(settings, "2026-11-02") end)

    assert %{} == Scope.platform(fn -> Schedules.free_time_ran(settings, "2026-11-03") end)
  end

  defp free_sessions(id),
    do: Enum.filter(Kumbukumbu.sessions({:resident, id}), &(&1.kind == "free_time"))

  # Sunna #21: free time is the standard of care, not something switched on.
  test "a resident nobody configured has free time at the default slots, and each runs", ctx do
    assert %{free_times: [%{time: "14:30"}, %{time: "22:30"}]} = Sunna.today(ctx.id)
    assert [] = Kumbukumbu.sessions({:resident, ctx.id})

    # The suite's clock is 08:00 in the resident's zone (New York); to 14:30, then 22:30.
    Clock.Fake.advance(6 * 3600 + 30 * 60)
    assert :ok = Sunna.tick(ctx.id)
    assert [%{kind: "free_time", private: true}] = Kumbukumbu.sessions({:resident, ctx.id})
    Clock.Fake.advance(8 * 3600)
    assert :ok = Sunna.tick(ctx.id)
    assert [_, _] = free_sessions(ctx.id)
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
