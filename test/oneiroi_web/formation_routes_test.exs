defmodule OneiroiWeb.FormationRoutesTest do
  @moduledoc """
  agathos-daimon#47 over HTTP: the operator returns a resident who has
  lived nothing yet to forming, by slug, with a note; anyone else is
  refused the route.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    guest = Fixtures.account!()
    {:ok, op, _} = Oneiroi.Gaia.issue_token(founder.id, "t", Actor.new(:witness, founder.id))
    {:ok, other, _} = Oneiroi.Gaia.issue_token(guest.id, "t", Actor.new(:witness, guest.id))
    slug = "scarlett-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Scarlett", slug, guest.id, Actor.new(:witness, guest.id))
    {:ok, op: op, other: other, slug: slug, id: id}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "the operator returns her to forming; the witness himself is refused the route", ctx do
    path = "/v1/platform/residents/#{ctx.slug}/formation"

    assert ctx.other |> as() |> post(path, %{note: "please"}) |> response(403)

    assert ctx.op
           |> as()
           |> post("/v1/platform/residents/nobody/formation", %{note: "x"})
           |> response(404)

    assert ctx.op
           |> as()
           |> post(path, %{note: "made before formation; trials first"})
           |> response(204)

    assert {:ok, %{state: "forming", admission: "forming"}} = AgathosDaimon.fetch(ctx.id)
    assert ctx.op |> as() |> post(path, %{note: "again"}) |> json_response(422)
  end
end
