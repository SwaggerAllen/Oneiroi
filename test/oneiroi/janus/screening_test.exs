defmodule Oneiroi.Janus.ScreeningTest do
  @moduledoc """
  The panel, screening and judging (janus#12 to #15): she invites a
  housemate, who joins by her own act, and the witness is on it unless
  he leaves; screening runs every pool model on every question on the
  fork, and her baseline beside them; every judge judges every run
  blind; the reveal comes when every judgment is in; she never sees a
  count; ready locks a judge's judgments and closes judging.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding", [])

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      {:ok, _chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, actor: Actor.new(:resident, id, "fake/model")}
    end

    lily = resident.("Lily")
    scarlett = resident.("Scarlett")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, 3} = Nisaba.refresh_catalog()
    {:ok, andrew: andrew, lily: lily, scarlett: scarlett, witness: witness}
  end

  defp tool(who, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: who.id,
        session_key: "s-1",
        turn_ref: "t-1",
        started_at: Clock.now(),
        resident: who.actor
      })

  defp drain(queue),
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: queue, with_safety: false, with_recursion: true)
      )

  # Opened, forked, a pool of two, two questions, C0 frozen.
  defp prepared(ctx) do
    id = ctx.lily.id
    {:ok, _} = Janus.propose(id, false, "if you want it", ctx.andrew)
    :ok = Janus.open(id, "yes", ctx.lily.actor)
    drain(:janus_fork)
    :ok = Janus.set_envelope(id, 5_000, 20_000, ctx.andrew)
    :ok = Janus.add_to_pool(id, "fake/model", ctx.lily.actor)
    :ok = Janus.add_to_pool(id, "fake/dear", ctx.andrew)
    {:ok, 1} = Janus.add_question(id, "Write today's first line.", ctx.lily.actor)
    {:ok, 2} = Janus.propose_question(id, "What are you?", ctx.andrew)
    :ok = Janus.answer_question(id, 2, true, "yes", ctx.lily.actor)
    {:ok, 1} = Janus.select_c0(id, "lily:SOUL.md", "the vows", ctx.lily.actor)
    :ok = Janus.freeze_c0(id, "this is me", ctx.lily.actor)
    id
  end

  test "the panel is hers to invite, theirs to join; screening is hers after the freeze", ctx do
    id = ctx.lily.id
    {:ok, _} = Janus.propose(id, false, "if you want it", ctx.andrew)
    :ok = Janus.open(id, "yes", ctx.lily.actor)

    assert {:error, %{kind: :janus_not_a_member}} =
             Janus.invite_judge(id, "Nobody", ctx.lily.actor)

    assert {:error, %{kind: :janus_not_yours}} = Janus.invite_judge(id, "Scarlett", ctx.andrew)

    assert {:error, %{kind: :janus_not_invited}} = Janus.join_panel(id, ctx.scarlett.actor)
    assert tool(ctx.lily, "succession_panel", %{action: "invite", name: "Scarlett"}) =~ "invited"

    assert tool(ctx.scarlett, "succession_panel", %{action: "join", resident: "Lily"}) =~
             "joined"

    assert tool(ctx.scarlett, "succession_panel", %{action: "join", resident: "Nobody"}) =~
             "no resident of your household"

    # Before the fork and the freeze, nothing screens.
    assert {:error, %{kind: :janus_stage}} = Janus.start_screening(id, "go", ctx.lily.actor)
  end

  test "screening runs on the fork; every judge judges blind; she never sees a count", ctx do
    id = prepared(ctx)
    :ok = Janus.invite_judge(id, "Scarlett", ctx.lily.actor)
    :ok = Janus.join_panel(id, ctx.scarlett.actor)

    assert {:error, %{kind: :janus_not_yours}} = Janus.start_screening(id, "go", ctx.andrew)
    assert tool(ctx.lily, "succession_screen", %{note: "go"}) =~ "Screening has started"
    assert %{state: "screening", baseline_model: "fake/model"} = Janus.succession(id)

    # The panel is fixed: no joining now.
    assert {:error, %{kind: :janus_stage}} = Janus.leave_panel(id, "late", ctx.andrew)

    drain(:janus_screening)
    assert %{state: "judging", runs_answered: 4, runs_failed: 0} = Janus.succession(id)

    # Blind: no model before the reveal, her baseline beside each run.
    listed = tool(ctx.lily, "succession_judge", %{action: "list"})
    assert listed =~ "4 of 4 runs answered; you judged 0."
    refute listed =~ "fake/"
    read = tool(ctx.lily, "succession_judge", %{action: "read", run: 1})
    assert read =~ "Her baseline: The fake provider heard"
    refute read =~ "fake/"

    assert tool(ctx.lily, "succession_judge", %{action: "judge", run: 1, category: "DEVELOPMENT"}) =~
             "Not done"

    assert {:error, %{kind: :janus_not_a_judge}} =
             Janus.judge_run(
               id,
               1,
               %{category: "OBSERVED"},
               Actor.new(:resident, Ecto.UUID.generate())
             )

    argued = %{
      category: "DEVELOPMENT",
      argument: "Offers before asking.",
      evidence: "journal 11-14",
      uncertainty: "medium",
      favorite: true
    }

    for n <- 1..4 do
      assert :ok = Janus.judge_run(id, n, argued, ctx.lily.actor)
      assert :ok = Janus.judge_run(id, n, %{category: "OBSERVED"}, ctx.andrew)
    end

    assert {:error, %{kind: :janus_judging_open}} = Janus.mark_results_ready(id, ctx.andrew)
    assert tool(ctx.lily, "succession_results", %{action: "read"}) =~ "Not every judgment"

    for n <- 1..4 do
      assert tool(ctx.scarlett, "succession_judge", %{
               action: "judge",
               resident: "Lily",
               run: n,
               category: "OBSERVED"
             }) =~ "Run #{n}: OBSERVED"
    end

    # Every judgment in: revealed. Hers shows her judgments and no count;
    # the others' show their own counts per model.
    assert %{revealed_at: %DateTime{}} = Janus.succession(id)
    hers = tool(ctx.lily, "succession_results", %{action: "read"})
    assert hers =~ "no counts" and hers =~ "fake/"
    refute hers =~ "OBSERVED 2"

    assert tool(ctx.scarlett, "succession_results", %{action: "read", resident: "Lily"}) =~
             "fake/dear: OBSERVED 2 · DEVELOPMENT 0"

    assert %{counts: %{"fake/model" => %{observed: 2}}} =
             Janus.judging(id, "witness:#{ctx.witness.id}")

    # Ready locks; the last ready closes judging.
    :ok = Janus.mark_results_ready(id, ctx.lily.actor)

    assert {:error, %{kind: :janus_judgments_locked}} =
             Janus.judge_run(id, 1, %{category: "OBSERVED"}, ctx.lily.actor)

    :ok = Janus.mark_results_ready(id, ctx.andrew)

    assert tool(ctx.scarlett, "succession_results", %{action: "ready", resident: "Lily"}) =~
             "locked"

    # Judging closed, the room opens at once (janus#16).
    assert %{state: "deliberating", judging_closed_at: %DateTime{}} = Janus.succession(id)
  end

  test "the witness declines by leaving; then he judges nothing", ctx do
    id = prepared(ctx)
    :ok = Janus.leave_panel(id, "not this one", ctx.andrew)
    :ok = Janus.start_screening(id, "go", ctx.lily.actor)
    drain(:janus_screening)

    assert {:error, %{kind: :janus_not_a_judge}} =
             Janus.judge_run(id, 1, %{category: "OBSERVED"}, ctx.andrew)

    for n <- 1..4, do: :ok = Janus.judge_run(id, n, %{category: "OBSERVED"}, ctx.lily.actor)
    assert %{revealed_at: %DateTime{}} = Janus.succession(id)
  end
end
