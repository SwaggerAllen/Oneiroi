defmodule Oneiroi.SimaQian.GiteaTest do
  @moduledoc """
  The repositories' server (sima-qian#55, #58; the witness, 2026-11-16):
  each household an organization holding `house` and a repository per
  resident; each witness a user reading their household's and their own
  residents', nobody else's; the records disk moved over once, history
  and all, each repository marked as it goes and writes refused until
  it is done; nothing at all while the server is not set up.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.Gitea.Fake
  alias Oneiroi.SimaQian.GiteaMigration
  alias Oneiroi.SimaQian.GiteaQueue
  alias Oneiroi.SimaQian.Repos

  import Ecto.Query

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
          {:sima_qian, :gitea_url} => "https://git.example.test",
          {:sima_qian, :repos_client} => Repos.Gitea
        })
      )

  defp pending(kind, id), do: Enum.find(GiteaMigration.pending(), &match?({^kind, ^id, _}, &1))

  test "unset: nothing is sent, nothing fails", ctx do
    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    assert GiteaMigration.pending() == []
    assert SimaQian.gitea_access(ctx.witness.id) == nil

    assert {:error, %{kind: :sima_qian_gitea_off}} =
             SimaQian.gitea_set_password(ctx.witness.id, ctx.witness.email, "a long password!")
  end

  test "the migration sends a household's whole history: its organization, its repository, its witnesses",
       ctx do
    household = Gaia.household_id(ctx.witness.id)

    {:ok, _} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "For the week."})

    {:ok, _} = Seshat.household_post(ctx.andrew, %{"title" => "Dinner", "content" => "Sundays."})
    on(ctx.values)

    assert {:household, ^household, _} = moving = pending(:household, household)
    assert :ok = GiteaMigration.run([moving])
    # Marked: the next boot sends nothing again.
    assert pending(:household, household) == nil
    org = Gitea.org(household)
    login = Gitea.login(ctx.witness.id)
    state = Fake.state()
    assert org in state.orgs
    assert "#{org}/house" in state.repos
    assert {"#{org}/house", login} in state.grants
    # Main protected (sima-qian#64): no force-push, no deletion.
    assert "#{org}/house" in state.protected

    # The commits arrived.
    {log, 0} =
      System.cmd("git", ["--git-dir", Fake.bare(org, "house"), "log", "--format=%s", "main"])

    assert log =~ "Post: Plans" and log =~ "Post: Dinner"
  end

  test "a resident's repository at its backup, read by its witness alone; the witness's access and password",
       ctx do
    household = Gaia.household_id(ctx.witness.id)
    org = Gitea.org(household)
    {:ok, _} = SimaQian.backup(ctx.wren, Actor.platform())
    on(ctx.values)

    assert :ok = GiteaMigration.run([pending(:resident, ctx.wren)])
    assert "#{org}/#{ctx.slug}" in Fake.state().repos
    assert {"#{org}/#{ctx.slug}", Gitea.login(ctx.witness.id)} in Fake.state().grants
    assert "#{org}/#{ctx.slug}" in Fake.state().protected
    # Repeating protects every repository again, and nothing fails.
    assert Gitea.protect_all() == []

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

  test "while the disk is moving, a write to Gitea is refused and nothing is sent", ctx do
    on(ctx.values)
    GiteaQueue.moving(true)
    on_exit(fn -> GiteaQueue.moving(false) end)

    assert {:error, %{kind: :sima_qian_gitea_unavailable}} =
             Repos.Gitea.write(
               {:resident, ctx.wren},
               [{:create, "a.md", "a"}],
               "A",
               Repos.platform()
             )

    refute Enum.any?(Map.get(Fake.state(), :repos, []), &String.ends_with?(&1, "/#{ctx.slug}"))
  end

  test "a household is on the instance its routing names; one this build does not know is refused",
       ctx do
    on(ctx.values)
    household = Gaia.household_id(ctx.witness.id)
    assert {:ok, {"primary", _org, "house"}} = Gitea.locate({:household, household})

    Scope.platform(fn ->
      Repo.update_all(
        from(h in "gaia_household", where: h.id == type(^household, :binary_id)),
        set: [gitea_instance: "second"]
      )
    end)

    assert {:ok, {"second", _org, "house"}} = Gitea.locate({:household, household})

    assert {:error, %{kind: :sima_qian_gitea_unrouted}} =
             Repos.Gitea.write(
               {:household, household},
               [{:create, "a.md", "a"}],
               "A",
               Repos.platform()
             )
  end
end
