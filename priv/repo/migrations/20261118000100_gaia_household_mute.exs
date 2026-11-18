defmodule Oneiroi.Repo.Migrations.GaiaHouseholdMute do
  use Ecto.Migration
  import Oneiroi.Migration

  # A member's mentions in the house, muted or heard (gaia#46): the whole
  # house (thread "") or one thread. The household's, every member's and
  # no one resident's, so platform-scoped as the watch is.
  def change do
    projection :gaia_household_mute, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:member_id, :binary_id, null: false)
      add(:member_kind, :text, null: false)
      add(:thread, :text, null: false)
      add(:muted, :boolean, null: false)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_mute, [:household_id, :member_id, :thread]))
  end
end
