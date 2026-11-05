defmodule Oneiroi.Repo.Migrations.GaiaPushSubscription do
  use Ecto.Migration
  import Oneiroi.Migration

  # The account's devices that asked to be told, content-free, when the
  # resident writes unprompted (gaia#15): the push service's endpoint.
  def change do
    projection :gaia_push_subscription, scope: :account do
      add(:endpoint, :text, null: false)
      add(:subscribed_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_push_subscription, [:account_id, :endpoint]))
  end
end
