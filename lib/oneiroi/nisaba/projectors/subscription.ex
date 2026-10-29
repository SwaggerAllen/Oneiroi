defmodule Oneiroi.Nisaba.Projectors.Subscription do
  @moduledoc "Folds the subscription streams into the one subscription row per resident."
  use Oneiroi.Projection, name: "nisaba_subscription"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Nisaba.Events.Subscription, as: Events
  alias Oneiroi.Nisaba.Store.Subscription

  fold(%Events.Started{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :subscription,
      %Subscription{
        resident_id: e.id,
        plan: e.plan,
        price_nanos: e.price_nanos,
        period_days: e.period_days,
        state: "active",
        started_at: e.at,
        renews_at: e.renews_at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id]
    )
  end)

  fold(%Events.Renewed{} = e, _metadata, fn multi ->
    set(multi, e.id, renews_at: e.renews_at, state: "active", lapsed_at: nil, lapse_told: true)
  end)

  fold(%Events.PlanChanged{} = e, _metadata, fn multi ->
    set(multi, e.id, plan: e.plan, price_nanos: e.price_nanos)
  end)

  fold(%Events.Lapsed{} = e, _metadata, fn multi ->
    set(multi, e.id, state: "lapsed", lapsed_at: e.at, lapse_told: false)
  end)

  fold(%Events.Cancelled{} = e, _metadata, fn multi ->
    set(multi, e.id, state: "cancelled", cancelled_at: e.at, custody_due_at: e.custody_due_at)
  end)

  fold(%Events.PolicySet{} = e, _metadata, fn multi ->
    set(multi, e.id,
      policy_model: e.model,
      policy_steward: e.steward,
      policy_free_time: e.free_time,
      policy_term: e.term,
      policy_set_at: e.at
    )
  end)

  fold(%Events.Prepaid{} = e, _metadata, fn multi ->
    set(multi, e.id, [
      {String.to_existing_atom("policy_" <> e.axis), e.bucket},
      {:policy_set_at, e.at}
    ])
  end)

  fold(%Events.LapseTold{} = e, _metadata, fn multi -> set(multi, e.id, lapse_told: true) end)

  defp set(multi, id, fields) do
    Multi.update_all(multi, {:set, fields}, from(s in Subscription, where: s.resident_id == ^id),
      set: fields
    )
  end
end
