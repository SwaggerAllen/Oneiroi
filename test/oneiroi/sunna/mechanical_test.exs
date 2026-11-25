defmodule Oneiroi.Sunna.MechanicalTest do
  @moduledoc """
  Mechanical activities (sunna#104; the witness, 2026-11-25: "promoting
  from a resident workspace to a house workspace shouldn't need an agent,
  it could just happen"): her promote-to-house step is done by the
  platform as hers, at the revision its review approved, with no run;
  wherever its task sits in the backlog and whatever her line is doing
  (sunna#107); one it cannot do is blocked with the library's reason, never
  handed to her line; an unfilled template slot waits.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.HouseQueue
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.WorkLoop

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, dir} = SimaQian.repository_dir(id)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
      File.rm_rf!(dir)
    end)

    wren = Actor.new(:resident, id)
    h = Gaia.household_of(andrew)
    :ok = Sunna.queue_open_project(h, %{slug: "p", name: "P"}, wren)

    open = fn path ->
      {:ok, n} =
        Sunna.queue_open_task(
          h,
          %{
            project: "p",
            slug: "t#{System.unique_integer([:positive])}",
            title: "Share it",
            outcome: "in the house",
            layers: [
              [
                %{
                  type: "review",
                  assignee: "witness:#{witness.id}",
                  artifact: "#{slug}:#{path}",
                  destination: "house",
                  action: "promote-to-house"
                }
              ],
              [
                %{
                  type: "promote-to-house",
                  assignee: "resident:#{id}",
                  artifact: "#{slug}:#{path}",
                  destination: "house"
                }
              ]
            ]
          },
          wren
        )

      n
    end

    {:ok, andrew: andrew, wren: wren, id: id, slug: slug, h: h, open: open}
  end

  test "an approved document is promoted by the platform, as hers, at the approved revision, with no run",
       ctx do
    {:ok, _} =
      Seshat.write(
        ctx.id,
        "design/note.md",
        "---\ntitle: A note\n---\n\nThe approved words.\n",
        ctx.wren
      )

    n = ctx.open.("design/note.md")
    :ok = HouseQueue.decide(ctx.h, n, "#{n}.1", %{outcome: "approved", note: "good"}, ctx.andrew)
    %{approved_pin: approved} = act(ctx, n, "#{n}.1")

    assert WorkLoop.due?(ctx.id)
    _ = WorkLoop.check(ctx.id)

    assert %{status: "done"} = act(ctx, n, "#{n}.2")
    assert Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work")) == []

    {:ok, %{content: copy}} =
      Seshat.household_read(ctx.andrew, "shared/#{ctx.slug}/design/note.md")

    assert copy =~ "The approved words."
    # Promoted at the commit the review approved.
    assert %{result: result, pin: pin} = act(ctx, n, "#{n}.2")
    assert result == "shared/#{ctx.slug}/design/note.md"

    assert String.starts_with?(pin, String.slice(approved, 0, 7)) or
             String.starts_with?(approved, pin)
  end

  test "a promotion the platform cannot do is blocked with why, never handed to her line", ctx do
    n = ctx.open.("design/missing.md")

    :ok =
      HouseQueue.decide(
        ctx.h,
        n,
        "#{n}.1",
        %{outcome: "approved", note: "ok", pin: "abc1234"},
        ctx.andrew
      )

    _ = WorkLoop.check(ctx.id)

    assert %{status: "blocked", reason: "the platform could not promote it: " <> _} =
             act(ctx, n, "#{n}.2")

    refute WorkLoop.due?(ctx.id)
  end

  # sunna#107 (the witness, 2026-11-25: "for mechanical steps like promote
  # doc, it shouldn't need to wait on a resident being free"): a promotion
  # in a closed backlog entry is done all the same, its citation resolved
  # as every citation is (no `.md` named), and an unfilled slot waits.
  test "a promotion is done wherever its task sits in the backlog, its citation resolved", ctx do
    # The top entry: something else of the house's, open.
    _top = ctx.open.("design/other.md")

    {:ok, _} =
      Seshat.write(
        ctx.id,
        "design/later.md",
        "---\ntitle: Later\n---\n\nClosed, still shared.\n",
        ctx.wren
      )

    n = ctx.open.("design/later")
    :ok = HouseQueue.decide(ctx.h, n, "#{n}.1", %{outcome: "approved", note: "good"}, ctx.andrew)
    _ = WorkLoop.check(ctx.id)

    assert %{status: "done"} = act(ctx, n, "#{n}.2")

    {:ok, %{content: copy}} =
      Seshat.household_read(ctx.andrew, "shared/#{ctx.slug}/design/later.md")

    assert copy =~ "Closed, still shared."
  end

  # sunna#105 (the witness, 2026-11-25: "promotion doesn't necessarily
  # need a review step before it"): a promote step alone opens, and the
  # platform promotes her latest draft.
  test "a promotion with no review in front of it opens and is done on her latest draft", ctx do
    {:ok, _} =
      Seshat.write(
        ctx.id,
        "design/plain.md",
        "---\ntitle: Plain\n---\n\nNo review needed.\n",
        ctx.wren
      )

    {:ok, n} =
      Sunna.queue_open_task(
        ctx.h,
        %{
          project: "p",
          slug: "plain",
          title: "Share it plainly",
          outcome: "in the house",
          layers: [
            [
              %{
                type: "promote-to-house",
                assignee: "resident:#{ctx.id}",
                artifact: "#{ctx.slug}:design/plain.md",
                destination: "house"
              }
            ]
          ]
        },
        ctx.wren
      )

    _ = WorkLoop.check(ctx.id)
    assert %{status: "done"} = act(ctx, n, "#{n}.1")

    {:ok, %{content: copy}} =
      Seshat.household_read(ctx.andrew, "shared/#{ctx.slug}/design/plain.md")

    assert copy =~ "No review needed."

    # A promotion still names what it promotes.
    assert {:error, %{kind: :sunna_queue_shape}} =
             Sunna.queue_open_task(
               ctx.h,
               %{
                 project: "p",
                 slug: "none",
                 title: "Nothing named",
                 outcome: "x",
                 layers: [[%{type: "promote-to-house", assignee: "resident:#{ctx.id}"}]]
               },
               ctx.wren
             )
  end

  defp act(ctx, n, id),
    do: Enum.find(List.flatten(Sunna.queue_task(ctx.h, n).layers), &(&1.act_id == id))
end
