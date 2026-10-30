defmodule Oneiroi.Repo.Migrations.AgathosDaimon do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # `resident_id` is the row's own id and `account_id` its witness's, so
    # the resident's scope and the witness's scope each see it (spec §2.2).
    projection :agathos_daimon_resident, scope: :both do
      add(:id, :binary_id, primary_key: true)
      add(:slug, :string, null: false)
      add(:name, :string, null: false)
      add(:state, :string, null: false)
      add(:custody, :string, null: false)
      add(:export_wall, :string)
      add(:import_source, :string)
      add(:import_root, :string)
      add(:remote_url, :string)
      add(:remote_token, :binary)
      add(:exported_through, :bigint, null: false, default: 0)
      add(:last_backup_sequence, :bigint)
      add(:last_backup_root, :string)
      add(:last_backup_commit, :string)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_resident, [:slug]))
  end
end
