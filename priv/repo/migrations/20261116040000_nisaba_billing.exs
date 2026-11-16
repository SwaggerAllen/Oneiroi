defmodule Oneiroi.Repo.Migrations.NisabaBilling do
  use Ecto.Migration

  # The payment provider's ids behind a subscription (nisaba#23).
  def change do
    alter table(:nisaba_subscription) do
      add(:billing_customer_id, :string)
      add(:billing_subscription_id, :string)
    end
  end
end
