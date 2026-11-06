defmodule Oneiroi.Repo.Migrations.KumbukumbuInstantInferred do
  use Ecto.Migration

  # A message whose source carried no instant (kumbukumbu#50): its sent_at
  # keeps the order only, and every view says the time is unknown.
  def change do
    alter table(:kumbukumbu_message) do
      add(:instant_inferred, :boolean, null: false, default: false)
    end
  end
end
