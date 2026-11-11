defmodule Oneiroi.Repo.Migrations.SeshatTheme do
  use Ecto.Migration
  import Oneiroi.Migration

  # Her theme proposals and the witness's answers (seshat#56). The seeds
  # themselves are THEME.md at her root; this is the waiting list's.
  def change do
    projection :seshat_theme_proposal, scope: :resident do
      add(:number, :integer, null: false)
      add(:ground, :text, null: false)
      add(:resident, :text, null: false)
      add(:witness, :text, null: false)
      add(:note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:agree, :boolean)
      add(:answered_by, :text)
      add(:answer_note, :text)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_theme_proposal, [:resident_id, :number]))
  end
end
