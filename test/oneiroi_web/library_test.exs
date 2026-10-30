defmodule OneiroiWeb.LibraryTest do
  @moduledoc "The library over HTTP: a write, the listing with unadopted files, the document with its references, review and publish copy, search, publish, discussions, the index by hand."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, key} = Oneiroi.Kumbukumbu.main_session(resident.id, account.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, slug: resident.slug, key: key, dir: dir}
  end

  test "the library's routes", %{conn: conn, id: id, slug: slug, key: key, dir: dir} do
    base = "/v1/residents/#{id}/library"

    assert %{"path" => "writing/a.md", "changed" => true, "indexed" => true} =
             conn
             |> put("#{base}/documents/writing/a.md", %{content: "# A\n\nSee #{slug}:bookmark/9."})
             |> json_response(200)

    assert conn |> put("#{base}/documents/mail/x/y.md", %{content: "x"}) |> json_response(422)
    assert conn |> put("#{base}/documents/writing/a.png", %{content: "x"}) |> json_response(422)

    File.mkdir_p!(Path.join(dir, "wiki"))
    File.write!(Path.join(dir, "wiki/w.md"), "# W\n\nA page.")

    assert %{
             "kinds" => kinds,
             "documents" => [%{"path" => "writing/a.md", "status" => "draft", "title" => "A"}],
             "unadopted" => ["wiki/w.md"],
             "runs" => [%{"outcome" => "ok"} | _]
           } =
             conn |> get(base) |> json_response(200)

    assert Enum.any?(kinds, &(&1["kind"] == "writing" and &1["cites"]))

    assert %{"path" => "wiki/w.md", "adopted" => true} =
             conn |> post("#{base}/adopt", %{path: "wiki/w.md"}) |> json_response(200)

    assert conn |> post("#{base}/adopt", %{path: "wiki/none.md"}) |> json_response(404)

    assert %{
             "document" => %{"kind" => "writing"},
             "content" => "# A" <> _,
             "references" => [
               %{"target" => target, "resolved" => false, "reason" => "no bookmark 9"}
             ]
           } =
             conn |> get("#{base}/documents/writing/a.md") |> json_response(200)

    assert target == "#{slug}:bookmark/9"
    assert conn |> get("#{base}/documents/writing/none.md") |> json_response(404)

    assert %{"rendered" => rendered, "status" => "draft"} =
             conn |> get("#{base}/review/writing/a.md") |> json_response(200)

    assert rendered =~ "unresolved, no bookmark 9"

    assert %{"content" => "# A\n\nSee."} =
             conn |> get("#{base}/publish-copy/writing/a.md") |> json_response(200)

    assert [%{"path" => "wiki/w.md"} | _] =
             conn |> get("#{base}/search", %{q: "page"}) |> json_response(200)

    assert [%{"from_path" => "writing/a.md"}] =
             conn
             |> get("#{base}/cited-by", %{target: "#{slug}:bookmark/9"})
             |> json_response(200)

    assert conn
           |> post("#{base}/publish", %{path: "writing/a.md", url: "https://p.test/a"})
           |> response(204)

    assert conn
           |> post("#{base}/publish", %{path: "wiki/w.md", url: "https://p.test/w"})
           |> json_response(422)

    assert conn
           |> post("#{base}/discussions", %{path: "writing/a.md", session_key: key})
           |> response(204)

    assert conn
           |> post("#{base}/discussions", %{path: "writing/none.md", session_key: key})
           |> json_response(404)

    assert %{
             "document" => %{"status" => "published", "published_url" => "https://p.test/a"},
             "discussions" => [%{"session_key" => ^key}]
           } =
             conn |> get("#{base}/documents/writing/a.md") |> json_response(200)

    assert %{"scanned" => 2, "embedded" => 0} =
             conn |> post("#{base}/index") |> json_response(200)
  end
end
