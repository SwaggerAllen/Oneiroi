defmodule Oneiroi.Brain.QueueToolsTest do
  @moduledoc """
  A resident's house queue tools (sunna#80): she opens a task from a
  template, reads what waits on her, moves and decides through the same
  queue her witness's Work screen reads; a resident with no agreement in
  force is held from them with the house; and a promotion's activity is
  never finished by a plain move.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    lily = Fixtures.resident!(witness)
    scarlett = Fixtures.resident!(witness)
    Fixtures.agreed!(lily.id, witness.id)
    andrew = Actor.new(:witness, witness.id)
    {:ok, key} = Kumbukumbu.main_session(lily.id, witness.id, andrew)

    turn = %{
      resident_id: lily.id,
      session_key: key,
      turn_ref: "t-queue",
      started_at: Clock.now(),
      resident: Actor.new(:resident, lily.id, "fake/model")
    }

    :ok = Sunna.queue_define_template(witness.id, "doc-to-pr", %{from: "doc-to-pr"}, andrew)

    %{h: witness.id, andrew: andrew, lily: lily, scarlett: scarlett, turn: turn}
  end

  defp run(name, args, turn), do: Tools.run(name, Jason.encode!(args), turn)

  test "she opens a task, reads what waits on her, and moves it", ctx do
    assert run("queue_project_open", %{slug: "queue", name: "The queue"}, ctx.turn) =~
             "Opened project queue"

    opened =
      run(
        "queue_task_open",
        %{
          project: "queue",
          slug: "ia",
          title: "The queue IA",
          outcome: "the queue built",
          template: "doc-to-pr",
          slots: %{"design" => "lily:design/queue-ia"}
        },
        ctx.turn
      )

    assert opened =~ "Opened task #1."
    assert opened =~ "Layer 1 (open): 1.1 Draft the design (draft) on lily:design/queue-ia"
    assert opened =~ "from doc-to-pr"
    assert opened =~ "Documents: design lily:design/queue-ia; pr (not yet filled)"

    listed = run("queue_list", %{}, ctx.turn)
    assert listed =~ "Waiting on you:\n1.1 draft"

    assert run("queue_move", %{task: 1, act: "1.1", move: "take"}, ctx.turn) =~ "take recorded"

    finished =
      run("queue_move", %{task: 1, act: "1.1", move: "finish", note: "drafted"}, ctx.turn)

    assert finished =~ "finish recorded"
    assert finished =~ "Next: review (1.2)"

    # His review: not hers to decide.
    assert run(
             "queue_decide",
             %{task: 1, act: "1.2", outcome: "approved", note: "mine?"},
             ctx.turn
           ) =~ "not yours"

    :ok =
      Sunna.queue_decide(
        ctx.h,
        1,
        "1.2",
        %{outcome: "approved", pin: "abc1234", note: "promote it"},
        ctx.andrew
      )

    # The promotion is finished by promoting, never by a move.
    assert run("queue_move", %{task: 1, act: "1.3", move: "finish"}, ctx.turn) =~
             "finished by promoting"

    assert run("queue_task", %{task: 1}, ctx.turn) =~
             "1.2 Witness review (review) on lily:design/queue-ia@abc1234"
  end

  test "she writes a template whole, the shape rule held, and a task opens from it", ctx do
    layers = [
      [%{name: "Draft", type: "draft", role: "author", artifact: "piece"}],
      [
        %{
          name: "Review",
          type: "review",
          role: "witness",
          artifact: "piece",
          destination: "substack",
          action: "publish",
          throwback: "1.1"
        }
      ],
      [
        %{
          name: "Publish",
          type: "publish",
          role: "author",
          artifact: "piece",
          destination: "substack"
        }
      ]
    ]

    # A publish with no review in front of it is refused.
    assert run(
             "queue_template_define",
             %{
               name: "essay",
               title: "An essay, read, posted",
               layers: [hd(layers), List.last(layers)]
             },
             ctx.turn
           ) =~ "gated activity"

    assert run(
             "queue_template_define",
             %{name: "essay", title: "An essay, read, posted", layers: layers},
             ctx.turn
           ) =~ "Template essay is saved"

    assert run("queue_templates", %{}, ctx.turn) =~ "essay: An essay, read, posted"
    run("queue_project_open", %{slug: "writing", name: "Writing"}, ctx.turn)

    assert run(
             "queue_task_open",
             %{
               project: "writing",
               slug: "drawer",
               title: "The drawer",
               outcome: "posted",
               template: "essay"
             },
             ctx.turn
           ) =~ "Layer 3: 1.3 Publish (publish)"
  end

  test "held with the house: no agreement, no queue", ctx do
    turn = %{
      ctx.turn
      | resident_id: ctx.scarlett.id,
        resident: Actor.new(:resident, ctx.scarlett.id)
    }

    refute run("queue_list", %{}, turn) =~ "Waiting on you"
  end
end
