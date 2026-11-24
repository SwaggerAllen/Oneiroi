defmodule Oneiroi.Sunna.BacklogTest do
  @moduledoc """
  The backlog (sunna#103; the witness, 2026-11-24): the house's work in
  one ranked list of entries, a numbered batch or a task in no batch,
  each open or closed, the top always open. Lines work only what is
  open, in its order; a new task lands at the bottom, closed; what
  finished lists newest first, a batch once all its tasks have.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.WorkLoop
  alias Oneiroi.Sunna.WorkRouter

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    Fixtures.agreed!(resident.id, witness.id)
    andrew = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    me = Actor.new(:resident, resident.id, "fake/model")
    h = witness.id
    :ok = Sunna.queue_open_project(h, %{slug: "p", name: "P"}, me)

    open = fn slug ->
      {:ok, n} =
        Sunna.queue_open_task(
          h,
          %{
            project: "p",
            slug: slug,
            title: slug,
            outcome: "done",
            layers: [[%{type: "draft", assignee: "resident:#{resident.id}"}]]
          },
          me
        )

      n
    end

    %{id: resident.id, h: h, me: me, andrew: andrew, open: open}
  end

  test "new tasks land at the bottom, closed; the top is open whatever it says", ctx do
    a = ctx.open.("a")
    b = ctx.open.("b")

    assert %{
             entries: [
               %{kind: "task", number: ^a, open: true, top: true},
               %{kind: "task", number: ^b, open: false, top: false}
             ],
             finished: []
           } = Sunna.queue_backlog(ctx.h)
  end

  test "a witness makes numbered batches and arranges the backlog; she cannot", ctx do
    a = ctx.open.("a")
    b = ctx.open.("b")
    c = ctx.open.("c")

    assert {:error, %{kind: :sunna_queue_not_yours}} =
             Sunna.queue_make_batch(ctx.h, "mine", ctx.me)

    assert {:ok, 1} = Sunna.queue_make_batch(ctx.h, "Consent", ctx.andrew)
    assert {:ok, 2} = Sunna.queue_make_batch(ctx.h, nil, ctx.andrew)

    entries = [
      %{"task" => c, "open" => false},
      %{"batch" => 1, "tasks" => [b, a], "open" => false}
    ]

    assert {:error, %{kind: :sunna_queue_not_yours}} = Sunna.queue_arrange(ctx.h, entries, ctx.me)
    assert :ok = Sunna.queue_arrange(ctx.h, entries, ctx.andrew)

    assert %{
             entries: [
               %{kind: "task", number: ^c, open: true, top: true},
               %{kind: "batch", number: 1, name: "Consent", tasks: [^b, ^a], open: false}
             ]
           } = Sunna.queue_backlog(ctx.h)

    # A task twice, or a batch never made, is refused whole.
    assert {:error, %{kind: :sunna_queue_invalid}} =
             Sunna.queue_arrange(
               ctx.h,
               [%{"task" => a}, %{"batch" => 1, "tasks" => [a]}],
               ctx.andrew
             )

    assert {:error, %{kind: :sunna_queue_invalid}} =
             Sunna.queue_arrange(ctx.h, [%{"batch" => 9, "tasks" => [a]}], ctx.andrew)
  end

  test "her line works only what is open, in its order, and holds when nothing of hers is",
       ctx do
    a = ctx.open.("a")
    b = ctx.open.("b")
    c = ctx.open.("c")
    {:ok, 1} = Sunna.queue_make_batch(ctx.h, nil, ctx.andrew)

    # Top: a batch of c then b; then a, closed.
    :ok =
      Sunna.queue_arrange(
        ctx.h,
        [%{"batch" => 1, "tasks" => [c, b], "open" => false}, %{"task" => a, "open" => false}],
        ctx.andrew
      )

    act = "#{c}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    :ok = Sunna.queue_finish(ctx.h, c, act, %{note: "drafted"}, ctx.me)
    end_run(ctx)

    act = "#{b}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    :ok = Sunna.queue_finish(ctx.h, b, act, %{note: "drafted"}, ctx.me)
    end_run(ctx)

    # The batch is done: it lists as finished, and a, now the top, opens.
    assert %{entries: [%{kind: "task", number: ^a, open: true}], finished: finished} =
             Sunna.queue_backlog(ctx.h)

    assert [%{kind: "batch", number: 1} | _] = Enum.sort_by(finished, &(&1.kind != "batch"))
    act = "#{a}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  test "a closed entry is never started; opening it lets the line reach it", ctx do
    a = ctx.open.("a")
    b = ctx.open.("b")

    # The top waits on him: its one step reassigned to the witness.
    :ok = Sunna.queue_assign(ctx.h, a, "#{a}.1", "witness:#{ctx.andrew.id}", "his", ctx.andrew)

    :ok =
      Sunna.queue_arrange(
        ctx.h,
        [%{"task" => a, "open" => true}, %{"task" => b, "open" => false}],
        ctx.andrew
      )

    assert {:rested, "running, holding: nothing of yours is ready in what is open"} =
             WorkLoop.check(ctx.id)

    :ok =
      Sunna.queue_arrange(
        ctx.h,
        [%{"task" => a, "open" => true}, %{"task" => b, "open" => true}],
        ctx.andrew
      )

    act = "#{b}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  defp end_run(ctx) do
    %{running_act: act} = Sunna.work_queue(ctx.id)

    if act do
      {:ok, _} =
        WorkRouter.dispatch(%Commands.EndActivityRun{
          actor: Actor.platform(),
          at: Clock.now(),
          id: ctx.id,
          act: act,
          moved: true
        })
    end
  end
end
