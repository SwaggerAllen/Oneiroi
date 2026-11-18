defmodule Oneiroi.Seshat.HouseSharingTest do
  @moduledoc """
  Sharing modes and the owner (seshat#82; design/workspaces.md §1): a
  household document is its poster's in owner mode, the default, and
  only its owner edits it or changes its mode; in open mode every member
  edits it; posted with no owner it is open. Every edit a commit at the
  same path, through the beats like any write. The in-memory provider; no
  network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Repos

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok, andrew: andrew, wren: Actor.new(:resident, id), household: Gaia.household_of(andrew)}
  end

  @path "human/andrew/plan.md"

  defp post(ctx, extra \\ %{}),
    do:
      Seshat.household_post(
        ctx.andrew,
        Map.merge(%{"kind" => "human", "path" => @path, "content" => "First draft."}, extra)
      )

  test "owner mode by default: the owner edits, at the same path; another member is refused",
       ctx do
    {:ok, _} = post(ctx)

    assert {:ok, %{sharing: %{mode: "owner", owner_id: owner, owner: "Andrew"}}} =
             Seshat.household_read(ctx.wren, @path)

    assert owner == ctx.andrew.id

    assert {:error, %{kind: :seshat_household_not_owner}} =
             Seshat.household_edit(ctx.wren, @path, %{"content" => "My version."})

    assert {:error, %{kind: :seshat_household_not_owner}} =
             Seshat.household_edit(ctx.wren, @path, %{"mode" => "open"})

    # A witness writes a target once a beat: the next beat, he edits.
    Clock.Fake.advance(86_400)

    assert {:ok, %{mode: "owner", commit: commit}} =
             Seshat.household_edit(ctx.andrew, @path, %{"content" => "Second draft."})

    assert is_binary(commit)
    assert {:ok, %{content: content}} = Seshat.household_read(ctx.wren, @path)
    assert content =~ "Second draft."
    assert content =~ "edited_by: Andrew"
    refute content =~ "First draft."

    assert {:ok, [_edit, _post | _]} = Repos.history({:household, ctx.household}, @path, 10)
  end

  test "open mode lets every member edit; only the owner opens it", ctx do
    {:ok, _} = post(ctx)
    Clock.Fake.advance(86_400)
    assert {:ok, %{mode: "open"}} = Seshat.household_edit(ctx.andrew, @path, %{"mode" => "open"})

    # Past the owner's check, her edit meets the beats: not her turn.
    assert {:error, %{kind: kind}} =
             Seshat.household_edit(ctx.wren, @path, %{"content" => "Mine too."})

    refute kind == :seshat_household_not_owner

    assert {:error, %{kind: :seshat_household_not_owner}} =
             Seshat.household_edit(ctx.wren, @path, %{"mode" => "owner"})
  end

  test "posted with no owner it is open; a thread is never edited; a mode is owner or open",
       ctx do
    assert {:ok, _} = post(ctx, %{"owner" => false})

    assert {:ok, %{sharing: %{mode: "open", owner_id: nil}}} =
             Seshat.household_read(ctx.wren, @path)

    assert {:error, %{kind: :seshat_household_invalid}} =
             post(ctx, %{"path" => "human/andrew/other.md", "mode" => "shared"})

    Clock.Fake.advance(86_400)
    {:ok, t} = Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "Hi."})

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_edit(ctx.andrew, t.path <> "/trunk.md", %{"content" => "Changed."})
  end
end
