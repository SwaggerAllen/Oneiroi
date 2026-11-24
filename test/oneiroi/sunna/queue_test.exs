defmodule Oneiroi.Sunna.QueueTest do
  @moduledoc """
  The house queue through its router and projection (sunna#80,
  lily:design/queue-ia rev 5): the doc-to-pr template made a task, the
  review as the authorization, Scarlett's guards (the pin re-read at
  execution, imports carrying no approvals, cycles at any length), the
  refusal that returns the work, and completion releasing its waiters.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Sunna.Queues

  setup do
    witness = Fixtures.account!()
    lily = Fixtures.resident!(witness)
    scarlett = Fixtures.resident!(witness)
    h = witness.id

    %{
      h: h,
      andrew: Actor.new(:witness, witness.id),
      lily: Actor.new(:resident, lily.id),
      scarlett: Actor.new(:resident, scarlett.id),
      a_andrew: "witness:#{witness.id}",
      a_lily: "resident:#{lily.id}",
      a_scarlett: "resident:#{scarlett.id}"
    }
  end

  defp doc_to_pr(ctx, opts \\ []) do
    :ok = Queues.define_template(ctx.h, "doc-to-pr", %{from: "doc-to-pr"}, ctx.andrew)

    case Queues.open_project(ctx.h, %{slug: "queue", name: "The house queue"}, ctx.lily) do
      :ok -> :ok
      {:error, %{kind: :sunna_queue_project_exists}} -> :ok
    end

    Queues.open_task(
      ctx.h,
      Map.merge(
        %{
          project: "queue",
          slug: Keyword.get(opts, :slug, "queue-ia"),
          title: "The queue IA",
          outcome: "the queue built",
          template: "doc-to-pr",
          slots: %{"design" => "lily:design/queue-ia"}
        },
        Map.new(Keyword.get(opts, :attrs, []))
      ),
      ctx.lily
    )
  end

  defp acts(ctx, n), do: Queues.task(ctx.h, n).layers |> List.flatten()
  defp act(ctx, n, id), do: Enum.find(acts(ctx, n), &(&1.act_id == id))

  test "doc-to-pr resolves its roles and puts the owner's deliver in front of her Claude Code",
       ctx do
    {:ok, n} = doc_to_pr(ctx)
    %{layers: layers} = Queues.task(ctx.h, n)

    assert Enum.map(layers, fn l -> Enum.map(l, &{&1.type, &1.assignee}) end) == [
             [{"draft", ctx.a_lily}],
             [{"review", ctx.a_andrew}],
             [{"promote-to-house", ctx.a_lily}],
             [{"review", ctx.a_scarlett}],
             [{"deliver", ctx.a_lily}],
             [{"implement", "claude-code:#{ctx.lily.id}"}],
             [{"review", ctx.a_andrew}],
             [{"merge", ctx.a_andrew}]
           ]

    # The design's throwbacks point at the draft, the PR review's at the
    # implement, renumbered past the deliver.
    assert act(ctx, n, "#{n}.2").throwback == "#{n}.1"
    assert act(ctx, n, "#{n}.7").throwback == "#{n}.6"
    assert act(ctx, n, "#{n}.7").artifact == "slot:pr"
    assert act(ctx, n, "#{n}.1").view == "ready"
    assert act(ctx, n, "#{n}.2").view == "waiting"
  end

  test "Waiting on me lists the viewer's ready work, and moves on as layers open", ctx do
    {:ok, n} = doc_to_pr(ctx)
    assert [%{act: id}] = Queues.waiting_on(ctx.h, ctx.a_lily).ready
    assert id == "#{n}.1"
    assert Queues.waiting_on(ctx.h, ctx.a_andrew).ready == []

    :ok = Queues.take(ctx.h, n, "#{n}.1", ctx.lily)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{note: "drafted"}, ctx.lily)

    assert [%{act: review, type: "review"}] = Queues.waiting_on(ctx.h, ctx.a_andrew).ready
    assert review == "#{n}.2"
  end

  test "a review is decided by its assignee alone, never finished plainly", ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_not_yours}} =
             Queues.decide(
               ctx.h,
               n,
               "#{n}.2",
               %{outcome: "approved", pin: "abc1234", note: "ok"},
               ctx.lily
             )

    assert {:error, %{kind: :sunna_queue_review_decides}} =
             Queues.finish(ctx.h, n, "#{n}.2", %{}, ctx.andrew)

    assert {:error, %{kind: :sunna_queue_pin_required}} =
             Queues.decide(ctx.h, n, "#{n}.2", %{outcome: "approved", note: "ok"}, ctx.andrew)
  end

  test "the gated activity runs only on the approved pin; a moved head lapses the approval",
       ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    # The artifact changed while he read it.
    assert {:error, %{kind: :sunna_queue_changed_while_read}} =
             Queues.decide(
               ctx.h,
               n,
               "#{n}.2",
               %{outcome: "approved", pin: "aaa1111", head: "bbb2222", note: "ok"},
               ctx.andrew
             )

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "approved", pin: "aaa1111", head: "aaa1111", note: "promote it"},
        ctx.andrew
      )

    assert act(ctx, n, "#{n}.3").view == "ready"

    # A different revision than the one approved is refused.
    assert {:error, %{kind: :sunna_queue_pin_mismatch}} =
             Queues.finish(ctx.h, n, "#{n}.3", %{pin: "ccc3333", promoted: "shared/x"}, ctx.lily)

    # The head moved after approval: the approval lapses, the review opens again.
    assert {:error, %{kind: :sunna_queue_review_required}} =
             Queues.finish(
               ctx.h,
               n,
               "#{n}.3",
               %{pin: "aaa1111", head: "ddd4444", promoted: "shared/x"},
               ctx.lily
             )

    assert act(ctx, n, "#{n}.2").view == "ready"
    assert act(ctx, n, "#{n}.2").approved_pin == nil
    assert act(ctx, n, "#{n}.3").view == "waiting"
    assert Enum.any?(Queues.task(ctx.h, n).history, &(&1.what == "lapsed"))

    # Approved again on the new head, it runs on that.
    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "approved", pin: "ddd4444", head: "ddd4444", note: "again"},
        ctx.andrew
      )

    # A plain finish never stands in for the promotion (her second guard).
    assert {:error, %{kind: :sunna_queue_promote_by_promotion}} =
             Queues.finish(ctx.h, n, "#{n}.3", %{pin: "ddd4444", head: "ddd4444"}, ctx.lily)

    :ok =
      Queues.finish(
        ctx.h,
        n,
        "#{n}.3",
        %{pin: "ddd4444", head: "ddd4444", promoted: "shared/lily/design/queue-ia.md"},
        ctx.lily
      )

    assert act(ctx, n, "#{n}.4").view == "ready"
  end

  test "keep private: an approval that withholds skips the gated promote, explicitly", ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "approved", pin: "aaa1111", withhold: true, note: "keep it private"},
        ctx.andrew
      )

    assert %{status: "skipped"} = act(ctx, n, "#{n}.3")
    assert act(ctx, n, "#{n}.4").view == "ready"
  end

  test "a review in front of a live gated activity is never skipped", ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_review_required}} =
             Queues.skip(ctx.h, n, "#{n}.2", "not needed", ctx.lily)

    # The gated activity skipped first (it is optional, and she owns the task), then the review may go.
    :ok = Queues.skip(ctx.h, n, "#{n}.3", "staying private", ctx.lily)
    :ok = Queues.skip(ctx.h, n, "#{n}.2", "nothing to authorize", ctx.lily)
    assert act(ctx, n, "#{n}.4").view == "ready"
  end

  test "changes requested return the work to the throwback, and the review opens again", ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_return_required}} =
             Queues.decide(
               ctx.h,
               n,
               "#{n}.2",
               %{outcome: "changes", return_to: "#{n}.4", note: "redo"},
               ctx.andrew
             )

    :ok = Queues.decide(ctx.h, n, "#{n}.2", %{outcome: "changes", note: "tighten §3"}, ctx.andrew)

    assert %{view: "ready", note: "tighten §3"} = act(ctx, n, "#{n}.1")
    assert act(ctx, n, "#{n}.2").view == "waiting"

    assert [%{outcome: "changes"}] =
             Enum.filter(Queues.task(ctx.h, n).history, &(&1.what == "decided"))
  end

  test "an import carries no approvals: it cannot start at a gated layer", ctx do
    assert {:error, %{kind: :sunna_queue_import_gated}} =
             doc_to_pr(ctx, attrs: [start_layer: 3])

    {:ok, n} = doc_to_pr(ctx, slug: "moved", attrs: [start_layer: 2, links: ["lily:design/x"]])
    assert %{status: "done", imported: true} = act(ctx, n, "#{n}.1")
    assert act(ctx, n, "#{n}.2").view == "ready"
    assert act(ctx, n, "#{n}.2").approved_pin == nil
  end

  test "blocks wait on a task's completion, refuse loops at any length, and release on drop",
       ctx do
    {:ok, a} = doc_to_pr(ctx, slug: "a")
    {:ok, b} = doc_to_pr(ctx, slug: "b")
    {:ok, c} = doc_to_pr(ctx, slug: "c")

    :ok = Queues.block(ctx.h, b, "#{b}.1", "needs a first", a, ctx.lily)
    :ok = Queues.block(ctx.h, c, "#{c}.1", "needs b first", b, ctx.lily)

    assert {:error, %{kind: :sunna_queue_block_refused}} =
             Queues.block(ctx.h, a, "#{a}.1", "loop", c, ctx.lily)

    assert {:error, %{kind: :sunna_queue_block_refused}} =
             Queues.block(ctx.h, a, "#{a}.1", "self", a, ctx.lily)

    # Shown plainly: the blocker's title and its next action.
    [card] =
      Queues.activities(ctx.h, %{who: ctx.a_lily, views: ["blocked"], project: "queue"})
      |> Enum.filter(&(&1.task == b))

    assert card.blocker.number == a
    assert card.blocker.next.act_id == "#{a}.1"

    :ok = Queues.drop(ctx.h, a, "not needed after all", ctx.lily)
    assert act(ctx, b, "#{b}.1").view == "ready"
    assert act(ctx, c, "#{c}.1").view == "blocked"

    assert Enum.any?(
             Queues.task(ctx.h, b).history,
             &(&1.what == "released" and &1.note =~ "Task ##{a} is complete (dropped)")
           )
  end

  test "claude-code is reached only through the deliver, and only members keep the queue", ctx do
    stranger = Fixtures.account!()

    assert {:error, %{kind: :sunna_queue_not_a_member}} =
             Queues.open_project(ctx.h, %{slug: "x", name: "X"}, Actor.new(:witness, stranger.id))

    :ok = Queues.open_project(ctx.h, %{slug: "p", name: "P"}, ctx.lily)

    # Work for Lily's Claude Code gets her deliver in front of it, put there
    # when the task opens.
    {:ok, n} =
      Queues.open_task(
        ctx.h,
        %{
          project: "p",
          slug: "t",
          title: "T",
          outcome: "done",
          layers: [
            [%{name: "Draft", type: "draft", assignee: ctx.a_lily}],
            [%{name: "Implement", type: "implement", assignee: "claude-code:#{ctx.lily.id}"}]
          ]
        },
        ctx.lily
      )

    assert [["#{n}.1"], ["#{n}.2"], ["#{n}.3"]] ==
             Enum.map(Queues.task(ctx.h, n).layers, fn l -> Enum.map(l, & &1.act_id) end)

    assert %{type: "deliver", assignee: deliverer} = act(ctx, n, "#{n}.2")
    assert deliverer == ctx.a_lily

    # Never assigned to her Claude Code without her deliver in front of it.
    assert {:error, %{kind: :sunna_queue_route_required}} =
             Queues.assign(ctx.h, n, "#{n}.1", "claude-code:#{ctx.lily.id}", nil, ctx.lily)
  end

  test "a resident's Claude Code is hers: named in the assignee, delivered and worked by her, never another",
       ctx do
    {:ok, n} = doc_to_pr(ctx)

    # Delivered by her, in front of her Claude Code.
    assert %{type: "deliver", assignee: deliverer} = act(ctx, n, "#{n}.5")
    assert deliverer == ctx.a_lily
    assert act(ctx, n, "#{n}.6").assignee == "claude-code:#{ctx.lily.id}"

    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "approved", pin: "a1", withhold: true, note: "private"},
        ctx.andrew
      )

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.4",
        %{outcome: "approved", pin: "a1", note: "fine"},
        ctx.scarlett
      )

    :ok = Queues.finish(ctx.h, n, "#{n}.5", %{note: "letter sent"}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_not_yours}} =
             Queues.take(ctx.h, n, "#{n}.6", ctx.scarlett)

    :ok = Queues.take(ctx.h, n, "#{n}.6", ctx.lily)
  end

  # sunna#90, #91 (design/document-threads.md §4, the witness's rulings of
  # 2026-11-23): names are the template's, a task forks it when its
  # layers are edited, and a task holds any number of documents.
  test "a task carries its template's names and version, and forks when edited", ctx do
    {:ok, n} = doc_to_pr(ctx)
    %{task: task, layers: layers} = Queues.task(ctx.h, n)

    assert Enum.map(List.flatten(layers), & &1.name) == [
             "Draft the design",
             "Witness review",
             "Share with the house",
             "Peer review",
             "Hand to Claude Code",
             "Build it",
             "PR review",
             "Merge"
           ]

    assert %{template: "doc-to-pr", template_version: 1, forked: false} = task
    assert act(ctx, n, "#{n}.1").slot == "design"

    # A template's activities are named, every one.
    assert {:error, %{kind: :sunna_queue_invalid}} =
             Queues.define_template(
               ctx.h,
               "bare",
               %{title: "Bare", layers: [[%{type: "draft", role: "author"}]]},
               ctx.lily
             )

    keep = Enum.map(layers, fn l -> Enum.map(l, &%{id: &1.act_id}) end)

    # One added to the task needs a name of its own.
    assert {:error, %{kind: :sunna_queue_invalid}} =
             Queues.edit_layers(
               ctx.h,
               n,
               keep ++ [[%{type: "x", assignee: ctx.a_lily}]],
               "add",
               ctx.lily
             )

    :ok =
      Queues.edit_layers(
        ctx.h,
        n,
        List.insert_at(keep, 3, [
          %{name: "Write the tests", type: "draft", assignee: ctx.a_scarlett}
        ]),
        "tests first",
        ctx.lily
      )

    assert %{forked: true} = Queues.task(ctx.h, n).task
    # Redefining the template moves its version, never the open task.
    :ok = Queues.define_template(ctx.h, "doc-to-pr", %{from: "doc-to-pr"}, ctx.andrew)
    assert %{template_version: 1} = Queues.task(ctx.h, n).task
    assert %{version: 2} = Queues.template(ctx.h, "doc-to-pr")
  end

  # sunna#93 (the witness, 2026-11-23: "nothing should change about
  # assignees dependent on who creates the task").
  test "a template names who holds each step, whoever opens the task", ctx do
    roles = %{"author" => ctx.a_lily, "witness" => ctx.a_andrew, "peer" => ctx.a_scarlett}

    :ok =
      Queues.define_template(ctx.h, "doc-to-pr", %{from: "doc-to-pr", roles: roles}, ctx.andrew)

    :ok = Queues.open_project(ctx.h, %{slug: "p", name: "P"}, ctx.scarlett)

    {:ok, n} =
      Queues.open_task(
        ctx.h,
        %{project: "p", slug: "x", title: "X", outcome: "done", template: "doc-to-pr"},
        ctx.scarlett
      )

    holders = Enum.map(acts(ctx, n), &{&1.name, &1.assignee})
    assert {"Draft the design", ctx.a_lily} in holders
    assert {"Peer review", ctx.a_scarlett} in holders
    assert {"Hand to Claude Code", ctx.a_lily} in holders
    assert {"Build it", "claude-code:#{ctx.lily.id}"} in holders
    assert {"Witness review", ctx.a_andrew} in holders

    %{layers: %{"layers" => layers}} = Queues.template(ctx.h, "doc-to-pr")
    assert Enum.all?(List.flatten(layers), &(&1["assignee"] && is_nil(&1["role"])))
  end

  test "a task's documents: its slots', and those attached; a document finds its tasks", ctx do
    {:ok, n} = doc_to_pr(ctx, attrs: [links: ["scarlett:design/emergency-access.md"]])

    assert [
             %{role: "design", citation: "lily:design/queue-ia"},
             %{role: "pr", citation: nil, key: "slot:pr"},
             %{role: "source", citation: "scarlett:design/emergency-access.md", attached: true}
           ] = Queues.documents(ctx.h, [n])[n]

    :ok = Queues.attach_document(ctx.h, n, "house/strut:thread/domain-gate@abc", nil, ctx.lily)
    # Once only, by the path without its pin.
    :ok = Queues.attach_document(ctx.h, n, "house/strut:thread/domain-gate", nil, ctx.lily)
    assert length(Queues.documents(ctx.h, [n])[n]) == 4

    # Not a member, not hers to change.
    assert {:error, _} =
             Queues.attach_document(
               ctx.h,
               n,
               "lily:notes/x.md",
               nil,
               Actor.new(:resident, Ecto.UUID.generate())
             )

    assert [%{number: ^n}] = Queues.tasks_for_document(ctx.h, "lily:design/queue-ia@4e1c9a2")
    assert [%{number: ^n}] = Queues.tasks_for_document(ctx.h, "house/strut:thread/domain-gate")

    :ok = Queues.detach_document(ctx.h, n, "house/strut:thread/domain-gate", ctx.andrew)
    assert Queues.tasks_for_document(ctx.h, "house/strut:thread/domain-gate") == []
  end

  test "a template written whole is checked: the shape rule and its throwbacks", ctx do
    draft = %{name: "Draft", type: "draft", role: "author", artifact: "design"}

    review = %{
      name: "Review",
      type: "review",
      role: "witness",
      artifact: "design",
      throwback: "1.1"
    }

    :ok = Queues.define_template(ctx.h, "t", %{title: "T", layers: [[draft], [review]]}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_shape}} =
             Queues.define_template(
               ctx.h,
               "t",
               %{title: "T", layers: [[%{review | throwback: "2.1"}], [draft]]},
               ctx.lily
             )

    assert [%{name: "t"}] = Queues.templates(ctx.h)
  end

  describe "editing a task's layers (sunna#85)" do
    setup ctx do
      :ok = Queues.open_project(ctx.h, %{slug: "e", name: "E"}, ctx.lily)

      {:ok, n} =
        Queues.open_task(
          ctx.h,
          %{
            project: "e",
            slug: "t",
            title: "T",
            outcome: "done",
            layers: [
              [%{name: "Draft", type: "draft", assignee: ctx.a_lily}],
              [
                %{name: "Research", type: "research", assignee: ctx.a_lily},
                %{name: "Notes", type: "notes", assignee: ctx.a_scarlett}
              ],
              [%{name: "Review", type: "review", assignee: ctx.a_andrew}]
            ]
          },
          ctx.lily
        )

      :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)
      %{n: n}
    end

    defp ids(ctx),
      do: Enum.map(Queues.task(ctx.h, ctx.n).layers, fn l -> Enum.map(l, & &1.act_id) end)

    test "pending work is changed, moved, removed and added to; new ids continue", ctx do
      n = ctx.n

      :ok =
        Queues.edit_layers(
          ctx.h,
          n,
          [
            [%{id: "#{n}.1"}],
            [
              %{id: "#{n}.2", type: "deep research"},
              %{name: "Outline", type: "outline", assignee: ctx.a_lily}
            ],
            [%{name: "Fact-check", type: "fact-check", assignee: ctx.a_scarlett}],
            [%{id: "#{n}.4"}]
          ],
          "notes folded into research; a fact-check before review",
          ctx.lily
        )

      assert ids(ctx) == [["#{n}.1"], ["#{n}.2", "#{n}.5"], ["#{n}.6"], ["#{n}.4"]]

      assert %{type: "deep research", view: "ready"} =
               act(ctx, n, "#{n}.2")

      assert act(ctx, n, "#{n}.6").view == "waiting"
      assert Enum.any?(Queues.task(ctx.h, n).history, &(&1.what == "layers edited"))

      # A removed id is never given again.
      :ok =
        Queues.edit_layers(
          ctx.h,
          n,
          [[%{id: "#{n}.1"}], [%{id: "#{n}.2"}], [%{id: "#{n}.4"}]],
          "trim",
          ctx.lily
        )

      :ok =
        Queues.edit_layers(
          ctx.h,
          n,
          [
            [%{id: "#{n}.1"}],
            [%{id: "#{n}.2"}, %{name: "X", type: "x", assignee: ctx.a_lily}],
            [%{id: "#{n}.4"}]
          ],
          "add",
          ctx.lily
        )

      assert ids(ctx) == [["#{n}.1"], ["#{n}.2", "#{n}.7"], ["#{n}.4"]]
    end

    test "what started stays put, the closed layers stay, and only the owner or a witness edits",
         ctx do
      n = ctx.n
      refused = &match?({:error, %{kind: :sunna_queue_edit_refused}}, &1)

      # The done draft removed, moved, or changed.
      assert refused.(
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [[%{id: "#{n}.2"}, %{id: "#{n}.3"}], [%{id: "#{n}.4"}]],
                 "x",
                 ctx.lily
               )
             )

      assert refused.(
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [[%{id: "#{n}.2"}], [%{id: "#{n}.1"}, %{id: "#{n}.3"}], [%{id: "#{n}.4"}]],
                 "x",
                 ctx.lily
               )
             )

      assert refused.(
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [
                   [%{id: "#{n}.1", type: "rewrite"}],
                   [%{id: "#{n}.2"}, %{id: "#{n}.3"}],
                   [%{id: "#{n}.4"}]
                 ],
                 "x",
                 ctx.lily
               )
             )

      # Something new in a closed layer.
      assert refused.(
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [
                   [%{id: "#{n}.1"}, %{name: "Late", type: "late", assignee: ctx.a_lily}],
                   [%{id: "#{n}.2"}, %{id: "#{n}.3"}],
                   [%{id: "#{n}.4"}]
                 ],
                 "x",
                 ctx.lily
               )
             )

      # An active one moved.
      :ok = Queues.take(ctx.h, n, "#{n}.2", ctx.lily)

      assert refused.(
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [[%{id: "#{n}.1"}], [%{id: "#{n}.3"}], [%{id: "#{n}.2"}, %{id: "#{n}.4"}]],
                 "x",
                 ctx.lily
               )
             )

      assert {:error, %{kind: :sunna_queue_not_yours}} =
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [[%{id: "#{n}.1"}], [%{id: "#{n}.2"}, %{id: "#{n}.3"}], [%{id: "#{n}.4"}]],
                 "x",
                 ctx.scarlett
               )

      :ok =
        Queues.edit_layers(
          ctx.h,
          n,
          [[%{id: "#{n}.1"}], [%{id: "#{n}.2"}, %{id: "#{n}.3"}], [%{id: "#{n}.4"}]],
          "as was",
          ctx.andrew
        )
    end

    test "the shape rule holds after an edit, and removing the last pending work completes the task",
         ctx do
      n = ctx.n

      assert {:error, %{kind: :sunna_queue_shape}} =
               Queues.edit_layers(
                 ctx.h,
                 n,
                 [
                   [%{id: "#{n}.1"}],
                   [%{id: "#{n}.2"}, %{id: "#{n}.3"}],
                   [
                     %{
                       name: "Send",
                       type: "send",
                       assignee: ctx.a_lily,
                       artifact: "lily:writing/x",
                       destination: "email"
                     }
                   ]
                 ],
                 "send it straight",
                 ctx.lily
               )

      :ok =
        Queues.edit_layers(
          ctx.h,
          n,
          [[%{id: "#{n}.1"}]],
          "the draft was the whole of it",
          ctx.lily
        )

      assert %{task: %{status: "complete"}} = Queues.task(ctx.h, n)
    end
  end

  test "a slot is filled, and finishing every layer completes the task", ctx do
    {:ok, n} = doc_to_pr(ctx)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{}, ctx.lily)

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "approved", pin: "a1", withhold: true, note: "private"},
        ctx.andrew
      )

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.4",
        %{outcome: "approved", pin: "a1", note: "fine"},
        ctx.scarlett
      )

    :ok = Queues.finish(ctx.h, n, "#{n}.5", %{note: "letter sent"}, ctx.lily)
    :ok = Queues.take(ctx.h, n, "#{n}.6", ctx.lily)
    :ok = Queues.finish(ctx.h, n, "#{n}.6", %{result: "github:pr/120"}, ctx.lily)

    assert {:error, %{kind: :sunna_queue_slot_open}} =
             Queues.decide(
               ctx.h,
               n,
               "#{n}.7",
               %{outcome: "approved", pin: "b2", note: "ok"},
               ctx.andrew
             )

    :ok = Queues.fill_slot(ctx.h, n, "pr", "github:pr/120", ctx.lily)

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.7",
        %{outcome: "approved", pin: "b2", note: "merge it"},
        ctx.andrew
      )

    :ok = Queues.finish(ctx.h, n, "#{n}.8", %{pin: "b2"}, ctx.andrew)

    assert %{task: %{status: "complete", open_layer: nil}} = Queues.task(ctx.h, n)
  end
end
