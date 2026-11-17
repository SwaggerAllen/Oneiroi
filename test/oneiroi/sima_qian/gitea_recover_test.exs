defmodule Oneiroi.SimaQian.GiteaRecoverTest do
  @moduledoc """
  What the first move to Gitea left on the disk (sima-qian#62): the push
  sent history, and a library write before #95 reached git only at the
  nightly backup, so files written since were on the disk and not in
  Gitea. The recovery writes them in without overwriting what was
  written since the move, and the move now commits the disk first.
  Against a real Gitea, named in ONEIROI_GITEA_TEST_URL and _TOKEN; skipped without one.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.GiteaMigration
  alias Oneiroi.SimaQian.Repos

  @store {Oneiroi.Config, :values}

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

  test "what the disk held past the last commit goes into Gitea; what Gitea changed since is left and named" do
    if System.get_env("ONEIROI_GITEA_TEST_URL") do
      values = :persistent_term.get(@store)
      on_exit(fn -> :persistent_term.put(@store, values) end)

      witness = Fixtures.account!()
      andrew = Actor.new(:witness, witness.id)
      {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
      slug = "wren-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
      {:ok, dir} = SimaQian.repository_dir(id)
      on_exit(fn -> File.rm_rf!(dir) end)

      # The history the old build committed, then the move as it ran:
      # history pushed, the repository marked sent.
      File.write!(Path.join(dir, "kept.md"), "kept\n")
      File.write!(Path.join(dir, "edited-since.md"), "as sent\n")
      {:ok, _} = Git.commit(dir, ["."], "Records: the night's backup")
      on_gitea(values)
      assert {:ok, :sent} = Gitea.sync_resident(id)
      File.write!(Path.join([dir, ".git", "oneiroi-sent-to-gitea"]), "")
      repo = {:resident, id}

      # Since the move, a write through Gitea to one file.
      {:ok, _, sent_blob} = Repos.read(repo, "edited-since.md")

      {:ok, _} =
        Repos.write(
          repo,
          [{:put, "edited-since.md", "written since\n", sent_blob}],
          "Since",
          Repos.platform()
        )

      # On the disk, uncommitted, as the old build left the morning's writes.
      File.mkdir_p!(Path.join(dir, "feeds/digests"))
      File.write!(Path.join(dir, "feeds/digests/11-2026-11-17.md"), "# Digest 11\n")
      File.write!(Path.join(dir, "kept.md"), "kept, then changed on the disk\n")
      File.write!(Path.join(dir, "edited-since.md"), "changed on the disk too\n")

      results = GiteaMigration.recover()
      assert {:resident, ^id, %{written: written, left: left}} = List.keyfind(results, id, 1)
      assert Enum.sort(written) == ["feeds/digests/11-2026-11-17.md", "kept.md"]
      assert left == ["edited-since.md"]

      assert {:ok, "# Digest 11\n", _} = Repos.read(repo, "feeds/digests/11-2026-11-17.md")
      assert {:ok, "kept, then changed on the disk\n", _} = Repos.read(repo, "kept.md")
      assert {:ok, "written since\n", _} = Repos.read(repo, "edited-since.md")

      # Run again, nothing new is written; what Gitea changed is still left.
      assert {:resident, ^id, %{written: [], left: ["edited-since.md"]}} =
               List.keyfind(GiteaMigration.recover(), id, 1)
    else
      IO.puts("skipped: no Gitea named (ONEIROI_GITEA_TEST_URL, ONEIROI_GITEA_TEST_TOKEN)")
    end
  end
end
