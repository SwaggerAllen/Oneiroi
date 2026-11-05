defmodule OneiroiWeb.SignUpTest do
  @moduledoc """
  gaia#19 (design/mvp.md item 1; the witness, 2026-11-05: no email
  verification before the door opens): closed refuses; invite takes a
  code, checked before anything is created and redeemed onto the new
  household; open takes anyone. Sign-up logs the new account in.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    # Asked about, the founding account's grant is recorded (gaia#16).
    assert Gaia.operator?(founder.id)
    {:ok, op: Actor.new(:witness, founder.id)}
  end

  defp sign_up(body),
    do: build_conn() |> put_req_header("origin", origin()) |> post("/v1/door/sign-up", body)

  defp origin, do: OneiroiWeb.Endpoint.url()
  defp email, do: "new-#{System.unique_integer([:positive])}@example.org"

  test "closed refuses; invite wants a code and redeems it onto the new household; the account is logged in",
       ctx do
    assert %{"state" => "closed"} = build_conn() |> get("/v1/door") |> json_response(200)
    assert sign_up(%{email: email(), password: "long enough pw"}) |> json_response(403)

    :ok = Gaia.set_gate("invite", "the alpha", ctx.op)
    assert %{"state" => "invite"} = build_conn() |> get("/v1/door") |> json_response(200)

    assert %{"error" => %{"kind" => "gaia_invite_required"}} =
             sign_up(%{email: email(), password: "long enough pw"}) |> json_response(422)

    assert %{"error" => %{"kind" => "gaia_invite_unknown"}} =
             sign_up(%{email: email(), password: "long enough pw", code: "ZZZZ-ZZZZ-ZZZZ"})
             |> json_response(422)

    {:ok, %{code: code}} = Gaia.issue_invite(%{}, "for a friend", ctx.op)

    assert %{"plan" => "monthly", "price_nanos" => 0} =
             build_conn()
             |> put_req_header("origin", origin())
             |> post("/v1/door/check", %{code: code})
             |> json_response(200)

    assert %{"error" => %{"kind" => "gaia_signup_invalid"}} =
             sign_up(%{email: email(), password: "short", code: code}) |> json_response(422)

    address = email()
    conn = sign_up(%{email: address, password: "long enough pw", code: code})
    assert %{"account_id" => id} = json_response(conn, 201)

    assert %{"household" => %{"terms" => %{"plan" => "monthly"}}} =
             conn
             |> recycle()
             |> put_req_header("origin", origin())
             |> get("/v1/me")
             |> json_response(200)

    assert Gaia.household(id).terms.source =~ "invite:"

    # The code is checked before the email, so a used code says so first;
    # a good code on a taken email says the email is taken.
    assert %{"error" => %{"kind" => "gaia_invite_spent"}} =
             sign_up(%{email: address, password: "long enough pw", code: code})
             |> json_response(422)

    {:ok, %{code: another}} = Gaia.issue_invite(%{}, "another", ctx.op)

    assert %{"error" => %{"kind" => "gaia_email_taken"}} =
             sign_up(%{email: address, password: "long enough pw", code: another})
             |> json_response(409)
  end

  test "open takes anyone, a code optional", ctx do
    :ok = Gaia.set_gate("open", "launch", ctx.op)

    assert %{"account_id" => id} =
             sign_up(%{email: email(), password: "long enough pw"}) |> json_response(201)

    assert %{terms: nil} = Gaia.household(id)
  end
end
