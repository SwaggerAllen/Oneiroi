defmodule Oneiroi.Repo.Migrations.SeshatResearch do
  use Ecto.Migration
  import Oneiroi.Migration

  # Research questions (seshat #38): what the reader's research pass was
  # asked, from which pages, by whom and from which conversation, and
  # how it settled, with the pages its notes came from.
  def change do
    projection :seshat_research, scope: :resident do
      add(:number, :bigint, null: false)
      add(:question, :text, null: false)
      add(:urls, {:array, :text}, null: false, default: [])
      add(:sources, {:array, :text}, null: false, default: [])
      add(:session_key, :string)
      add(:asked_by, :string, null: false)
      add(:status, :string, null: false)
      add(:path, :text)
      add(:reason, :text)
      add(:asked_at, :utc_datetime_usec, null: false)
      add(:settled_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_research, [:resident_id, :number]))
  end
end
