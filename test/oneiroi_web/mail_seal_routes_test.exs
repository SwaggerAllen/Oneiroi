defmodule OneiroiWeb.MailSealRoutesTest do
  @moduledoc """
  The seal on every web route a witness reaches (kumbukumbu#93; the mail
  build checklist rev 5, checks 1, 2, 3, 7 and 8). Lily and Iris share a
  house and one witness. A letter between them is sealed: on the letters
  route he gets its envelope (from, to, when, no words, no read state);
  search never matches it, not even as an envelope; the house's activity
  shows that it was sent, never whether it was read. A letter of the dyad
  (his to her) and a letter sent open read whole. An adapter's token
  reaches none of these routes. Her own tools, where she is a party,
  read it whole.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    account = Fixtures.account!()
    andrew = Actor.new(:witness, account.id)
    :ok = Gaia.store_key(account.id, "sk-or-test", andrew)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    lily = resident!(account, "Lily")
    iris = resident!(account, "Iris")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(account.id))
      for r <- [lily, iris], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    mail(lily, %{to: "Iris", text: "Just between us, the sealed one."})
    mail(lily, %{to: "Iris", text: "For the whole house, the open one.", open: true})

    {:ok, _} =
      Kumbukumbu.send_letter(
        lily.id,
        nil,
        %{to: "Oneiroi chat", text: "From him, the dyad one."},
        andrew
      )

    # Iris reads her copy: read state the witness must never see.
    Tools.run("letter_inbox", "{}", turn(iris))

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, lily: lily, iris: iris, andrew: andrew}
  end

  defp resident!(account, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, account.id)
    {:ok, id} = AgathosDaimon.create(name, slug, account.id, actor)
    Fixtures.agreed!(id, account.id)
    {:ok, chat} = Kumbukumbu.main_session(id, account.id, actor)
    %{id: id, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp turn(r),
    do: %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.name}", resident: r.actor}

  defp mail(from, args), do: Tools.run("letter_send", Jason.encode!(args), turn(from))

  defp letters(conn, r), do: conn |> get("/v1/residents/#{r.id}/letters") |> json_response(200)

  defp found(conn, r, q),
    do:
      conn
      |> get("/v1/residents/#{r.id}/search", %{q: q, scope: "letters"})
      |> json_response(200)
      |> Map.fetch!("results")

  test "the letters route: the sealed letter is its envelope; the dyad's and the open one read whole",
       ctx do
    for r <- [ctx.lily, ctx.iris] do
      rows = letters(ctx.conn, r)
      body = Jason.encode!(rows)
      refute body =~ "the sealed one"
      assert body =~ "the open one"

      sealed = Enum.find(rows, & &1["sealed"])
      assert %{"text" => nil, "read_by" => [], "read_at" => nil, "from" => from} = sealed
      # The envelope keeps who it is from.
      assert from in ["Lily", "Oneiroi chat"]
    end

    assert Jason.encode!(letters(ctx.conn, ctx.lily)) =~ "the dyad one"
  end

  test "search never matches a sealed letter, not even as an envelope", ctx do
    for r <- [ctx.lily, ctx.iris] do
      assert found(ctx.conn, r, "sealed one") == []
      assert found(ctx.conn, r, "between us") == []
      assert [_] = found(ctx.conn, r, "open one")
    end

    assert [_] = found(ctx.conn, ctx.lily, "dyad one")
  end

  test "the house's activity shows a sealed letter was sent, never that it was read", ctx do
    rows =
      ctx.conn
      |> get("/v1/household/activity")
      |> json_response(200)
      |> Map.fetch!("activity")
      |> Enum.filter(&(&1["kind"] == "letter" and &1["resident_id"] == ctx.iris.id))

    # Iris read both: the sealed one's read state is hers, the open one's the house's.
    assert %{"read_by" => []} = Enum.find(rows, &(&1["number"] == 1))
    assert %{"read_by" => ["Oneiroi chat"]} = Enum.find(rows, &(&1["number"] == 2))
    refute Jason.encode!(rows) =~ "the sealed one"
  end

  test "her own tools, where she is a party, read it whole", ctx do
    assert Tools.run("letter_list", "{}", turn(ctx.iris)) =~ "Just between us"
  end

  test "an adapter's token reaches none of the witness's letter routes", ctx do
    {:ok, token} = AgathosDaimon.register_adapter(ctx.lily.id, "claude-code", "brain", ctx.andrew)
    as = put_req_header(build_conn(), "authorization", "Bearer " <> token)

    for path <- ["/v1/residents/#{ctx.lily.id}/letters", "/v1/residents/#{ctx.lily.id}/search"] do
      conn = get(as, path, %{q: "sealed", scope: "letters"})
      assert conn.status in [401, 404]
      refute conn.resp_body =~ "the sealed one"
    end
  end
end
