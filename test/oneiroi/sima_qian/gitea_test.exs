defmodule Oneiroi.SimaQian.GiteaTest do
  @moduledoc """
  The repositories' server (sima-qian#55, #56; the witness, 2026-11-16):
  each household an organization holding `house` and a repository per
  resident; each witness a user reading their household's and their own
  residents', nobody else's; a household's write pushed within seconds,
  one job per repository; a resident's at its backup; nothing at all
  while the server is not set up.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.Gitea.Fake
  alias Oneiroi.SimaQian.GiteaWorker

  @store {Oneiroi.Config, :values}

  setup do
    values = :persistent_term.get(@store)
    on_exit(fn -> :persistent_term.put(@store, values) end)
    Fake.clear()
    on_exit(&Fake.clear/0)

    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, wren} = AgathosDaimon.create("Wren", slug, witness.id, andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      {:ok, dir} = SimaQian.repository_dir(wren)
      File.rm_rf!(dir)
    end)

    {:ok, values: values, witness: witness, andrew: andrew, wren: wren, slug: slug}
  end

  defp on(values),
    do:
      :persistent_term.put(
        @store,
        Map.merge(values, %{
          {:sima_qian, :gitea_token} => Secret.wrap("token"),
          {:sima_qian, :gitea_url} => "https://git.example.test"
        })
      )

  defp jobs, do: for(j <- all_enqueued(worker: GiteaWorker), do: Map.delete(j.args, "trace_id"))

  test "unset: nothing is sent, nothing fails", ctx do
    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    assert jobs() == []
    assert SimaQian.gitea_access(ctx.witness.id) == nil

    assert {:error, %{kind: :sima_qian_gitea_off}} =
             SimaQian.gitea_set_password(ctx.witness.id, ctx.witness.email, "a long password!")
  end

  test "a household's writes: one job, then its organization, its repository, its witnesses and the push",
       ctx do
    on(ctx.values)
    household = Gaia.household_id(ctx.witness.id)

    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    {:ok, _} = Seshat.household_post(ctx.andrew, %{"title" => "Dinner", "content" => "Sundays."})
    assert jobs() == [%{"household_id" => household}]

    assert :ok = perform_job(GiteaWorker, %{"household_id" => household})
    org = Gitea.org(household)
    login = Gitea.login(ctx.witness.id)
    state = Fake.state()
    assert org in state.orgs
    assert "#{org}/house" in state.repos
    assert {"#{org}/house", login} in state.grants

    # The commits arrived.
    {log, 0} =
      System.cmd("git", ["--git-dir", Fake.bare(org, "house"), "log", "--format=%s", "main"])

    assert log =~ "Post: Plans" and log =~ "Post: Dinner"
  end

  test "a resident's repository at its backup, read by its witness alone; the witness's access and password",
       ctx do
    on(ctx.values)
    household = Gaia.household_id(ctx.witness.id)
    org = Gitea.org(household)
    {:ok, _} = SimaQian.backup(ctx.wren, Actor.platform())
    assert %{"resident_id" => ctx.wren} in jobs()

    assert :ok = perform_job(GiteaWorker, %{"resident_id" => ctx.wren})
    assert "#{org}/#{ctx.slug}" in Fake.state().repos
    assert {"#{org}/#{ctx.slug}", Gitea.login(ctx.witness.id)} in Fake.state().grants

    {count, 0} =
      System.cmd("git", ["--git-dir", Fake.bare(org, ctx.slug), "rev-list", "--count", "main"])

    assert String.to_integer(String.trim(count)) > 0

    # A stranger reads none of it.
    stranger = Fixtures.account!()
    refute Enum.any?(Fake.state().grants, fn {_repo, l} -> l == Gitea.login(stranger.id) end)

    assert %{
             url: "https://git.example.test",
             login: login,
             repositories: repos
           } = SimaQian.gitea_access(ctx.witness.id)

    assert repos == ["#{org}/house", "#{org}/#{ctx.slug}"]

    assert {:error, %{kind: :sima_qian_gitea_invalid}} =
             SimaQian.gitea_set_password(ctx.witness.id, ctx.witness.email, "short")

    :ok = SimaQian.gitea_set_password(ctx.witness.id, ctx.witness.email, "a long password!")
    assert {login, "a long password!"} in Fake.state().passwords
  end
end
