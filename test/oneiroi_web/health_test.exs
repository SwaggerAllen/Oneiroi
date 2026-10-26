defmodule OneiroiWeb.HealthTest do
  use OneiroiWeb.ConnCase, async: true

  test "/health reports the sha and every system's readiness", %{conn: conn} do
    conn = get(conn, "/health")

    assert conn.status == 200

    assert %{"ok" => true, "sha" => sha, "components" => %{"platform" => true}} =
             json_response(conn, 200)

    assert is_binary(sha)
  end

  test "anything else reaches the router and its 404", %{conn: conn} do
    assert get(conn, "/nothing-here").status == 404
  end
end
