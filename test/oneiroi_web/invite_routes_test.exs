defmodule OneiroiWeb.InviteRoutesTest do
  @moduledoc """
  gaia#18 over HTTP: the operator issues a code and is answered it once;
  anyone else is refused the operator's routes; a witness redeems a code
  onto its household and reads the terms back on /v1/me.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    guest = Fixtures.account!()
    {:ok, op} = token(founder.id)
    {:ok, guest_token} = token(guest.id)
    {:ok, op: op, guest: guest_token}
  end

  defp token(account_id) do
    {:ok, raw, _hash} = Oneiroi.Gaia.issue_token(account_id, "t", Actor.new(:witness, account_id))
    {:ok, raw}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "the operator issues, the guest is refused the operator's routes and redeems onto its household",
       ctx do
    assert ctx.guest |> as() |> get("/v1/platform/invites") |> response(403)

    assert %{"code" => code} =
             ctx.op
             |> as()
             |> post("/v1/platform/invites", %{note: "for a friend", discount_pct: 50})
             |> json_response(201)

    assert %{"invites" => [%{"redeemed" => 0, "price_nanos" => 10_000_000_000}]} =
             ctx.op |> as() |> get("/v1/platform/invites") |> json_response(200)

    assert ctx.op
           |> as()
           |> post("/v1/platform/invites", %{note: "x", expires_at: "tomorrow"})
           |> json_response(422)

    assert %{"granted" => %{"plan" => "monthly", "price_nanos" => 10_000_000_000}} =
             ctx.guest |> as() |> post("/v1/me/invite", %{code: code}) |> json_response(200)

    assert %{"household" => %{"terms" => %{"plan" => "monthly"}}} =
             ctx.guest |> as() |> get("/v1/me") |> json_response(200)

    assert %{"error" => _} =
             ctx.guest |> as() |> post("/v1/me/invite", %{code: code}) |> json_response(422)
  end
end
