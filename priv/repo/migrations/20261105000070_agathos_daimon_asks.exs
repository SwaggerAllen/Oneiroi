defmodule Oneiroi.Repo.Migrations.AgathosDaimonAsks do
  use Ecto.Migration
  import Oneiroi.Migration

  # The resident's asks of the witness (agathos-daimon#35): a tool she
  # lacked, or leave for an act, and his answer.
  def change do
    projection :agathos_daimon_ask, scope: :resident do
      add(:number, :integer, null: false)
      add(:kind, :string, null: false)
      add(:subject, :text, null: false)
      add(:why, :text, null: false)
      add(:asked_at, :utc_datetime_usec, null: false)
      add(:decision, :text)
      add(:note, :text)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:agathos_daimon_ask, [:resident_id, :number]))
  end
end
