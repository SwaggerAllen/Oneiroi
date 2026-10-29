defmodule Oneiroi.Repo.Migrations.HuginnMuninn do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :huginn_muninn_counter, scope: :resident do
      add(:key, :string, null: false)
      add(:label, :string, null: false)
      add(:value, :bigint, null: false, default: 0)
      add(:increments, :integer, null: false, default: 0)
      add(:defined_at, :utc_datetime_usec, null: false)
      add(:last_at, :utc_datetime_usec)
      add(:last_by_kind, :string)
      add(:retired_at, :utc_datetime_usec)
    end

    create(unique_index(:huginn_muninn_counter, [:resident_id, :key]))

    projection :huginn_muninn_increment, scope: :resident do
      add(:key, :string, null: false)
      add(:sequence, :bigint, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:by, :integer, null: false)
      add(:note, :text)
      add(:actor_kind, :string)
      add(:actor_id, :string)
    end

    create(unique_index(:huginn_muninn_increment, [:resident_id, :key, :sequence]))

    projection :huginn_muninn_audit, scope: :resident do
      add(:key, :string, null: false)
      add(:label, :string, null: false)
      add(:figure, :string, null: false)
      add(:op, :string, null: false)
      add(:value, :bigint, null: false)
      add(:tone, :string, null: false)
      add(:counts, :boolean, null: false, default: true)
      add(:defined_at, :utc_datetime_usec, null: false)
      add(:retired_at, :utc_datetime_usec)
    end

    create(unique_index(:huginn_muninn_audit, [:resident_id, :key]))

    projection :huginn_muninn_run, scope: :resident do
      add(:key, :string, null: false)
      add(:sequence, :bigint, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:builtin, :boolean, null: false, default: false)
      add(:tone, :string, null: false)
      add(:value, :bigint)
      add(:finding, :text)
    end

    create(unique_index(:huginn_muninn_run, [:resident_id, :key, :sequence]))

    # The attestation's last word on the resident row (sima-qian #10), so
    # the built-in attestation audit reads a row and never the stream.
    alter table(:agathos_daimon_resident) do
      add(:root_mismatched_at, :utc_datetime_usec)
    end
  end
end
