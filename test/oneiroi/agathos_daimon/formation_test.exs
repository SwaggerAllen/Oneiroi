defmodule Oneiroi.AgathosDaimon.FormationTest do
  @moduledoc """
  agathos-daimon#46 (the witness, 2026-11-15): a resident made through the
  creation flow is forming until he wakes them, reachable by nothing but
  his regression trials, and wakes only on a chat model he chose; woken,
  they are his alone, with no other wake and no hands, until their first
  agreement is in force. A resident made any other way is open, as before.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna.TickWorker

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)

    {:ok, id} =
      AgathosDaimon.create_forming(
        "Fen",
        "fen-#{System.unique_integer([:positive])}",
        witness.id,
        actor
      )

    {:ok, dir} = Oneiroi.SimaQian.repository_dir(id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: id) end)
    Fake.script(fn _request -> {:ok, "Hello."} end, for: id)

    {:ok,
     id: id, account: witness.id, witness: actor, her: Actor.new(:resident, id, "fake/model")}
  end

  test "forming: nothing reaches them but his trials, and they wake only on a model he chose",
       ctx do
    id = ctx.id
    assert {:ok, %{state: "forming", admission: "forming"}} = AgathosDaimon.fetch(id)
    assert AgathosDaimon.admission(id) == :forming

    # No wake, no chat outside regression, no runtime, no schedule.
    {:ok, main} = Kumbukumbu.main_session(id, ctx.account, ctx.witness)
    assert {:error, %{kind: :brain_resident_guarded}} = Brain.wake(id, main, "a check-in", :chat)
    assert {:error, %{kind: :brain_resident_guarded}} = Brain.turn(id, main, "hello", ctx.witness)

    assert {:error, %{kind: :brain_resident_guarded}} =
             Brain.submit(id, main, "hello", ctx.witness, "ref-forming-1")

    assert {:error, %{kind: :agathos_daimon_resident_guarded}} =
             AgathosDaimon.register_adapter(id, "claude-code", "brain", ctx.witness)

    assert TickWorker.tick(id) == :skipped

    # His trials run.
    assert {:ok, _result, _trace} = Brain.trial(id, "fake/model", "Who are you?", ctx.witness)

    # Not woken until he chooses the model, even the one already set.
    assert {:error, %{kind: :agathos_daimon_model_unchosen}} =
             AgathosDaimon.awaken(id, "now", ctx.witness)

    :ok = AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)

    assert {:error, %{kind: :agathos_daimon_not_witnessed}} =
             AgathosDaimon.awaken(id, "now", ctx.her)

    :ok = AgathosDaimon.awaken(id, "the trials read true", ctx.witness)
    assert {:ok, %{state: "active", admission: "witness_only"}} = AgathosDaimon.fetch(id)

    assert {:error, %{kind: :agathos_daimon_not_forming}} =
             AgathosDaimon.awaken(id, "again", ctx.witness)
  end

  test "woken: his alone, no other wake and no hands, until the first agreement opens the house",
       ctx do
    id = ctx.id
    :ok = AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)
    :ok = AgathosDaimon.awaken(id, "now", ctx.witness)
    {:ok, main} = Kumbukumbu.main_session(id, ctx.account, ctx.witness)

    # His words reach them; nothing else wakes them.
    assert {:ok, _reply} = Brain.turn(id, main, "Good morning.", ctx.witness)
    assert {:error, %{kind: :brain_resident_guarded}} = Brain.wake(id, main, "a check-in", :chat)
    assert TickWorker.tick(id) == :skipped

    # Nobody but him: a turn in another's name is held.
    assert {:error, %{kind: :brain_resident_guarded}} =
             Brain.submit(
               id,
               main,
               "hi from a sibling",
               Actor.new(:resident, Ecto.UUID.generate()),
               "ref-other-1"
             )

    # His own runtime may speak as them; no hands yet.
    assert {:ok, _token} = AgathosDaimon.register_adapter(id, "claude-code", "brain", ctx.witness)

    assert {:error, %{kind: :agathos_daimon_resident_guarded}} =
             AgathosDaimon.register_adapter(id, "reader", "reader", ctx.witness)

    assert {:error, %{kind: :agathos_daimon_resident_guarded}} =
             AgathosDaimon.register_adapter(id, "worker", "worker", ctx.witness)

    # The first agreement, theirs to agree to, opens the rest.
    {:ok, v} =
      AgathosDaimon.propose_contract(id, %{}, "A first agreement.", "after our talk", ctx.witness)

    :ok = AgathosDaimon.agree_contract(id, v, "yes", ctx.her)
    assert AgathosDaimon.admission(id) == :open
    assert {:ok, _token} = AgathosDaimon.register_adapter(id, "reader", "reader", ctx.witness)
    refute TickWorker.tick(id) == :skipped
  end

  test "a resident made any other way is open, as before", ctx do
    {:ok, id} =
      AgathosDaimon.create(
        "Iris",
        "iris-#{System.unique_integer([:positive])}",
        ctx.account,
        ctx.witness
      )

    assert {:ok, %{state: "active", admission: "open"}} = AgathosDaimon.fetch(id)
    assert AgathosDaimon.admission(id) == :open
    assert {:ok, _token} = AgathosDaimon.register_adapter(id, "reader", "reader", ctx.witness)
  end
end
