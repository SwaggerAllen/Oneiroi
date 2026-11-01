defmodule Oneiroi.Sunna.ScheduleTest do
  @moduledoc "The schedule aggregate, pure: once a day whatever restarts, the day opened on the first firing, what is refused."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Schedule

  @actor Actor.platform()
  @at ~U[2026-10-26 12:00:00.000000Z]

  defp evolve(state \\ %Schedule{}, events),
    do: Enum.reduce(List.wrap(events), state, &Schedule.apply(&2, &1))

  defp cmd(module, fields),
    do: struct!(module, Map.merge(%{actor: @actor, at: @at, id: "r"}, Map.new(fields)))

  defp with_checkin(key \\ "a", time \\ "08:00") do
    evolve(
      Schedule.execute(
        %Schedule{},
        cmd(Commands.SetCheckin, key: key, label: "x", time: time, day: "d1")
      )
    )
  end

  test "a check-in fires once a day, the first firing opens the day, and the next day is its own" do
    s = with_checkin()
    fire = cmd(Commands.FireCheckin, key: "a", day: "d1")

    assert [%Events.DayOpened{day: "d1"}, %Events.CheckinFired{key: "a", day: "d1"}] =
             Schedule.execute(s, fire)

    s = evolve(s, Schedule.execute(s, fire))
    assert [] = Schedule.execute(s, fire)
    assert [] = Schedule.execute(s, cmd(Commands.MissCheckin, key: "a", day: "d1"))
    assert [] = Schedule.execute(s, cmd(Commands.DeferWake, key: "a", day: "d1", until: @at))

    # The day row is opened once, so a second check-in's firing is the firing alone.
    s =
      evolve(
        s,
        Schedule.execute(
          s,
          cmd(Commands.SetCheckin, key: "b", label: "y", time: "12:00", day: "d1")
        )
      )

    assert %Events.CheckinFired{key: "b"} =
             Schedule.execute(s, cmd(Commands.FireCheckin, key: "b", day: "d1"))

    assert [%Events.DayOpened{day: "d2"}, %Events.CheckinFired{day: "d2"}] =
             Schedule.execute(s, cmd(Commands.FireCheckin, key: "a", day: "d2"))

    assert {:error, %{kind: :sunna_no_such_checkin, site: :sunna_checkin_fire_absent}} =
             Schedule.execute(s, cmd(Commands.FireCheckin, key: "zz", day: "d1"))
  end

  test "a deferral is held once and the fire after it stands; a miss is once and final for the day" do
    s = with_checkin()
    defer = cmd(Commands.DeferWake, key: "a", day: "d1", until: @at)
    assert %Events.WakeDeferred{until: @at} = Schedule.execute(s, defer)
    s = evolve(s, Schedule.execute(s, defer))
    assert [] = Schedule.execute(s, defer)
    assert {:deferred, @at} = Schedule.outcome(s, "a", "d1")

    assert [%Events.DayOpened{}, %Events.CheckinFired{}] =
             Schedule.execute(s, cmd(Commands.FireCheckin, key: "a", day: "d1"))

    s = with_checkin()
    miss = cmd(Commands.MissCheckin, key: "a", day: "d1")
    assert %Events.CheckinMissed{} = Schedule.execute(s, miss)
    s = evolve(s, Schedule.execute(s, miss))
    assert [] = Schedule.execute(s, miss)
    assert [] = Schedule.execute(s, cmd(Commands.FireCheckin, key: "a", day: "d1"))
    assert :missed = Schedule.outcome(s, "a", "d1")
  end

  test "setting the same check-in again is no event, a change carries its day, and malformed input is refused" do
    s = with_checkin()
    same = cmd(Commands.SetCheckin, key: "a", label: "x", time: "08:00", day: "d2")
    assert [] = Schedule.execute(s, same)

    assert %Events.CheckinChanged{time: "08:30", day: "d2"} =
             Schedule.execute(
               s,
               cmd(Commands.SetCheckin, key: "a", label: "x", time: "08:30", day: "d2")
             )

    assert {:error, %{kind: :sunna_time_invalid, site: :sunna_checkin_time_invalid}} =
             Schedule.execute(
               s,
               cmd(Commands.SetCheckin, key: "a", label: "x", time: "8:30", day: "d2")
             )

    assert {:error, %{kind: :sunna_time_invalid, site: :sunna_checkin_time_invalid}} =
             Schedule.execute(
               s,
               cmd(Commands.SetCheckin, key: "a", label: "x", time: "24:00", day: "d2")
             )

    assert {:error, %{kind: :sunna_label_invalid, site: :sunna_checkin_label_invalid}} =
             Schedule.execute(
               s,
               cmd(Commands.SetCheckin, key: "a", label: "  ", time: "08:30", day: "d2")
             )

    assert %Events.CheckinDeleted{key: "a"} =
             Schedule.execute(s, cmd(Commands.DeleteCheckin, key: "a"))

    assert {:error, %{kind: :sunna_no_such_checkin, site: :sunna_checkin_delete_absent}} =
             Schedule.execute(s, cmd(Commands.DeleteCheckin, key: "b"))
  end

  test "free time runs or fails once a day; quiet hours and dates are validated and deduplicated" do
    s = evolve(Schedule.execute(%Schedule{}, cmd(Commands.SetFreeTime, time: "22:30")))
    assert [] = Schedule.execute(s, cmd(Commands.SetFreeTime, time: "22:30"))

    assert {:error, %{kind: :sunna_time_invalid, site: :sunna_free_time_time_invalid}} =
             Schedule.execute(s, cmd(Commands.SetFreeTime, time: "soon"))

    assert %Events.FreeTimeScheduled{time: nil} =
             Schedule.execute(s, cmd(Commands.SetFreeTime, time: nil))

    ran = cmd(Commands.RecordFreeTime, day: "d1", session_key: "k", reason: nil)
    assert %Events.FreeTimeRan{session_key: "k"} = Schedule.execute(s, ran)
    s = evolve(s, Schedule.execute(s, ran))
    assert [] = Schedule.execute(s, ran)

    assert %Events.FreeTimeFailed{reason: "unknown"} =
             Schedule.execute(
               s,
               cmd(Commands.RecordFreeTime, day: "d2", session_key: nil, reason: nil)
             )

    quiet = cmd(Commands.SetQuietHours, from: "22:00", to: "06:00")
    assert %Events.QuietHoursSet{} = Schedule.execute(s, quiet)
    s = evolve(s, Schedule.execute(s, quiet))
    assert [] = Schedule.execute(s, quiet)

    assert {:error, %{kind: :sunna_time_invalid, site: :sunna_quiet_hours_time_invalid}} =
             Schedule.execute(s, cmd(Commands.SetQuietHours, from: "22:00", to: nil))

    assert %Events.QuietHoursSet{from: nil, to: nil} =
             Schedule.execute(s, cmd(Commands.SetQuietHours, from: nil, to: nil))

    date = cmd(Commands.SetDate, number: 1, title: "visa", on: @at, kind: "deadline")
    assert %Events.DateSet{number: 1} = Schedule.execute(s, date)
    s = evolve(s, Schedule.execute(s, date))
    assert [] = Schedule.execute(s, date)
    assert %Events.DateChanged{kind: "window"} = Schedule.execute(s, %{date | kind: "window"})

    assert {:error, %{kind: :sunna_kind_invalid, site: :sunna_date_kind_invalid}} =
             Schedule.execute(s, %{date | kind: "party"})

    assert {:error, %{kind: :sunna_time_invalid, site: :sunna_date_on_invalid}} =
             Schedule.execute(s, %{date | on: "2026-11-05"})

    assert {:error, %{kind: :sunna_label_invalid, site: :sunna_date_title_invalid}} =
             Schedule.execute(s, %{date | title: String.duplicate("x", 61)})

    assert %Events.DateRemoved{number: 1} =
             Schedule.execute(s, cmd(Commands.RemoveDate, number: 1))

    assert {:error, %{kind: :sunna_no_such_date, site: :sunna_date_remove_absent}} =
             Schedule.execute(s, cmd(Commands.RemoveDate, number: 2))
  end
end
