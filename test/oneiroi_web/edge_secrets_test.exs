defmodule OneiroiWeb.EdgeSecretsTest do
  @moduledoc "Every credential a request carries is wrapped before it crosses a system boundary."
  use OneiroiWeb.ConnCase, async: false

  # A crash report prints the arguments of the frame that raised. On
  # 2026-11-01 that frame held a clone URL with Lily's read token, and
  # the token went into the service log. A credential is therefore
  # wrapped in `Oneiroi.Config.Secret` by the controller, and these watch
  # the boundary function itself, through call tracing, to see what it
  # was handed: the ports accept a plain value too (tasks and tests pass
  # one), so nothing downstream would notice a controller that forgot.

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, account: account}
  end

  # The arguments the boundary function was called with, as a call trace
  # saw them. The tracer is its own process forwarding to the test: a
  # process tracing itself is accepted and delivered nothing, measured,
  # and a test reading an empty mailbox reads it the same way either way.
  defp traced({module, function, _arity} = mfa, request) do
    test = self()
    tracer = spawn_link(fn -> forward(test) end)
    :erlang.trace(test, true, [:call, {:tracer, tracer}])
    1 = :erlang.trace_pattern(mfa, true, [:local])

    try do
      request.()
    after
      :erlang.trace(test, false, [:call])
      :erlang.trace_pattern(mfa, false, [:local])
    end

    assert_receive {:traced, ^module, ^function, args}, 1_000
    args
  end

  defp forward(test) do
    receive do
      {:trace, _pid, :call, {module, function, args}} ->
        send(test, {:traced, module, function, args})
    end

    forward(test)
  end

  test "the password and the code at login" do
    account = Fixtures.account!()

    [_email, password, code] =
      traced({Oneiroi.Gaia, :login, 3}, fn ->
        build_conn()
        |> put_req_header("origin", OneiroiWeb.Endpoint.url())
        |> post("/v1/session", %{email: account.email, password: "wrong", code: "123456"})
      end)

    assert %Secret{} = password
    assert %Secret{} = code
  end

  test "the provider key", %{conn: conn} do
    [_account, key, _actor] =
      traced({Oneiroi.Gaia, :store_key, 3}, fn ->
        put(conn, "/v1/me/key", %{key: "sk-or-v1-TESTONLY"})
      end)

    assert %Secret{} = key
  end

  test "the import URL, which carries a token in its userinfo", %{conn: conn} do
    [url, _attrs, _account, _actor] =
      traced({Oneiroi.SimaQian, :import_resident, 4}, fn ->
        post(conn, "/v1/residents/import", %{
          url: "https://x-access-token:github_pat_TESTONLY@127.0.0.1:9/x.git",
          name: "Lily",
          slug: "lily-edge"
        })
      end)

    assert %Secret{} = url
  end

  test "the backup remote's token", %{conn: conn, account: account} do
    resident = Fixtures.resident!(account)

    [_id, _url, token, _actor] =
      traced({Oneiroi.SimaQian, :set_remote, 4}, fn ->
        put(conn, "/v1/residents/#{resident.id}/remote", %{
          url: "https://github.com/lily/records.git",
          token: "github_pat_TESTONLY"
        })
      end)

    assert %Secret{} = token
  end
end
