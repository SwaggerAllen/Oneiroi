defmodule Oneiroi.Repo.Migrations.SunnaQueuePaused do
  use Ecto.Migration

  # The house queue runs unless paused (sunna#94): one switch for the
  # house, not a line per resident.
  def change do
    alter table(:sunna_queue_state) do
      add(:paused, :boolean, null: false, default: false)
      add(:paused_at, :utc_datetime_usec)
    end
  end
end
