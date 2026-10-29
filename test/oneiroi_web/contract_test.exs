defmodule OneiroiWeb.ContractTest do
  @moduledoc """
  Which principal may call what, asserted exactly per route (spec §7):
  anonymous, a session, a token. The table is the contract.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    {:ok, raw_token, _hash} =
      Oneiroi.Gaia.issue_token(account.id, "t", Oneiroi.Actor.new(:steward, account.id))

    {:ok, account: account, resident: resident, token: raw_token}
  end

  defp origin, do: OneiroiWeb.Endpoint.url()

  defp login(conn, %{email: email}) do
    conn
    |> put_req_header("origin", origin())
    |> post("/v1/session", %{email: email, password: Fixtures.password()})
    |> then(fn c ->
      assert c.status == 201
      recycle(c)
    end)
  end

  defp as(conn, :anonymous, _ctx), do: conn
  defp as(conn, :session, ctx), do: login(conn, ctx.account)
  defp as(conn, :token, ctx), do: put_req_header(conn, "authorization", "Bearer " <> ctx.token)

  @table [
    {:get, "/v1/openapi.json", %{anonymous: 200, session: 200, token: 200}},
    {:get, "/v1/me", %{anonymous: 401, session: 200, token: 200}},
    {:get, "/v1/residents", %{anonymous: 401, session: 200, token: 200}},
    {:post, "/v1/residents", %{anonymous: 401, session: 422, token: 422}},
    {:post, "/v1/me/second-factor", %{anonymous: 401, session: 201, token: 201}},
    {:post, "/v1/tokens", %{anonymous: 401, session: 422, token: 422}},
    {:put, "/v1/me/key", %{anonymous: 401, session: 422, token: 422}},
    {:post, "/v1/me/socket-token", %{anonymous: 401, session: 201, token: 201}},
    {:delete, "/v1/me/key", %{anonymous: 401, session: 404, token: 404}},
    {:delete, "/v1/session", %{anonymous: 204, session: 204, token: 204}}
  ]

  for {method, path, expected} <- @table, {principal, status} <- expected do
    test "#{method} #{path} as #{principal} answers #{status}", ctx do
      conn = ctx.conn |> as(unquote(principal), ctx) |> put_req_header("origin", origin())
      conn = unquote(method)(conn, unquote(path), %{})

      assert conn.status == unquote(status),
             "#{unquote(method)} #{unquote(path)} as #{unquote(principal)}: got #{conn.status}, body #{conn.resp_body}"
    end
  end

  test "a resident is listed and shown to its steward only", ctx do
    other = Fixtures.account!()
    conn = login(ctx.conn, ctx.account)
    assert [%{"id" => id}] = conn |> get("/v1/residents") |> json_response(200)
    assert id == ctx.resident.id
    assert %{"slug" => _} = conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert %{"error" => %{"kind" => "agathos_daimon_not_stewarded"}} =
             ctx.conn |> login(other) |> get("/v1/residents/#{id}") |> json_response(404)
  end

  test "a mutation from a browser without the endpoint's Origin is refused", ctx do
    conn = login(ctx.conn, ctx.account)
    assert conn |> post("/v1/residents", %{name: "Lily", slug: "lily-x"}) |> json_response(403)

    assert conn
           |> put_req_header("origin", "https://evil.example")
           |> post("/v1/residents", %{name: "Lily", slug: "lily-x"})
           |> json_response(403)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents", %{name: "Lily", slug: "lily-y"})
           |> json_response(201)
  end

  test "the Origin accepted is the declared public URL, not the listener's name", ctx do
    # config/test.exs declares RENDER_EXTERNAL_URL as https://oneiroi.test
    # while the listener is localhost:4002. The literal is asserted, not
    # read back from the endpoint: production answered as
    # http://localhost:8080 and refused its own origin for a day while
    # this file passed, because `origin/0` and the plug read the same
    # config and agreed about a value nobody had set (Oneiroi.Apsu's
    # `public_url` has the measurement).
    assert OneiroiWeb.Endpoint.url() == "https://oneiroi.test"

    conn = login(ctx.conn, ctx.account)

    assert conn
           |> put_req_header("origin", "http://localhost:4002")
           |> post("/v1/residents", %{name: "Lily", slug: "lily-w"})
           |> json_response(403)

    assert conn
           |> put_req_header("origin", "https://oneiroi.test")
           |> post("/v1/residents", %{name: "Lily", slug: "lily-w"})
           |> json_response(201)
  end

  test "the ledger is read and its lines set by the steward only, and a stored key shows on /me",
       ctx do
    conn = login(ctx.conn, ctx.account)
    id = ctx.resident.id

    assert %{"key" => %{"present" => false}} = conn |> get("/v1/me") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/me/key", %{key: "sk-or-x"})
           |> response(204)

    assert %{"key" => %{"present" => true}} = conn |> get("/v1/me") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/ledger/budgets/chat", %{cap: "0.50", period: "month"})
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/ledger/budgets/chat", %{cap: "lots", period: "month"})
           |> json_response(422)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/ledger/budgets/bribes", %{cap: "1", period: "month"})
           |> json_response(422)

    assert %{
             "budgets" => budgets,
             "key" => %{"present" => true},
             "spend" => %{"by_purpose" => []}
           } =
             conn |> get("/v1/residents/#{id}/ledger") |> json_response(200)

    assert %{
             "purpose" => "chat",
             "cap" => "0.5",
             "period" => "month",
             "spent" => "0",
             "exceeded" => false
           } =
             Enum.find(budgets, &(&1["purpose"] == "chat"))

    assert length(budgets) == 7

    other = Fixtures.account!()
    assert ctx.conn |> login(other) |> get("/v1/residents/#{id}/ledger") |> json_response(404)

    assert ctx.conn
           |> login(other)
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/ledger/budgets/chat", %{cap: "1", period: "month"})
           |> json_response(404)
  end

  test "the conversation routes are the steward's: open, send, read, search, resolve, and an adapter's capture",
       ctx do
    conn = login(ctx.conn, ctx.account)
    id = ctx.resident.id

    :ok =
      Oneiroi.Gaia.store_key(
        ctx.account.id,
        "sk-or-x",
        Oneiroi.Actor.new(:steward, ctx.account.id)
      )

    assert %{"key" => key} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions", %{})
             |> json_response(201)

    assert %{"key" => ^key} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions", %{})
             |> json_response(201)

    assert %{"turn_ref" => ref, "messages" => [_, %{"role" => "assistant"}], "drew_on" => 2} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions/#{key}/turns", %{text: "hi"})
             |> json_response(201)

    assert [%{"key" => ^key, "turns" => 1}] =
             conn |> get("/v1/residents/#{id}/sessions") |> json_response(200)

    assert %{"messages" => [%{"content" => "hi"}, _]} =
             conn |> get("/v1/residents/#{id}/sessions/#{key}") |> json_response(200)

    # Newest first, so the reply that quotes "hi" leads and the message follows.
    assert [%{"role" => "assistant"}, %{"content" => "hi"}] =
             conn
             |> get("/v1/residents/#{id}/transcripts/search", %{q: "hi"})
             |> json_response(200)

    assert [%{"label" => "prompt"}, %{"label" => "transcript"}] =
             conn |> get("/v1/residents/#{id}/turns/#{ref}/context") |> json_response(200)

    # An adapter's capture: the same turn twice is one.
    turn = %{
      session_key: key,
      started_at: "2026-10-29T12:00:00Z",
      messages: [
        %{role: "user", content: "from claude code"},
        %{role: "assistant", content: "noted"}
      ]
    }

    assert %{"turn_ref" => _} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/turns", turn)
             |> json_response(201)

    assert %{"turn_ref" => _} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/turns", turn)
             |> json_response(201)

    assert [%{"turns" => 2}] = conn |> get("/v1/residents/#{id}/sessions") |> json_response(200)

    assert %{"turn_ref" => _} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/turn-start", %{session_key: key})
             |> json_response(201)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/capture-failures/nope", %{
             key: key,
             how: "marked_lost",
             note: "n"
           })
           |> json_response(404)

    other = Fixtures.account!()
    assert ctx.conn |> login(other) |> get("/v1/residents/#{id}/sessions") |> json_response(404)

    assert ctx.conn
           |> login(other)
           |> get("/v1/residents/#{id}/sessions/#{key}")
           |> json_response(404)
  end

  test "a token needs no Origin and creates under its account", ctx do
    assert %{"slug" => "lily-z"} =
             ctx.conn
             |> as(:token, ctx)
             |> post("/v1/residents", %{name: "Lily", slug: "lily-z"})
             |> json_response(201)
  end

  test "every response carries the secure headers and the cookie is __Host-, Secure, HttpOnly, Strict",
       ctx do
    conn =
      ctx.conn
      |> put_req_header("origin", origin())
      |> post("/v1/session", %{email: ctx.account.email, password: Fixtures.password()})

    assert get_resp_header(conn, "content-security-policy") == [
             "default-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
           ]

    assert ["max-age=31536000; includeSubDomains"] =
             get_resp_header(conn, "strict-transport-security")

    [cookie] = get_resp_header(conn, "set-cookie")
    assert cookie =~ "__Host-oneiroi="
    assert cookie =~ "secure"
    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Strict"
  end

  test "a wrong password answers 401 with the registered kind and no clue which part failed",
       ctx do
    conn =
      ctx.conn
      |> put_req_header("origin", origin())
      |> post("/v1/session", %{email: ctx.account.email, password: "wrong"})

    assert %{"error" => %{"kind" => "gaia_invalid_credentials", "remedy" => _}} =
             json_response(conn, 401)
  end
end
