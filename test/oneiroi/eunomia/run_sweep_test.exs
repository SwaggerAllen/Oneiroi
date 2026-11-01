defmodule Oneiroi.Eunomia.RunSweepTest do
  @moduledoc "A run whose node died mid-answer ends (eunomia #30): Lifeline discards its orphaned one-attempt job, and the sweep fails every running run whose job is no longer live, and no other."
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Eunomia
  alias Oneiroi.Eunomia.RunSweepWorker
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope

  @sweeper Actor.new(:job, "eunomia_run_sweep")

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)

    {:ok, 1} =
      Eunomia.write_test(resident.id, %{prompt: "Hello?", passes_if: "y", fails_if: "n"}, actor)

    Fake.reply("hello", for: resident.id)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, actor: actor}
  end

  defp job(ref) do
    Scope.platform(fn ->
      Repo.one!(
        from(j in Oban.Job,
          where:
            j.worker == "Oneiroi.Eunomia.RunWorker" and
              fragment("?->>'run_ref' = ?", j.args, ^ref)
        )
      )
    end)
  end

  defp set_job(ref, changes) do
    id = job(ref).id

    Scope.platform(fn ->
      {1, _} = Repo.update_all(from(j in Oban.Job, where: j.id == ^id), set: changes)
    end)
  end

  defp running?(id, ref) do
    {:ok, run, _, _} = Eunomia.run_detail(id, ref)
    run.finished_at == nil and run.failed_at == nil
  end

  test "a run orphaned by a stopped node: Lifeline discards its one-attempt job and the sweep fails the run, broadcasting its end",
       ctx do
    {:ok, ref} = Eunomia.run(ctx.id, ["m1"], :all, ctx.actor)
    :ok = PubSub.subscribe(:eunomia, :regression)

    # The node stopped mid-answer: the job is left executing, attempted
    # long ago, which is what Lifeline's own query looks for.
    long_ago = DateTime.add(DateTime.utc_now(), -10 * 3600, :second)
    set_job(ref, state: "executing", attempt: 1, attempted_at: long_ago)
    Clock.Fake.advance(120)

    # While it is executing, the sweep must not touch it.
    assert [] = RunSweepWorker.sweep(@sweeper)
    assert running?(ctx.id, ref)

    rescue_after = Oneiroi.Config.fetch!(:apsu, :lifeline_rescue_after_minutes) * 60_000

    assert {:ok, [%{state: "discarded"}]} =
             Oban.Engine.rescue_jobs(Oban.config(), Oban.Job, rescue_after: rescue_after)

    assert [^ref] = RunSweepWorker.sweep(@sweeper)

    assert [%{ref: ^ref, failed_at: %DateTime{}, failure: "eunomia_run_sweep_abandoned"}] =
             Eunomia.runs(ctx.id)

    assert_received {:oneiroi, "eunomia:regression",
                     {_, ^ref, {:finished, %{state: "failed", cards: 0}}}, _trace}

    # Once is enough: the run has ended.
    assert [] = RunSweepWorker.sweep(@sweeper)
  end

  test "a running run whose job was completed, cancelled or removed is failed too", ctx do
    for change <- [[state: "completed"], [state: "cancelled"], :removed] do
      {:ok, ref} = Eunomia.run(ctx.id, ["m1"], :all, ctx.actor)

      case change do
        :removed -> Scope.platform(fn -> Repo.delete!(job(ref)) end)
        changes -> set_job(ref, changes)
      end

      Clock.Fake.advance(120)
      assert [^ref] = RunSweepWorker.sweep(@sweeper)
      refute running?(ctx.id, ref)
    end
  end

  test "a run whose job is live is never touched", ctx do
    for state <- ~w(available scheduled executing retryable) do
      {:ok, ref} = Eunomia.run(ctx.id, ["m1"], :all, ctx.actor)
      set_job(ref, state: state)
      Clock.Fake.advance(120)
      assert [] = RunSweepWorker.sweep(@sweeper), "a #{state} job's run was swept"
      assert running?(ctx.id, ref)
    end
  end

  test "a finished run is left alone, and so is one started within the minute", ctx do
    {:ok, ref} = Eunomia.run(ctx.id, ["m1"], :all, ctx.actor)

    assert %{success: 1, discard: 0} =
             Oban.drain_queue(queue: :eunomia_regression, with_safety: false)

    :ok = PubSub.subscribe(:eunomia, :regression)
    Clock.Fake.advance(120)
    assert [] = RunSweepWorker.sweep(@sweeper)
    assert [%{ref: ^ref, finished_at: %DateTime{}, failed_at: nil}] = Eunomia.runs(ctx.id)
    refute_received {:oneiroi, "eunomia:regression", _, _}

    # Started, its job not inserted yet: the sweep waits out the gap.
    {:ok, young} = Eunomia.run(ctx.id, ["m1"], :all, ctx.actor)
    Scope.platform(fn -> Repo.delete!(job(young)) end)
    assert [] = RunSweepWorker.sweep(@sweeper)
    assert running?(ctx.id, young)
  end

  test "the sweep acts on the minutes its setting divides" do
    every = Oneiroi.Config.fetch!(:eunomia, :run_sweep_minutes)
    assert every == 5
    assert RunSweepWorker.due?(~U[2026-11-01 10:10:00Z])
    refute RunSweepWorker.due?(~U[2026-11-01 10:11:00Z])
    assert RunSweepWorker.due?(~U[2026-11-01 00:00:00Z])
  end

  test "a worker that must not run twice has one attempt, so Lifeline discards its orphan" do
    for worker <- [Eunomia.RunWorker, Eunomia.AuditWorker, Eunomia.WashWorker] do
      assert Ecto.Changeset.get_field(worker.new(%{}), :max_attempts) == 1, inspect(worker)
    end

    assert Ecto.Changeset.get_field(Eunomia.NightWorker.new(%{}), :max_attempts) == 20
  end
end
