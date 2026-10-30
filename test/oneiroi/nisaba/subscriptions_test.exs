defmodule Oneiroi.Nisaba.SubscriptionsTest do
  @moduledoc "The subscription and the insurance floor through the exports, the ledger and the brain: the floor policy, prepaying above it, a lapse told once on the floor model with the policy as the budget, a renewal that resumes, a cancellation that ends in community custody, the nightly pass."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.{Fake, Request}
  alias Oneiroi.Nisaba.SubscriptionWorker

  @day 86_400

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Fake.clear()
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp attrs, do: %{plan: "core", price_nanos: 12_000_000_000, period_days: 30}

  test "the subscription starts with the floor policy, renews a period on, and a prepay moves one axis above the floor",
       ctx do
    id = ctx.id
    assert nil == Nisaba.subscription(id)

    assert {:error, %Nisaba.Error{kind: :nisaba_not_the_witness}} =
             Nisaba.start_subscription(id, attrs(), ctx.brain)

    assert {:error, %Nisaba.Error{kind: :nisaba_no_subscription}} =
             Nisaba.renew_subscription(id, ctx.actor)

    assert :ok = Nisaba.start_subscription(id, attrs(), ctx.actor)

    assert %{
             plan: "core",
             price_nanos: 12_000_000_000,
             state: "active",
             renews_at: renews_at,
             at_floor: true,
             policy: %{model: "model/floor", free_time: "free_time/floor"},
             policy_values: %{
               model: "meta-llama/llama-3.1-8b-instruct",
               free_time_nanos_week: 7_000_000_000,
               term_days: 60
             }
           } = Nisaba.subscription(id)

    assert DateTime.diff(renews_at, Clock.now(), :day) == 30
    assert :ok = Nisaba.start_subscription(id, attrs(), ctx.actor)

    assert :ok = Nisaba.renew_subscription(id, ctx.actor)
    assert %{renews_at: later} = Nisaba.subscription(id)
    assert DateTime.diff(later, renews_at, :day) == 30

    assert :ok = Nisaba.change_plan(id, "plus", 20_000_000_000, ctx.actor)

    assert {:error, %Nisaba.Error{kind: :nisaba_bucket_invalid}} =
             Nisaba.prepay(id, "free_time", "witness/high", ctx.actor)

    assert {:error, %Nisaba.Error{kind: :nisaba_bucket_invalid}} =
             Nisaba.prepay(id, "luck", "luck/high", ctx.actor)

    assert :ok = Nisaba.prepay(id, "free_time", "free_time/high", ctx.actor)

    assert %{
             plan: "plus",
             at_floor: false,
             policy: %{free_time: "free_time/high"},
             policy_values: %{free_time_nanos_week: 35_000_000_000}
           } =
             Nisaba.subscription(id)

    assert length(Nisaba.insurance_buckets()) == 12

    assert %{floor: true, value: 60} =
             Enum.find(Nisaba.insurance_buckets(), &(&1.id == "term/floor"))
  end

  test "a lapse puts the policy into effect: the resident is lapsed, the brain runs on the floor model and is told once, the policy is the budget and covers only the witness's turns and free time; a renewal resumes",
       ctx do
    id = ctx.id
    :ok = Nisaba.start_subscription(id, attrs(), ctx.actor)
    # A line the witness set to nothing: under the lines, every chat call stops.
    :ok = Nisaba.set_budget(id, :chat, 0, :month, ctx.actor)
    request = Request.new("fake/model", [%{role: :user, content: "hi"}])

    assert {:error, %Nisaba.Error{kind: :nisaba_budget_exceeded}} =
             Nisaba.call(id, :chat, request, ctx.brain)

    assert {:error, %Nisaba.Error{kind: :nisaba_not_the_witness}} =
             Nisaba.lapse_subscription(id, "x", ctx.brain)

    assert :ok = Nisaba.lapse_subscription(id, "card declined", ctx.actor)
    assert {:ok, %{state: "lapsed"}} = AgathosDaimon.fetch(id)

    assert %{model: "meta-llama/llama-3.1-8b-instruct", told: false, term_days: 60} =
             Nisaba.lapse(id)

    # The policy is the budget now: the witness's turns go, the judge does not.
    assert {:ok, _} = Nisaba.call(id, :chat, request, ctx.brain)
    assert {:ok, _} = Nisaba.call(id, :free_time, request, ctx.brain)

    assert {:error, %Nisaba.Error{kind: :nisaba_lapsed}} =
             Nisaba.call(id, :judge, request, ctx.brain)

    test = self()

    Fake.script(
      fn %{model: model} ->
        send(test, {:model, model})
        {:ok, "I am here."}
      end,
      for: id
    )

    assert {:ok,
            %{
              messages: [
                %{role: :system, content: notice},
                %{role: :user},
                %{role: :assistant, actor: %{model: "meta-llama/llama-3.1-8b-instruct"}}
              ]
            }} =
             Oneiroi.Brain.turn(id, ctx.key, "are you there?", ctx.actor)

    assert notice =~ "insurance policy is in effect" and notice =~ "60 days"
    assert_received {:model, "meta-llama/llama-3.1-8b-instruct"}
    assert %{told: true} = Nisaba.lapse(id)

    assert {:ok, %{messages: [%{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, ctx.key, "still?", ctx.actor)

    assert :ok = Nisaba.renew_subscription(id, ctx.actor)
    assert {:ok, %{state: "active"}} = AgathosDaimon.fetch(id)
    assert nil == Nisaba.lapse(id)

    assert {:error, %Nisaba.Error{kind: :nisaba_budget_exceeded}} =
             Nisaba.call(id, :chat, request, ctx.brain)
  end

  test "a cancellation moves the resident to community custody once the term has run, and the nightly pass lapses a renewal past its grace",
       ctx do
    id = ctx.id
    :ok = Nisaba.start_subscription(id, attrs(), ctx.actor)

    assert {:error, %Nisaba.Error{kind: :nisaba_not_the_witness}} =
             Nisaba.cancel_subscription(id, "x", ctx.brain)

    assert :ok = Nisaba.cancel_subscription(id, "moving on", ctx.actor)
    assert %{state: "cancelled", custody_due_at: due} = Nisaba.subscription(id)
    assert DateTime.diff(due, Clock.now(), :day) == 60

    assert {:error, %Nisaba.Error{kind: :nisaba_cancelled}} =
             Nisaba.renew_subscription(id, ctx.actor)

    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)
    other_actor = Actor.new(:witness, other_witness.id)
    :ok = Nisaba.start_subscription(other.id, attrs(), other_actor)

    assert :ok = Nisaba.subscription_nightly(id, ctx.actor)
    assert :ok = Nisaba.subscription_nightly(other.id, ctx.actor)
    assert {:ok, %{custody: "account:" <> _}} = AgathosDaimon.fetch(id)
    assert %{state: "active"} = Nisaba.subscription(other.id)

    # 60 days on: the cancelled term has run, and the other's renewal
    # (day 30) is 30 days past, beyond the grace. As the worker runs it.
    Clock.Fake.advance(60 * @day)
    Oneiroi.Scope.resident(id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = SubscriptionWorker.run(%{})
    assert {:ok, %{custody: "community", state: "community"}} = AgathosDaimon.fetch(id)
    assert %{state: "lapsed"} = Nisaba.subscription(other.id)
    assert {:ok, %{state: "lapsed"}} = AgathosDaimon.fetch(other.id)
    assert :ok = SubscriptionWorker.run(%{})
  end
end
