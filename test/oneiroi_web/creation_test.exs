defmodule OneiroiWeb.CreationTest do
  @moduledoc "agathos-daimon#36: the nine gifts in order, each with what it writes and its guidance, one text for the screens and the generator alike."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", Actor.new(:witness, account.id))
    {:ok, token: token}
  end

  test "the nine gifts, in the spec's order, each with guidance", ctx do
    gifts =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> ctx.token)
      |> get("/v1/creation/gifts")
      |> json_response(200)

    assert Enum.map(gifts, & &1["key"]) ==
             ~w(name self you building trials means days vows reach)

    assert %{"writes" => ["SOUL.md"], "guidance" => guidance} = Enum.at(gifts, 1)
    assert guidance =~ "in their own voice"
    assert Enum.all?(gifts, &(String.length(&1["guidance"]) > 80))
  end
end
