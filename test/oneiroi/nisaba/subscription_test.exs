defmodule Oneiroi.Nisaba.SubscriptionTest do
  @moduledoc "The subscription aggregate, pure: started once, validated, a lapse told once, a cancellation final."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Nisaba.Events.Subscription, as: Events
  alias Oneiroi.Nisaba.Subscription
  alias Oneiroi.Nisaba.SubscriptionCommands, as: Commands

  @actor Actor.new(:witness, "a")
  @at ~U[2026-10-26 12:00:00.000000Z]

  defp evolve(state \\ %Subscription{}, events),
    do: Enum.reduce(List.wrap(events), state, &Subscription.apply(&2, &1))

  defp cmd(module, fields),
    do: struct!(module, Map.merge(%{actor: @actor, at: @at, id: "r"}, Map.new(fields)))

  defp started do
    evolve(
      Subscription.execute(
        %Subscription{},
        cmd(Commands.Start,
          plan: "core",
          price_nanos: 12_000_000_000,
          period_days: 30,
          renews_at: @at
        )
      )
    )
  end

  test "a subscription starts once, validated, and nothing happens before it starts" do
    start =
      cmd(Commands.Start,
        plan: "core",
        price_nanos: 12_000_000_000,
        period_days: 30,
        renews_at: @at
      )

    assert %Events.Started{plan: "core"} = Subscription.execute(%Subscription{}, start)

    assert {:error, %{kind: :nisaba_plan_invalid, site: :nisaba_start_plan_invalid}} =
             Subscription.execute(%Subscription{}, %{start | plan: " "})

    assert {:error, %{kind: :nisaba_price_invalid, site: :nisaba_start_price_invalid}} =
             Subscription.execute(%Subscription{}, %{start | price_nanos: -1})

    assert {:error, %{kind: :nisaba_period_invalid, site: :nisaba_start_period_days_invalid}} =
             Subscription.execute(%Subscription{}, %{start | period_days: 0})

    assert {:error, %{kind: :nisaba_no_subscription, site: :nisaba_subscription_not_started}} =
             Subscription.execute(%Subscription{}, cmd(Commands.Renew, renews_at: @at))

    s = started()
    assert [] = Subscription.execute(s, start)
  end

  test "a lapse is once and told once, a renewal resumes, and a cancellation is final" do
    s = started()
    assert %Events.Lapsed{} = Subscription.execute(s, cmd(Commands.Lapse, reason: "unpaid"))
    s = evolve(s, Subscription.execute(s, cmd(Commands.Lapse, reason: "unpaid")))
    assert [] = Subscription.execute(s, cmd(Commands.Lapse, reason: "again"))
    assert s.lapse_told == false
    s = evolve(s, Subscription.execute(s, cmd(Commands.RecordLapseTold, [])))
    assert s.lapse_told == true
    s = evolve(s, Subscription.execute(s, cmd(Commands.Renew, renews_at: @at)))
    assert s.state == :active

    assert {:error, %{kind: :nisaba_period_invalid, site: :nisaba_cancel_custody_due_invalid}} =
             Subscription.execute(s, cmd(Commands.Cancel, custody_due_at: nil, note: "x"))

    cancel = cmd(Commands.Cancel, custody_due_at: @at, note: "moving on")
    assert %Events.Cancelled{note: "moving on"} = Subscription.execute(s, cancel)
    s = evolve(s, Subscription.execute(s, cancel))

    assert {:error, %{kind: :nisaba_cancelled, site: :nisaba_subscription_cancelled}} =
             Subscription.execute(s, cmd(Commands.Renew, renews_at: @at))

    assert {:error, %{kind: :nisaba_cancelled}} =
             Subscription.execute(s, cmd(Commands.Lapse, reason: "x"))

    assert %Events.LapseTold{} = Subscription.execute(s, cmd(Commands.RecordLapseTold, []))
  end

  test "the policy is one bucket per axis; setting the same is no event; a prepay moves one axis" do
    s = started()

    set =
      cmd(Commands.SetPolicy,
        model: "model/floor",
        witness: "witness/floor",
        free_time: "free_time/floor",
        term: "term/floor"
      )

    assert %Events.PolicySet{} = Subscription.execute(s, set)
    s = evolve(s, Subscription.execute(s, set))
    assert [] = Subscription.execute(s, set)
    prepay = cmd(Commands.Prepay, axis: "free_time", bucket: "free_time/high")
    assert %Events.Prepaid{axis: "free_time"} = Subscription.execute(s, prepay)
    s = evolve(s, Subscription.execute(s, prepay))
    assert [] = Subscription.execute(s, prepay)
    assert s.policy.free_time == "free_time/high"

    assert %Events.PlanChanged{plan: "plus"} =
             Subscription.execute(s, cmd(Commands.ChangePlan, plan: "plus", price_nanos: 1))

    assert [] =
             Subscription.execute(
               s,
               cmd(Commands.ChangePlan, plan: "core", price_nanos: 12_000_000_000)
             )
  end
end
