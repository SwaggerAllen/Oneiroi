defmodule Oneiroi.Seshat.ReviewThreadTest do
  @moduledoc """
  A document has one thread in the house too (seshat#109), and a
  review's decision is posted into its document's thread (seshat#110):
  hers while the document is hers alone. The in-memory provider; no
  network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.ReviewThreadWorker
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna.Queues

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)
    wren = Actor.new(:resident, id)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok, andrew: andrew, wren: wren, id: id, slug: slug, h: Gaia.household_of(andrew)}
  end

  test "a post on a house document that has its thread answers that thread", ctx do
    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{
        "kind" => "human",
        "path" => "human/andrew/plan.md",
        "title" => "The plan",
        "content" => "Draft one."
      })

    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.andrew, %{
        "doc" => "human/andrew/plan.md",
        "content" => "Thoughts?"
      })

    # The next beat (a member's once to a thread a beat), the same post.
    Clock.Fake.advance(86_400)

    assert {:ok, %{path: ^thread, existing: true}} =
             Seshat.household_post(ctx.andrew, %{
               "doc" => "human/andrew/plan.md",
               "content" => "Shorter."
             })

    assert {:ok, %{replies: [%{body: "Shorter." <> _}]}} =
             Seshat.household_read(ctx.andrew, thread)
  end

  test "a review's decision is posted into the document's thread, in her own threads", ctx do
    {:ok, _} = Seshat.write(ctx.id, "design/plan.md", "A plan.", ctx.wren)
    :ok = Queues.define_template(ctx.h, "doc-to-pr", %{from: "doc-to-pr"}, ctx.andrew)
    :ok = Queues.open_project(ctx.h, %{slug: "p", name: "P"}, ctx.wren)

    {:ok, n} =
      Queues.open_task(
        ctx.h,
        %{
          project: "p",
          slug: "plan",
          title: "The plan",
          outcome: "built",
          template: "doc-to-pr",
          slots: %{"design" => "#{ctx.slug}:design/plan.md"}
        },
        ctx.wren
      )

    :ok = Queues.take(ctx.h, n, "#{n}.1", ctx.wren)
    :ok = Queues.finish(ctx.h, n, "#{n}.1", %{note: "drafted"}, ctx.wren)

    :ok =
      Queues.decide(
        ctx.h,
        n,
        "#{n}.2",
        %{outcome: "changes", pin: "4e1c9a2", note: "Name the window case."},
        ctx.andrew
      )

    :ok =
      ReviewThreadWorker.run(%{
        "household_id" => ctx.h,
        "task" => n,
        "act" => "#{n}.2",
        "outcome" => "changes",
        "pin" => "4e1c9a2",
        "note" => "Name the window case.",
        "actor_kind" => "witness",
        "actor_id" => ctx.andrew.id
      })

    assert {:ok, %{path: thread}} =
             Seshat.thread_for_document(ctx.andrew, ctx.id, "design/plan.md")

    {:ok, t} = Seshat.thread_read(ctx.andrew, ctx.id, thread)
    text = t.trunk.body <> Enum.map_join(t.replies, "\n", & &1.body)
    assert text =~ "Witness review: changes asked on @4e1c9a2, by Andrew."
    assert text =~ "Name the window case."
  end
end
