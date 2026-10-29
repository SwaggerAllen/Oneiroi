defmodule Oneiroi.Repo.Migrations.EunomiaRegression do
  use Ecto.Migration
  import Oneiroi.Migration

  # Sealed from the resident (spec §6.4): the rows are under the
  # resident's scope like every other, and what seals them is that no
  # tool, export or other system reads them; the invariant test asserts
  # it over every resident-reachable surface.
  def change do
    projection :eunomia_regression_test, scope: :resident do
      add(:number, :bigint, null: false)
      add(:prompt, :text, null: false)
      add(:passes_if, :text, null: false)
      add(:fails_if, :text, null: false)
      add(:written_at, :utc_datetime_usec, null: false)
      add(:changed_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_regression_test, [:resident_id, :number]))

    projection :eunomia_regression_run, scope: :resident do
      add(:ref, :string, null: false)
      add(:models, {:array, :string}, null: false, default: [])
      add(:tests, {:array, :bigint}, null: false, default: [])
      add(:started_at, :utc_datetime_usec, null: false)
      add(:finished_at, :utc_datetime_usec)
      add(:cards, :integer, null: false, default: 0)
    end

    create(unique_index(:eunomia_regression_run, [:resident_id, :ref]))

    projection :eunomia_regression_answer, scope: :resident do
      add(:run_ref, :string, null: false)
      add(:card_ref, :string, null: false)
      add(:model, :string, null: false)
      add(:test_number, :bigint, null: false)
      add(:content, :text)
      add(:refusal, :boolean, null: false, default: false)
      add(:failure, :string)
      add(:grade, :string)
      add(:favourite, :boolean, null: false, default: false)
      add(:recorded_at, :utc_datetime_usec, null: false)
      add(:graded_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_regression_answer, [:resident_id, :run_ref, :card_ref]))

    # The pinned chat model (spec §6.4), and whether the resident has been
    # told of the latest change.
    alter table(:agathos_daimon_resident) do
      add(:chat_model, :string)
      add(:model_pinned_at, :utc_datetime_usec)
      add(:model_told, :boolean, null: false, default: true)
    end
  end
end
