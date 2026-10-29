defmodule Oneiroi.Nisaba.SubscriptionRouter do
  @moduledoc "The subscription router: `subscription-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Nisaba.Subscription",
    prefix: "subscription-",
    commands: "Oneiroi.Nisaba.SubscriptionCommands",
    dispatching: ~w(Start Renew ChangePlan Lapse Cancel SetPolicy Prepay RecordLapseTold)
end
