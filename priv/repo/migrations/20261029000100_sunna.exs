defmodule Oneiroi.Repo.Migrations.Sunna do
  use Ecto.Migration
  import Oneiroi.Migration

  # The schedule's rows are the resident's (spec §6.7); the steward reads
  # them as the steward under the resident's scope, and the tick reads
  # every resident's under the platform scope by name (sunna #11).
  def change do
    projection :sunna_checkin, scope: :resident do
      add(:key, :string, null: false)
      add(:label, :string, null: false)
      add(:time, :string, null: false)
      add(:changed_day, :string)
      add(:last_day, :string)
      add(:last_outcome, :string)
      add(:last_at, :utc_datetime_usec)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_checkin, [:resident_id, :key]))

    projection :sunna_firing, scope: :resident do
      add(:key, :string, null: false)
      add(:day, :string, null: false)
      add(:outcome, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:until, :utc_datetime_usec)
    end

    create(unique_index(:sunna_firing, [:resident_id, :key, :day]))

    projection :sunna_day, scope: :resident do
      add(:day, :string, null: false)
      add(:opened_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_day, [:resident_id, :day]))

    projection :sunna_date, scope: :resident do
      add(:number, :bigint, null: false)
      add(:title, :string, null: false)
      add(:on, :utc_datetime_usec, null: false)
      add(:kind, :string, null: false)
      add(:set_by_kind, :string)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_date, [:resident_id, :number]))

    projection :sunna_schedule, scope: :resident do
      add(:free_time, :string)
      add(:quiet_from, :string)
      add(:quiet_to, :string)
      add(:free_time_day, :string)
      add(:free_time_outcome, :string)
      add(:free_time_session_key, :string)
    end

    create(unique_index(:sunna_schedule, [:resident_id]))

    # The resident's zone (spec §6.7): UTC until the steward sets one.
    alter table(:agathos_daimon_resident) do
      add(:timezone, :string, null: false, default: "Etc/UTC")
    end
  end
end
