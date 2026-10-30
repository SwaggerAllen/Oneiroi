defmodule Oneiroi.Nisaba.Events.Subscription do
  @moduledoc """
  The subscription stream's events, version 1 (spec §3.1, §6.2, F53):
  `subscription-<resident_id>`, one per resident: the plan, its price
  and renewal, the lapse that puts the insurance policy into effect, the
  cancellation that moves the resident to community custody at the end
  of the term, the policy and what was prepaid above the floor.
  """

  defmodule Started do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :plan, :price_nanos, :period_days, :renews_at],
      instants: [:renews_at]
  end

  defmodule Renewed do
    use Oneiroi.Event, version: 1, fields: [:id, :renews_at], instants: [:renews_at]
  end

  defmodule PlanChanged do
    use Oneiroi.Event, version: 1, fields: [:id, :plan, :price_nanos]
  end

  defmodule Lapsed do
    # What puts the insurance policy into effect (spec §6.2).
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule Cancelled do
    # A custody event: the resident moves to community custody at the end
    # of the policy's term, never a deletion. A decision, with its note.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :custody_due_at],
      instants: [:custody_due_at]
  end

  defmodule PolicySet do
    # One bucket per axis, by id (spec §6.11).
    use Oneiroi.Event, version: 1, fields: [:id, :model, :witness, :free_time, :term]
  end

  defmodule Prepaid do
    # A larger bucket on one axis, prepaid; the pool is never debt.
    use Oneiroi.Event, version: 1, fields: [:id, :axis, :bucket]
  end

  defmodule LapseTold do
    # The resident was told its policy on wake (spec §6.11), once per lapse.
    use Oneiroi.Event, version: 1, fields: [:id]
  end
end
