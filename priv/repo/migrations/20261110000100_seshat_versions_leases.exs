defmodule Oneiroi.Repo.Migrations.SeshatVersionsLeases do
  use Ecto.Migration
  import Oneiroi.Migration

  # A document's versions as the library stream recorded them (seshat
  # #54): each write, adoption, move or archive of a path, by whom, with
  # its hash and note; joined to the repository's history for the words.
  # And the witness's edit leases (seshat#55): coordination state, a
  # plain table on the db-only list (spec §6.10, `leases`), never events.
  def change do
    projection :seshat_document_version, scope: :resident do
      add(:path, :text, null: false)
      add(:event_number, :bigint, null: false)
      add(:act, :text, null: false)
      add(:hash, :string, null: false)
      add(:bytes, :integer)
      add(:actor_kind, :string)
      add(:actor_id, :string)
      add(:note, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_document_version, [:resident_id, :path, :event_number]))

    projection :seshat_lease, scope: :resident do
      add(:path, :text, null: false)
      add(:holder_id, :binary_id, null: false)
      add(:state, :string, null: false)
      add(:acquired_at, :utc_datetime_usec, null: false)
      add(:renewed_at, :utc_datetime_usec, null: false)
      add(:draft, :text)
      add(:waiting_at, :utc_datetime_usec)
      add(:taken_at, :utc_datetime_usec)
      add(:kept_at, :text)
    end

    create(unique_index(:seshat_lease, [:resident_id, :path]))
  end
end
