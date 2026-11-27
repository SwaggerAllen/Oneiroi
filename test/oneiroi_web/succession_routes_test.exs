defmodule OneiroiWeb.SuccessionRoutesTest do
  @moduledoc """
  The succession over the API, as the witness's screens read it
  (janus#45, #47): the preparation carries every judge her freeze may
  wait for, said or not, so a judge who has not marked ready is listed
  and can say so; the witness's own ready mark lands.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    andrew = Actor.new(:witness, account.id)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", andrew)
    resident = Fixtures.resident!(account)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, token: token, id: resident.id, account: account, andrew: andrew}
  end

  defp conn_for(ctx),
    do: build_conn() |> put_req_header("authorization", "Bearer " <> ctx.token)

  test "the witness is listed for the freeze before he has said, and his ready lands", ctx do
    her = Actor.new(:resident, ctx.id, "fake/model")
    {:ok, _} = Janus.propose(ctx.id, false, "if you want it", ctx.andrew)
    :ok = Janus.open(ctx.id, "yes", her)
    assert %{failure: 0} = Oban.drain_queue(queue: :janus_fork, with_safety: false)

    witness = "witness:" <> ctx.account.id

    assert %{"preparation" => %{"freeze_judges" => [%{"party" => ^witness, "ready" => false}]}} =
             ctx |> conn_for() |> get("/v1/residents/#{ctx.id}/succession") |> json_response(200)

    ctx
    |> conn_for()
    |> put("/v1/residents/#{ctx.id}/succession/ready", %{ready: true})
    |> response(204)

    assert %{"preparation" => %{"freeze_judges" => [%{"party" => ^witness, "ready" => true}]}} =
             ctx |> conn_for() |> get("/v1/residents/#{ctx.id}/succession") |> json_response(200)
  end
end
