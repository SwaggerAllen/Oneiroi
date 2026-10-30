defmodule Oneiroi.Repo.Migrations.KumbukumbuMadeleine do
  use Ecto.Migration
  import Oneiroi.Migration

  # The madeleine layer (spec §6.3, P10): the bookmarks' words and the
  # limits embedded at the library's width, derived rows rebuilt from
  # the bookmarks; and when a bookmark was last recalled, so a recall
  # does not repeat. pgvector is created by the library's migration.
  def change do
    projection :kumbukumbu_vector, scope: :resident do
      add(:kind, :string, null: false)
      add(:number, :bigint, null: false)
      add(:text, :text, null: false)
      add(:hash, :string, null: false)
      add(:model, :string, null: false)
      add(:embedding, :vector, size: 1536, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_vector, [:resident_id, :kind, :number]))

    alter table(:kumbukumbu_bookmark) do
      add(:last_recalled_at, :utc_datetime_usec)
    end
  end
end
