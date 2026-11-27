defmodule Oneiroi.SimaQian.GiteaForkLiveTest do
  @moduledoc """
  A succession's fork and graft against a real Gitea (sima-qian#74), run
  only when one is named (`ONEIROI_GITEA_TEST_URL` and
  `ONEIROI_GITEA_TEST_TOKEN`, an admin's; never in CI, which runs no
  network): Gitea's own fork of her repository, her head its head; a
  second fork while the first stands (a dry run's scratch copy), each in
  an organization of its own; the fork's tree grafted onto her history
  as one commit; a discard taking the repository and its organization.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.Repos

  @store {Oneiroi.Config, :values}
  @lily %{name: "Lily", email: "lily@oneiroi.invalid"}

  setup do
    values = :persistent_term.get(@store)
    on_exit(fn -> :persistent_term.put(@store, values) end)
    {:ok, values: values}
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

  # Gitea's own answer for a path, read outside the code under test.
  defp status(path) do
    url = System.get_env("ONEIROI_GITEA_TEST_URL") <> "/api/v1" <> path
    token = System.get_env("ONEIROI_GITEA_TEST_TOKEN")
    # oneiroi:allow model_port
    {:ok, %Req.Response{status: status}} =
      Req.get(url, headers: [{"authorization", "token " <> token}], retry: false)

    status
  end

  test "Gitea forks her repository in place, twice over; a graft is one commit; a discard leaves nothing",
       ctx do
    if System.get_env("ONEIROI_GITEA_TEST_URL") do
      on_gitea(ctx.values)
      witness = Fixtures.account!()
      andrew = Actor.new(:witness, witness.id)

      {:ok, _} =
        Oneiroi.Seshat.household_propose_contract(andrew, "We share this house.", "founding")

      slug = "wren-#{System.unique_integer([:positive])}"
      {:ok, wren} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
      hers = {:resident, wren}
      on_exit(fn -> on_gitea(ctx.values) && Repos.delete(hers) end)

      {:ok, first} =
        Repos.write(
          hers,
          [{:create, "SOUL.md", "Curious."}, {:create, "a/b.md", "b"}],
          "Seed",
          @lily
        )

      # Gitea's fork: her head is its head.
      {:ok, %{copy_id: fork}} = SimaQian.succession_fork(wren, andrew)
      assert {:ok, ^first} = Repos.head({:resident, fork})

      # A second while the first stands, as a dry run's scratch copy is.
      {:ok, %{copy_id: scratch}} = SimaQian.succession_fork(wren, andrew)
      assert {:ok, ^first} = Repos.head({:resident, scratch})
      assert Gitea.fork_org(fork) != Gitea.fork_org(scratch)

      # The fork lives on; the graft puts its tree on her history.
      {:ok, _} =
        Repos.write({:resident, fork}, [{:create, "new.md", "The fork's own."}], "Lived", @lily)

      {:ok, grafted} = Repos.graft(hers, {:resident, fork}, "cutover", Repos.platform())
      assert {:ok, ^grafted} = Repos.head(hers)
      assert {:ok, "The fork's own.", _} = Repos.read(hers, "new.md")
      # One commit on her history: the graft's parent is her head.
      assert {:ok, [%{sha: top, subject: "cutover"}, %{sha: below, subject: "Seed"}]} =
               Repos.log(hers, nil, 5)

      assert String.starts_with?(grafted, top) and String.starts_with?(first, below)

      # A discard takes the repository and its organization.
      {:ok, %{slug: fork_slug}} = AgathosDaimon.fetch(fork)
      org = Gitea.fork_org(fork)
      assert :ok = SimaQian.discard_fork(fork)
      assert status("/repos/#{org}/#{fork_slug}") == 404
      assert status("/orgs/#{org}") == 404
      assert :ok = SimaQian.discard_fork(scratch)
    else
      IO.puts("skipped: no Gitea named (ONEIROI_GITEA_TEST_URL, ONEIROI_GITEA_TEST_TOKEN)")
    end
  end
end
