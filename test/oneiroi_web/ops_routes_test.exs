defmodule OneiroiWeb.OpsRoutesTest do
  @moduledoc """
  apsu#23 (design/logging-and-alerting.md step 1; the witness: "a formal,
  owned querying surface"): the operator reads the failure ring as facts,
  scrubbed; the witness reads the resident's heartbeats, an adapter's
  last ask of /waiting among them. Nobody else reads either.
  """
  use OneiroiWeb.ConnCase, async: false

  require Logger

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    assert Oneiroi.Gaia.operator?(founder.id)
    other = Fixtures.account!()
    resident = Fixtures.resident!(other)
    op = Actor.new(:witness, founder.id)
    witness = Actor.new(:witness, other.id)
    {:ok, op_token, _} = Oneiroi.Gaia.issue_token(founder.id, "t", op)
    {:ok, w_token, _} = Oneiroi.Gaia.issue_token(other.id, "t", witness)
    {:ok, reader} = AgathosDaimon.register_adapter(resident.id, "scrape", "reader", witness)
    {:ok, op: op_token, witness: w_token, reader: reader, id: resident.id}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "the operator reads the ring as facts, the credential scrubbed; a witness is refused",
       ctx do
    marker = "ops-probe-#{System.unique_integer([:positive])}"

    Logger.error("#{marker} with sk-or-v1-abcdef0123456789",
      component: "gaia",
      error_kind: :gaia_probe,
      error_site: :gaia_probe_site
    )

    assert %{"failures" => failures, "discarded_jobs" => _} =
             ctx.op |> as() |> get("/v1/ops/failures?kind=gaia_probe") |> json_response(200)

    assert [%{"error_site" => "gaia_probe_site", "component" => "gaia", "message" => message} | _] =
             failures

    assert message =~ marker
    refute message =~ "sk-or-v1-abcdef"

    assert ctx.witness |> as() |> get("/v1/ops/failures") |> json_response(403)
  end

  test "the witness reads the heartbeats: free time never ran is late, the reader is late until it asks",
       ctx do
    beats =
      ctx.witness |> as() |> get("/v1/residents/#{ctx.id}/ops/heartbeats") |> json_response(200)

    assert %{"late" => true, "last" => nil} = Enum.find(beats, &(&1["name"] == "free time"))
    assert %{"late" => true} = Enum.find(beats, &(&1["name"] =~ "adapter scrape"))

    assert ctx.reader |> as() |> get("/v1/residents/#{ctx.id}/waiting") |> json_response(200)

    beats =
      ctx.witness |> as() |> get("/v1/residents/#{ctx.id}/ops/heartbeats") |> json_response(200)

    assert %{"late" => false, "last" => last} =
             Enum.find(beats, &(&1["name"] =~ "adapter scrape"))

    assert is_binary(last)

    assert ctx.op |> as() |> get("/v1/residents/#{ctx.id}/ops/heartbeats") |> json_response(404)
  end
end
