defmodule Oneiroi.Repo.Migrations.SeshatJournal do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :seshat_journal_entry, scope: :resident do
      add(:day, :string, null: false)
      add(:number, :integer, null: false)
      add(:kind, :string, null: false)
      add(:text, :text, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:actor_kind, :string)
      add(:done_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_journal_entry, [:resident_id, :day, :number]))
  end
end
