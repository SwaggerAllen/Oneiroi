defmodule Oneiroi.Repo.Migrations.EunomiaJudgement do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # Trials derived from behaviours (spec §6.4): a run lists the
    # behaviours it drew on and a card names which one it answers.
    alter table(:eunomia_regression_run) do
      add(:behaviours, {:array, :bigint}, null: false, default: [])
    end

    alter table(:eunomia_regression_answer) do
      add(:behaviour_number, :bigint)
      # A derived trial's card names a behaviour and no test.
      modify(:test_number, :bigint, null: true, from: {:bigint, null: false})
    end

    projection :eunomia_position, scope: :resident do
      add(:number, :bigint, null: false)
      add(:statement, :text, null: false)
      add(:session_key, :string)
      add(:turn_ref, :string)
      add(:replaces, :bigint)
      add(:replaced_by, :bigint)
      add(:taken_at, :utc_datetime_usec, null: false)
      add(:replaced_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_position, [:resident_id, :number]))

    projection :eunomia_dispute, scope: :resident do
      add(:ref, :string, null: false)
      add(:source, :string, null: false)
      add(:position_number, :bigint)
      add(:claim, :text)
      add(:stance, :text)
      add(:session_key, :string)
      add(:turn_ref, :string)
      add(:outcome, :string, null: false)
      add(:advice, :string)
      add(:advice_text, :text)
      add(:judge_model, :string)
      add(:checked_at, :utc_datetime_usec, null: false)
      add(:settlement, :string)
      add(:settled_note, :text)
      add(:settled_by_kind, :string)
      add(:settled_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_dispute, [:resident_id, :ref]))

    projection :eunomia_prediction, scope: :resident do
      add(:number, :bigint, null: false)
      add(:statement, :text, null: false)
      add(:due, :utc_datetime_usec, null: false)
      add(:session_key, :string)
      add(:turn_ref, :string)
      add(:logged_at, :utc_datetime_usec, null: false)
      add(:outcome, :string)
      add(:note, :text)
      add(:resolved_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_prediction, [:resident_id, :number]))

    projection :eunomia_night, scope: :resident do
      add(:day, :string, null: false)
      add(:outcome, :string, null: false)
      add(:messages, :integer)
      add(:chars, :integer)
      add(:found, :integer)
      add(:judge_model, :string)
      add(:summary, :text)
      add(:reason, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(index(:eunomia_night, [:resident_id, :day]))

    # The judge's model as chosen, and every change, so the ratio chart
    # marks them (spec §6.4).
    projection :eunomia_judge_change, scope: :resident do
      add(:model, :string, null: false)
      add(:previous, :string)
      add(:at, :utc_datetime_usec, null: false)
    end
  end
end
