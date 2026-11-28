defmodule Oneiroi.Repo.Migrations.SunnaQueueHandoffMerge do
  use Ecto.Migration

  # Whether a Claude Code activity has been handed to it (sunna#117), and
  # whether an approved pull request review waits on its merge (sunna#118).
  def change do
    alter table(:sunna_queue_activity) do
      add(:handed_off, :boolean, null: false, default: false)
      add(:awaiting_merge, :boolean, null: false, default: false)
    end
  end
end
