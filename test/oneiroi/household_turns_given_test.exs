defmodule Oneiroi.HouseholdTurnsGivenTest do
  @moduledoc """
  The beats' turns as they read and run (2026-11-18, Scarlett's turn
  #15): one who has had her share is not listed as waiting (gaia#51); an
  empty answer does not spend a turn without one more wake (seshat#88);
  a witness can give a resident a turn now (gaia#52). The in-memory
  provider; no network.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.HouseholdBallotWorker
  alias Oneiroi.Seshat.HouseholdTurnWorker
  alias Oneiroi.SimaQian

  @zone "Etc/UTC"

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    Clock.Fake.put(~U[2026-11-11 09:00:00.000000Z])
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "the founding version")

    ada = resident!(witness, "Ada")
    bea = resident!(witness, "Bea")
    cy = resident!(witness, "Cy")
    household = witness.id

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(household))
      for r <- [ada, bea, cy], do: Fake.clear(for: r.id)
    end)

    {:ok, household: household, witness: witness, andrew: andrew, ada: ada, bea: bea, cy: cy}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    Fixtures.agreed!(id, witness.id)
    :ok = AgathosDaimon.set_timezone(id, @zone, actor)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    Clock.Fake.advance(1)
    %{id: id, slug: slug, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp run(name, args, r),
    do:
      Tools.run(
        name,
        Jason.encode!(args),
        %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.slug}", resident: r.actor}
      )

  defp tick(household), do: assert(:ok = Seshat.tick_household_beats(household))
  defp beats(household), do: Gaia.household_beats(household, Clock.now())
  defp open_turn(household), do: beats(household).open_turn
  defp shape(household), do: Gaia.household_beat_shape(household)

  # The beat after the one now, and the clock put at an offset into it.
  defp next_top(household) do
    s = shape(household)
    Beats.ends(Beats.top(household, s, Clock.now()), s)
  end

  defp put(at), do: Clock.Fake.put(at)

  defp turn_jobs(household),
    do:
      for(
        j <- all_enqueued(worker: HouseholdTurnWorker),
        j.args["household_id"] == household,
        j.args["turn"],
        do: j.args["turn"]
      )

  defp digest_jobs(household),
    do:
      for(
        j <- all_enqueued(worker: HouseholdTurnWorker),
        j.args["household_id"] == household,
        j.args["digest"],
        do: {j.args["digest"], j.args["beat_top"]}
      )

  # Runs a fired turn's job: the wake answers, the turn ends with it, and
  # the next ready resident fires.
  defp run_turn(household, r, number) do
    Fake.reply("Thank you; I've read the shelf.", for: r.id)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{"household_id" => household, "turn" => number})
  end

  defp in_turn(household, r, fun) do
    Clock.Fake.advance(1)
    {:ok, %{turn: turn}} = Seshat.household_open_turn(household, r.id, "the suite")
    result = fun.()
    :ok = Seshat.household_end_turn(household, turn, "the suite's writes are in")
    result
  end

  defp system_lines(witness, r) do
    {:ok, _session, messages} = Kumbukumbu.transcript({:account, witness.id}, r.chat)
    for m <- messages, m.role == "system", do: m.content
  end

  defp missed(household, r),
    do: Enum.find(beats(household).profiles, &(&1.id == r.id)).missed

  defp fire_first(h, r) do
    assert run("household_register", %{}, r) =~ "Registered for the beat at"
    [%{beat_top: waits} | _] = beats(h).registrations
    put(Beats.signup_closes(waits, shape(h)))
    tick(h)
    assert %{resident_id: id, turn: n} = open_turn(h)
    assert id == r.id
    n
  end

  test "one who has had her turn is not waiting: the queue drops her and her view says so", ctx do
    %{household: h, ada: ada} = ctx
    n = fire_first(h, ada)
    run_turn(h, ada, n)

    b = beats(h)
    assert b.queue == []
    assert [%{resident_id: id}] = b.had_turn
    assert id == ada.id

    said = run("household_beat", %{}, ada)
    assert said =~ "You have had your turn in the beat now"
    assert said =~ "Nobody is waiting."
  end

  test "an empty answer is woken once more in the same turn; a second empty one ends it", ctx do
    %{household: h, ada: ada} = ctx
    n = fire_first(h, ada)

    # Both wakes answer with nothing at all.
    Fake.reply("", for: ada.id)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{"household_id" => h, "turn" => n})

    [turn | _] = Enum.reverse(beats(h).beat.turns)
    assert turn.outcome == "completed"
    assert turn.note =~ "empty twice"

    notes = system_lines(ctx.witness, ada)
    assert Enum.any?(notes, &(&1 =~ "your last answer came back empty"))
  end

  test "a witness gives a resident a turn now, run as a scheduled one; not while one is open",
       ctx do
    %{household: h, ada: ada, bea: bea} = ctx

    assert {:ok, %{turn: n, resident_id: id, opened_by: "witness"}} =
             Seshat.household_grant_turn(ctx.andrew, ada.id)

    assert id == ada.id
    assert n in turn_jobs(h)

    assert {:error, %{kind: :gaia_turn_open}} = Seshat.household_grant_turn(ctx.andrew, bea.id)
    assert {:error, _} = Seshat.household_grant_turn(bea.actor, ada.id)

    run_turn(h, ada, n)
    assert open_turn(h) == nil
  end
end
