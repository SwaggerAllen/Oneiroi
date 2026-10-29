defmodule Oneiroi.Nisaba.SubscriptionCommands do
  @moduledoc "The subscription aggregate's commands; `id` is the resident's id."

  defmodule Start do
    use Oneiroi.Command, fields: [:id, :plan, :price_nanos, :period_days, :renews_at]
  end

  defmodule Renew do
    use Oneiroi.Command, fields: [:id, :renews_at]
  end

  defmodule ChangePlan do
    use Oneiroi.Command, fields: [:id, :plan, :price_nanos]
  end

  defmodule Lapse do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule Cancel do
    use Oneiroi.Command, decision: true, fields: [:id, :custody_due_at]
  end

  defmodule SetPolicy do
    use Oneiroi.Command, fields: [:id, :model, :steward, :free_time, :term]
  end

  defmodule Prepay do
    use Oneiroi.Command, fields: [:id, :axis, :bucket]
  end

  defmodule RecordLapseTold do
    use Oneiroi.Command, fields: [:id]
  end
end
