defmodule Oneiroi.Brain.QueueDocsTest do
  @moduledoc """
  sunna#95 (the witness, 2026-11-23): a document named to the house queue
  is one that exists; her file named where the house holds it is refused
  with the house's citation, and what the platform cannot read passes.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.QueueDocs
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)
    house = "nest#{System.unique_integer([:positive])}"
    {:ok, _} = Seshat.household_name(andrew, house)
    {:ok, _} = Seshat.write(id, "design/mine.md", "Mine.", Actor.new(:resident, id))

    {:ok, _} =
      Seshat.household_post(andrew, %{
        "kind" => "human",
        "path" => "human/andrew/plan.md",
        "title" => "The plan",
        "content" => "Draft one."
      })

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok, h: Gaia.household_of(andrew), slug: slug, house: house}
  end

  test "a file that exists passes; one that does not is refused, naming the house's copy", ctx do
    assert :ok = QueueDocs.check(ctx.h, "#{ctx.slug}:design/mine.md")
    assert :ok = QueueDocs.check(ctx.h, "#{ctx.slug}:design/mine.md@abc123")
    assert :ok = QueueDocs.check(ctx.h, "house/#{ctx.house}:doc/human/andrew/plan.md")
    assert :ok = QueueDocs.check(ctx.h, "github:pr/12")

    assert {:error, %{kind: :brain_queue_document_absent} = e} =
             QueueDocs.check(ctx.h, "#{ctx.slug}:human/andrew/plan.md")

    assert QueueDocs.said(e) =~
             "the house holds it as house/#{ctx.house}:doc/human/andrew/plan.md"

    assert {:error, %{kind: :brain_queue_document_absent} = none} =
             QueueDocs.check(ctx.h, "house/#{ctx.house}:doc/design/absent.md")

    assert QueueDocs.said(none) =~ "names no file. Name a file that exists"
  end
end
