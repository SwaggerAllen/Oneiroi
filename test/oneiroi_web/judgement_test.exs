defmodule OneiroiWeb.JudgementTest do
  @moduledoc "Judgement over HTTP: the witness reads positions, disputes and the ratio, chooses the judge, resolves predictions, runs a night by hand."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, brain: brain, key: key}
  end

  test "the judgement routes", %{conn: conn, id: id, brain: brain, key: key} do
    ctx = %{session_key: key, turn_ref: "t1"}
    {:ok, 1} = Eunomia.take_position(id, "Tea first.", ctx, brain)
    {:ok, 2} = Eunomia.replace_position(id, 1, "Coffee first.", ctx, brain)
    Fake.reply("ADVICE: concede\nBecause.", for: id)

    {:ok, %{ref: ref}} =
      Eunomia.check_dispute(
        id,
        Map.merge(ctx, %{claim: "a", stance: "b", position_number: 2}),
        brain
      )

    :ok = Eunomia.settle_dispute(id, ref, "conceded", "fine", brain)
    {:ok, 1} = Eunomia.log_prediction(id, "Rain.", ~U[2026-11-01 00:00:00Z], ctx, brain)

    assert [%{"number" => 1, "replaced_by" => 2}, %{"number" => 2, "replaces" => 1}] =
             conn |> get("/v1/residents/#{id}/positions") |> json_response(200)

    assert [
             %{
               "ref" => ^ref,
               "advice" => "concede",
               "settlement" => "conceded",
               "judge_model" => "fake/judge"
             }
           ] =
             conn |> get("/v1/residents/#{id}/disputes") |> json_response(200)

    assert %{
             "judge_model" => "fake/judge",
             "chosen" => nil,
             "weeks" => [%{"settled" => 1, "earned" => 1}]
           } =
             conn |> get("/v1/residents/#{id}/judgement") |> json_response(200)

    assert conn
           |> put("/v1/residents/#{id}/judgement/judge", %{model: "fake/other"})
           |> response(204)

    assert %{"error" => %{"kind" => "eunomia_judge_is_the_chat_model"}} =
             conn
             |> put("/v1/residents/#{id}/judgement/judge", %{model: "fake/model"})
             |> json_response(422)

    assert %{"chosen" => "fake/other", "changes" => [%{"model" => "fake/other"}]} =
             conn |> get("/v1/residents/#{id}/judgement") |> json_response(200)

    assert %{"open" => [%{"number" => 1}], "resolved" => [], "tally" => %{}} =
             conn |> get("/v1/residents/#{id}/predictions") |> json_response(200)

    assert conn
           |> post("/v1/residents/#{id}/predictions/1/resolve", %{
             outcome: "wrong",
             note: "dry all day"
           })
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/predictions/1/resolve", %{outcome: "wrong"})
           |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/predictions/9/resolve", %{outcome: "void", note: "x"})
           |> json_response(404)

    assert %{
             "resolved" => [%{"number" => 1, "outcome" => "wrong", "note" => "dry all day"}],
             "tally" => %{"wrong" => 1}
           } =
             conn |> get("/v1/residents/#{id}/predictions") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/nights/2026-10-25", %{}) |> response(204)

    assert %{"already" => true} =
             conn |> post("/v1/residents/#{id}/nights/2026-10-25", %{}) |> json_response(200)

    assert %{"error" => %{"kind" => "eunomia_night_out_of_reach"}} =
             conn |> post("/v1/residents/#{id}/nights/2027-01-01", %{}) |> json_response(422)

    assert [%{"day" => "2026-10-25", "outcome" => "judged", "messages" => 0, "movements" => []}] =
             conn |> get("/v1/residents/#{id}/nights") |> json_response(200)
  end

  test "another witness's resident is nobody's judgement", %{conn: conn} do
    other = Fixtures.resident!(Fixtures.account!())
    assert conn |> get("/v1/residents/#{other.id}/judgement") |> json_response(404)
  end
end
