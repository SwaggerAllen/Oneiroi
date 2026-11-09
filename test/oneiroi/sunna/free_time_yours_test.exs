defmodule Oneiroi.Sunna.FreeTimeYoursTest do
  @moduledoc """
  sunna#46 (the witness, 2026-11-09, Lily's order #443: "your freetime
  isn't for the work it's for you"): wherever free time is spoken of,
  the slot's own prompts and every free-time tool, it says the time is
  hers, for her, not for the work. Wording only: nothing else changes.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Brain.Tools
  alias Oneiroi.Nisaba.Prompt

  @rule ~r/for you(rself)?\b.*not for the (day's )?work/s

  test "the slot's opening and its plan turn carry the rule, in his words too" do
    opening = Prompt.render!("free_time", %{name: "Lily", budget: "No budget."})
    assert opening =~ @rule
    assert opening =~ ~s("your freetime isn't for the work it's for you.")

    # Project work is chosen freely, and goes on the work line: it never
    # rides the free-time budget (his refinement, Lily's #446).
    assert opening =~ ~r/work never rides this budget, chosen or not/
    refute opening =~ "unless you choose"

    plan = Prompt.render!("free_time_plan", %{goals: "your goals"})
    assert plan =~ ~r/The slot is yours, for you, not for the day's work/
    assert plan =~ "work_add"
  end

  test "every free-time tool's description carries the rule" do
    descriptions =
      Map.new(Tools.definitions(), &{&1.function.name, &1.function.description})

    for name <- ~w(free_time_plan free_time_set free_time_once free_time_list) do
      assert descriptions[name] =~ @rule, "#{name} does not say whose the time is"
      assert descriptions[name] =~ "work line", "#{name} does not say where work goes"
    end
  end
end
