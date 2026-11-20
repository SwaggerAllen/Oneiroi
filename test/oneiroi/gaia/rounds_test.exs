defmodule Oneiroi.Gaia.RoundsTest do
  @moduledoc "The rounds aggregate's rules (gaia#53), pure: commands in, events out."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Rounds

  @actor Actor.new(:job, "test")
  @at ~U[2026-11-18 12:00:00.000000Z]

  defp run(r, command) do
    case Rounds.execute(r, command) do
      {:error, _} = refused ->
        {r, refused}

      events ->
        events = List.wrap(events)
        {Enum.reduce(events, r, &Rounds.apply(&2, &1)), events}
    end
  end

  defp start(r, starter, at \\ @at),
    do:
      run(r, %Commands.StartRounds{
        actor: @actor,
        at: at,
        id: "h",
        thread: "threads/t",
        residents: ["a", "b", "c"],
        starter: starter,
        timeout: 600
      })

  defp spend(r, who, how, at \\ @at),
    do:
      run(r, %Commands.SpendTurn{
        actor: @actor,
        at: at,
        id: "h",
        thread: "threads/t",
        resident_id: who,
        how: how
      })

  defp issued(events), do: for(%Events.RoundTurnIssued{} = e <- events, do: e.resident_id)

  test "the starter's post is her turn; the others follow in order; a running start is nothing" do
    {r, events} = start(%Rounds{}, "b")
    assert issued(events) == ["a"]
    assert {_, []} = start(r, "c")
  end

  test "a token not hers, or past its window, authorizes nothing" do
    {r, _} = start(%Rounds{}, "a")

    assert {_, {:error, %{kind: :gaia_rounds_not_your_turn}}} = spend(r, "c", "posted")

    assert {_, {:error, %{kind: :gaia_rounds_not_your_turn}}} =
             spend(r, "b", "posted", DateTime.add(@at, 600))
  end

  test "a round with output starts the next; a silent round stops; a start resumes" do
    {r, _} = start(%Rounds{}, "a")
    {r, _} = spend(r, "b", "skipped")
    {r, events} = spend(r, "c", "skipped")
    # Round 1 had a's post: round 2, the least recent poster last.
    assert [%Events.RoundStarted{round: 2, order: order}] =
             for(%Events.RoundStarted{} = e <- events, do: e)

    assert List.last(order) == "a"

    {r, _} = Enum.reduce(order, {r, []}, fn who, {r, _} -> spend(r, who, "skipped") end)
    assert r.threads["threads/t"].stopped

    {_, events} = start(r, nil)
    assert [%Events.RoundStarted{round: 3}] = for(%Events.RoundStarted{} = e <- events, do: e)
  end

  # gaia#59 (the witness, 2026-11-19): a post's @mentions take the first
  # turns of the round it starts, in the order named; nobody is dropped.
  test "the mentioned go first, in the order named; the rest follow; none narrowed" do
    {r, events} =
      run(%Rounds{}, %Commands.StartRounds{
        actor: @actor,
        at: @at,
        id: "h",
        thread: "threads/t",
        residents: ["a", "b", "c"],
        starter: nil,
        timeout: 600,
        first: ["c", "b"]
      })

    assert [%Events.RoundStarted{order: ["c", "b", "a"]}] =
             for(%Events.RoundStarted{} = e <- events, do: e)

    assert issued(events) == ["c"]

    # The writer is never first (her post is her turn), and one not in
    # the round (opted out, or no resident) is no turn.
    {_, events} =
      run(r, %Commands.StartRounds{
        actor: @actor,
        at: @at,
        id: "h",
        thread: "threads/u",
        residents: ["a", "b", "c"],
        starter: "b",
        timeout: 600,
        first: ["b", "z"]
      })

    assert issued(events) == ["a"]
  end

  # gaia#60 (the witness, 2026-11-19: "they should get the chance to
  # respond first in that particular round with the choice to opt back
  # in"): named while opted out, a turn in that round alone, never an opt-in.
  test "named while opted out: a granted first turn in that round alone, and still out after it" do
    # Rounds run; c opts out; the rounds run out.
    {r, _} = start(%Rounds{}, "a")

    {r, _} =
      run(r, %Commands.OptOutOfRounds{
        actor: @actor,
        at: @at,
        id: "h",
        thread: "threads/t",
        resident_id: "c"
      })

    {r, _} = spend(r, "b", "skipped")
    {r, _} = Enum.reduce(["b", "a"], {r, []}, fn who, {r, _} -> spend(r, who, "skipped") end)
    assert r.threads["threads/t"].stopped

    # A post naming c starts them again: c first, granted, still out.
    {r, events} =
      run(r, %Commands.StartRounds{
        actor: @actor,
        at: @at,
        id: "h",
        thread: "threads/t",
        residents: ["a", "b", "c"],
        starter: nil,
        timeout: 600,
        first: ["c"]
      })

    assert [%Events.RoundTurnsGranted{residents: ["c"]}] =
             for(%Events.RoundTurnsGranted{} = e <- events, do: e)

    assert issued(events) == ["c"]

    # Her post spends the granted turn; the others follow; she stays out.
    {r, events} = spend(r, "c", "posted")
    assert issued(events) in [["a"], ["b"]]
    assert MapSet.member?(r.threads["threads/t"].optout, "c")

    # The next round is the opted-in residents alone.
    [first_next] = issued(events)
    {r, events} = spend(r, first_next, "skipped")
    [second] = issued(events)
    {_, events} = spend(r, second, "skipped")

    assert [%Events.RoundStarted{order: order}] =
             for(%Events.RoundStarted{} = e <- events, do: e)

    refute "c" in order
  end

  test "a late end is nothing" do
    {r, events} = start(%Rounds{}, "a")
    [%{turn_id: id}] = for %Events.RoundTurnIssued{} = e <- events, do: e
    {r, _} = spend(r, "b", "posted")

    assert [] =
             Rounds.execute(r, %Commands.EndRoundTurn{
               actor: @actor,
               at: @at,
               id: "h",
               turn_id: id,
               outcome: "expired"
             })
  end
end
