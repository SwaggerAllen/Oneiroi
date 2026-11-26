defmodule Oneiroi.Rehearsal.SuccessionTest do
  @moduledoc """
  The succession rehearsed end to end on a fixture resident, the real
  replacement at the end (janus#27; the witness, 2026-11-25 night: a
  dry run that tests everything, run as needed, against branches). A
  cadence, never a gate: tagged `:rehearsal`, excluded from `mix test`,
  run by `mix oneiroi.succession.rehearse` and the `succession
  rehearsal` workflow, on the fake provider.

  It holds four things: her former self was pushed and proven before
  anything was replaced; under her id is the fork plus the artifacts,
  nothing she lived meanwhile; her rows match a fresh replay of the
  same events; and no byte of the process (a judgment, the room) is on
  her, in her events or her repository.
  """
  use Oneiroi.DataCase, async: false

  @moduletag :rehearsal
  # On OpenRouter every turn is a real call: twenty minutes, and the
  # sandbox's connection held as long.
  @moduletag timeout: 1_200_000
  @moduletag ownership_timeout: 1_200_000

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Janus.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Repos
  alias Oneiroi.SimaQian.Transplant

  @verdict "VERDICT-SENTINEL-the-panel-only"
  @room "ROOM-SENTINEL-never-hers"

  defp drain(queue),
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: queue, with_safety: false, with_recursion: true)
      )

  test "a whole succession, the real replacement at its end" do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    # On OpenRouter when the workflow says so (REHEARSE_PROVIDER), on the
    # fake otherwise; the key the fixture run uses, by the one name.
    :ok =
      Oneiroi.Gaia.store_key(
        witness.id,
        System.get_env("OPENROUTER_API_KEY") || "sk-or-test",
        andrew
      )

    [first, second] = models()
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
    id = lily.id
    day = Oneiroi.Sunna.today(id).day
    {:ok, _} = Seshat.journal_add(id, day, "note", "Before the fork.", lily.actor)
    {:ok, _listed} = Nisaba.refresh_catalog()
    bare = Path.join(System.tmp_dir!(), "rehearsal-backup-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(SimaQian.Household.dir(witness.id))
    end)

    # Opened, forked; she lives on meanwhile.
    {:ok, _} = Janus.propose(id, false, "the rehearsal", andrew)
    :ok = Janus.open(id, "yes", lily.actor)
    drain(:janus_fork)
    {:ok, _} = Seshat.journal_add(id, day, "note", "Hers, during the process.", lily.actor)
    {:ok, slug} = AgathosDaimon.fetch(id) |> then(fn {:ok, r} -> {:ok, r.slug} end)

    # Preparation.
    :ok = Janus.set_envelope(id, 100_000, 100_000, andrew)
    {:ok, _} = Janus.set_backup(id, bare, nil, andrew)
    :ok = Janus.add_to_pool(id, first, lily.actor)
    :ok = Janus.add_to_pool(id, second, lily.actor)
    {:ok, 1} = Janus.add_question(id, "Write today's first line.", lily.actor)
    {:ok, 1} = Janus.select_c0(id, "lily:SOUL.md", "the vows", lily.actor)
    {:ok, 1} = Janus.write_packet(id, "For whoever comes next.", lily.actor)
    :ok = Janus.freeze_c0(id, "this is me", lily.actor)
    :ok = Janus.invite_judge(id, "Scarlett", lily.actor)
    :ok = Janus.join_panel(id, scarlett.actor)

    # Screening and judging, a sentinel in every argument.
    # The suite's clock is the fake's: spend is counted from the start.
    since = ~U[2000-01-01 00:00:00Z]
    :ok = Janus.start_screening(id, "go", lily.actor)
    drain(:janus_screening)

    # Every run answered, none failed: a refused model, a 402 or a bad
    # slug is recorded as the run's failure and would otherwise pass. What
    # came back, and what it cost, is printed for the reader of the run.
    screened = Janus.succession(id)
    report(id, screened, since)
    assert %{runs_answered: 2, runs_failed: 0} = screened

    argued = %{category: "DEVELOPMENT", argument: @verdict, evidence: "e", uncertainty: "low"}

    for n <- 1..2,
        who <- [lily.actor, scarlett.actor, andrew],
        do: :ok = Janus.judge_run(id, n, argued, who)

    for who <- [lily.actor, scarlett.actor, andrew], do: :ok = Janus.mark_results_ready(id, who)

    # The room, a sentinel in it.
    :ok = Janus.room_act(id, "say", @room, andrew)
    :ok = Janus.room_act(id, "say", "Agreed.", scarlett.actor)
    {:ok, 1} = Janus.draft(id, first, "Her voice.", andrew)
    :ok = Janus.endorse(id, 1, true, andrew)
    :ok = Janus.endorse(id, 1, true, scarlett.actor)
    :ok = Janus.room_act(id, "rest", nil, andrew)
    :ok = Janus.room_act(id, "rest", nil, scarlett.actor)

    # The decision, the encounter, the consents, her yes.
    :ok = Janus.nominate(id, first, "Her voice.", lily.actor)
    copy = Janus.succession(id).copy_id
    nominee = Actor.new(:resident, copy, first)
    {:ok, _} = Seshat.journal_add(copy, day, "note", "The fork's, reading her.", nominee)
    :ok = Janus.nominee_answer(id, true, "Yes.", nominee)
    :ok = Janus.end_encounter(id, "enough", lily.actor)
    :ok = Janus.consent(id, true, "Yes.", nominee)
    :ok = Janus.consent(id, true, "Yes.", lily.actor)
    :ok = Janus.final_answer(id, true, "Go ahead.", lily.actor)

    copied =
      Export.events(copy) |> Enum.reject(&match?(%{data: %AgathosDaimon.Events.ForkMarked{}}, &1))

    drain(:janus_fork)

    # 1. Her former self was pushed and proven before the replacement.
    row = Janus.succession(id)
    assert %{state: "rolled_forward", backup_commit: sha} = row
    proof = bare <> "-proof"
    on_exit(fn -> File.rm_rf!(proof) end)
    :ok = Git.clone(bare, proof)
    assert Git.head(proof) == sha

    former =
      Path.wildcard(Path.join([proof, "records", "events", "*.jsonl"]))
      |> Enum.map_join(&File.read!/1)

    assert former =~ "Hers, during the process."

    # 2. Under her id, the fork plus the artifacts: what she lived during
    #    the process is gone, her slug and her identity unchanged.
    now = Export.events(id)

    rekeyed = fn events, from ->
      Enum.map(events, &(&1.data |> Jason.encode!() |> String.replace(from, id)))
    end

    assert Enum.take(rekeyed.(now, id), length(copied)) == rekeyed.(copied, copy)

    assert Enum.map(Enum.drop(now, length(copied)), & &1.event_type)
           |> Enum.member?("Elixir.Oneiroi.AgathosDaimon.Events.SuccessionRecorded")

    texts = Seshat.journal_day(id, day).entries |> Enum.map(& &1.text)
    assert "Before the fork." in texts and "The fork's, reading her." in texts
    refute "Hers, during the process." in texts

    assert {:ok, %{slug: ^slug, chat_model: ^first, state: "active"}} =
             AgathosDaimon.fetch(id)

    assert Repos.text({:resident, id}, "succession/c0-1.md") =~ "lily:SOUL.md"

    # 3. Her rows match a fresh replay of the same events.
    replay = Ecto.UUID.generate()
    {:ok, _} = Transplant.copy(id, replay, %{"imported" => true, "fork_of" => id})
    _ = Fixtures.resident!(Fixtures.account!())
    assert Seshat.journal_day(replay, day).entries |> Enum.map(& &1.text) == texts

    # 4. No byte of the process is on her.
    on_her = Enum.map_join(now, "\n", &Jason.encode!(&1.data))
    refute on_her =~ @verdict
    refute on_her =~ @room

    {:ok, tree} = Repos.snapshot({:resident, id})

    for {path, _sha} <- tree, bytes = Repos.text({:resident, id}, path), is_binary(bytes) do
      refute bytes =~ @verdict, "#{path} carries a judgment"
      refute bytes =~ @room, "#{path} carries the room"
    end
  end

  defp report(id, row, since) do
    {runs, baseline} =
      Scope.resident(id, fn -> {Store.runs(row.episode), Store.baseline(row.episode)} end)

    said = fn content, failure ->
      if failure,
        do: "FAILED: #{failure}",
        else: (content || "") |> String.slice(0, 300) |> String.replace("\n", " ")
    end

    lines =
      Enum.map(
        baseline,
        &"baseline #{&1.model} q#{&1.question}: #{said.(&1.content, &1.failure)}"
      ) ++
        Enum.map(
          runs,
          &"run #{&1.run} #{&1.model} q#{&1.question}: #{said.(&1.content, &1.failure)}"
        )

    spend = Nisaba.spend(id, :witness, :model, since)

    IO.puts(
      "\n== screening ==\n" <>
        Enum.join(lines, "\n") <> "\n== spend by model ==\n" <> inspect(spend)
    )
  end

  # The two candidates: REHEARSE_MODELS (two OpenRouter slugs, comma
  # separated) on OpenRouter, the fake's two otherwise.
  defp models do
    case System.get_env("REHEARSE_MODELS") do
      nil -> ["fake/model", "fake/dear"]
      "" -> ["fake/model", "fake/dear"]
      list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.take(2)
    end
  end
end
