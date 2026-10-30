defmodule Oneiroi.Repo.Migrations.Glitnir do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :glitnir_report, scope: :resident do
      add(:number, :integer, null: false)
      add(:by_kind, :string)
      add(:by_id, :string)
      add(:text, :text, null: false)
      add(:filed_at, :utc_datetime_usec, null: false)
      add(:state, :string, null: false)
      add(:outcome, :string)
      add(:resolved_at, :utc_datetime_usec)
      add(:resolution_note, :text)
      add(:resolved_by_id, :string)
    end

    create(unique_index(:glitnir_report, [:resident_id, :number]))

    projection :glitnir_step, scope: :resident do
      add(:number, :integer, null: false)
      add(:sequence, :bigint, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:reason, :text)
      add(:by_id, :string)
    end

    create(unique_index(:glitnir_step, [:resident_id, :number, :sequence]))

    projection :glitnir_strike, scope: :resident do
      add(:number, :integer, null: false)
      add(:report, :integer, null: false)
      add(:witness_account_id, :binary_id)
      add(:consequence, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:glitnir_strike, [:resident_id, :number]))
  end
end
