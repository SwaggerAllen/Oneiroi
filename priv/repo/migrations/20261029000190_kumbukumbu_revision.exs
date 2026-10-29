defmodule Oneiroi.Repo.Migrations.KumbukumbuRevision do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :kumbukumbu_revision, scope: :resident do
      add(:number, :integer, null: false)
      add(:target_kind, :string, null: false)
      add(:target_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:text, :text, null: false)
      add(:note, :text)
      add(:state, :string, null: false)
      add(:by_kind, :string)
      add(:by_id, :string)
      add(:at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
      add(:decision_note, :text)
    end

    create(unique_index(:kumbukumbu_revision, [:resident_id, :number]))
    create(index(:kumbukumbu_revision, [:resident_id, :target_kind, :target_id]))
  end
end
