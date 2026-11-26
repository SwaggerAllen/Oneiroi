defmodule Oneiroi.Repo.Migrations.Janus do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # A succession, one row an episode (janus#3).
    projection :janus_succession, scope: :resident do
      add(:episode, :integer, null: false)
      add(:state, :string, null: false)
      add(:dry_run, :boolean, null: false, default: false)
      add(:proposed_by, :string)
      add(:proposed_note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:opened_note, :text)
      add(:opened_at, :utc_datetime_usec)
      add(:copy_id, :binary_id)
      add(:fork_sequence, :bigint)
      add(:fork_commit, :text)
      add(:fork_events, :integer)
      add(:forked_at, :utc_datetime_usec)
      add(:fork_failure, :text)
      add(:backup_url, :text)
      add(:backup_token, :binary)
      add(:backup_visibility, :text)
      add(:backup_push, :text)
      add(:backup_set_at, :utc_datetime_usec)
      add(:ended_note, :text)
      add(:ended_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_succession, [:resident_id, :episode]))

    # A succession's fork copy names the resident it was made from
    # (agathos-daimon#63).
    alter table(:agathos_daimon_resident) do
      add(:fork_of, :binary_id)
    end
  end
end
