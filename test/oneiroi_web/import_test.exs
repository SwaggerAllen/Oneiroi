defmodule OneiroiWeb.ImportTest do
  @moduledoc "The intake from a repository over HTTP: a file URL to a local bare repository in the suite, a path refused, a slug taken."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Git

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()

    :ok =
      Oneiroi.Gaia.store_key(account.id, "sk-or-test", Oneiroi.Actor.new(:witness, account.id))

    bare = Path.join(System.tmp_dir!(), "oneiroi-web-bare-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    work = Path.join(System.tmp_dir!(), "oneiroi-web-work-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(work, "wiki"))
    identity = ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]
    {_, 0} = System.cmd("git", identity ++ ["init", "-q", "-b", "main"], cd: work)
    File.write!(Path.join(work, "SOUL.md"), "# Lily\n")
    File.write!(Path.join(work, "wiki/bread.md"), "# Bread\n")
    File.write!(Path.join(work, "notes.txt"), "loose")
    {_, 0} = System.cmd("git", identity ++ ["add", "-A"], cd: work)
    {_, 0} = System.cmd("git", identity ++ ["commit", "-q", "-m", "repo"], cd: work)
    :ok = Git.push(work, bare)
    on_exit(fn -> File.rm_rf!(work) && File.rm_rf!(bare) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, bare: bare, account: account}
  end

  test "the import route", %{conn: conn, bare: bare} do
    url = "file://" <> bare

    assert %{"error" => %{"kind" => "sima_qian_scheme_refused"}} =
             conn
             |> post("/v1/residents/import", %{url: bare, name: "Lily", slug: "lily-w"})
             |> json_response(422)

    assert %{"error" => %{"kind" => "url_required"}} =
             conn
             |> post("/v1/residents/import", %{name: "Lily", slug: "lily-w"})
             |> json_response(422)

    assert %{"error" => %{"kind" => "sima_qian_name_required"}} =
             conn |> post("/v1/residents/import", %{url: url}) |> json_response(422)

    assert %{
             "id" => id,
             "slug" => "lily-w",
             "import" => %{
               "attestation" => "none",
               "events" => 0,
               "seeded" => ["SOUL.md"],
               "adopted" => 1,
               "not_transferred" => ["notes.txt"]
             }
           } =
             conn
             |> post("/v1/residents/import", %{url: url, name: "Lily", slug: "lily-w"})
             |> json_response(201)

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    assert %{"import" => %{"source" => ^url, "not_transferred" => ["notes.txt"], "told" => false}} =
             conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert %{"error" => %{"kind" => "sima_qian_already_imported"}} =
             conn
             |> post("/v1/residents/import", %{url: url, name: "Lily", slug: "lily-w2"})
             |> json_response(422)
  end
end
