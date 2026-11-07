defmodule Oneiroi.Repo.Migrations.SeshatExternal do
  use Ecto.Migration
  import Oneiroi.Migration

  # External sources (seshat#46): web pages and repositories' documents
  # commissioned for citing, with the latest copy the reader brought (its
  # path in the library, digest, commit and instant) and the one before.
  def change do
    projection :seshat_external, scope: :resident do
      add(:number, :bigint, null: false)
      add(:kind, :string, null: false)
      add(:key, :text, null: false)
      add(:url, :text, null: false)
      add(:ref, :text)
      add(:title, :text)
      add(:status, :string, null: false)
      add(:path, :text)
      add(:content_hash, :string)
      add(:previous_hash, :string)
      add(:commit, :text)
      add(:bytes, :bigint)
      add(:fetches, :integer, null: false, default: 0)
      add(:reason, :text)
      add(:session_key, :string)
      add(:commissioned_by, :string, null: false)
      add(:commissioned_at, :utc_datetime_usec, null: false)
      add(:asked_at, :utc_datetime_usec)
      add(:fetched_at, :utc_datetime_usec)
      add(:previous_fetched_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_external, [:resident_id, :number]))
    create(unique_index(:seshat_external, [:resident_id, :key]))
  end
end
