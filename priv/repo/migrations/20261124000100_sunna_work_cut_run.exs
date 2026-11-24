defmodule Oneiroi.Repo.Migrations.SunnaWorkCutRun do
  use Ecto.Migration
  import Oneiroi.Migration

  # The run the check ended, left behind by a restart or a crash
  # (sunna#100): kept on her line so the next run of that activity is
  # told it was cut off, and where.
  def change do
    alter table(:sunna_work_queue) do
      add(:cut_act, :text)
      add(:cut_key, :string)
      add(:cut_since, :utc_datetime_usec)
      add(:cut_at, :utc_datetime_usec)
    end

    # Her runs of each activity since it last moved (sunna#101): the
    # guard on one activity run again and again with nothing changing.
    projection :sunna_work_activity_runs, scope: :resident do
      add(:act, :text, null: false)
      add(:runs, :integer, null: false, default: 0)
    end

    create(unique_index(:sunna_work_activity_runs, [:resident_id, :act]))
  end
end
