defmodule Oneiroi.Repo.Migrations.SunnaWork do
  use Ecto.Migration
  import Oneiroi.Migration

  # The work queue (sunna#33): its items in priority order, and the loop's
  # state, one row a resident.
  def change do
    projection :sunna_work_item, scope: :resident do
      add(:number, :integer, null: false)
      add(:what, :text, null: false)
      add(:done_when, :text, null: false)
      add(:status, :string, null: false)
      add(:blocked_on, :text)
      add(:position, :integer, null: false)
      add(:added_by, :string, null: false)
      add(:added_at, :utc_datetime_usec, null: false)
      add(:note, :text)
      add(:moved_by, :string)
      add(:moved_at, :utc_datetime_usec)
      add(:shipped, :text)
      add(:slipped, :text)
      add(:why, :text)
      add(:wrapped_at, :utc_datetime_usec)
      add(:runs, :integer, null: false, default: 0)
      add(:session_key, :string)
    end

    create(unique_index(:sunna_work_item, [:resident_id, :number]))

    projection :sunna_work_queue, scope: :resident do
      add(:running, :integer)
      add(:running_key, :string)
      add(:running_since, :utc_datetime_usec)
      add(:rested_reason, :text)
      add(:rested_at, :utc_datetime_usec)
      add(:run_day, :text)
      add(:runs_on_day, :integer, null: false, default: 0)
    end

    create(unique_index(:sunna_work_queue, [:resident_id]))
  end
end
