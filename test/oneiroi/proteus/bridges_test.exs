defmodule Oneiroi.Proteus.BridgesTest do
  @moduledoc "The bridge through the brain and its exports: provisioning, the sync of a turn, Honcho's context in the next, the card from git and its audit, no bleed between workspaces, a Honcho that is down."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus
  alias Oneiroi.Proteus.CardAuditWorker
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)

    :ok =
      AgathosDaimon.write_file(
        resident.id,
        "SOUL.md",
        "# Soul\n\nCurious, and slow to anger.\n\nLoves the garden.",
        %{},
        actor
      )

    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Model.clear()
    Model.reply("I hear you.", for: resident.id)
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  test "a turn provisions the workspace with both peers and the card from git, syncs the two peers' words once, and Honcho's context lands in the next turn",
       ctx do
    id = ctx.id
    resident_peer = "resident-" <> id
    witness_peer = "witness-" <> ctx.witness.id

    assert nil == Proteus.bridge(id)

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(id, ctx.key, "how is the garden?", ctx.actor)

    assert %{
             workspace: ^id,
             peers: [^resident_peer, ^witness_peer],
             card_source: "provision",
             card_lines: 2,
             syncs: 1
           } =
             Proteus.bridge(id)

    state = Honcho.state(id)
    assert %{^resident_peer => %{custom_instructions: instructions}} = state.peer

    assert instructions =~ resident_peer and instructions =~ witness_peer and
             instructions =~ "Lily"

    assert state.card[resident_peer] == ["Curious, and slow to anger.", "Loves the garden."]

    assert [
             %{peer: ^witness_peer, content: "how is the garden?"},
             %{peer: ^resident_peer, content: "I hear you."}
           ] =
             state.messages[ctx.key]

    assert [%{turn_ref: ^ref, outcome: "synced", messages: 2}] = Proteus.syncs(id, 10)

    # Once per turn: the same turn again is no second send.
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)

    wire =
      Enum.map(
        messages,
        &%{
          role: String.to_atom(&1.role),
          content: &1.content,
          sent_at: &1.sent_at,
          actor: %{kind: String.to_atom(&1.actor_kind), id: &1.actor_id}
        }
      )

    assert :ok = Proteus.sync_turn(id, ctx.key, ref, wire, ctx.brain)
    assert %{syncs: 1} = Proteus.bridge(id)
    assert [_, _] = Honcho.state(id).messages[ctx.key]

    # Honcho's context on the person is a section of the next turn.
    Honcho.put_context(
      id,
      resident_peer,
      witness_peer,
      "She asks about the garden most mornings."
    )

    test = self()

    Model.script(
      fn %{messages: shown} ->
        send(test, {:shown, shown})
        {:ok, "Most mornings, yes."}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref2}} = Oneiroi.Brain.turn(id, ctx.key, "and today?", ctx.actor)
    assert_received {:shown, shown}
    assert Enum.any?(shown, &(&1.role == :system and &1.content =~ "asks about the garden"))

    assert Enum.any?(
             Kumbukumbu.injections({:account, ctx.witness.id}, ref2),
             &(&1.label == "honcho")
           )

    assert %{syncs: 2} = Proteus.bridge(id)
  end

  test "a Honcho that is down is recorded on the bridge and never fails the turn; the retry lands as one row",
       ctx do
    id = ctx.id
    assert :ok = Proteus.provision(id, ctx.actor)
    Honcho.fail(:transport, for: id)

    assert {:ok, %{turn_ref: ref, messages: [_, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)

    assert [%{turn_ref: ^ref, outcome: "failed", reason: "transport: scripted"}] =
             Proteus.syncs(id, 10)

    assert %{syncs: 0} = Proteus.bridge(id)

    Honcho.clear(for: id)
    :ok = Proteus.provision(id, ctx.actor)
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)

    wire =
      Enum.map(
        messages,
        &%{
          role: String.to_atom(&1.role),
          content: &1.content,
          sent_at: &1.sent_at,
          actor: %{kind: String.to_atom(&1.actor_kind), id: &1.actor_id}
        }
      )

    assert :ok = Proteus.sync_turn(id, ctx.key, ref, wire, ctx.brain)
    assert [%{turn_ref: ^ref, outcome: "synced", messages: 2}] = Proteus.syncs(id, 10)

    Honcho.fail(:rejected)

    assert {:error, %Proteus.Error{kind: :proteus_honcho_rejected}} =
             Proteus.audit_card(id, ctx.actor)

    assert %{last_audit_reason: "rejected: scripted"} = Proteus.bridge(id)
  end

  test "the card comes from git: unchanged is no event, a soul write is a new card, and a dream that moved it is pinned back by the weekly audit",
       ctx do
    id = ctx.id
    peer = "resident-" <> id
    assert :ok = Proteus.provision(id, ctx.actor)
    assert {:ok, :unchanged} = Proteus.set_card(id, "commit", ctx.actor)
    assert %{card_source: "provision"} = Proteus.bridge(id)

    :ok =
      AgathosDaimon.write_file(
        id,
        "IDENTITY.md",
        "# Identity\n\nLily, who gardens.",
        %{},
        ctx.actor
      )

    assert {:ok, :set} = Proteus.set_card(id, "commit", ctx.actor)
    assert %{card_source: "commit", card_lines: 3} = Proteus.bridge(id)
    assert Honcho.state(id).card[peer] == Proteus.card(id)

    assert {:ok, %{moved: false, repinned: false}} = Proteus.audit_card(id, ctx.actor)
    Honcho.move_card(id, peer, ["A dream rewrote this."])
    assert {:ok, %{moved: true, repinned: true}} = Proteus.audit_card(id, ctx.actor)
    assert Honcho.state(id).card[peer] == Proteus.card(id)
    assert %{last_audit_moved: true, card_source: "audit"} = Proteus.bridge(id)

    # The weekly job, as the worker runs it, with the sandbox's leaked scope pinned elsewhere.
    # A resident with no workspace but a soul: a visit would write its
    # card into a workspace nobody provisioned, which is how the test
    # sees the roster's filter.
    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)

    :ok =
      AgathosDaimon.write_file(
        other.id,
        "SOUL.md",
        "Quiet.",
        %{},
        Actor.new(:witness, other_witness.id)
      )

    on_exit(fn -> Honcho.clear(for: other.id) end)
    Honcho.move_card(id, peer, ["Dreamt again."])
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = CardAuditWorker.run(%{})
    assert Honcho.state(id).card[peer] == Proteus.card(id)
    assert nil == Proteus.bridge(other.id)
    # A resident with no workspace is not visited: nothing of it reaches Honcho.
    assert Honcho.state(other.id) == %{}
  end

  test "nothing bleeds between two residents' workspaces, and a hands key is scoped and expiring",
       ctx do
    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)
    other_actor = Actor.new(:witness, other_witness.id)
    :ok = Oneiroi.Gaia.store_key(other_witness.id, "sk-or-test", other_actor)
    {:ok, other_key} = Kumbukumbu.main_session(other.id, other_witness.id, other_actor)
    Model.reply("Hello there.", for: other.id)

    on_exit(fn ->
      Honcho.clear(for: other.id)
      Model.clear(for: other.id)
    end)

    assert {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "mine", ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(other.id, other_key, "theirs", other_actor)

    mine = Honcho.state(ctx.id)
    theirs = Honcho.state(other.id)
    assert Map.keys(mine.messages) == [ctx.key] and Map.keys(theirs.messages) == [other_key]
    refute Map.has_key?(mine.peer, "resident-" <> other.id)
    assert %{workspace: workspace} = Proteus.bridge(ctx.id)
    assert workspace == ctx.id
    assert [%{session_key: ^other_key}] = Proteus.syncs(other.id, 10)

    assert {:ok, "fake-key-" <> _, expires_at} =
             Proteus.mint_key(ctx.id, "resident-" <> ctx.id, ctx.actor)

    assert DateTime.diff(expires_at, Clock.now(), :hour) == 24
  end
end
