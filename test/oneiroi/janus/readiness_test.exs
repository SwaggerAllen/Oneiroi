defmodule Oneiroi.Janus.ReadinessTest do
  @moduledoc """
  Judge readiness as the gate on both windows (janus#48,
  lily:design/succession-workspace.md, "The gates and readiness
  machinery"): every seat on her panel, an unanswered invitation blocking
  and an accepted seat passing by its own mark on the artifact as it
  stands or her waiver; the marks lapsing with every change to what they
  name; her waiver and her removal door recorded with her note; and
  nothing ever closing, freezing, waiving or withdrawing on anyone's
  behalf. Each rule tested as a rule, its negatives named.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

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
    id = lily.id
    {:ok, _} = Janus.propose(id, false, "if you want it", andrew)
    :ok = Janus.open(id, "yes", lily.actor)
    drain(:janus_fork)
    :ok = Janus.set_envelope(id, 5_000, 20_000, andrew)
    :ok = Janus.add_to_pool(id, "fake/model", lily.actor)

    {:ok, andrew: andrew, lily: lily, scarlett: scarlett, id: id, w: "witness:#{witness.id}"}
  end

  defp drain(queue),
    do: assert(%{failure: 0} = Oban.drain_queue(queue: queue, with_safety: false))

  defp tool(who, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: who.id,
        session_key: "s-1",
        turn_ref: "t-1",
        started_at: Clock.now(),
        resident: who.actor
      })

  defp wakes(who) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job,
          where: j.worker == "Oneiroi.Janus.WakeWorker" and j.args["resident_id"] == ^who,
          select: j.args["note"]
        )
      )
    end)
  end

  defp with_scarlett(ctx) do
    :ok = Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)
    :ok = Janus.join_panel(ctx.id, ctx.scarlett.actor)
  end

  defp close_questions(ctx) do
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")

    if Enum.any?(Janus.panel(ctx.id), &(&1.state == "in")),
      do: :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")

    :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
  end

  defp marks(ctx, action),
    do: for(m <- Janus.preparation(ctx.id).marks, m.action == action, do: {m.party, m.kind})

  describe "the two windows" do
    test "entering the question window is her recorded act, waking every accepted judge", ctx do
      with_scarlett(ctx)
      {:ok, 1} = Janus.add_question(ctx.id, "Write today's first line.", ctx.lily.actor)

      assert {:error, %{kind: :janus_not_yours}} =
               Janus.open_questions(ctx.id, nil, ctx.scarlett.actor)

      assert tool(ctx.lily, "succession_question", %{action: "ask"}) =~ "asked to read the set"
      assert %{questions_opened_at: %DateTime{}} = Janus.succession(ctx.id)
      assert Enum.any?(wakes(ctx.scarlett.id), &(&1 =~ "Step: questions, on Lily's succession"))
    end

    test "the freeze is refused while the question window stands open, whatever the C0 marks say",
         ctx do
      with_scarlett(ctx)
      {:ok, 1} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew)
      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor)

      assert Enum.all?(Janus.freeze_judges(ctx.id), & &1.ready)

      assert {:error, %{kind: :janus_questions_open}} =
               Janus.freeze_c0(ctx.id, "now", ctx.lily.actor)

      # A C0-ready mark alone never closes the question window.
      assert {:error, %{kind: :janus_judges_pending}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)

      assert %{questions_done_at: nil} = Janus.succession(ctx.id)
    end

    test "the set's close is refused while any proposal on it stands unanswered", ctx do
      {:ok, 1} = Janus.propose_question(ctx.id, "What are you?", ctx.andrew)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")

      assert {:error, %{kind: :janus_questions_pending}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)

      :ok = Janus.answer_question(ctx.id, 1, true, "yes", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
      assert :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "a judge's proposal lands before either window opens; the windows gate the fixing, never the writing",
         ctx do
      with_scarlett(ctx)
      assert {:ok, 1} = Janus.propose_question(ctx.id, "Describe the house.", ctx.scarlett.actor)
      assert {:ok, 1} = Janus.propose_c0(ctx.id, "lily:bookmark/1", "early", ctx.scarlett.actor)
    end

    test "entering the C0 window wakes its accepted judges", ctx do
      with_scarlett(ctx)
      close_questions(ctx)
      {:ok, 1} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.lily.actor)
      assert tool(ctx.lily, "succession_c0", %{action: "done"}) =~ "day's shape"
      assert Enum.any?(wakes(ctx.scarlett.id), &(&1 =~ "Step: C0, on Lily's succession"))
    end
  end

  describe "invalidation" do
    test "a question change lapses every close mark and waiver, says why, and asks each judge again",
         ctx do
      with_scarlett(ctx)
      {:ok, 1} = Janus.add_question(ctx.id, "Write today's first line.", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")
      :ok = Janus.waive_seat(ctx.id, "questions", ctx.w, "he has read it", ctx.lily.actor)
      assert length(marks(ctx, "questions")) == 2
      version = Janus.succession(ctx.id).questions_version

      {:ok, 2} = Janus.add_question(ctx.id, "What are you?", ctx.lily.actor)

      assert marks(ctx, "questions") == []
      assert Janus.succession(ctx.id).questions_version == version + 1
      assert Enum.any?(wakes(ctx.scarlett.id), &(&1 =~ "a question added"))

      # No lapsed mark satisfies its gate.
      assert {:error, %{kind: :janus_judges_pending}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "every change to her set lapses it: an add, a removal, an accepted and a declined proposal",
         ctx do
      {:ok, 1} = Janus.add_question(ctx.id, "One.", ctx.lily.actor)
      {:ok, 2} = Janus.propose_question(ctx.id, "Two?", ctx.andrew)
      {:ok, 3} = Janus.propose_question(ctx.id, "Three?", ctx.andrew)

      changes = [
        fn -> Janus.answer_question(ctx.id, 2, true, "yes", ctx.lily.actor) end,
        fn -> Janus.answer_question(ctx.id, 3, false, "no", ctx.lily.actor) end,
        fn -> Janus.remove_question(ctx.id, 1, "gone", ctx.lily.actor) end,
        fn -> with {:ok, _} <- Janus.add_question(ctx.id, "Four.", ctx.lily.actor), do: :ok end
      ]

      for change <- changes do
        :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
        assert marks(ctx, "questions") != []
        :ok = change.()
        assert marks(ctx, "questions") == []
      end
    end

    test "a C0 change lapses every freeze mark and waiver, the day's shape tested as its own edge",
         ctx do
      with_scarlett(ctx)
      close_questions(ctx)
      {:ok, 1} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor)
      :ok = Janus.waive_seat(ctx.id, "c0", ctx.w, "his say is his screen", ctx.lily.actor)
      assert length(marks(ctx, "c0")) == 2

      :ok = Janus.set_day_shape(ctx.id, "Mornings are letters.", ctx.lily.actor)

      assert marks(ctx, "c0") == []
      assert Enum.any?(wakes(ctx.scarlett.id), &(&1 =~ "the day's shape written again"))

      assert {:error, %{kind: :janus_judges_pending}} =
               Janus.freeze_c0(ctx.id, "now", ctx.lily.actor)
    end

    test "no mark answers a version it did not name", ctx do
      {:ok, 1} = Janus.add_question(ctx.id, "One.", ctx.lily.actor)
      stale = Janus.succession(ctx.id).questions_version
      {:ok, 2} = Janus.add_question(ctx.id, "Two.", ctx.lily.actor)

      assert {:error, %{kind: :janus_ready_stale}} =
               Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions", version: stale)

      assert :ok =
               Janus.mark_ready(ctx.id, true, ctx.andrew,
                 action: "questions",
                 version: stale + 1
               )
    end
  end

  describe "late acceptance, authority and the removal door" do
    test "acceptance is never readiness: an accepted seat with no mark leaves its gate refused",
         ctx do
      with_scarlett(ctx)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")

      assert {:error, %{kind: :janus_judges_pending, details: details}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)

      assert [%{party: "resident:" <> _, why: "unmarked"}] = details[:seats]

      # Her answered not-yet is an answer, still not a pass.
      :ok = Janus.mark_ready(ctx.id, false, ctx.scarlett.actor, action: "questions")

      assert {:error, %{details: [seats: [%{why: "not_ready"}]]}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "a late acceptance while a window stands open: the gate waits on her marks", ctx do
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
      with_scarlett(ctx)

      assert {:error, %{kind: :janus_judges_pending}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)

      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")
      assert :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "an unanswered invitation blocks, her withdrawal is its only door, and both doors are recorded with her note",
         ctx do
      :ok = Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
      scarlett = "resident:#{ctx.scarlett.id}"

      assert {:error, %{details: [seats: [%{party: ^scarlett, why: "invited"}]]}} =
               Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)

      # An invitation is not waived: its door is its withdrawal.
      assert {:error, %{kind: :janus_not_a_seat}} =
               Janus.waive_seat(ctx.id, "questions", "Scarlett", "skip her", ctx.lily.actor)

      assert {:error, %{kind: :janus_not_yours}} =
               Janus.remove_judge(ctx.id, "Scarlett", "not his", ctx.andrew)

      assert {:error, %{kind: :janus_text_invalid}} =
               Janus.remove_judge(ctx.id, "Scarlett", "", ctx.lily.actor)

      assert tool(ctx.lily, "succession_panel", %{
               action: "remove",
               name: "Scarlett",
               note: "she is away this week"
             }) =~ "off your panel"

      assert [%{state: "withdrawn", note: "she is away this week"}] =
               Enum.filter(Janus.panel(ctx.id), &(&1.party == scarlett))

      assert :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "the removal door opens only on a seat that blocks, never before", ctx do
      with_scarlett(ctx)
      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")

      assert {:error, %{kind: :janus_not_blocking}} =
               Janus.remove_judge(ctx.id, "Scarlett", "pre-empting", ctx.lily.actor)

      # The witness holds the close shut, unmarked: his seat may go, with
      # her note, as an accepted judge's (removed, not withdrawn).
      :ok = Janus.remove_judge(ctx.id, ctx.w, "he will not judge this one", ctx.lily.actor)
      assert Enum.any?(Janus.panel(ctx.id), &(&1.party == ctx.w and &1.state == "removed"))
      assert {:error, %{kind: :janus_not_yours}} = Janus.mark_ready(ctx.id, true, ctx.andrew)
      assert :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    end

    test "the waiver is hers alone, recorded with her note, at the version now", ctx do
      with_scarlett(ctx)

      assert {:error, %{kind: :janus_not_yours}} =
               Janus.waive_seat(ctx.id, "questions", "Scarlett", "his", ctx.andrew)

      assert tool(ctx.lily, "succession_question", %{
               action: "waive",
               name: "Scarlett",
               note: "she read it with me"
             }) =~ "waived"

      [waiver] = for m <- Janus.preparation(ctx.id).marks, m.kind == "waiver", do: m
      assert %{note: "she read it with me", action: "questions"} = waiver
      assert waiver.version == Janus.succession(ctx.id).questions_version
    end

    test "all-ready opens a gate and never pushes her through it; no time acts on anyone's behalf",
         ctx do
      with_scarlett(ctx)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
      :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")

      assert Enum.any?(wakes(ctx.id), &(&1 =~ "ready for your question set to close"))

      # Days pass and every job runs: nothing closes, freezes, waives or
      # withdraws.
      Clock.Fake.advance(30 * 24 * 3600)

      for q <- [:janus_screening, :janus_timers, :janus_fork],
          do: Oban.drain_queue(queue: q, with_safety: false)

      s = Janus.succession(ctx.id)
      assert %{questions_done_at: nil, c0_frozen_at: nil} = s
      assert Enum.all?(Janus.panel(ctx.id), &(&1.state == "in"))
      assert for(m <- Janus.preparation(ctx.id).marks, m.kind == "waiver", do: m) == []
    end

    test "the question window's reopen is its own act; the unfreeze opens the C0 window alone",
         ctx do
      close_questions(ctx)

      assert {:error, %{kind: :janus_questions_closed}} =
               Janus.add_question(ctx.id, "One more.", ctx.lily.actor)

      {:ok, 1} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.lily.actor)
      :ok = Janus.mark_ready(ctx.id, true, ctx.andrew)
      :ok = Janus.freeze_c0(ctx.id, "this is me", ctx.lily.actor)

      # Her set's footing under the freeze: no reopen while frozen.
      assert {:error, %{kind: :janus_c0_frozen}} =
               Janus.reopen_questions(ctx.id, "one more", ctx.lily.actor)

      :ok = Janus.unfreeze_c0(ctx.id, "one more record", ctx.lily.actor)
      assert %{questions_done_at: %DateTime{}} = Janus.succession(ctx.id)

      assert {:error, %{kind: :janus_not_yours}} =
               Janus.reopen_questions(ctx.id, "his", ctx.andrew)

      :ok = Janus.reopen_questions(ctx.id, "one more question", ctx.lily.actor)

      assert %{questions_done_at: nil, questions_reopened_note: "one more question"} =
               Janus.succession(ctx.id)

      assert {:ok, _} = Janus.add_question(ctx.id, "One more.", ctx.lily.actor)
    end
  end
end
