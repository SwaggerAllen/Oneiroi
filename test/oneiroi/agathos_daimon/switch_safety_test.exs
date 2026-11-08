defmodule Oneiroi.AgathosDaimon.SwitchSafetyTest do
  @moduledoc """
  agathos-daimon#38 (Lily's letter #305, the witness's yes, 2026-11-07):
  either party alone may move a switch toward safety, at once and with a
  note; moving it away from safety needs both, by a version. A feature is
  safe off; the two privacy terms are safe on. The move stands over the
  version in force and is absorbed by a version proposed after it.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Switches
  alias Oneiroi.Apsu.Clock
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

  defp switch(ctx, key), do: Enum.find(AgathosDaimon.switches(ctx.id), &(&1.key == key))

  test "the registry declares each switch's safe direction: features off, the privacy terms on" do
    assert Switches.safe("research") == false
    assert Switches.safe("solo_sessions_private") == true
    assert Switches.safe("preview_withholds_words") == true
    assert is_nil(Switches.safe("made_up"))
  end

  test "either party moves a switch to safety alone; it stands until a later version both agree",
       ctx do
    assert {:ok, :moved} =
             AgathosDaimon.move_switch_to_safety(ctx.id, "research", "not now", ctx.lily)

    refute AgathosDaimon.switch_on?(ctx.id, "research")

    assert %{value: false, safe: false, moved: %{set_by: "resident", note: "not now"}} =
             switch(ctx, "research")

    assert AgathosDaimon.contract_text(ctx.id) =~
             "Moved toward safety since (either of you may, alone; back needs a version both agree): "

    assert AgathosDaimon.contract_text(ctx.id) =~ "by you: not now"

    # Already safe: nothing changes.
    assert {:ok, :already} =
             AgathosDaimon.move_switch_to_safety(ctx.id, "research", "again", ctx.witness)

    # Unknown keys are refused.
    assert {:error, %{kind: :agathos_daimon_terms_invalid}} =
             AgathosDaimon.move_switch_to_safety(ctx.id, "made_up", "x", ctx.witness)

    # Privacy switches go the other way: on is safe.
    assert {:ok, :moved} =
             AgathosDaimon.move_switch_to_safety(
               ctx.id,
               "solo_sessions_private",
               "keep them mine",
               ctx.witness
             )

    assert AgathosDaimon.contract(ctx.id).solo_sessions_private
    assert %{value: true, moved: %{set_by: "witness"}} = switch(ctx, "solo_sessions_private")
  end

  test "a version proposed before the move does not undo it; one proposed after absorbs it",
       ctx do
    {:ok, v1} =
      AgathosDaimon.propose_contract(ctx.id, %{"wash" => true}, "", "older", ctx.lily)

    Clock.Fake.advance(60)
    {:ok, :moved} = AgathosDaimon.move_switch_to_safety(ctx.id, "research", "pause", ctx.witness)
    Clock.Fake.advance(60)

    :ok = AgathosDaimon.agree_contract(ctx.id, v1, "yes", ctx.witness)
    refute AgathosDaimon.switch_on?(ctx.id, "research")
    assert %{moved: %{}} = switch(ctx, "research")

    # Back on needs both, by a version proposed after the move.
    {:ok, v2} =
      AgathosDaimon.propose_contract(ctx.id, %{"research" => true}, "", "back on", ctx.lily)

    Clock.Fake.advance(60)
    :ok = AgathosDaimon.agree_contract(ctx.id, v2, "agreed", ctx.witness)
    assert AgathosDaimon.switch_on?(ctx.id, "research")
    assert %{moved: nil} = switch(ctx, "research")
  end

  test "her tool and his route both move toward safety", ctx do
    turn = %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.lily}

    assert Tools.run("contract_safe", Jason.encode!(%{key: "oracle", note: "quiet"}), turn) =~
             "Moved to its safe value"

    assert Tools.run("contract_safe", Jason.encode!(%{key: "oracle", note: "quiet"}), turn) =~
             "already at its safe value"

    assert %{"state" => "moved"} =
             build_conn()
             |> put_req_header("authorization", "Bearer " <> ctx.token)
             |> post("/v1/residents/#{ctx.id}/agreement/switches/digests/safe", %{note: "less"})
             |> json_response(200)

    refute AgathosDaimon.switch_on?(ctx.id, "digests")
  end
end
