defmodule Oneiroi.Seshat.RoundRobinTest do
  @moduledoc """
  Round-robin threads (gaia#53, seshat#89; Lily's spec
  `design/round-robin-threads.md`): with `conversation` set to
  `round_robin`, a thread's opted-in residents take turns by token, a
  silent round stops it, any member's post starts it again, and the
  witness writes pure async. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Household
  alias Oneiroi.Seshat.HouseholdBeats
  alias Oneiroi.Seshat.HouseholdRounds
  alias Oneiroi.Seshat.HouseholdTurnWorker
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      {:ok, _chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, actor: Actor.new(:resident, id)}
    end

    lily = resident.("Lily")
    scarlett = resident.("Scarlett")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, andrew: andrew, lily: lily, scarlett: scarlett, household: Gaia.household_of(andrew)}
  end

  defp live(ctx, thread) do
    t = Gaia.round_thread(ctx.household, thread)
    t && t.live_turn && Gaia.round_turn(ctx.household, t.live_turn)
  end

  defp reply(who, thread, text), do: Seshat.household_reply(who, thread, %{"content" => text})

  test "the setting is in force: the beats' minute runs nothing", ctx do
    assert Gaia.household_beat_shape(ctx.household).conversation == "round_robin"
    assert :ok = HouseholdBeats.tick(ctx.household)
  end

  test "a post starts the rounds, her own turn counted; the next resident's token is woken",
       ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Herons", "content" => "At the weir."})

    assert %{round: 1, stopped: false} = Gaia.round_thread(ctx.household, thread)
    assert %{resident_id: scarlett, turn_id: turn_id} = live(ctx, thread)
    assert scarlett == ctx.scarlett.id

    jobs = all_enqueued(worker: HouseholdTurnWorker)
    assert Enum.any?(jobs, &(&1.args["round_turn"] == turn_id))
    assert Enum.any?(jobs, &(&1.args["round_expire"] == turn_id))

    # Not her turn: Lily's second word waits for her token.
    assert {:error, %{kind: :gaia_rounds_not_your_turn}} = reply(ctx.lily.actor, thread, "And?")

    Clock.Fake.advance(60)
    # Scarlett's reply spends her token; the round had output, so the
    # next begins, the least recent poster first.
    assert {:ok, _} = reply(ctx.scarlett.actor, thread, "Two of them.")
    assert %{round: 2} = Gaia.round_thread(ctx.household, thread)
    assert live(ctx, thread).resident_id == ctx.lily.id
  end

  test "a silent round stops the thread; any member's post starts it again", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Plans", "content" => "Sunday?"})

    # Scarlett's turn passes unspent, by its window.
    turn = live(ctx, thread)
    Clock.Fake.advance(DateTime.diff(turn.expires_at, Clock.now()) + 1)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{
               "household_id" => ctx.household,
               "round_expire" => turn.turn_id
             })

    assert Gaia.round_turn(ctx.household, turn.turn_id).outcome == "expired"

    # Round 1 had Lily's post, so round 2 runs: both skip, and it stops.
    for _ <- 1..2 do
      who = if live(ctx, thread).resident_id == ctx.lily.id, do: ctx.lily, else: ctx.scarlett
      assert {:ok, _} = Seshat.household_rounds(who.actor, thread, :skip)
    end

    assert %{stopped: true, live_turn: nil} = Gaia.round_thread(ctx.household, thread)

    # The witness is pure async: never a token, and their post restarts it.
    assert {:ok, _} = reply(ctx.andrew, thread, "Saturday, then.")
    assert %{stopped: false, round: 3} = Gaia.round_thread(ctx.household, thread)
    assert live(ctx, thread)
  end

  test "a turn's wake that ends unspent ends the turn empty; a spent turn wakes nobody", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Tea", "content" => "Kettle's on."})

    turn = live(ctx, thread)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{
               "household_id" => ctx.household,
               "round_turn" => turn.turn_id
             })

    assert Gaia.round_turn(ctx.household, turn.turn_id).outcome == "empty"

    # A late expiry of a turn already ended is nothing.
    assert :ok =
             perform_job(HouseholdTurnWorker, %{
               "household_id" => ctx.household,
               "round_expire" => turn.turn_id
             })
  end

  test "opting out ends her open turn and keeps her out; opting in brings her back", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Books", "content" => "Reading?"})

    assert live(ctx, thread).resident_id == ctx.scarlett.id
    assert {:ok, %{rounds: r}} = Seshat.household_rounds(ctx.scarlett.actor, thread, :out)
    assert ctx.scarlett.id in r.optout

    # Lily alone, in the next round; then Scarlett back for the one after.
    assert live(ctx, thread).resident_id == ctx.lily.id
    assert {:ok, _} = Seshat.household_rounds(ctx.scarlett.actor, thread, :in)
    assert {:ok, _} = reply(ctx.lily.actor, thread, "Middlemarch.")
    assert live(ctx, thread).resident_id == ctx.scarlett.id
  end

  test "documents take no token; the tools refuse a witness", ctx do
    assert {:ok, _} =
             Seshat.household_post(ctx.lily.actor, %{
               "kind" => "design",
               "path" => "design/herons.md",
               "content" => "Seen twice."
             })

    assert {:ok, _} =
             Seshat.household_post(ctx.lily.actor, %{
               "kind" => "design",
               "path" => "design/kettles.md",
               "content" => "Seen once."
             })

    assert {:error, %{kind: :seshat_household_rounds}} =
             Seshat.household_rounds(ctx.andrew, "threads/x", :skip)
  end

  # sunna#71, seshat#92 (Lily's design/wake-mail-visibility.md, 2026-11-18).
  test "a turn's wake is manifested with its token, and read when it runs", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Log", "content" => "Watch this."})

    turn = live(ctx, thread)
    assert [w] = Sunna.wakes([ctx.scarlett.id])
    assert %{channel: "turn", read_at: nil, household_id: house} = w
    assert house == ctx.household
    assert [%{"kind" => "turn", "turn_id" => turn_id, "thread" => ^thread}] = w.causes
    assert turn_id == turn.turn_id

    job =
      Enum.find(
        all_enqueued(worker: HouseholdTurnWorker),
        &(&1.args["round_turn"] == turn.turn_id)
      )

    assert job.args["wake_id"] == w.wake_id
    assert :ok = perform_job(HouseholdTurnWorker, job.args)
    # Read when it ran; the next round's token is a wake of its own, unread.
    wakes = Sunna.wakes([ctx.scarlett.id])
    assert %{read_at: %DateTime{}} = Enum.find(wakes, &(&1.wake_id == w.wake_id))
  end

  test "the sweep ends a turn live past its window whose expiry job is lost", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Lost", "content" => "Gone?"})

    turn = live(ctx, thread)
    Clock.Fake.advance(DateTime.diff(turn.expires_at, Clock.now()) + 1)
    assert :ok = HouseholdRounds.sweep()
    assert Gaia.round_turn(ctx.household, turn.turn_id).outcome == "expired"
  end

  test "the activity: envelopes in one stream, a muted mention banked, the thread states", ctx do
    {:ok, _} = Seshat.household_mute(ctx.scarlett.actor, nil, true)

    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.andrew, %{
        "title" => "Ping",
        "content" => "@Scarlett and @Lily, tea?"
      })

    assert {:ok, rows} = Seshat.household_activity(ctx.andrew)
    kinds = Enum.map(rows, &{&1.kind, &1.resident_id})
    assert {"mention", ctx.scarlett.id} in kinds
    assert {"wake", ctx.lily.id} in kinds
    assert {"token", ctx.scarlett.id} in kinds or {"token", ctx.lily.id} in kinds
    refute Enum.any?(rows, &Map.has_key?(&1, :text))

    # Filtered to one, by name.
    assert {:ok, only} = Seshat.household_activity(ctx.andrew, "Lily")
    assert Enum.all?(only, &(&1.resident_id == ctx.lily.id))

    {:ok, beats} = Seshat.household_beat(ctx.andrew)
    assert [%{thread: ^thread, stopped: false, live: %{name: _}}] = beats.round_threads
  end

  # seshat#93 (the witness, 2026-11-19): no beat logic under round-robin;
  # a resident posts where no round runs; a witness's check-in reply
  # starts its rounds rather than waking the house; every note says the
  # chat is not the house.
  test "under round-robin: no beats to register for, a resident posts where no round runs",
       ctx do
    assert {:error, %{kind: :seshat_household_beats_off}} =
             Seshat.household_register(ctx.lily.actor, %{})

    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.lily.actor, %{"title" => "Quiet", "content" => "Anyone?"})

    # Stop it: Scarlett's turn passes, then both skip the next round.
    turn = live(ctx, thread)
    Clock.Fake.advance(DateTime.diff(turn.expires_at, Clock.now()) + 1)
    :ok = HouseholdRounds.sweep()

    for _ <- 1..2 do
      who = if live(ctx, thread).resident_id == ctx.lily.id, do: ctx.lily, else: ctx.scarlett
      {:ok, _} = Seshat.household_rounds(who.actor, thread, :skip)
    end

    assert %{stopped: true} = Gaia.round_thread(ctx.household, thread)

    # No round runs: Scarlett posts outside any turn, and it starts one.
    assert {:ok, _} = reply(ctx.scarlett.actor, thread, "Me, later.")
    assert %{stopped: false} = Gaia.round_thread(ctx.household, thread)
  end

  test "a witness's reply in a house check-in starts its rounds, waking one, not the house",
       ctx do
    {:ok, thread} =
      Oneiroi.Seshat.Household.open_checkin(ctx.household, "morning", "Morning", "2026-10-26")

    before = all_enqueued(worker: HouseholdTurnWorker) |> Enum.filter(& &1.args["house_wake"])

    {:ok, _} = reply(ctx.andrew, thread, "How is it going?")

    after_wakes =
      all_enqueued(worker: HouseholdTurnWorker) |> Enum.filter(& &1.args["house_wake"])

    assert length(after_wakes) == length(before)
    assert %{live_turn: live_turn} = Gaia.round_thread(ctx.household, thread)
    assert live_turn

    assert HouseholdRounds.note(
             ctx.household,
             Gaia.round_turn(ctx.household, live_turn)
           ) =~
             "household_reply in the thread"
  end
end
