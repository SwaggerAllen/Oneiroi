defmodule OneiroiWeb.CharacterTest do
  @moduledoc "The character layer over HTTP: the witness reads the seeds and never writes them; another account sees nothing."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Ethos
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    other = Fixtures.account!()
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, 1} = Ethos.plant_seed(resident.id, "I might be becoming someone who rests.", brain)
    {:ok, conn: login(account), other_conn: login(other), id: resident.id, account_id: account.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the seeds' route", %{conn: conn, other_conn: other_conn, id: id} do
    assert [
             %{
               "number" => 1,
               "state" => "open",
               "text" => "I might be becoming someone who rests.",
               "citations" => 0,
               "days" => 0,
               "graduated_to" => nil
             }
           ] = conn |> get("/v1/residents/#{id}/seeds") |> json_response(200)

    assert other_conn |> get("/v1/residents/#{id}/seeds") |> json_response(404)
    assert [] = conn |> get("/v1/residents/#{id}/habits") |> json_response(200)
  end

  test "the baselines' route", %{conn: conn, other_conn: other_conn, id: id, account_id: a} do
    assert [] = conn |> get("/v1/residents/#{id}/baselines") |> json_response(200)
    witness = Actor.new(:witness, a)

    {:ok, 1} =
      Ethos.define_habit(
        id,
        %{name: "rests", trigger: %{"times" => ["evening"]}, stance: "keep"},
        witness
      )

    %{tone: "silent"} = Ethos.measure(id, "trait_baseline", Actor.new(:job, "test"))

    assert [
             %{
               "spread" => 0.0,
               "breadth" => 0.0,
               "habits" => [%{"number" => 1, "name" => "rests"}]
             }
           ] =
             conn |> get("/v1/residents/#{id}/baselines") |> json_response(200)

    assert other_conn |> get("/v1/residents/#{id}/baselines") |> json_response(404)
  end
end
