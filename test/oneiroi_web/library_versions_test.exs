defmodule OneiroiWeb.LibraryVersionsTest do
  @moduledoc "Versions, diff, restore and edit leases over HTTP (seshat#54, #54), and a react on a document (kumbukumbu#61)."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, dir: dir, account: account}
  end

  defp commit!(dir) do
    identity = ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]
    {_, 0} = System.cmd("git", ["add", "-A"], cd: dir, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", identity ++ ["commit", "-q", "-m", "writing"], cd: dir)
    Clock.Fake.advance(60)
  end

  test "versions, a version's words, the diff and a restore", %{conn: conn, id: id, dir: dir} do
    base = "/v1/residents/#{id}/library"

    assert %{"changed" => true} =
             conn
             |> put("#{base}/documents/writing/a.md", %{content: "a\nb\n", note: "first"})
             |> json_response(200)

    commit!(dir)
    conn |> put("#{base}/documents/writing/a.md", %{content: "a\nc\n"}) |> json_response(200)

    assert %{"path" => "writing/a.md", "current" => current, "versions" => [now, first]} =
             conn |> get("#{base}/versions/writing/a.md") |> json_response(200)

    assert %{"current" => true, "actor" => %{"kind" => "witness"}} = now
    assert now["version"] == current

    assert %{"note" => "first", "restorable" => true, "commit" => <<_::binary-size(40)>>} =
             first

    assert %{"content" => "a\nb\n"} =
             conn
             |> get("#{base}/version/writing/a.md", %{version: first["version"]})
             |> json_response(200)

    assert conn
           |> get("#{base}/version/writing/a.md", %{version: String.duplicate("0", 64)})
           |> json_response(404)

    assert %{"added" => 1, "removed" => 1, "runs" => [%{"op" => "eq", "lines" => ["a"]} | _]} =
             conn
             |> get("#{base}/diff/writing/a.md", %{from: first["version"]})
             |> json_response(200)

    assert %{"version" => v, "written" => %{"changed" => true}} =
             conn
             |> post("#{base}/restore", %{path: "writing/a.md", version: first["version"]})
             |> json_response(200)

    assert v == first["version"]
    assert File.read!(Path.join(dir, "writing/a.md")) == "a\nb\n"
  end

  test "an edit lease: acquired, shown on the read, renewed with a draft, released, and a document react",
       %{conn: conn, id: id} do
    base = "/v1/residents/#{id}/library"
    conn |> put("#{base}/documents/writing/l.md", %{content: "x"}) |> json_response(200)

    assert %{"state" => "held", "takeable" => false, "holder_id" => _} =
             conn |> post("#{base}/leases", %{path: "writing/l.md"}) |> json_response(200)

    assert %{"lease" => %{"state" => "held"}} =
             conn |> get("#{base}/documents/writing/l.md") |> json_response(200)

    assert %{"has_draft" => true} =
             conn
             |> post("#{base}/leases/renew", %{path: "writing/l.md", draft: "y"})
             |> json_response(200)

    assert [%{"path" => "writing/l.md"}] = conn |> get("#{base}/leases") |> json_response(200)

    assert conn
           |> post("#{base}/leases/release", %{path: "writing/l.md"})
           |> response(204)

    assert %{"lease" => nil} = conn |> get("#{base}/documents/writing/l.md") |> json_response(200)

    assert %{"kind" => "seshat_no_such_lease"} =
             conn
             |> post("#{base}/leases/renew", %{path: "writing/l.md"})
             |> json_response(422)
             |> Map.fetch!("error")

    assert %{"number" => n} =
             conn
             |> post("/v1/residents/#{id}/reacts", %{
               target: %{kind: "document", path: "writing/l.md"},
               emoji: "✨"
             })
             |> json_response(201)

    assert [%{"number" => ^n, "target_kind" => "document", "path" => "writing/l.md"}] =
             conn
             |> get("/v1/residents/#{id}/reacts", %{path: "writing/l.md"})
             |> json_response(200)
  end
end
