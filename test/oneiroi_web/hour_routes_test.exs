defmodule OneiroiWeb.HourRoutesTest do
  @moduledoc """
  The public hour (apsu#29), the operator's span policy (apsu#26) and the
  ops token (gaia#40, apsu#30): the hour is anyone's and shows a small
  count as "few"; the policy is a super admin's, with a note and its
  history; an ops token reads the ops routes and nothing else, and only a
  super admin mints one.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Spans
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    assert Oneiroi.Gaia.operator?(founder.id)
    other = Fixtures.account!()
    op = Actor.new(:witness, founder.id)
    witness = Actor.new(:witness, other.id)
    {:ok, op_token, _} = Oneiroi.Gaia.issue_token(founder.id, "t", op)
    {:ok, w_token, _} = Oneiroi.Gaia.issue_token(other.id, "t", witness)
    on_exit(fn -> :persistent_term.erase({Oneiroi.Apsu.Health, :hour}) end)
    {:ok, op: op_token, witness: w_token, founder: founder, other: other}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "the hour is anyone's: counted units in buckets, a small count read as few" do
    open = DateTime.add(Clock.now(), 0)
    bucket = DateTime.add(open, -rem(DateTime.to_unix(open), 300) - 300)

    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.insert_all("apsu_health", [
        %{
          bucket_at: bucket,
          kind: "http",
          name: "GET /v1/residents/:id/needs_you",
          n: 12,
          failed: 0,
          sum_ms: 3_000,
          db_ms: 1_200,
          queue_ms: 600,
          hist: %{"100" => 6, "250" => 4, "1000" => 2},
          extra: %{}
        },
        %{
          bucket_at: bucket,
          kind: "turn",
          name: "turn free_time",
          n: 1,
          failed: 0,
          sum_ms: 40_000,
          db_ms: 0,
          queue_ms: 0,
          hist: %{"60000" => 1},
          extra: %{}
        },
        %{
          bucket_at: bucket,
          kind: "pressure",
          name: "platform",
          n: 0,
          failed: 0,
          sum_ms: 0,
          db_ms: 0,
          queue_ms: 0,
          hist: %{},
          extra: %{
            "jobs_waiting" => 2,
            "oldest_wait_s" => 30,
            "failures" => %{"brain_turn_crashed" => 1}
          }
        }
      ])
    end)

    :persistent_term.erase({Oneiroi.Apsu.Health, :hour})
    hour = build_conn() |> get("/v1/hour") |> json_response(200)

    assert %{"few_below" => 5, "trend" => trend, "work" => work, "pressure" => pressure} = hour
    assert length(trend) == 12

    assert %{"units" => 12, "p50_ms" => 100, "p95_ms" => 1000, "mean_db_ms" => 100} =
             Enum.find(work, &(&1["name"] == "GET /v1/residents/:id/needs_you"))

    # One free-time run says when she was in free time: few, and no time.
    assert %{"units" => "few", "p95_ms" => nil} = Enum.find(work, &(&1["kind"] == "turn"))

    assert %{"jobs_waiting" => 2, "failures_by_kind" => %{"brain_turn_crashed" => "few"}} =
             pressure
  end

  test "every unit is kept until the operator samples, with a note and its history", ctx do
    assert Spans.policy().mode == "all"

    assert %{"mode" => "sample", "sample_percent" => 5, "slow_ms" => 400} =
             ctx.op
             |> as()
             |> put("/v1/platform/span-policy", %{
               mode: "sample",
               slow_ms: 400,
               sample_percent: 5,
               note: "a second household"
             })
             |> json_response(200)

    assert %{
             "span_policy" => %{"mode" => "sample"},
             "span_policies" => [%{"note" => "a second household"} | _]
           } =
             ctx.op |> as() |> get("/v1/platform") |> json_response(200)

    assert ctx.op
           |> as()
           |> put("/v1/platform/span-policy", %{mode: "sample"})
           |> json_response(422)

    assert ctx.witness
           |> as()
           |> put("/v1/platform/span-policy", %{mode: "all", note: "x"})
           |> json_response(403)
  after
    Spans.set_policy("all", 250, 1, "back to every unit", nil)
  end

  test "an ops token reads the ops routes and nothing else; only a super admin mints one", ctx do
    assert %{"token" => ops} =
             ctx.op
             |> as()
             |> post("/v1/tokens", %{label: "claude-code", scope: "ops"})
             |> json_response(201)

    assert ctx.witness
           |> as()
           |> post("/v1/tokens", %{label: "x", scope: "ops"})
           |> json_response(422)

    assert ctx.witness
           |> as()
           |> post("/v1/tokens", %{label: "x", scope: "admin"})
           |> json_response(422)

    assert %{"failures" => _} = ops |> as() |> get("/v1/ops/failures") |> json_response(200)
    assert is_list(ops |> as() |> get("/v1/ops/spans") |> json_response(200))
    assert is_list(ops |> as() |> get("/v1/ops/spans/summary") |> json_response(200))

    # Nothing else: not the account, not the platform, not a write.
    assert ops |> as() |> get("/v1/me") |> json_response(401)
    assert ops |> as() |> get("/v1/platform") |> json_response(401)
    assert ops |> as() |> post("/v1/tokens", %{label: "more"}) |> json_response(401)

    assert ctx.op
           |> as()
           |> get("/v1/tokens")
           |> json_response(200)
           |> Enum.any?(&(&1["label"] == "claude-code" and &1["scope"] == "ops"))
  end
end
