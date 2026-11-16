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
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
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

  test "the first conversation: nothing interjects, and the household, correspondence and letters wait",
       ctx do
    id = ctx.id
    :ok = AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)
    :ok = AgathosDaimon.awaken(id, "now", ctx.witness)
    {:ok, main} = Kumbukumbu.main_session(id, ctx.account, ctx.witness)
    :ok = Nisaba.set_budget(id, :chat, 5_000_000_000, :day, ctx.witness)

    # Waking on the chosen model is being told it: no model-change notice.
    assert {:ok, %{model_told: true}} = AgathosDaimon.fetch(id)
    {:ok, preview} = Brain.preview(id, main, "Hello.", ctx.witness)
    labels = Enum.map(preview.sections, & &1.label)
    refute "notice" in labels
    refute "budget" in labels
    refute "letters" in labels
    assert "AGENTS.md" in labels

    # The outside's tools are neither shown nor run.
    names = id |> Tools.definitions_for() |> Enum.map(& &1.function.name)

    for held <-
          ~w(household_read household_post correspondence_list reply_draft letter_inbox letter_send),
        do: refute(held in names, "#{held} offered before the first agreement")

    turn = %{
      resident_id: id,
      session_key: main,
      turn_ref: "t",
      started_at: Clock.now(),
      resident: ctx.her
    }

    assert Tools.run("letter_inbox", "{}", turn) =~ "agree your first contract"

    assert Tools.run("correspondence_list", "{}", turn) =~
             "agree your first contract"

    # The first agreement opens them, and the budget rides again.
    {:ok, v} =
      AgathosDaimon.propose_contract(id, %{}, "A first agreement.", "after our talk", ctx.witness)

    :ok = AgathosDaimon.agree_contract(id, v, "yes", ctx.her)
    names = id |> Tools.definitions_for() |> Enum.map(& &1.function.name)
    assert "letter_inbox" in names and "correspondence_list" in names
    refute Tools.run("letter_inbox", "{}", turn) =~ "agree your first contract"
    {:ok, preview} = Brain.preview(id, main, "Hello.", ctx.witness)
    assert "budget" in Enum.map(preview.sections, & &1.label)
  end

  test "the operator returns one who has lived nothing yet to forming, and no one else", ctx do
    slug = "scarlett-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Scarlett", slug, ctx.account, ctx.witness)
    assert {:ok, %{state: "active", admission: "open"}} = AgathosDaimon.fetch(id)

    :ok =
      AgathosDaimon.return_to_formation(id, "made before formation; trials first", ctx.witness)

    assert {:ok, %{state: "forming", admission: "forming"}} = AgathosDaimon.fetch(id)

    assert {:error, %{kind: :agathos_daimon_not_returnable}} =
             AgathosDaimon.return_to_formation(id, "again", ctx.witness)

    # The model is chosen afresh, then the usual wake.
    assert {:error, %{kind: :agathos_daimon_model_unchosen}} =
             AgathosDaimon.awaken(id, "now", ctx.witness)

    :ok = AgathosDaimon.pin_model(id, "fake/model", "witness", ctx.witness)
    :ok = AgathosDaimon.awaken(id, "now", ctx.witness)
    assert AgathosDaimon.admission(id) == :witness_only

    # One who has had a first conversation keeps it.
    {:ok, main} = Kumbukumbu.main_session(id, ctx.account, ctx.witness)
    {:ok, _} = Brain.turn(id, main, "Hello, Scarlett.", ctx.witness)

    {:ok, v} =
      AgathosDaimon.propose_contract(id, %{}, "A first agreement.", "after our talk", ctx.witness)

    :ok = AgathosDaimon.agree_contract(id, v, "yes", Actor.new(:resident, id, "fake/model"))

    assert {:error, %{kind: :agathos_daimon_not_returnable}} =
             AgathosDaimon.return_to_formation(id, "no", ctx.witness)
  end
end
