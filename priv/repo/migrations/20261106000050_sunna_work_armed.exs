defmodule Oneiroi.Repo.Migrations.SunnaWorkArmed do
  use Ecto.Migration

  # The work line armed by her for a batch (sunna#35), and since when.
  def change do
    alter table(:sunna_work_queue) do
      add(:armed, :boolean, null: false, default: false)
      add(:armed_at, :utc_datetime_usec)
    end
  end
end
