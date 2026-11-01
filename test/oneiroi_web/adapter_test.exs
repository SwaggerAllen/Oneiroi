defmodule OneiroiWeb.AdapterTest do
  @moduledoc "The adapter contract over HTTP (spec §8): a registered adapter's token opens a session, starts and captures turns, reads the context, and calls the memory tools over MCP; nothing else."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    {:ok, token} = AgathosDaimon.register_adapter(resident.id, "claude-code", "brain", actor)
    {:ok, account: account, resident: resident, token: token, actor: actor}
  end

  defp as_adapter(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp rpc(conn, token, method, params, id \\ 1) do
    conn
    |> as_adapter(token)
    |> post("/mcp", %{jsonrpc: "2.0", id: id, method: method, params: params})
  end

  test "an adapter opens its session, starts a turn, bookmarks over MCP against it, and captures the turn",
       ctx do
    id = ctx.resident.id

    assert %{"key" => key} =
             ctx.conn
             |> as_adapter(ctx.token)
             |> post("/v1/residents/#{id}/sessions", %{kind: "main"})
             |> json_response(201)

    assert [%{adapter: "claude-code", kind: "main", participants: [party]}] =
             Kumbukumbu.sessions({:resident, id})

    assert party == ctx.account.id

    assert %{"turn_ref" => ref} =
             ctx.conn
             |> as_adapter(ctx.token)
             |> post("/v1/residents/#{id}/turn-start", %{session_key: key})
             |> json_response(201)

    assert {^key, ^ref} = Kumbukumbu.open_turn(id, "claude-code")

    assert %{
             "result" => %{
               "protocolVersion" => "2025-06-18",
               "serverInfo" => %{"name" => "oneiroi"}
             }
           } =
             ctx.conn |> rpc(ctx.token, "initialize", %{}) |> json_response(200)

    assert ctx.conn
           |> as_adapter(ctx.token)
           |> post("/mcp", %{jsonrpc: "2.0", method: "notifications/initialized"})
           |> response(202)

    assert %{"result" => %{"tools" => tools}} =
             ctx.conn |> rpc(ctx.token, "tools/list", %{}) |> json_response(200)

    assert Enum.any?(tools, &(&1["name"] == "bookmark_add" and is_map(&1["inputSchema"])))

    # The brain role's reads include the whole-document read.
    assert %{"inputSchema" => %{"required" => ["path"]}} =
             Enum.find(tools, &(&1["name"] == "library_read"))

    refute Enum.any?(tools, &(&1["name"] =~ "regression"))

    assert %{"result" => %{"content" => [%{"type" => "text", "text" => "Bookmarked as #1."}]}} =
             ctx.conn
             |> rpc(ctx.token, "tools/call", %{
               name: "bookmark_add",
               arguments: %{line: "she asked", summary: "the ask"}
             })
             |> json_response(200)

    assert [%{number: 1, anchor_ref: ^ref, session_key: ^key}] = Kumbukumbu.bookmarks(id)

    # The prefix is the session's: the prompt and the files, not the index.
    assert %{"text" => prefix, "digest" => "prompt=" <> _, "part" => 1, "parts" => 1} =
             ctx.conn
             |> as_adapter(ctx.token)
             |> get("/v1/residents/#{id}/context", %{runtime: "claude-code"})
             |> json_response(200)

    assert prefix =~ "You are Lily"
    assert prefix =~ "mcp__plugin_oneiroi_oneiroi__bookmark_add"
    refute prefix =~ "she asked"

    # The next turn carries the index, assembled against the words.
    assert %{"turn_ref" => next, "text" => turn_text, "drew_on" => drew_on} =
             ctx.conn
             |> as_adapter(ctx.token)
             |> post("/v1/residents/#{id}/turn-start", %{
               session_key: key,
               text: "what did I ask?"
             })
             |> json_response(201)

    assert turn_text =~ "#1 2026-10-26 she asked"
    assert drew_on > 0
    assert {^key, ^next} = Kumbukumbu.open_turn(id, "claude-code")
    ref = next

    assert %{"turn_ref" => ^ref} =
             ctx.conn
             |> as_adapter(ctx.token)
             |> post("/v1/residents/#{id}/turns", %{
               session_key: key,
               turn_ref: ref,
               started_at: "2026-10-26T12:00:00Z",
               messages: [
                 %{role: "user", content: "remember this", sent_at: "2026-10-26T12:00:00Z"},
                 %{role: "assistant", content: "I will.", sent_at: "2026-10-26T12:00:01Z"}
               ]
             })
             |> json_response(201)

    assert nil == Kumbukumbu.open_turn(id, "claude-code")
    {:ok, _s, [user, reply]} = Kumbukumbu.transcript({:account, ctx.account.id}, key)
    assert user.actor_kind == "witness" and reply.actor_kind == "resident"

    # Without an open turn a tool that needs one says so rather than failing.
    assert %{"result" => %{"content" => [%{"text" => "No turn is open" <> _}]}} =
             ctx.conn
             |> rpc(ctx.token, "tools/call", %{
               name: "bookmark_add",
               arguments: %{line: "x", summary: "y"}
             })
             |> json_response(200)

    assert %{"error" => %{"code" => -32_601}} =
             ctx.conn |> rpc(ctx.token, "nope", %{}) |> json_response(200)

    assert ctx.conn
           |> as_adapter(ctx.token)
           |> post("/mcp", %{hello: "world"})
           |> json_response(400)
  end

  test "an adapter's token reaches nothing else, a hands role gets no tools, and a revoked token is a stranger's",
       ctx do
    id = ctx.resident.id

    # Off the four contract paths an adapter's token is no principal at all.
    assert ctx.conn
           |> as_adapter(ctx.token)
           |> get("/v1/residents/#{id}/bookmarks")
           |> json_response(401)

    assert ctx.conn
           |> as_adapter(ctx.token)
           |> get("/v1/residents/#{id}/sessions")
           |> json_response(401)

    assert ctx.conn |> as_adapter(ctx.token) |> get("/v1/me") |> json_response(401)

    assert ctx.conn
           |> as_adapter(ctx.token)
           |> post("/v1/residents/#{id}/bookmark-proposals", %{})
           |> json_response(401)

    other = Fixtures.resident!(ctx.account)

    assert ctx.conn
           |> as_adapter(ctx.token)
           |> post("/v1/residents/#{other.id}/turn-start", %{session_key: "x"})
           |> json_response(404)

    {:ok, reader} = AgathosDaimon.register_adapter(id, "reader", "reader", ctx.actor)
    assert ctx.conn |> rpc(reader, "tools/list", %{}) |> json_response(401)

    assert ctx.conn
           |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "ping"})
           |> json_response(401)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_adapter_invalid}} =
             AgathosDaimon.register_adapter(id, "Bad Name", "brain", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_adapter_invalid}} =
             AgathosDaimon.register_adapter(id, "ok", "judge", ctx.actor)

    assert :ok = AgathosDaimon.revoke_adapter(id, "claude-code", ctx.actor)
    assert ctx.conn |> rpc(ctx.token, "ping", %{}) |> json_response(401)

    assert [%{adapter: "claude-code", revoked_at: %DateTime{}}, %{adapter: "reader"}] =
             AgathosDaimon.adapters(id)

    # Registering again rotates: a new token works, the old stays dead.
    {:ok, fresh} = AgathosDaimon.register_adapter(id, "claude-code", "brain", ctx.actor)
    assert %{"result" => %{}} = ctx.conn |> rpc(fresh, "ping", %{}) |> json_response(200)
    assert ctx.conn |> rpc(ctx.token, "ping", %{}) |> json_response(401)
  end

  test "the witness registers and revokes adapters over the API and the token shows once", ctx do
    id = ctx.resident.id

    conn =
      ctx.conn
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: ctx.account.email, password: Fixtures.password()})
      |> recycle()

    assert %{"token" => token, "role" => "brain"} =
             conn
             |> put_req_header("origin", OneiroiWeb.Endpoint.url())
             |> post("/v1/residents/#{id}/adapters", %{adapter: "laptop", role: "brain"})
             |> json_response(201)

    assert [%{"adapter" => "claude-code"}, %{"adapter" => "laptop", "revoked_at" => nil}] =
             conn |> get("/v1/residents/#{id}/adapters") |> json_response(200)

    refute Enum.any?(
             conn |> get("/v1/residents/#{id}/adapters") |> json_response(200),
             &Map.has_key?(&1, "token")
           )

    assert %{"result" => %{}} = ctx.conn |> rpc(token, "ping", %{}) |> json_response(200)

    assert conn
           |> put_req_header("origin", OneiroiWeb.Endpoint.url())
           |> delete("/v1/residents/#{id}/adapters/laptop")
           |> response(204)

    assert conn
           |> put_req_header("origin", OneiroiWeb.Endpoint.url())
           |> delete("/v1/residents/#{id}/adapters/laptop")
           |> json_response(404)

    assert ctx.conn |> rpc(token, "ping", %{}) |> json_response(401)
  end
end
