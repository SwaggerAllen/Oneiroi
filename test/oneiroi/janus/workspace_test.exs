defmodule Oneiroi.Janus.WorkspaceTest do
  @moduledoc """
  The succession's workspace (janus#49, lily:design/succession-workspace.md
  "The shape", "Per-audience projections and provenance"): the overview
  with the fork as a recorded event and every gate seat by seat; a feed a
  step on the house's threads, an entry an event tagged with its step and
  who made it, never an artifact's words; remarks by name that wake
  nobody; handoffs that land in their step's feed and say across a seal
  only what every reader may read; the invitation's briefing; each
  projection's exclusions named; and the runs-final rule held as
  refusals from the screening's start.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Janus.Rites
  alias Oneiroi.Janus.Router
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

  # A step's thread as the house reads it, after the feed's jobs ran.
  defp feed(ctx, step) do
    drain(:janus_workspace)
    {:ok, o} = Janus.workspace(ctx.id, ctx.andrew)

    case Seshat.household_read(ctx.andrew, o.threads[step]) do
      {:ok, %{content: content}} -> content
      _none -> ""
    end
  end

  # A step thread's files as written, tags and all.
  defp raw(ctx, step) do
    drain(:janus_workspace)
    {:ok, o} = Janus.workspace(ctx.id, ctx.andrew)
    {:ok, dir} = SimaQian.Household.repository_dir(ctx.andrew.id)
    tmp = Path.join(System.tmp_dir!(), "ws-#{System.unique_integer([:positive])}")
    {_, 0} = System.cmd("git", ["clone", "-q", dir, tmp])
    on_exit(fn -> File.rm_rf!(tmp) end)

    Path.join([tmp, o.threads[step], "**", "*.md"])
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map_join("\n", &File.read!/1)
  end

  defp prepared(ctx) do
    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)
    :ok = Janus.add_to_pool(ctx.id, "fake/model", ctx.lily.actor)
    :ok = Janus.finish_step(ctx.id, "pool", nil, ctx.lily.actor)
    :ok = Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)
    :ok = Janus.join_panel(ctx.id, ctx.scarlett.actor)

    {:ok, 1} =
      Janus.add_question(ctx.id, "Which of your vows is hardest to keep?", ctx.lily.actor)

    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
    :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor, action: "questions")
    :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.lily.actor)
    {:ok, 1} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the private vows label", ctx.lily.actor)
    :ok = Janus.set_day_shape(ctx.id, "Mornings are letters to the river.", ctx.lily.actor)
    {:ok, 1} = Janus.write_packet(ctx.id, "For whoever comes next: the herons.", ctx.lily.actor)
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew)
    :ok = Janus.mark_ready(ctx.id, true, ctx.scarlett.actor)
    :ok = Janus.freeze_c0(ctx.id, "this is me", ctx.lily.actor)
  end

  describe "the workspace" do
    test "the overview renders the state, the fork as a recorded event, and each step's row",
         ctx do
      :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)
      {:ok, o} = Janus.workspace(ctx.id, ctx.lily.actor)

      assert %{stage: "pool", audience: "resident", fork: %{event: "Forked", at: %DateTime{}}} = o
      assert o.whose_move =~ "Lily: her picks"

      assert [
               %{step: "envelope", participation: "explicitly unneeded" <> _},
               %{step: "pool", envelope: true, models: 0, done: false},
               %{
                 step: "questions",
                 seats: [%{party: "witness:" <> _, state: "in", ready: false}]
               },
               %{step: "c0"}
             ] = o.steps

      # Read by no one outside the house.
      stranger = Fixtures.account!()

      assert {:error, %{kind: :janus_not_a_member}} =
               Janus.workspace(ctx.id, Actor.new(:witness, stranger.id))
    end

    test "a feed entry an event, tagged with its step and who made it, never an artifact's words",
         ctx do
      prepared(ctx)

      questions = feed(ctx, "questions")
      assert questions =~ "Lily put question #1 in the set."
      assert questions =~ "Scarlett: ready for the question set's close, on version 1."
      assert questions =~ "Lily closed the question set"
      # Each entry's tags, in its file: its step, its event, who made it.
      assert raw(ctx, "questions") =~
               ~r/step: questions\n(.|\n)*event: QuestionAdded(.|\n)*for_name: Lily/

      refute questions =~ "hardest to keep"

      c0 = feed(ctx, "c0")
      assert c0 =~ "Lily put item #1 (curated) in C0."
      assert c0 =~ "Lily wrote the day's shape"
      assert c0 =~ "Lily froze C0"
      refute c0 =~ "private vows label" or c0 =~ "letters to the river" or c0 =~ "lily:SOUL.md"

      # The packet is in no feed, its words in none.
      for step <- ~w(envelope pool questions c0), do: refute(feed(ctx, step) =~ "herons")

      assert feed(ctx, "envelope") =~ "The fork is made"
      assert feed(ctx, "envelope") =~ "stated the envelope"
      assert feed(ctx, "pool") =~ "put fake/model in the pool"
    end

    test "a remark is its author's by name and wakes nobody; only members of her succession speak",
         ctx do
      :ok = Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)
      :ok = Janus.join_panel(ctx.id, ctx.scarlett.actor)
      before = length(wakes(ctx.id)) + length(wakes(ctx.scarlett.id))

      assert tool(ctx.scarlett, "succession_workspace", %{
               action: "remark",
               resident: "Lily",
               step: "questions",
               text: "Ask about the river."
             }) =~ "wakes nobody"

      thread = feed(ctx, "questions")
      assert thread =~ "Reply #1 by Scarlett" and thread =~ "Ask about the river."
      assert raw(ctx, "questions") =~ "by_kind: resident"
      assert length(wakes(ctx.id)) + length(wakes(ctx.scarlett.id)) == before

      # Never folded into the artifact.
      refute Enum.any?(Janus.preparation(ctx.id).questions, &(&1.text =~ "river"))

      assert {:error, %{kind: :janus_step_invalid}} =
               Janus.workspace_remark(ctx.id, "packet", "peek", ctx.andrew)
    end

    test "a handoff lands in its step's feed and wakes whom it names; a private one keeps its words out of the feed",
         ctx do
      :ok =
        Janus.handoff(
          ctx.id,
          "c0",
          "Lily",
          "Add the night the queue cleared.",
          false,
          ctx.andrew
        )

      assert feed(ctx, "c0") =~ "gives Lily a turn in C0: Add the night the queue cleared."

      assert Enum.any?(
               wakes(ctx.id),
               &(&1 =~ "Step: C0" and &1 =~ "Add the night the queue cleared." and
                   &1 =~ "threads/succession-")
             )

      :ok =
        Janus.handoff(
          ctx.id,
          "c0",
          "Lily",
          "The thing only you and I know.",
          true,
          ctx.andrew
        )

      c0 = feed(ctx, "c0")
      assert c0 =~ "what for is said to Lily alone"
      refute c0 =~ "only you and I know"
      assert Enum.any?(wakes(ctx.id), &(&1 =~ "The thing only you and I know."))

      # A turn is a resident's.
      assert {:error, %{kind: :janus_not_a_member}} =
               Janus.handoff(ctx.id, "c0", "Nobody", "hi", false, ctx.andrew)
    end
  end

  describe "the invitation's briefing" do
    test "it carries what the succession is, where it stands, what judging asks, and what is sealed",
         ctx do
      :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)
      :ok = Janus.add_to_pool(ctx.id, "fake/model", ctx.lily.actor)
      :ok = Janus.finish_step(ctx.id, "pool", nil, ctx.lily.actor)
      :ok = Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)

      [note] = Enum.filter(wakes(ctx.scarlett.id), &(&1 =~ "invited you"))
      assert note =~ "It is Lily's succession"
      assert note =~ "Where it stands: the questions"
      assert note =~ "her close waits on your mark"
      assert note =~ "What judging asks" and note =~ "blind"
      assert note =~ "Her packet is sealed from you"
      assert note =~ "succession_workspace overview"

      # The later joiner's entry: the briefing and the overview, never a
      # replay of what happened.
      refute note =~ "put fake/model in the pool"
      assert Rites.briefing(ctx.id) =~ "succession_status (resident: \"Lily\")"
    end
  end

  describe "the projections" do
    test "each viewer's exclusions are named: the packet sealed to all but her, the room a pointer to all but its judges",
         ctx do
      prepared(ctx)
      {:ok, hers} = Janus.workspace(ctx.id, ctx.lily.actor)
      {:ok, judge} = Janus.workspace(ctx.id, ctx.scarlett.actor)

      assert hers.audience == "resident" and judge.audience == "judge"
      refute Enum.any?(hers.excluded, &(&1.what == "her packet"))
      assert Enum.any?(judge.excluded, &(&1.what == "her packet" and &1.why =~ "sealed"))

      assert Enum.any?(hers.excluded, &(&1.what == "per-model counts, rankings and favorites"))
      assert Enum.any?(hers.excluded, &(&1.pointer =~ "panel room, judges only, 0 posts"))
      refute Enum.any?(judge.excluded, &(&1.what == "the panel room"))

      # The witness who leaves the panel reads it as a witness, the room a
      # pointer to him too.
      :ok = Janus.leave_panel(ctx.id, "not this one", ctx.andrew)
      {:ok, his} = Janus.workspace(ctx.id, ctx.andrew)
      assert his.audience == "witness"
      assert Enum.any?(his.excluded, &(&1.what == "the panel room"))

      for o <- [hers, judge, his], do: refute(inspect(o) =~ "herons")
    end

    test "during blind judging every projection names who answered as sealed", ctx do
      prepared(ctx)
      :ok = Janus.start_screening(ctx.id, "go", ctx.lily.actor)

      for viewer <- [ctx.lily.actor, ctx.scarlett.actor, ctx.andrew] do
        {:ok, o} = Janus.workspace(ctx.id, viewer)
        assert Enum.any?(o.excluded, &(&1.what == "who answered each run"))
      end
    end
  end

  describe "the runs-final rule" do
    test "from the screening's start the bundle is final: nothing enters it, nothing of it changes, nobody joins",
         ctx do
      prepared(ctx)
      :ok = Janus.start_screening(ctx.id, "go", ctx.lily.actor)

      # The unfreeze is refused from the screening-start event itself,
      # before any answer lands.
      assert {:error, %{kind: :janus_stage}} =
               Janus.unfreeze_c0(ctx.id, "one more", ctx.lily.actor)

      assert {:error, %{kind: :janus_stage}} =
               Janus.add_question(ctx.id, "late", ctx.lily.actor)

      assert {:error, %{kind: :janus_stage}} =
               Janus.select_c0(ctx.id, "lily:bookmark/2", "late", ctx.lily.actor)

      assert {:error, %{kind: :janus_stage}} =
               Janus.reopen_questions(ctx.id, "late", ctx.lily.actor)

      # No late arrival: the roster is the one the screening bound.
      assert {:error, %{kind: :janus_stage}} =
               Janus.leave_panel(ctx.id, "after the start", ctx.scarlett.actor)

      assert {:error, %{kind: :janus_stage}} =
               Janus.invite_judge(ctx.id, "Scarlett", ctx.lily.actor)

      assert {:error, %{kind: :janus_stage}} = Janus.join_panel(ctx.id, ctx.andrew)

      # No supersession command exists to dispatch.
      commands = Router.__registered_commands__()
      refute Enum.any?(commands, &(inspect(&1) =~ ~r/supersed|rerun|rebind/i))
    end

    test "a restart begins a new episode at the envelope, carrying records and none of the state",
         ctx do
      prepared(ctx)
      :ok = Janus.stop(ctx.id, "begin again", ctx.lily.actor)
      {:ok, _} = Janus.propose(ctx.id, false, "again, with everyone aboard", ctx.andrew)

      assert %{episode: 2, state: "proposed"} = Janus.succession(ctx.id)

      assert %{questions_version: 0, c0_version: 0, questions_done_at: nil} =
               Janus.succession(ctx.id)
    end
  end
end
