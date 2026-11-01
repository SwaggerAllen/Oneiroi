defmodule OneiroiWeb.ContextPreviewTest do
  @moduledoc """
  The two witness reads of what the resident is given (kumbukumbu #38,
  brain #41): Memory's index as it stands now, and Chat's preview of the
  next turn; withheld words never on the wire; another account answered
  404 and an adapter's token refused before the controller.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    id = resident.id
    actor = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(id, account.id, actor)
    Honcho.clear(for: id)
    on_exit(fn -> Honcho.clear(for: id) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok,
     conn: conn, id: id, key: key, account: account, actor: actor, brain: brain, at: Clock.now()}
  end

  defp capture!(ctx, key, ref) do
    :ok =
      Kumbukumbu.capture(
        ctx.id,
        key,
        ref,
        ctx.at,
        [%{role: :assistant, content: "a moment", sent_at: ctx.at, actor: ctx.brain}],
        ctx.brain
      )
  end

  defp bookmark!(ctx, key, ref, n, line) do
    {:ok, ^n} =
      Kumbukumbu.add_bookmark(ctx.id, %{session_key: key, anchor_ref: ref, line: line}, ctx.brain)
  end

  test "Memory's index is what the index holds now, with no turn ever taken, worded by the server",
       ctx do
    {:ok, ikey} =
      Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.account.id], ctx.actor,
        domain: "intimate"
      )

    capture!(ctx, ctx.key, "t-main")
    capture!(ctx, ikey, "t-intimate")
    bookmark!(ctx, ctx.key, "t-main", 1, "the garden")
    bookmark!(ctx, ikey, "t-intimate", 2, "the night we talked")
    bookmark!(ctx, ctx.key, "t-main", 3, "the heron")
    :ok = Kumbukumbu.pin_bookmark(ctx.id, 1, ctx.actor)

    budget = Oneiroi.Config.fetch!(:kumbukumbu, :index_tokens)

    assert %{
             "listed" => [1, 3],
             "left_out" => 0,
             "elsewhere" => 1,
             "description" => description
           } = ctx.conn |> get("/v1/residents/#{ctx.id}/index") |> json_response(200)

    assert description =~ "under a budget of #{budget} tokens (a bound)"
    assert description =~ "listed only in that room's conversations"

    # Every row is unmarked: the tab never read last_indexed_at.
    assert ctx.conn
           |> get("/v1/residents/#{ctx.id}/bookmarks")
           |> json_response(200)
           |> Enum.all?(&is_nil(&1["last_indexed_at"]))
  end

  test "an empty memory lists nothing and says so", ctx do
    assert %{"listed" => [], "left_out" => 0, "elsewhere" => 0, "description" => d} =
             ctx.conn |> get("/v1/residents/#{ctx.id}/index") |> json_response(200)

    assert d =~ "0 bookmarks listed"
  end

  test "the preview answers the sections, and withheld words are not on the wire", ctx do
    :ok = Oneiroi.Gaia.store_key(ctx.account.id, "sk-or-test", ctx.actor)
    :ok = AgathosDaimon.write_file(ctx.id, "SOUL.md", "# Soul\n\nCurious.", %{}, ctx.actor)
    Model.reply("I hear you.", for: ctx.id)
    on_exit(fn -> Model.clear(for: ctx.id) end)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(ctx.id, ctx.key, "hello", ctx.actor)

    Honcho.put_context(
      ctx.id,
      "resident-" <> ctx.id,
      "witness-" <> ctx.account.id,
      "HONCHO-ONLY words"
    )

    bookmark!(ctx, ctx.key, ref, 1, "the heron")

    response =
      ctx.conn |> post("/v1/residents/#{ctx.id}/sessions/#{ctx.key}/preview", %{text: "hi"})

    body = response.resp_body

    assert %{"description" => _, "compacts_first" => false, "sections" => sections} =
             json_response(response, 200)

    refute body =~ "HONCHO-ONLY"

    by = Map.new(sections, &{&1["label"], &1})
    assert %{"text" => nil, "shown" => false, "note" => note} = by["honcho"]
    assert note =~ "No screen shows it to you."
    assert %{"text" => nil, "shown" => false} = by["index"]
    assert %{"text" => "# SOUL.md" <> _, "shown" => true} = by["SOUL.md"]
    assert %{"run" => false, "text" => nil} = by["madeleine"]
  end

  test "the preview is the witness's: another account, another resident's session and a private session get 404, an adapter's token is refused",
       ctx do
    path = "/v1/residents/#{ctx.id}/sessions/#{ctx.key}/preview"
    other = Fixtures.account!()

    other_conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: other.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    assert %{"error" => %{"kind" => "agathos_daimon_not_witnessed"}} =
             other_conn |> post(path, %{}) |> json_response(404)

    assert other_conn |> get("/v1/residents/#{ctx.id}/index") |> json_response(404)

    {:ok, token} = AgathosDaimon.register_adapter(ctx.id, "claude-code", "brain", ctx.actor)

    adapter = fn conn -> put_req_header(conn, "authorization", "Bearer " <> token) end

    # An adapter's token opens the adapter contract's four paths and is
    # refused before any controller everywhere else (RequirePrincipal):
    # a 401 naming no principal, as on every account route.
    for refused <- [
          build_conn() |> adapter.() |> post(path, %{}),
          build_conn() |> adapter.() |> get("/v1/residents/#{ctx.id}/index")
        ] do
      assert %{"error" => %{"kind" => "gaia_not_a_principal"}} = json_response(refused, 401)
    end

    # A session of another resident the same account witnesses is not
    # this resident's next turn.
    second = Fixtures.resident!(ctx.account)
    {:ok, second_key} = Kumbukumbu.main_session(second.id, ctx.account.id, ctx.actor)

    assert %{"error" => %{"kind" => "no_such_session"}} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/sessions/#{second_key}/preview", %{})
             |> json_response(404)

    {:ok, private} =
      Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.account.id], ctx.actor,
        private: true
      )

    assert %{"error" => %{"kind" => "kumbukumbu_session_private"}} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/sessions/#{private}/preview", %{})
             |> json_response(404)
  end
end
