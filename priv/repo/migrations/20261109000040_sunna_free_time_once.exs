defmodule Oneiroi.Repo.Migrations.SunnaFreeTimeOnce do
  use Ecto.Migration
  import Oneiroi.Migration

  # One-off free-time slots (sunna#45), beside the standing list: a day
  # and a time in her zone, and who added it.
  def change do
    projection :sunna_free_time_once, scope: :resident do
      add(:day, :text, null: false)
      add(:time, :text, null: false)
      add(:added_by, :text)
      add(:added_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_free_time_once, [:resident_id, :day, :time]))
  end
end
