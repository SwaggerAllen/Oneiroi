defmodule Oneiroi.Repo.Migrations.SunnaQueueBacklog do
  use Ecto.Migration
  import Oneiroi.Migration

  # The backlog (sunna#103): numbered batches, and where each task and
  # batch stands in the house's order, open or closed.
  def change do
    projection :sunna_queue_batch, scope: :platform do
      add(:household_id, :binary_id, primary_key: true)
      add(:number, :integer, primary_key: true)
      add(:name, :text)
      add(:made_at, :utc_datetime_usec)
      add(:rank, :integer)
      add(:open, :boolean, null: false, default: false)
    end

    alter table(:sunna_queue_task) do
      add(:batch, :integer)
      add(:rank, :integer)
      add(:open, :boolean, null: false, default: false)
    end
  end
end
