defmodule Oneiroi.Repo.Migrations.EunomiaAudit do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :eunomia_audit, scope: :resident do
      add(:ref, :string, null: false)
      add(:outcome, :string, null: false)
      add(:conclusions, :integer)
      add(:flagged, :integer)
      add(:judge_model, :string)
      add(:summary, :text)
      add(:reason, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:eunomia_audit, [:resident_id, :ref]))

    projection :eunomia_audit_flag, scope: :resident do
      add(:ref, :string, null: false)
      add(:audit_ref, :string, null: false)
      add(:conclusion_id, :string, null: false)
      add(:conclusion, :text, null: false)
      add(:reason, :text)
      add(:raised_at, :utc_datetime_usec, null: false)
      add(:decision, :string)
      add(:note, :text)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_audit_flag, [:resident_id, :ref]))
  end
end
