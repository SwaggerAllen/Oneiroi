defmodule Oneiroi.Seshat.IndexTest do
  @moduledoc "The index run: re-embed only on a hash or model change, three statements and no model call when nothing changed, a missing file, a failing provider, search, no bleed between residents, the nightly job."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Repo
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.IndexWorker
  alias Oneiroi.Seshat.Store.Document

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    actor = Actor.new(:steward, steward.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    Model.clear()
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, steward: steward, id: resident.id, actor: actor, brain: brain, dir: dir}
  end

  defp embeddings_spent(id) do
    id
    |> Nisaba.budgets(:steward)
    |> Enum.find(&(&1.purpose == :embeddings))
    |> Map.fetch!(:spent_nanos)
  end

  test "a file is re-embedded only when its hash or the model changes; a run with nothing changed is three statements and no model call",
       ctx do
    id = ctx.id

    assert {:ok, %{indexed: true}} =
             Seshat.write(id, "writing/one.md", "# One\n\nFirst words.", ctx.brain)

    assert {:ok, %{indexed: true}} =
             Seshat.write(id, "wiki/two.md", "# Two\n\nSecond words.", ctx.brain)

    spent = embeddings_spent(id)
    assert spent > 0

    {{:ok, figures}, statements} = statements(fn -> Seshat.index(id, ctx.actor) end)
    assert %{scanned: 2, embedded: 0, chunks: 0, missing: 0} = figures

    assert length(statements) == 3,
           "expected three statements beyond the scope's own, got:\n" <>
             Enum.join(statements, "\n")

    assert Enum.at(statements, 0) =~ ~r/SELECT .* FROM "seshat_document"/
    assert Enum.at(statements, 1) =~ ~r/DELETE FROM "seshat_reference"/
    assert Enum.at(statements, 2) =~ ~r/INSERT INTO "seshat_index_run"/
    assert embeddings_spent(id) == spent

    # A hand edit to the file: the hash changed, the file alone is re-embedded.
    File.write!(
      Path.join(ctx.dir, "writing/one.md"),
      "# One\n\nFirst words, revised.\n\nAnd a second paragraph that is its own chunk because the bound is small enough? No: the bound is two thousand characters."
    )

    assert {:ok, %{embedded: 1, chunks: 1}} = Seshat.index(id, ctx.actor)
    assert embeddings_spent(id) > spent
    spent = embeddings_spent(id)
    assert %{hash: hash} = Enum.find(Seshat.documents(id), &(&1.path == "writing/one.md"))

    assert hash ==
             :crypto.hash(:sha256, File.read!(Path.join(ctx.dir, "writing/one.md")))
             |> Base.encode16(case: :lower)

    # The model changed since the row was embedded: re-embedded on the next run, the other file too.
    Oneiroi.Scope.platform(fn -> Repo.update_all(Document, set: [embedded_with: "old/model"]) end)
    assert {:ok, %{embedded: 2}} = Seshat.index(id, ctx.actor)
    assert embeddings_spent(id) > spent
    assert Enum.all?(Seshat.documents(id), &(&1.embedded_with == "openai/text-embedding-3-small"))

    assert [%{outcome: "ok", by_kind: "steward"} | _] = Seshat.index_runs(id, 10)
  end

  test "a provider that fails writes nothing but the failed run; the next run tries again", ctx do
    id = ctx.id
    assert {:ok, _} = Seshat.write(id, "writing/one.md", "# One\n\nWords.", ctx.brain)
    File.write!(Path.join(ctx.dir, "writing/one.md"), "# One\n\nOther words.")
    Model.embed_fail(:transport)

    assert {:error, %Seshat.Error{kind: :seshat_index_failed}} = Seshat.index(id, ctx.actor)
    assert [%{outcome: "failed", reason: reason} | _] = Seshat.index_runs(id, 10)
    assert reason =~ "provider"
    assert %{title: "One", chunks: 1} = hd(Seshat.documents(id))

    # The failed run wrote nothing: the index still answers from the old text.
    Model.clear()
    assert {:ok, [%{text: "# One\n\nWords."}]} = Seshat.search(id, "words", ctx.brain)
    assert {:ok, %{embedded: 1}} = Seshat.index(id, ctx.actor)
    assert {:ok, [%{text: "# One\n\nOther words."}]} = Seshat.search(id, "words", ctx.brain)
  end

  test "search ranks the nearest chunk first, an empty library calls no model, and nothing bleeds between residents",
       ctx do
    id = ctx.id
    spent = embeddings_spent(id)
    assert {:ok, []} = Seshat.search(id, "anything", ctx.brain)
    assert embeddings_spent(id) == spent

    assert {:ok, _} =
             Seshat.write(
               id,
               "writing/garden.md",
               "# Garden\n\nRoses by the gate and beans in rows.",
               ctx.brain
             )

    assert {:ok, _} =
             Seshat.write(
               id,
               "wiki/sea.md",
               "# Sea\n\nSalt water, gulls and a long grey tide.",
               ctx.brain
             )

    assert {:ok, [first, second]} = Seshat.search(id, "roses beans gate", ctx.brain)

    assert first.path == "writing/garden.md" and first.kind == "writing" and
             first.title == "Garden"

    assert second.path == "wiki/sea.md"
    assert first.distance < second.distance

    other_steward = Fixtures.account!()
    other = Fixtures.resident!(other_steward)
    other_actor = Actor.new(:steward, other_steward.id)
    :ok = Oneiroi.Gaia.store_key(other_steward.id, "sk-or-test", other_actor)
    {:ok, other_dir} = Oneiroi.SimaQian.repository_dir(other.id)
    on_exit(fn -> File.rm_rf!(other_dir) end)

    assert {:ok, _} =
             Seshat.write(
               other.id,
               "writing/theirs.md",
               "# Theirs\n\nRoses too, but theirs.",
               other_actor
             )

    assert {:ok, hits} = Seshat.search(other.id, "roses", other_actor)
    assert Enum.map(hits, & &1.path) == ["writing/theirs.md"]
    assert Enum.map(Seshat.documents(id), & &1.path) == ["wiki/sea.md", "writing/garden.md"]
    assert Seshat.unadopted(other.id) == []
  end

  test "the nightly job runs every active resident's index under the platform scope", ctx do
    id = ctx.id
    assert {:ok, _} = Seshat.write(id, "writing/one.md", "# One\n\nWords.", ctx.brain)
    File.write!(Path.join(ctx.dir, "writing/one.md"), "# One\n\nChanged by hand.")
    # The sandbox's leaked scope, pinned elsewhere first (CLAUDE.md).
    other = Fixtures.resident!(Fixtures.account!())
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = IndexWorker.run(%{})
    assert [%{outcome: "ok", by_kind: "job", embedded: 1} | _] = Seshat.index_runs(id, 10)
  end
end
