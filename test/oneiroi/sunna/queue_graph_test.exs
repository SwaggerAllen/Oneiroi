defmodule Oneiroi.Sunna.QueueGraphTest do
  @moduledoc """
  The house queue's pure rules (lily:design/queue-ia rev 5 §1, §6.1),
  including Scarlett's fourth build guard: transitive cycles, missing
  targets, and repeated block and release.
  """
  use ExUnit.Case, async: true

  alias Oneiroi.Sunna.Queue
  alias Oneiroi.Sunna.QueueGraph, as: G

  defp act(id, task, status, extra \\ %{}),
    do: Map.merge(%{id: id, task: task, status: status, type: "work"}, extra)

  defp task(n, layers, status \\ "open"), do: %{number: n, status: status, layers: layers}

  describe "layers and completion" do
    test "the open layer is the first not all done or skipped; skipped counts" do
      acts = %{
        "a" => act("a", 1, "done"),
        "b" => act("b", 1, "skipped"),
        "c" => act("c", 1, "pending"),
        "d" => act("d", 1, "pending")
      }

      t = task(1, [["a", "b"], ["c"], ["d"]])
      assert G.open_layer(t, acts) == 1
      assert G.view(acts["c"], t, acts) == :ready
      assert G.view(acts["d"], t, acts) == :waiting
      refute G.complete?(t, acts)
    end

    test "every layer finished is complete; dropped is complete whatever its layers" do
      acts = %{"a" => act("a", 1, "done"), "b" => act("b", 1, "pending")}
      assert G.complete?(task(1, [["a"]]), acts)
      refute G.complete?(task(1, [["a"], ["b"]]), acts)
      assert G.complete?(task(1, [["a"], ["b"]], "dropped"), acts)
      assert G.open_layer(task(1, [["b"]], "dropped"), acts) == nil
    end

    test "blocked and failed are carried in place, never moved" do
      acts = %{"a" => act("a", 1, "blocked"), "b" => act("b", 1, "failed")}
      t = task(1, [["a", "b"]])
      assert G.view(acts["a"], t, acts) == :blocked
      assert G.view(acts["b"], t, acts) == :failed
      assert G.open_layer(t, acts) == 0
    end
  end

  describe "blocks across tasks" do
    setup do
      tasks = %{1 => task(1, [["a"]]), 2 => task(2, [["b"]]), 3 => task(3, [["c"]])}

      acts = %{
        "a" => act("a", 1, "pending"),
        "b" => act("b", 2, "pending"),
        "c" => act("c", 3, "pending")
      }

      %{tasks: tasks, acts: acts}
    end

    test "a block may not name its own task or one that doesn't exist", ctx do
      assert G.block_ok?(ctx.tasks, ctx.acts, 1, 1) == :self
      assert G.block_ok?(ctx.tasks, ctx.acts, 1, 99) == :no_such_task
      assert G.block_ok?(ctx.tasks, ctx.acts, 1, 2) == :ok
    end

    test "a two-way loop is refused", ctx do
      acts = Map.put(ctx.acts, "b", act("b", 2, "blocked", %{waits_on: 1}))
      assert G.block_ok?(ctx.tasks, acts, 1, 2) == :cycle
    end

    test "a transitive loop a→b→c→a is refused, at any length", ctx do
      acts =
        ctx.acts
        |> Map.put("b", act("b", 2, "blocked", %{waits_on: 3}))
        |> Map.put("c", act("c", 3, "blocked", %{waits_on: 1}))

      assert G.block_ok?(ctx.tasks, acts, 1, 2) == :cycle
      # The chain without its last link is fine.
      acts = Map.put(acts, "c", act("c", 3, "pending"))
      assert G.block_ok?(ctx.tasks, acts, 1, 2) == :ok
    end

    test "completion releases every waiter; dropped releases too", ctx do
      acts =
        ctx.acts
        |> Map.put("b", act("b", 2, "blocked", %{waits_on: 1}))
        |> Map.put("c", act("c", 3, "blocked", %{waits_on: 1}))

      assert Enum.sort(G.releases(acts, 1)) == ["b", "c"]
      assert G.releases(acts, 2) == []
      assert G.complete?(task(1, [["a"]], "dropped"), acts)
    end

    test "repeated block and release leaves no stale wait behind", ctx do
      blocked = Map.put(ctx.acts, "b", act("b", 2, "blocked", %{waits_on: 1}))
      assert G.releases(blocked, 1) == ["b"]
      released = Map.put(blocked, "b", act("b", 2, "pending"))
      assert G.releases(released, 1) == []
      # Blocked again on the same task, then on another: only the live wait counts.
      again = Map.put(released, "b", act("b", 2, "blocked", %{waits_on: 3}))
      assert G.releases(again, 1) == []
      assert G.releases(again, 3) == ["b"]
      # And the old edge no longer counts toward a cycle.
      assert G.block_ok?(ctx.tasks, again, 1, 2) == :ok
      assert G.block_ok?(ctx.tasks, again, 3, 2) == :cycle
    end
  end

  describe "the shape rule" do
    defp specs,
      do: %{
        "draft" => %{type: "draft", artifact: "design/x"},
        "review" => %{
          type: "review",
          artifact: "design/x",
          destination: "house",
          action: "merge"
        },
        "promote" => %{type: "merge", artifact: "design/x", destination: "house"},
        "share" => %{type: "promote-to-house", artifact: "design/x", destination: "house"},
        "other-review" => %{
          type: "review",
          artifact: "design/y",
          destination: "house",
          action: "merge"
        }
      }

    test "a gated activity right after a review of the same artifact, destination and action holds" do
      assert G.shape_errors([["draft"], ["review"], ["promote"]], specs()) == []
    end

    test "a promotion needs no review in front of it (sunna#105)" do
      assert G.shape_errors([["draft"], ["share"]], specs()) == []
      assert G.shape_errors([["share"]], specs()) == []
    end

    test "a gated activity without its review in the layer before is refused" do
      assert G.shape_errors([["draft"], ["promote"]], specs()) == ["promote"]
      assert G.shape_errors([["promote"]], specs()) == ["promote"]
      # A review two layers back is not in front of it.
      assert G.shape_errors([["review"], ["draft"], ["promote"]], specs()) == ["promote"]
      # A review of another artifact doesn't stand in.
      assert G.shape_errors([["other-review"], ["promote"]], specs()) == ["promote"]
    end
  end

  # sunna#108 (the witness, 2026-11-25: task 14 showed two design
  # documents, one cited with its `.md` and one without): a document's
  # key resolves as its citation does.
  test "a document's key is its citation resolved, pin and extension alike" do
    key = Queue.doc_key("lily:design/succession-protocol-delta")
    assert key == "lily:design/succession-protocol-delta.md"
    assert Queue.doc_key("lily:design/succession-protocol-delta.md@abc1234") == key
    assert Queue.doc_key("house/strut:doc/design/x.md") == "house/strut:doc/design/x.md"
  end
end
