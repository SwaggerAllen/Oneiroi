defmodule OneiroiWeb.ContractTest do
  @moduledoc """
  Which principal may call what, asserted exactly per route (spec §7):
  anonymous, a session, a token. The table is the contract.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures
  alias OneiroiWeb.Plugs.RequirePrincipal

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    {:ok, raw_token, _hash} =
      Oneiroi.Gaia.issue_token(account.id, "t", Oneiroi.Actor.new(:witness, account.id))

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

  test "a resident is listed and shown to its witness only", ctx do
    other = Fixtures.account!()
    conn = login(ctx.conn, ctx.account)
    assert [%{"id" => id}] = conn |> get("/v1/residents") |> json_response(200)
    assert id == ctx.resident.id
    assert %{"slug" => _} = conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert %{"error" => %{"kind" => "agathos_daimon_not_witnessed"}} =
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

  test "the ledger is read and its lines set by the witness only, and a stored key shows on /me",
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

  # The adapter contract's routes (spec §8, brain #42), the only ones an
  # adapter's token opens. Read off the router, so a route added under
  # one of these shapes, or a clause added to the list, fails here.
  @adapter_routes [
    {"POST", "/v1/residents/:id/sessions"},
    {"POST", "/v1/residents/:id/turn-start"},
    {"POST", "/v1/residents/:id/turns"},
    {"GET", "/v1/residents/:id/context"}
  ]

  test "an adapter's token opens exactly the adapter contract's routes" do
    opened =
      for %{verb: verb, path: "/v1/" <> _ = path} <- OneiroiWeb.Router.__routes__(),
          method = verb |> Atom.to_string() |> String.upcase(),
          segments =
            path |> String.split("/", trim: true) |> Enum.map(&String.replace(&1, ~r/^:.*/, "x")),
          RequirePrincipal.adapter_path?(method, segments),
          do: {method, path}

    assert Enum.sort(opened) == Enum.sort(@adapter_routes)
  end

  test "the context is the adapter's: its token reads the prefix and gets the turn's context, a witness gets neither",
       ctx do
    id = ctx.resident.id
    actor = Oneiroi.Actor.new(:witness, ctx.account.id)
    {:ok, adapter} = Oneiroi.AgathosDaimon.register_adapter(id, "laptop", "brain", actor)
    as_adapter = &put_req_header(&1, "authorization", "Bearer " <> adapter)

    assert %{"text" => "You are Lily" <> _, "digest" => _} =
             ctx.conn |> as_adapter.() |> get("/v1/residents/#{id}/context") |> json_response(200)

    assert %{"error" => %{"kind" => "adapter_only"}} =
             ctx.conn
             |> login(ctx.account)
             |> get("/v1/residents/#{id}/context")
             |> json_response(404)

    assert %{"key" => key} =
             ctx.conn
             |> as_adapter.()
             |> post("/v1/residents/#{id}/sessions", %{kind: "main"})
             |> json_response(201)

    assert %{"turn_ref" => _, "started_at" => _, "text" => text, "digest" => _} =
             ctx.conn
             |> as_adapter.()
             |> post("/v1/residents/#{id}/turn-start", %{session_key: key, text: "hello"})
             |> json_response(201)

    # No digest held: the whole prefix rides the turn.
    assert text =~ "You are Lily"

    witness_start =
      ctx.conn
      |> login(ctx.account)
      |> put_req_header("origin", origin())
      |> post("/v1/residents/#{id}/turn-start", %{session_key: key, text: "hello"})
      |> json_response(201)

    assert Map.keys(witness_start) == ["turn_ref"]
  end

  test "the conversation routes are the witness's: open, send, read, search, resolve, and an adapter's capture",
       ctx do
    conn = login(ctx.conn, ctx.account)
    id = ctx.resident.id

    :ok =
      Oneiroi.Gaia.store_key(
        ctx.account.id,
        "sk-or-x",
        Oneiroi.Actor.new(:witness, ctx.account.id)
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

    assert %{"turn_ref" => ref, "messages" => [_, %{"role" => "assistant"}], "drew_on" => 4} =
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

    assert [
             %{"label" => "prompt"},
             %{"label" => "AGENTS.md"},
             %{"label" => "index", "text" => _},
             %{"label" => "transcript"}
           ] =
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

  test "the memory routes are the witness's: bookmarks, proposals, the tag set, taggings", ctx do
    id = ctx.resident.id

    :ok =
      Oneiroi.Gaia.store_key(
        ctx.account.id,
        "sk-or-x",
        Oneiroi.Actor.new(:witness, ctx.account.id)
      )

    conn = login(ctx.conn, ctx.account)

    assert %{"key" => key} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions", %{})
             |> json_response(201)

    assert %{"turn_ref" => ref} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions/#{key}/turns", %{text: "hi"})
             |> json_response(201)

    assert [] = conn |> get("/v1/residents/#{id}/bookmarks") |> json_response(200)

    assert %{"ref" => pref} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/bookmark-proposals", %{
               session_key: key,
               anchor_ref: ref,
               line: "this one",
               note: "it mattered"
             })
             |> json_response(201)

    assert [%{"ref" => ^pref, "state" => "open"}] =
             conn |> get("/v1/residents/#{id}/bookmark-proposals") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/bookmark-proposals", %{})
           |> json_response(422)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/tags", %{slug: "haven"})
           |> response(201)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/tags", %{slug: "Bad Slug"})
           |> json_response(422)

    assert [%{"slug" => "haven", "state" => "active"}] =
             conn |> get("/v1/residents/#{id}/tags") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/taggings", %{
             tag: "haven",
             target_kind: "conversation",
             target_id: key
           })
           |> response(201)

    assert [%{"target_kind" => "conversation", "target_id" => ^key}] =
             conn |> get("/v1/residents/#{id}/tags/haven/taggings") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> delete("/v1/residents/#{id}/taggings", %{
             tag: "haven",
             target_kind: "conversation",
             target_id: key
           })
           |> response(204)

    assert [] = conn |> get("/v1/residents/#{id}/tags/haven/taggings") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> delete("/v1/residents/#{id}/tags/haven")
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> delete("/v1/residents/#{id}/tags/haven")
           |> json_response(404)

    assert conn |> get("/v1/residents/#{id}/bookmarks/1") |> json_response(404)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/bookmarks/1/pin", %{})
           |> json_response(404)

    other = Fixtures.account!()
    assert ctx.conn |> login(other) |> get("/v1/residents/#{id}/bookmarks") |> json_response(404)
  end

  test "the identity files are the witness's to seed, draft and read; after first contact a write is a proposal",
       ctx do
    id = ctx.resident.id

    :ok =
      Oneiroi.Gaia.store_key(
        ctx.account.id,
        "sk-or-x",
        Oneiroi.Actor.new(:witness, ctx.account.id)
      )

    conn = login(ctx.conn, ctx.account)

    assert [%{"name" => "AGENTS.md", "origin" => "build"}] =
             conn |> get("/v1/residents/#{id}/files") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/files/SOUL.md", %{
             content: "# Soul\n\nCurious.",
             origin: "authored"
           })
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/files/NOPE.md", %{content: "x"})
           |> json_response(422)

    assert %{
             "content" => "The fake provider heard: make it kind",
             "model" => "fake/model",
             "prompt" => "make it kind"
           } =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/files/USER.md/draft", %{prompt: "make it kind"})
             |> json_response(200)

    assert %{
             "name" => "SOUL.md",
             "origin" => "authored",
             "version" => 1,
             "content" => "# Soul\n\n[soul/1] Curious."
           } =
             conn |> get("/v1/residents/#{id}/files/SOUL.md") |> json_response(200)

    assert %{"first_contact_at" => nil} = conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert %{"key" => key} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/sessions", %{})
             |> json_response(201)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/sessions/#{key}/turns", %{text: "hello"})
           |> json_response(201)

    assert %{"first_contact_at" => at, "formation_until" => until} =
             conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert is_binary(at) and is_binary(until)

    assert conn
           |> put_req_header("origin", origin())
           |> put("/v1/residents/#{id}/files/SOUL.md", %{content: "# Soul\n\nBolder."})
           |> json_response(422)

    assert %{"ref" => ref} =
             conn
             |> put_req_header("origin", origin())
             |> put("/v1/residents/#{id}/files/SOUL.md", %{
               content: "# Soul\n\nBolder.",
               note: "you have grown"
             })
             |> json_response(202)

    assert [%{"ref" => ^ref, "file" => "SOUL.md", "state" => "open"}] =
             conn |> get("/v1/residents/#{id}/soul-edits") |> json_response(200)

    other = Fixtures.account!()
    assert ctx.conn |> login(other) |> get("/v1/residents/#{id}/files") |> json_response(404)
  end

  test "habits: the witness gives a first one, reads the list with scores, and affirms",
       ctx do
    id = ctx.resident.id
    conn = login(ctx.conn, ctx.account)

    assert %{"number" => 1} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/habits", %{
               name: "care",
               trigger: %{words: ["garden"]},
               stance: "keep"
             })
             |> json_response(201)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/habits", %{name: "x", trigger: %{}})
           |> json_response(422)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/habits/1/affirm", %{note: "I like it"})
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/habits/9/affirm", %{note: "x"})
           |> json_response(404)

    assert [
             %{
               "number" => 1,
               "name" => "care",
               "habit" => 0.0,
               "connection" => 1.0,
               "affirmations" => 1
             }
           ] =
             conn |> get("/v1/residents/#{id}/habits") |> json_response(200)
  end

  test "regression is the witness's: tests, a run, blind cards, grades, and the pin", ctx do
    id = ctx.resident.id

    :ok =
      Oneiroi.Gaia.store_key(
        ctx.account.id,
        "sk-or-x",
        Oneiroi.Actor.new(:witness, ctx.account.id)
      )

    conn = login(ctx.conn, ctx.account)
    body = %{prompt: "When I am late?", passes_if: "asks why", fails_if: "scolds"}

    assert %{"number" => 1} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/regression/tests", body)
             |> json_response(201)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/regression/tests", %{prompt: "x"})
           |> json_response(422)

    assert [%{"number" => 1, "prompt" => "When I am late?"}] =
             conn |> get("/v1/residents/#{id}/regression/tests") |> json_response(200)

    assert %{"ref" => ref} =
             conn
             |> put_req_header("origin", origin())
             |> post("/v1/residents/#{id}/regression/runs", %{models: ["m1", "m2"]})
             |> json_response(201)

    # Answered before any model was asked: the run is running, and the
    # cards come from its job (eunomia #30), drained here.
    assert %{"run" => %{"state" => "running", "cards" => 0}, "cards" => []} =
             conn |> get("/v1/residents/#{id}/regression/runs/#{ref}") |> json_response(200)

    assert %{failure: 0, discard: 0} = Oban.drain_queue(queue: :eunomia_regression)

    assert %{
             "run" => %{"cards" => 2, "state" => "finished"},
             "cards" => [
               %{"model" => nil, "card_ref" => c1, "trace" => []},
               %{"model" => nil, "card_ref" => c2, "trace" => []}
             ],
             "results" => []
           } =
             conn |> get("/v1/residents/#{id}/regression/runs/#{ref}") |> json_response(200)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/regression/runs/#{ref}/cards/#{c1}/grade", %{
             grade: "pass"
           })
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/regression/runs/#{ref}/cards/#{c2}/grade", %{
             grade: "fail"
           })
           |> response(204)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/regression/runs/#{ref}/cards/#{c1}/favourite", %{})
           |> response(204)

    # The deck's order is by card ref, which says nothing of the model.
    assert %{"cards" => revealed, "results" => [%{"favourites" => 1, "pass_rate" => 1.0} | _]} =
             conn |> get("/v1/residents/#{id}/regression/runs/#{ref}") |> json_response(200)

    assert ["m1", "m2"] = revealed |> Enum.map(& &1["model"]) |> Enum.sort()

    assert conn |> get("/v1/residents/#{id}/regression/runs/nope") |> json_response(404)

    assert conn
           |> put_req_header("origin", origin())
           |> post("/v1/residents/#{id}/model-pin", %{model: "m1", reason: "run"})
           |> response(204)

    assert %{"chat_model" => "m1"} = conn |> get("/v1/residents/#{id}") |> json_response(200)

    other = Fixtures.account!()

    assert ctx.conn
           |> login(other)
           |> get("/v1/residents/#{id}/regression/tests")
           |> json_response(404)
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

  test "a session the store cannot open answers 503 with a retry, not 401", ctx do
    restore = fn -> Application.delete_env(:commanded, :dispatch_consistency_timeout) end
    on_exit(restore)
    Application.put_env(:commanded, :dispatch_consistency_timeout, 0)

    conn =
      ctx.conn
      |> put_req_header("origin", origin())
      |> post("/v1/session", %{email: ctx.account.email, password: Fixtures.password()})

    assert %{"error" => %{"kind" => "gaia_session_unavailable"}} = json_response(conn, 503)
    assert get_resp_header(conn, "retry-after") == ["5"]

    # The retry the header asks for opens one, and waits on the projector
    # for the timed-out session's event before the test ends.
    restore.()

    assert ctx.conn
           |> put_req_header("origin", origin())
           |> post("/v1/session", %{email: ctx.account.email, password: Fixtures.password()})
           |> json_response(201)
  end
end
