defmodule Oneiroi.Repo.Migrations.SeshatPieceReview do
  use Ecto.Migration
  import Oneiroi.Migration

  # A writing piece's review and Substack draft (seshat#42).
  def change do
    projection :seshat_piece_review, scope: :resident do
      add(:path, :text, null: false)
      add(:state, :string, null: false)
      add(:note, :text)
      add(:hash, :string)
      add(:decided_at, :utc_datetime_usec, null: false)
      add(:draft_url, :text)
      add(:drafted_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_piece_review, [:resident_id, :path]))
  end
end
