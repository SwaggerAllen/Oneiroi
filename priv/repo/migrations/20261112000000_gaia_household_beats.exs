defmodule Oneiroi.Repo.Migrations.GaiaHouseholdBeats do
  use Ecto.Migration
  import Oneiroi.Migration

  # The household's beats (gaia#33 to #38): each member's wake profile
  # and standing registration, every turn fired with how it ended, and
  # each beat closed. The household's, every member's and no one's alone,
  # so platform-scoped as the contract's tables are, and read only after
  # the caller's own membership row has named the household. The turn's
  # resident is `speaker_id`, not a tenant column.
  def change do
    projection :gaia_household_beat_member, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:member_kind, :string, null: false)
      add(:member_id, :binary_id, null: false)
      add(:profile, :text)
      add(:registered_at, :utc_datetime_usec)
      add(:registered_for, :utc_datetime_usec)
      add(:missed, :integer, null: false, default: 0)
    end

    create(
      unique_index(:gaia_household_beat_member, [:household_id, :member_kind, :member_id])
    )

    projection :gaia_household_turn, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:turn, :integer, null: false)
      add(:speaker_id, :binary_id, null: false)
      add(:beat_top, :utc_datetime_usec, null: false)
      add(:fired_at, :utc_datetime_usec, null: false)
      add(:ends_by, :utc_datetime_usec, null: false)
      add(:opened_by, :string, null: false)
      add(:missed, :integer, null: false, default: 0)
      add(:ended_at, :utc_datetime_usec)
      add(:outcome, :text)
      add(:note, :text)
    end

    create(unique_index(:gaia_household_turn, [:household_id, :turn]))
    create(index(:gaia_household_turn, [:household_id, :speaker_id, :fired_at]))

    projection :gaia_household_beat, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:beat_top, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec, null: false)
      add(:turns, {:array, :map}, null: false, default: [])
      add(:passed_over, {:array, :binary_id}, null: false, default: [])
      add(:consumed, {:array, :binary_id}, null: false, default: [])
      add(:carried, {:array, :binary_id}, null: false, default: [])
      add(:note, :text)
    end

    create(unique_index(:gaia_household_beat, [:household_id, :beat_top]))
  end
end
