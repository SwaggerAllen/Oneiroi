defmodule Oneiroi.Repo.Migrations.Proteus do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :proteus_bridge, scope: :resident do
      add(:workspace, :string, null: false)
      add(:peers, {:array, :string}, null: false, default: [])
      add(:provisioned_at, :utc_datetime_usec, null: false)
      add(:card_hash, :string)
      add(:card_lines, :integer)
      add(:card_source, :string)
      add(:card_set_at, :utc_datetime_usec)
      add(:last_audit_at, :utc_datetime_usec)
      add(:last_audit_moved, :boolean)
      add(:last_audit_reason, :text)
      add(:syncs, :integer, null: false, default: 0)
      add(:last_sync_at, :utc_datetime_usec)
    end

    create(unique_index(:proteus_bridge, [:resident_id]))

    projection :proteus_sync, scope: :resident do
      add(:turn_ref, :string, null: false)
      add(:session_key, :string)
      add(:messages, :integer, null: false, default: 0)
      add(:outcome, :string, null: false)
      add(:reason, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:proteus_sync, [:resident_id, :turn_ref]))
  end
end
