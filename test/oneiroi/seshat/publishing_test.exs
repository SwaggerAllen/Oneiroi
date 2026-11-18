defmodule Oneiroi.Seshat.PublishingTest do
  @moduledoc """
  Publishing (seshat#85; design/workspaces.md §2 and §4, the witness's
  answers of 2026-11-17): a draft is public to the household one commit
  at a time, recorded in PUBLISHED.md in the repository the file is in;
  only a draft after the one published can be; an earlier one comes back
  by a restore, a new commit, published in turn. A housemate reads a
  published draft by its citation, resolved against its source, and
  nothing unpublished. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Repos

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, slug: slug, actor: Actor.new(:resident, id), chat: chat}
    end

    lily = resident.("Lily")
    scarlett = resident.("Scarlett")
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, andrew: andrew, lily: lily, scarlett: scarlett}
  end

  defp run(name, args, r),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: r.id,
        session_key: r.chat,
        turn_ref: "t",
        resident: r.actor
      })

  defp drafts(r, path) do
    {:ok, h} = Repos.history({:resident, r.id}, path, 10)
    Enum.map(h, & &1.commit)
  end

  test "she publishes her draft; her housemate reads it, and not the draft after", ctx do
    path = "writing/essay.md"
    {:ok, _} = Seshat.write(ctx.lily.id, path, "First draft.\n", ctx.lily.actor)
    cite = "#{ctx.lily.slug}:#{path}"

    # Unpublished, it is not the house's to read.
    assert run("household_read", %{path: cite}, ctx.scarlett) =~ "no housemate's published draft"

    published = run("document_publish", %{path: path, note: "for the house"}, ctx.lily)
    assert published =~ "Published #{path} at"
    # Lily's letter #1175: it says plainly what it did not do.
    assert published =~ "It is not on the household shelf"

    [first] = drafts(ctx.lily, path)
    assert Seshat.published_latest(ctx.lily.id, path) == first

    assert [%{path: ^path, commit: ^first, note: "for the house", by: "resident:" <> _}] =
             Seshat.published(ctx.lily.id)

    assert Repos.text({:resident, ctx.lily.id}, "PUBLISHED.md") =~ "- #{path} @ #{first}"

    # The next draft stays hers until published too.
    {:ok, _} = Seshat.write(ctx.lily.id, path, "Second draft.\n", ctx.lily.actor)
    read = run("household_read", %{path: cite}, ctx.scarlett)
    assert read =~ "First draft."
    refute read =~ "Second draft."
    assert read =~ "#{cite}@#{String.slice(first, 0, 12)}"

    # The draft published, or an earlier one, cannot be published again.
    assert {:error, %{kind: :seshat_publish_already}} =
             Seshat.publish(ctx.lily.id, path, first, nil, ctx.lily.actor)

    {:ok, %{commit: second}} = Seshat.publish(ctx.lily.id, path, nil, "better", ctx.lily.actor)
    assert run("household_read", %{path: cite}, ctx.scarlett) =~ "Second draft."

    # A pinned citation reads a published commit, and only a published one.
    assert run("household_read", %{path: "#{cite}@#{String.slice(first, 0, 12)}"}, ctx.scarlett) =~
             "First draft."

    assert {:ok, %{commit: ^second}} = Seshat.household_read_published(ctx.scarlett.actor, cite)
  end

  test "who publishes: she her own, he his name-folder's, recorded in her repository", ctx do
    {:ok, _} = Seshat.write(ctx.lily.id, "human/andrew/notes.md", "His notes.\n", ctx.andrew)
    {:ok, _} = Seshat.write(ctx.lily.id, "writing/hers.md", "Hers.\n", ctx.lily.actor)

    assert {:error, %{kind: :seshat_publish_not_yours}} =
             Seshat.publish(ctx.lily.id, "writing/hers.md", nil, nil, ctx.andrew)

    assert {:error, %{kind: :seshat_publish_not_yours}} =
             Seshat.publish(ctx.lily.id, "human/andrew/notes.md", nil, nil, ctx.lily.actor)

    assert {:error, %{kind: :seshat_publish_not_yours}} =
             Seshat.publish(ctx.lily.id, "writing/hers.md", nil, nil, ctx.scarlett.actor)

    assert {:ok, %{path: "human/andrew/notes.md"}} =
             Seshat.publish(ctx.lily.id, "human/andrew/notes.md", nil, nil, ctx.andrew)

    assert [%{by: "witness:" <> _}] = Seshat.published(ctx.lily.id)

    assert {:error, %{kind: :seshat_publish_no_such_draft}} =
             Seshat.publish(ctx.lily.id, "writing/hers.md", "0000000", nil, ctx.lily.actor)

    # PUBLISHED.md is the platform's: no document write reaches it.
    assert {:error, _} = Seshat.write(ctx.lily.id, "PUBLISHED.md", "forged", ctx.lily.actor)
  end

  test "an earlier draft comes back by a restore, a new commit, published in turn", ctx do
    path = "writing/poem.md"
    {:ok, _} = Seshat.write(ctx.lily.id, path, "One.\n", ctx.lily.actor)
    {:ok, _} = Seshat.write(ctx.lily.id, path, "Two.\n", ctx.lily.actor)
    {:ok, %{commit: two}} = Seshat.publish(ctx.lily.id, path, nil, nil, ctx.lily.actor)

    {:ok, %{versions: versions}} = Seshat.versions(ctx.lily.id, path)
    one = Enum.find(versions, &(&1.commit != two and &1.restorable))
    {:ok, _} = Seshat.restore(ctx.lily.id, path, one.version, "back to one", ctx.lily.actor)

    [restored, ^two | _] = drafts(ctx.lily, path)

    assert {:ok, %{commit: ^restored}} =
             Seshat.publish(ctx.lily.id, path, nil, nil, ctx.lily.actor)

    assert run("household_read", %{path: "#{ctx.lily.slug}:#{path}"}, ctx.scarlett) =~ "One."
  end
end
