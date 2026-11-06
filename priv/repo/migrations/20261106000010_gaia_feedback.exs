defmodule Oneiroi.Repo.Migrations.GaiaFeedback do
  use Ecto.Migration
  import Oneiroi.Migration

  # Platform reports (gaia#20): the platform's own triage list, so
  # platform-scoped; a reporter reads their own through the service.
  def change do
    projection :gaia_feedback, scope: :platform do
      add(:id, :string, primary_key: true)
      add(:stream_key, :string, null: false)
      add(:number, :integer, null: false)
      add(:kind, :string, null: false)
      add(:surface, :text)
      add(:body, :text, null: false)
      add(:trace_id, :string)
      add(:author_kind, :string, null: false)
      add(:author_id, :binary_id)
      add(:account_id, :binary_id, null: false)
      add(:resident_id, :binary_id)
      add(:status, :string, null: false)
      add(:note, :text)
      add(:filed_at, :utc_datetime_usec, null: false)
      add(:moved_at, :utc_datetime_usec)
      add(:moved_by, :string)
    end

    create(unique_index(:gaia_feedback, [:stream_key, :number]))
  end
end
