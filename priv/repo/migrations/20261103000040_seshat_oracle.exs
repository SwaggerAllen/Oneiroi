defmodule Oneiroi.Repo.Migrations.SeshatOracle do
  use Ecto.Migration
  import Oneiroi.Migration

  # The oracle's questions (brain #49, seshat #34): what was asked, of
  # which sources, by whom and from which conversation, and how it
  # settled. Found deliberately, by question, source, asker or state,
  # never by the ranked index.
  def change do
    projection :seshat_oracle, scope: :resident do
      add(:number, :bigint, null: false)
      add(:question, :text, null: false)
      add(:sources, {:array, :text}, null: false, default: [])
      # What it read (named and opened) and what it said it used, in
      # citation form: retrieval's read/used, searchable by either.
      add(:read, {:array, :text}, null: false, default: [])
      add(:used, {:array, :text}, null: false, default: [])
      add(:session_key, :string)
      add(:asked_by, :string, null: false)
      add(:status, :string, null: false)
      add(:path, :text)
      add(:confidence, :text)
      add(:model, :text)
      add(:reason, :text)
      add(:dispatched_at, :utc_datetime_usec, null: false)
      add(:settled_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_oracle, [:resident_id, :number]))
  end
end
