defmodule Oneiroi.Repo.Migrations.EthosVector do
  use Ecto.Migration
  import Oneiroi.Migration

  # The trigger lane's vector index (spec §6.17's load question): the
  # habits' triggers and names and the open seeds' words, embedded at
  # the library's width, derived from the rows and rebuilt from them;
  # pgvector is created by the library's migration before this one.
  def change do
    projection :ethos_vector, scope: :resident do
      add(:kind, :string, null: false)
      add(:number, :bigint, null: false)
      add(:text, :text, null: false)
      add(:hash, :string, null: false)
      add(:model, :string, null: false)
      add(:embedding, :vector, size: 1536, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:ethos_vector, [:resident_id, :kind, :number]))
  end
end
