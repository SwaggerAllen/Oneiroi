defmodule Oneiroi.Repo.Migrations.SeshatScenes do
  use Ecto.Migration
  import Oneiroi.Migration

  # The scenes as rows (seshat#52): each scene of a day, or a correction
  # of one's summary, and the day with whether the pass closed it.
  def change do
    projection :seshat_scene, scope: :resident do
      add(:day, :text, null: false)
      add(:number, :integer, null: false)
      add(:kind, :string, null: false)
      add(:corrects, :integer)
      add(:title, :text)
      add(:from_turn, :text, null: false)
      add(:to_turn, :text, null: false)
      add(:from_time, :utc_datetime_usec)
      add(:to_time, :utc_datetime_usec)
      add(:summary, :text, null: false)
      add(:mood, :text)
      add(:mood_was, :text)
      add(:mood_corrected_at, :utc_datetime_usec)
      add(:rounds_ran_out, :boolean, null: false, default: false)
      add(:register, :string)
      add(:at, :utc_datetime_usec, null: false)
      add(:actor_kind, :string)
      add(:corrected_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_scene, [:resident_id, :day, :number]))

    projection :seshat_scene_day, scope: :resident do
      add(:day, :text, null: false)
      add(:complete, :boolean, null: false, default: false)
      add(:closed_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_scene_day, [:resident_id, :day]))
  end
end
