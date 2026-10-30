defmodule Oneiroi.Sunna.HourTest do
  @moduledoc "The hour marker, pure (spec §6.7, P20 as amended): the local hour as a key, once, and nothing else."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Schedule

  @at ~U[2026-10-26 12:00:00Z]
  @actor Actor.new(:job, "sunna_tick")

  test "an hour is marked once, and only a local hour key is one" do
    mark = %Commands.MarkHour{actor: @actor, at: @at, id: "r1", hour: "2026-10-26T08"}

    assert %Events.HourMarked{hour: "2026-10-26T08"} =
             marked = Schedule.execute(%Schedule{}, mark)

    state = Schedule.apply(%Schedule{}, marked)
    assert [] = Schedule.execute(state, mark)

    assert %Events.HourMarked{hour: "2026-10-26T09"} =
             Schedule.execute(state, %{mark | hour: "2026-10-26T09"})

    for bad <- ["2026-10-26", "2026-10-26T24", "2026-10-26T08:00", nil, 8] do
      assert {:error, :hour_invalid} = Schedule.execute(state, %{mark | hour: bad})
    end
  end
end
