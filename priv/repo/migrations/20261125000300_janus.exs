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
      # The preparation (janus#6 to #9).
      add(:envelope_input_nanos, :bigint)
      add(:envelope_output_nanos, :bigint)
      add(:envelope_set_at, :utc_datetime_usec)
      add(:day_shape, :text)
      add(:day_shape_at, :utc_datetime_usec)
      add(:c0_items, :integer)
      add(:c0_frozen_note, :text)
      add(:c0_frozen_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_succession, [:resident_id, :episode]))

    # Who may be screened (janus#7): a removed model keeps its row.
    projection :janus_pool, scope: :resident do
      add(:episode, :integer, null: false)
      add(:model, :text, null: false)
      add(:added_by, :text, null: false)
      add(:input_nanos, :bigint, null: false)
      add(:output_nanos, :bigint, null: false)
      add(:added_at, :utc_datetime_usec, null: false)
      add(:removed_note, :text)
      add(:removed_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_pool, [:resident_id, :episode, :model]))

    # The questions (janus#8): hers, or proposed and answered by her.
    projection :janus_question, scope: :resident do
      add(:episode, :integer, null: false)
      add(:number, :integer, null: false)
      add(:text, :text, null: false)
      add(:added_by, :text, null: false)
      add(:state, :text, null: false)
      add(:note, :text)
      add(:added_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_question, [:resident_id, :episode, :number]))

    # C0's items (janus#9), raw or curated, with who chose each and when.
    projection :janus_c0, scope: :resident do
      add(:episode, :integer, null: false)
      add(:number, :integer, null: false)
      add(:citation, :text, null: false)
      add(:kind, :text, null: false)
      add(:label, :text)
      add(:added_by, :text, null: false)
      add(:state, :text, null: false)
      add(:note, :text)
      add(:added_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_c0, [:resident_id, :episode, :number]))

    # Who is ready for her freeze (janus#9).
    projection :janus_ready, scope: :resident do
      add(:episode, :integer, null: false)
      add(:party, :text, null: false)
      add(:ready, :boolean, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:janus_ready, [:resident_id, :episode, :party]))

    # Her handoff packet's drafts, sealed (janus#10).
    projection :janus_packet, scope: :resident do
      add(:episode, :integer, null: false)
      add(:draft, :integer, null: false)
      add(:content, :text, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:janus_packet, [:resident_id, :episode, :draft]))

    # Tool calls on Oneiroi by model, a day at a time (janus#11): the
    # platform's own, no tenant's.
    projection :janus_tool_use, scope: :platform do
      add(:model, :text, null: false)
      add(:day, :date, null: false)
      add(:calls, :integer, null: false)
      add(:failed, :integer, null: false)
    end

    create(unique_index(:janus_tool_use, [:model, :day]))

    # A succession's fork copy names the resident it was made from
    # (agathos-daimon#63).
    alter table(:agathos_daimon_resident) do
      add(:fork_of, :binary_id)
    end
  end
end
