defmodule Oneiroi.Nisaba.Projectors.Ledger do
  @moduledoc "Folds the ledger stream into the budget lines and the usage rows."
  use Oneiroi.Projection, name: "nisaba_ledger"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Nisaba.Events
  alias Oneiroi.Nisaba.Store.{Budget, Usage}

  fold(%Events.BudgetSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :budget,
      %Budget{
        resident_id: e.id,
        purpose: e.purpose,
        cap_nanos: e.cap_nanos,
        period: e.period,
        set_at: e.at
      },
      on_conflict: [
        set: [
          cap_nanos: e.cap_nanos,
          period: e.period,
          set_at: e.at,
          exceeded_period_key: nil,
          exceeded_at: nil
        ]
      ],
      conflict_target: [:resident_id, :purpose]
    )
  end)

  # `ref` is the call's own id, so a replayed record is one row.
  fold(%Events.ModelCallRecorded{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :usage,
      %Usage{
        ref: e.ref,
        resident_id: e.id,
        purpose: e.purpose,
        model: e.model,
        actor_kind: Atom.to_string(e.actor.kind),
        actor_id: e.actor.id,
        prompt_tokens: e.prompt_tokens,
        completion_tokens: e.completion_tokens,
        cost_nanos: e.cost_nanos,
        estimated: e.estimated,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:ref]
    )
  end)

  fold(%Events.BudgetExceeded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :exceeded,
      from(b in Budget, where: b.resident_id == ^e.id and b.purpose == ^e.purpose),
      set: [exceeded_period_key: e.period_key, exceeded_at: e.at]
    )
  end)
end
