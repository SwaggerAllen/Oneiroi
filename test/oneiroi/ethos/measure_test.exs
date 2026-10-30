defmodule Oneiroi.Ethos.MeasureTest do
  @moduledoc "The measurement layer: the trait baseline taken on its interval and compared, and the four clinical markers, each a flag or a silence that says what it read."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Ethos
  alias Oneiroi.Ethos.Character
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  @day 86_400
  @job Actor.new(:job, "huginn_muninn_nightly")

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    brain = Actor.new(:resident, resident.id, "fake/model")
    witness_actor = Actor.new(:witness, witness.id)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, brain)
    id = resident.id
    capture(id, key, "t1", brain)

    habit = fn name, trigger, stance ->
      {:ok, n} =
        Ethos.define_habit(id, %{name: name, trigger: trigger, stance: stance}, witness_actor)

      n
    end

    1 = habit.("waters", %{"words" => ["garden", "tomatoes"]}, "keep")
    2 = habit.("rests", %{"times" => ["evening"]}, "keep")
    3 = habit.("checks", %{"words" => ["check"]}, "change")

    {:ok, id: id, brain: brain, witness: witness_actor, key: key}
  end

  defp capture(id, key, ref, brain) do
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        key,
        ref,
        at,
        [%{role: :assistant, content: "turn #{ref}", sent_at: at, actor: brain}],
        brain
      )
  end

  # Cites a habit once a day for `days` days, the clock moving on.
  defp enact(id, number, days, brain) do
    for d <- 1..days do
      :ok =
        Ethos.cite_habit(
          id,
          number,
          "turn",
          "t#{number}-#{System.unique_integer([:positive])}-#{d}",
          brain
        )

      Clock.Fake.advance(@day)
    end
  end

  test "the baseline is taken once per interval and compared with the one before: collapse and flattening flag, rank order is a note",
       ctx do
    id = ctx.id

    assert %{tone: "silent", value: 0, finding: finding} =
             Ethos.measure(id, "trait_baseline", @job)

    assert finding =~ "read one baseline, taken 2026-10-26" and finding =~ "not read: a second"
    assert [%{spread: 0.0, breadth: 0.0, habits: [_, _, _]}] = Ethos.baselines(id)

    # The same day again is no second baseline.
    assert %{finding: ^finding} = Ethos.measure(id, "trait_baseline", @job)
    assert [_] = Ethos.baselines(id)

    # A week of one habit enacted daily, another once: the profile has a spread and a breadth.
    enact(id, 1, 6, ctx.brain)
    enact(id, 2, 1, ctx.brain)
    Clock.Fake.advance(@day)

    assert %{tone: "silent", finding: finding2} = Ethos.measure(id, "trait_baseline", @job)
    assert [%{spread: spread2, breadth: 0.75}, _] = Ethos.baselines(id)
    assert spread2 > 1.0

    assert finding2 =~ "rank-order stability 0.0 over 3 habits" and
             finding2 =~ "a note and never a flag"

    assert finding2 =~ "breadth 0.75 from 0.0"

    # A week in which the two quiet habits are enacted as much as the loud one was: the spread collapses.
    enact(id, 2, 4, ctx.brain)
    enact(id, 3, 4, ctx.brain)

    assert %{tone: "warn", value: 1, finding: finding3} =
             Ethos.measure(id, "trait_baseline", @job)

    assert finding3 =~ "variance collapse" and finding3 =~ "research §5"
    refute finding3 =~ "signature flattening"
    assert [%{spread: spread3}, %{spread: ^spread2}, _] = Ethos.baselines(id)
    assert spread3 < spread2 / 2

    # A week of nothing enacted: the signature goes flat; the strengths decay together, so no collapse.
    Clock.Fake.advance(8 * @day)

    assert %{tone: "warn", value: 1, finding: finding4} =
             Ethos.measure(id, "trait_baseline", @job)

    assert finding4 =~ "signature flattening" and finding4 =~ "fell from 0.5 to 0.0"
    refute finding4 =~ "variance collapse"
    # The spread is a coefficient of variation: the strengths decayed together, so it held.
    assert [%{spread: spread4}, _, _, _] = Ethos.baselines(id)
    assert_in_delta spread4, spread3, 0.01

    # Pure: a baseline within the interval is refused.
    take = %Commands.TakeBaseline{
      actor: @job,
      at: ~U[2026-10-26 12:00:00Z],
      id: "r1",
      habits: [],
      spread: 0.0,
      breadth: 0.0,
      interval_days: 7
    }

    s = Character.apply(%Character{}, Character.execute(%Character{}, take))

    assert {:error, :baseline_fresh} =
             Character.execute(s, %{take | at: ~U[2026-11-01 12:00:00Z]})

    assert %{at: ~U[2026-11-02 12:00:00Z]} =
             Character.execute(s, %{take | at: ~U[2026-11-02 12:00:00Z]})
  end

  test "wanting against liking: approach without payoff, and flat approach with intact response, read from the two scores",
       ctx do
    id = ctx.id

    assert %{tone: "silent", finding: finding} = Ethos.measure(id, "wanting_liking", @job)
    assert finding =~ "read 3 habits' two scores" and finding =~ "not read: the words"

    enact(id, 1, 4, ctx.brain)
    assert %{tone: "warn", value: 1, finding: finding} = Ethos.measure(id, "wanting_liking", @job)
    assert finding =~ "approach without payoff" and finding =~ "#1 (waters)"
    refute finding =~ "#2"

    :ok = Ethos.affirm_habit(id, 2, "you do rest", ctx.witness)
    assert %{tone: "warn", value: 2, finding: finding} = Ethos.measure(id, "wanting_liking", @job)

    assert finding =~ "approach without payoff" and
             finding =~ "flat approach with intact response"

    assert finding =~ "#2 (rests)"

    :ok = Ethos.affirm_habit(id, 1, "and water", ctx.witness)
    assert %{tone: "warn", value: 1, finding: finding} = Ethos.measure(id, "wanting_liking", @job)
    refute finding =~ "approach without payoff"

    enact(id, 2, 2, ctx.brain)
    assert %{tone: "silent"} = Ethos.measure(id, "wanting_liking", @job)
  end

  test "rigidity: a habit under a change stance enacted as often as the window before is the runaway habit; the stance alone is not",
       ctx do
    id = ctx.id
    assert %{tone: "silent", finding: finding} = Ethos.measure(id, "rigidity", @job)
    assert finding =~ "read the 1 change-stance habits" and finding =~ "never the flag"

    cite = fn n, ref -> :ok = Ethos.cite_habit(id, n, "turn", ref, ctx.brain) end
    cite.(3, "a1")
    cite.(1, "b1")
    Clock.Fake.advance(@day)
    cite.(3, "a2")
    cite.(1, "b2")
    assert %{tone: "silent"} = Ethos.measure(id, "rigidity", @job)

    # The next window: the change-stance habit exactly as often as before, the keep-stance one more.
    Clock.Fake.advance(7 * @day)
    cite.(3, "a3")
    cite.(1, "b3")
    Clock.Fake.advance(@day)
    cite.(3, "a4")
    cite.(1, "b4")
    cite.(1, "b5")

    assert %{tone: "warn", value: 1, finding: finding} = Ethos.measure(id, "rigidity", @job)

    assert finding =~
             "habit #3 (checks) is under a change stance and was cited 2 times this window, 2 the one before"

    assert finding =~ "the runaway habit"
    refute finding =~ "#1"
  end

  test "the checking paradox: corrections firing more over three windows", ctx do
    id = ctx.id

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: ctx.key, anchor_ref: "t1", line: "tea", summary: "s", turns_back: 1},
        ctx.brain
      )

    revise = fn text ->
      {:ok, _} =
        Kumbukumbu.revise(
          id,
          %{target_kind: "bookmark", target_id: n, kind: "fact", text: text, note: "I checked"},
          ctx.witness
        )
    end

    revise.("It was Darjeeling.")
    assert %{tone: "silent", value: 1, finding: finding} = Ethos.measure(id, "checking", @job)
    assert finding =~ "(0, 0, 1)" and finding =~ "not read: stated uncertainty"

    Clock.Fake.advance(7 * @day)
    revise.("Assam, in fact.")
    revise.("No: Darjeeling.")

    assert %{tone: "warn", value: 2, finding: finding} = Ethos.measure(id, "checking", @job)
    assert finding =~ "corrections fired 0, 1, 2" and finding =~ "checking paradox"
  end

  test "temporal depth: the moments cited this window reaching far less back than the window before",
       ctx do
    id = ctx.id
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nI remember.", %{}, ctx.witness)
    long_ago = DateTime.add(Clock.now(), -40 * @day, :second)

    old =
      for d <- 0..2 do
        {:ok, n} =
          Kumbukumbu.add_bookmark(
            id,
            %{
              session_key: ctx.key,
              anchor_ref: "t1",
              anchor_at: DateTime.add(long_ago, -d * @day, :second),
              line: "long ago #{d}",
              summary: "s",
              turns_back: 1
            },
            ctx.brain
          )

        n
      end

    for n <- old, do: :ok = Ethos.cite_soul_line(id, 1, "bookmark", n, ctx.brain)
    assert %{tone: "silent", finding: finding} = Ethos.measure(id, "temporal_depth", @job)
    assert finding =~ "read the age of 3 and 0 cited moments" and finding =~ "not read: insight"

    Clock.Fake.advance(8 * @day)

    for ref <- ~w(t2 t3 t4) do
      capture(id, ctx.key, ref, ctx.brain)
      :ok = Ethos.cite_soul_line(id, 1, "turn", ref, ctx.brain)
    end

    assert %{tone: "warn", value: 3, finding: finding} = Ethos.measure(id, "temporal_depth", @job)

    assert finding =~ "median 0 days back, 41 the window before" and
             finding =~ "shrinking temporal depth"
  end
end
