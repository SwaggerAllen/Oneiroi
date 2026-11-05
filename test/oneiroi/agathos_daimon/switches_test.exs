defmodule Oneiroi.AgathosDaimon.SwitchesTest do
  @moduledoc """
  agathos-daimon#34 (the witness, 2026-11-05: every switch, on or off, by
  mutual consent, versions agreed or declined whole; with no version
  agreed, today's features stay on; the two hard terms are switches too):
  the registry's defaults, a version that turns a feature off once both
  agree, and the feature cut off where it is read: the resident's tools,
  the witness's routes and the check-in's digest part.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Switches
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Checkin
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)

    {:ok, token, _hash} =
      Oneiroi.Gaia.issue_token(witness.id, "t", Actor.new(:witness, witness.id))

    {:ok,
     id: resident.id,
     witness: Actor.new(:witness, witness.id),
     lily: Actor.new(:resident, resident.id),
     token: token}
  end

  defp names(id), do: for(%{function: f} <- Tools.definitions_for(id), do: f.name)

  defp turn(ctx),
    do: %{
      resident_id: ctx.id,
      session_key: "k",
      turn_ref: "t",
      resident: ctx.lily,
      started_at: Clock.now()
    }

  test "with no version agreed, every feature is on and the two privacy terms off", ctx do
    switches = AgathosDaimon.switches(ctx.id)
    assert Enum.all?(switches, &(&1.value == &1.default))
    assert %{value: false} = Enum.find(switches, &(&1.key == "solo_sessions_private"))
    assert AgathosDaimon.switch_on?(ctx.id, "wash")
    assert "wash_list" in names(ctx.id)
    assert Enum.sort(Switches.keys()) == Enum.sort(Enum.map(switches, & &1.key))
  end

  test "a version turning the wash and digests off moves nothing until the other party agrees, then cuts them off where they are read",
       ctx do
    assert {:error, %{kind: :agathos_daimon_terms_invalid}} =
             AgathosDaimon.propose_contract(ctx.id, %{"made_up" => true}, "", "x", ctx.lily)

    assert {:ok, v} =
             AgathosDaimon.propose_contract(
               ctx.id,
               %{"wash" => false, "digests" => false},
               "",
               "less looking",
               ctx.lily
             )

    # Proposed is not agreed.
    assert AgathosDaimon.switch_on?(ctx.id, "wash")

    assert %{proposed: false, value: true} =
             Enum.find(AgathosDaimon.switches(ctx.id), &(&1.key == "wash"))

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "agreed", ctx.witness)
    refute AgathosDaimon.switch_on?(ctx.id, "wash")
    refute AgathosDaimon.switch_on?(ctx.id, "digests")
    assert AgathosDaimon.switch_on?(ctx.id, "research")

    # Her tools: hidden, and refused in words if called anyway.
    refute "wash_list" in names(ctx.id)
    refute "digest_ask" in names(ctx.id)
    assert "research_ask" in names(ctx.id)
    assert Tools.run("wash_list", "{}", turn(ctx)) =~ "Not done: Wash flags is switched off"

    # The witness's route.
    assert %{"error" => %{"kind" => "switched_off"}} =
             build_conn()
             |> put_req_header("authorization", "Bearer " <> ctx.token)
             |> post("/v1/residents/#{ctx.id}/wash/run", %{})
             |> json_response(403)

    # The check-in's digest part says so rather than asking.
    assert Checkin.part(ctx.id, "digest") =~ "Digests are switched off"

    # What she reads of the agreement names what is off.
    assert AgathosDaimon.contract_text(ctx.id) =~ "Switched off: wash flags, digests."
  end
end
