defmodule Oneiroi.Repo.Migrations.SunnaWorkCareSkipped do
  use Ecto.Migration

  # The witness's skip of the free-time wait (sunna#76): free-time passes
  # begun before this instant no longer hold the work line.
  def change do
    alter table(:sunna_work_queue) do
      add(:care_skipped_at, :utc_datetime_usec)
    end
  end
end
