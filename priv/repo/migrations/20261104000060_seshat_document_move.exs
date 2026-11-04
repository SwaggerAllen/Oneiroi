defmodule Oneiroi.Repo.Migrations.SeshatDocumentMove do
  use Ecto.Migration
  import Oneiroi.Migration

  # Where a document moved from and to (seshat#39): the old path's
  # citations follow it. One row per path moved from; a later move from
  # the same path (after something new was written there and moved too)
  # replaces it.
  def change do
    projection :seshat_document_move, scope: :resident do
      add(:from_path, :text, null: false)
      add(:to_path, :text, null: false)
      add(:moved_at, :utc_datetime_usec, null: false)
      add(:moved_by_kind, :string, null: false)
    end

    create(unique_index(:seshat_document_move, [:resident_id, :from_path]))
  end
end
