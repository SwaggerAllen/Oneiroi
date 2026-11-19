defmodule Oneiroi.Repo.Migrations.SeshatBooks do
  use Ecto.Migration
  import Oneiroi.Migration

  # Books (seshat#98): each book imported, with her place in it, and its
  # reading history a row per chapter reached (read or peeked at). The
  # files are the repository's; these are what the tools read each turn.
  def change do
    projection :seshat_book, scope: :resident do
      add(:slug, :text, null: false)
      add(:title, :text, null: false)
      add(:author, :text)
      add(:identifier, :text)
      add(:rights, :text, null: false)
      add(:caveat, :text)
      add(:units, {:array, :text}, null: false, default: [])
      add(:titles, {:array, :text}, null: false, default: [])
      add(:current, :text)
      add(:read_at, :utc_datetime_usec)
      add(:imported_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_book, [:resident_id, :slug]))

    projection :seshat_book_read, scope: :resident do
      add(:sequence, :bigint, null: false)
      add(:slug, :text, null: false)
      add(:unit, :text, null: false)
      add(:mode, :text, null: false)
      add(:advanced, :boolean, null: false, default: false)
      add(:via, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_book_read, [:resident_id, :sequence]))
    create(index(:seshat_book_read, [:resident_id, :slug]))
  end
end
