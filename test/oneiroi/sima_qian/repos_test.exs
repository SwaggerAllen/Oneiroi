defmodule Oneiroi.SimaQian.ReposTest do
  @moduledoc """
  The repositories' port (sima-qian#57): one commit of several changes,
  each held to its condition, refused whole when one no longer holds; a
  file read with its blob; the tree; history; a blob by its sha. Run on
  the local adapter always, and on a real Gitea when one is named
  (`ONEIROI_GITEA_TEST_URL` and `ONEIROI_GITEA_TEST_TOKEN`, an admin's;
  never in CI, which runs no network).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.SimaQian.Repos

  @store {Oneiroi.Config, :values}
  @lily %{name: "Lily", email: "lily@oneiroi.invalid"}

  setup do
    values = :persistent_term.get(@store)
    on_exit(fn -> :persistent_term.put(@store, values) end)
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)

    {:ok, _} =
      Oneiroi.Seshat.household_propose_contract(actor, "We share this house.", "founding")

    household = Gaia.household_id(witness.id)
    on_exit(fn -> File.rm_rf!(Repos.Local.dir({:household, household})) end)
    {:ok, values: values, household: household}
  end

  defp on_gitea(values) do
    :persistent_term.put(
      @store,
      Map.merge(values, %{
        {:sima_qian, :repos_client} => Repos.Gitea,
        {:sima_qian, :gitea_client} => Oneiroi.SimaQian.Gitea.HTTP,
        {:sima_qian, :gitea_url} => System.get_env("ONEIROI_GITEA_TEST_URL"),
        {:sima_qian, :gitea_token} => Secret.wrap(System.get_env("ONEIROI_GITEA_TEST_TOKEN"))
      })
    )
  end

  defp contract(repo) do
    assert {:ok, first} =
             Repos.write(
               repo,
               [
                 {:create, "threads/plans/trunk.md", "For the week."},
                 {:create, "threads/.kind", "thread"}
               ],
               "Post: Plans",
               @lily
             )

    assert is_binary(first)
    assert {:ok, "For the week.", sha} = Repos.read(repo, "threads/plans/trunk.md")
    assert {:error, %{kind: :sima_qian_repos_absent}} = Repos.read(repo, "threads/nothing.md")

    # An append never overwrites: the same path again is a conflict, and
    # nothing of the commit lands.
    assert {:error, %{kind: :sima_qian_repos_conflict}} =
             Repos.write(
               repo,
               [
                 {:create, "threads/plans/replies/0001.md", "Yes."},
                 {:create, "threads/plans/trunk.md", "x"}
               ],
               "Reply",
               @lily
             )

    assert {:error, %{kind: :sima_qian_repos_absent}} =
             Repos.read(repo, "threads/plans/replies/0001.md")

    # An update holds to the blob it read; a stale one is a conflict.
    assert {:ok, _} =
             Repos.write(
               repo,
               [{:put, "threads/plans/trunk.md", "For the month.", sha}],
               "Edit",
               @lily
             )

    assert {:error, %{kind: :sima_qian_repos_conflict}} =
             Repos.write(repo, [{:put, "threads/plans/trunk.md", "Stale.", sha}], "Edit", @lily)

    assert {:ok, _} = Repos.write(repo, [{:put, "notes.md", "any", :any}], "Note", @lily)
    assert {:ok, _} = Repos.write(repo, [{:put, "notes.md", "any again", :any}], "Note", @lily)

    assert {:ok, files} = Repos.tree(repo)
    paths = Enum.map(files, & &1.path)
    assert Enum.all?(["notes.md", "threads/.kind", "threads/plans/trunk.md"], &(&1 in paths))
    assert {:ok, [%{path: "threads/plans/trunk.md"}]} = Repos.list(repo, "threads/plans")

    assert {:ok, [%{subject: "Note", author: "Lily"} | _]} = Repos.log(repo, nil, 10)

    assert {:ok, [%{subject: "Edit", blob: now}, %{subject: "Post: Plans", blob: ^sha}]} =
             Repos.history(repo, "threads/plans/trunk.md", 10)

    assert {:ok, "For the month."} = Repos.blob(repo, now)
    assert {:ok, "For the week."} = Repos.blob(repo, sha)

    assert {:ok, _} = Repos.write(repo, [{:delete, "notes.md", :any}], "Gone", @lily)
    assert {:error, %{kind: :sima_qian_repos_absent}} = Repos.read(repo, "notes.md")
  end

  test "the local adapter holds every condition", ctx do
    contract({:household, ctx.household})
  end

  test "Gitea holds the same conditions", ctx do
    if System.get_env("ONEIROI_GITEA_TEST_URL") do
      on_gitea(ctx.values)
      contract({:household, ctx.household})
    else
      IO.puts("skipped: no Gitea named (ONEIROI_GITEA_TEST_URL, ONEIROI_GITEA_TEST_TOKEN)")
    end
  end
end
