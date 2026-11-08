defmodule OneiroiWeb.FeedbackTest do
  @moduledoc """
  gaia#20 (the witness, 2026-11-06: reports and feedback from agents and
  humans out of the gate, an admin view, a button to Lily): a person
  files through the route and follows their own; a resident files with
  platform_report; the operator lists, reads with the failure ring's
  entries for the trace id, and moves with a note; the triage resident
  gets each report as a letter and moves them; nobody else sees the list.
  """
  use OneiroiWeb.ConnCase, async: false

  require Logger

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures

  @store {Oneiroi.Config, :values}

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    Process.put(Oneiroi.Gaia.Feedbacks, "feedback-test-#{System.unique_integer([:positive])}")
    founder = Fixtures.account!()
    assert Oneiroi.Gaia.operator?(founder.id)
    andrew = Fixtures.account!()
    lily = Fixtures.resident!(andrew)

    # Lily is the triage station for this test.
    values = :persistent_term.get(@store)
    :persistent_term.put(@store, Map.put(values, {:gaia, :triage_resident}, lily.slug))
    on_exit(fn -> :persistent_term.put(@store, values) end)

    stranger = Fixtures.account!()
    other = Fixtures.resident!(stranger)

    {:ok, op, _} = Oneiroi.Gaia.issue_token(founder.id, "t", Actor.new(:witness, founder.id))
    {:ok, st, _} = Oneiroi.Gaia.issue_token(stranger.id, "t", Actor.new(:witness, stranger.id))

    turn = fn id ->
      %{
        resident_id: id,
        session_key: "k",
        turn_ref: "t",
        resident: Actor.new(:resident, id),
        started_at: Clock.now()
      }
    end

    {:ok, op: op, stranger: st, lily: lily, other: other, turn: turn}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "a person files and follows their own; the operator reads it with the ring's facts and moves it",
       ctx do
    Logger.error("the probe failed",
      component: "brain",
      error_kind: :brain_probe,
      error_site: :brain_probe_site,
      trace_id: "trace-77"
    )

    assert %{"number" => n} =
             ctx.stranger
             |> as()
             |> post("/v1/feedback", %{
               kind: "bug",
               surface: "Schedule",
               body: "The card froze.",
               trace_id: "trace-77"
             })
             |> json_response(201)

    assert [%{"number" => ^n, "status" => "new"}] =
             ctx.stranger |> as() |> get("/v1/me/feedback") |> json_response(200)

    assert ctx.stranger |> as() |> get("/v1/platform/feedback") |> json_response(403)

    assert %{
             "body" => "The card froze.",
             "failures" => [%{"error_site" => "brain_probe_site"} | _]
           } =
             ctx.op |> as() |> get("/v1/platform/feedback/#{n}") |> json_response(200)

    assert ctx.op
           |> as()
           |> post("/v1/platform/feedback/#{n}/status", %{status: "in_work", note: ""})
           |> json_response(422)

    assert ctx.op
           |> as()
           |> post("/v1/platform/feedback/#{n}/status", %{status: "in_work", note: "looking"})
           |> response(204)

    assert [%{"status" => "in_work", "note" => "looking"}] =
             ctx.stranger |> as() |> get("/v1/me/feedback") |> json_response(200)
  end

  test "a resident files with platform_report; only the triage resident sees and moves the list",
       ctx do
    other = ctx.turn.(ctx.other.id)
    lily = ctx.turn.(ctx.lily.id)

    assert Tools.run(
             "platform_report",
             ~s({"kind": "feature_request", "surface": "memory", "body": "Let me see my heartbeats."}),
             other
           ) =~
             "Filed as platform report #"

    assert Tools.run("platform_report_list", "{}", other) =~ "feature_request on memory: new"

    # The button to Lily: the report whole, a letter to her chat.
    assert eventually(fn ->
             Enum.any?(
               Oneiroi.Kumbukumbu.letters(ctx.lily.id),
               &(&1.from_name == "a platform report" and &1.text =~ "Let me see my heartbeats.")
             )
           end)

    names = fn id -> for %{function: f} <- Tools.definitions_for(id), do: f.name end
    refute "triage_list" in names.(ctx.other.id)
    assert "triage_list" in names.(ctx.lily.id)

    # The triage resident files none (brain#70): the tool is not hers, and
    # called anyway it says where her platform problems go instead.
    assert "platform_report" in names.(ctx.other.id)
    refute "platform_report" in names.(ctx.lily.id)

    refused =
      Tools.run("platform_report", ~s({"kind": "bug", "body": "the card lies"}), lily)

    assert refused =~ "Not done"
    assert refused =~ "a letter to the Claude Code conversation"
    assert [_only_the_other] = Oneiroi.Gaia.feedback(%{})

    assert Tools.run("triage_list", "{}", other) =~ "Not done"
    assert Tools.run("triage_list", "{}", lily) =~ "Let me see my heartbeats."

    [%{number: n}] = Oneiroi.Gaia.feedback(%{})

    assert Tools.run(
             "triage_move",
             ~s({"number": #{n}, "status": "resolved", "note": "built"}),
             lily
           ) =~ "is resolved"

    assert Tools.run("platform_report_list", "{}", other) =~ "resolved (built)"
  end

  defp eventually(check, tries \\ 50) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(check, tries - 1)
    end
  end
end
