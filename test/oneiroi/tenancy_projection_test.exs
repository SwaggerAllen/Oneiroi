defmodule Oneiroi.TenancyProjectionTest do
  @moduledoc "A per-resident number in one resident's event changes that resident's row and no other's."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures

  test "resolving one resident's prediction #1 leaves another resident's prediction #1 open" do
    rows =
      for _ <- 1..2 do
        w = Fixtures.account!()
        r = Fixtures.resident!(w)
        brain = Actor.new(:resident, r.id, "fake/model")
        {:ok, 1} = Eunomia.log_prediction(r.id, "rain", ~U[2026-11-01 00:00:00Z], %{}, brain)
        {r, Actor.new(:witness, w.id)}
      end

    [{a, a_witness}, {b, _}] = rows
    :ok = Eunomia.resolve_prediction(a.id, 1, "right", "it rained", a_witness)

    assert %{resolved: [%{number: 1, outcome: "right"}]} = Eunomia.predictions(a.id)
    assert %{open: [%{number: 1, outcome: nil}], resolved: []} = Eunomia.predictions(b.id)
  end
end
