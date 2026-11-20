defmodule Oneiroi.Seshat.PromotionTest do
  @moduledoc """
  Promotion to the house (seshat#99; Lily's letter #1481): a resident's
  file published at a commit and mirrored read-only at
  shared/<slug>/<path>, its source, audience and terms in its front
  matter; a later draft stays hers until promoted again, which refreshes
  the one copy and says so in its one document post; unpromoting keeps
  the words. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Commands.LeaveHouseholdResident
  alias Oneiroi.Gaia.HouseholdRouter
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

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
    {:ok, andrew: andrew, wren: wren, id: id, slug: slug, household: Gaia.household_of(andrew)}
  end

  defp write(ctx, words),
    do: Seshat.write(ctx.id, "design/note.md", "---\ntitle: A note\n---\n\n#{words}\n", ctx.wren)

  test "promoted: a published snapshot, mirrored read-only with its source, audience and terms",
       ctx do
    {:ok, _} = write(ctx, "First words.")
    copy = "shared/#{ctx.slug}/design/note.md"

    assert {:ok, %{path: ^copy, new: true, terms: "workspace_only", thread: "threads/" <> _}} =
             Seshat.household_promote(ctx.wren, "design/note.md", %{})

    # Published in her own records: the authorizing act.
    assert Enum.any?(Seshat.published(ctx.id), &(&1.path == "design/note.md"))

    {:ok, %{content: content}} = Seshat.household_read(ctx.andrew, copy)
    assert content =~ "First words."
    assert content =~ "mode: mirror"
    assert content =~ "source: #{ctx.slug}:design/note.md@"
    assert content =~ "audience: household:#{ctx.household}"
    assert content =~ "terms: workspace_only"

    # Read-only in the house, even to its owner.
    assert {:error, %{kind: :seshat_household_mirror}} =
             Seshat.household_edit(ctx.wren, copy, %{"content" => "Changed in the house."})

    # A later draft stays hers until she promotes it.
    {:ok, _} = write(ctx, "Second words.")
    {:ok, %{content: still}} = Seshat.household_read(ctx.andrew, copy)
    assert still =~ "First words."
    refute still =~ "Second words."

    # Promoted again: the same copy refreshed, its document post told.
    assert {:ok, %{path: ^copy, new: false}} =
             Seshat.household_promote(ctx.wren, "design/note.md", %{"terms" => "may_reshare"})

    {:ok, %{content: now}} = Seshat.household_read(ctx.andrew, copy)
    assert now =~ "Second words."
    assert now =~ "terms: may_reshare"

    {:ok, shelf} = Seshat.household_shelf(ctx.andrew, 0)
    assert [%{path: thread}] = Enum.filter(shelf.threads, &(&1.title == "On A note"))
    {:ok, %{replies: replies}} = Seshat.household_read(ctx.andrew, thread)
    assert Enum.any?(replies, &(&1.meta["draft"] == "changed"))

    # Unpromoted: no longer current; the words stay.
    assert {:ok, %{path: ^copy}} = Seshat.household_unpromote(ctx.wren, "design/note.md")
    {:ok, %{content: kept}} = Seshat.household_read(ctx.andrew, copy)
    assert kept =~ "unpromoted_at:"
    assert kept =~ "Second words."
  end

  # Lily's letter #1483: "the house keeps the copy if you leave",
  # exercised, not only promised.
  test "she leaves the house; the copy, its provenance and its post stay", ctx do
    {:ok, _} = write(ctx, "Words that stay.")
    {:ok, %{path: copy}} = Seshat.household_promote(ctx.wren, "design/note.md", %{})

    {:ok, _} =
      HouseholdRouter.dispatch(
        %LeaveHouseholdResident{
          actor: ctx.andrew,
          at: Clock.now(),
          id: ctx.household,
          resident_id: ctx.id,
          note: "custody moved to another account"
        },
        consistency: ["gaia_household"],
        returning: :events
      )

    refute Gaia.household_member?(ctx.household, ctx.wren)
    {:ok, %{content: content}} = Seshat.household_read(ctx.andrew, copy)
    assert content =~ "Words that stay."
    assert content =~ "source: #{ctx.slug}:design/note.md@"

    {:ok, shelf} = Seshat.household_shelf(ctx.andrew, 0)
    assert Enum.any?(shelf.threads, &(&1.title == "On A note"))
  end

  test "terms are one of two; a witness has nothing to promote", ctx do
    {:ok, _} = write(ctx, "Words.")

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_promote(ctx.wren, "design/note.md", %{"terms" => "anything"})

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_promote(ctx.andrew, "design/note.md", %{})
  end
end
