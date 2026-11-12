defmodule Oneiroi.Repo.Migrations.GaiaHouseholdRegistration do
  use Ecto.Migration
  import Oneiroi.Migration

  # A registration is for one beat (gaia#35, #39): a row per resident per
  # beat, deleted when that beat closes. The member row keeps her profile
  # and what she has missed; its one standing registration goes.
  def change do
    projection :gaia_household_registration, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:speaker_id, :binary_id, null: false)
      add(:beat_top, :utc_datetime_usec, null: false)
      add(:registered_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_registration, [:household_id, :speaker_id, :beat_top]))
    create(index(:gaia_household_registration, [:household_id, :beat_top]))

    alter table(:gaia_household_beat_member) do
      remove(:registered_at, :utc_datetime_usec)
      remove(:registered_for, :utc_datetime_usec)
    end
  end
end
