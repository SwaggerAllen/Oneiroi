defmodule Oneiroi.Repo.Migrations.SeshatDigest do
  use Ecto.Migration
  import Oneiroi.Migration

  # Digests asked of the reader (seshat#40): since when, by whom, from
  # which conversation, and how each settled.
  def change do
    projection :seshat_digest, scope: :resident do
      add(:number, :bigint, null: false)
      add(:session_key, :string)
      add(:since, :utc_datetime_usec, null: false)
      add(:asked_by, :string, null: false)
      add(:status, :string, null: false)
      add(:path, :text)
      add(:items, :integer)
      add(:reason, :text)
      add(:asked_at, :utc_datetime_usec, null: false)
      add(:settled_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_digest, [:resident_id, :number]))
  end
end
