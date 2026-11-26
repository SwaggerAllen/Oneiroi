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
      # Screening and judging (janus#12 to #15).
      add(:baseline_model, :text)
      add(:screening_note, :text)
      add(:screening_started_at, :utc_datetime_usec)
      add(:screening_finished_at, :utc_datetime_usec)
      add(:runs_answered, :integer)
      add(:runs_failed, :integer)
      add(:revealed_at, :utc_datetime_usec)
      add(:judging_closed_at, :utc_datetime_usec)
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

    # The panel (janus#12): invited, in, left, and at screening the
    # judges fixed, each with when their results were ready.
    projection :janus_panel, scope: :resident do
      add(:episode, :integer, null: false)
      add(:party, :text, null: false)
      add(:state, :text, null: false)
      add(:note, :text)
      add(:at, :utc_datetime_usec, null: false)
      add(:results_ready_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_panel, [:resident_id, :episode, :party]))

    # The runs (janus#13): who answered is a column no judge's read
    # returns before the reveal.
    projection :janus_run, scope: :resident do
      add(:episode, :integer, null: false)
      add(:run, :integer, null: false)
      add(:model, :text, null: false)
      add(:question, :integer, null: false)
      add(:content, :text)
      add(:refusal, :boolean, null: false, default: false)
      add(:failure, :text)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_run, [:resident_id, :episode, :run]))

    # Her baseline, a question at a time (janus#13).
    projection :janus_baseline, scope: :resident do
      add(:episode, :integer, null: false)
      add(:question, :integer, null: false)
      add(:model, :text, null: false)
      add(:content, :text)
      add(:refusal, :boolean, null: false, default: false)
      add(:failure, :text)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:janus_baseline, [:resident_id, :episode, :question]))

    # Each judge's judgment of each run (janus#14): a verdict record,
    # read only by the judge who wrote it.
    projection :janus_judgment, scope: :resident do
      add(:episode, :integer, null: false)
      add(:party, :text, null: false)
      add(:run, :integer, null: false)
      add(:category, :text, null: false)
      add(:argument, :text)
      add(:evidence, :text)
      add(:uncertainty, :text)
      add(:favorite, :boolean, null: false, default: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:janus_judgment, [:resident_id, :episode, :party, :run]))

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
