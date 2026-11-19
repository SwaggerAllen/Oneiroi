defmodule Oneiroi.Repo.Migrations.GaiaHouseholdPush do
  use Ecto.Migration
  import Oneiroi.Migration

  # A witness's pushes for the house (gaia#57): the end of a round-robin
  # round and its rounds running out, each on unless set off. The
  # household's, so platform-scoped as its other tables are.
  def change do
    projection :gaia_household_push, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:member_id, :binary_id, null: false)
      add(:kind, :text, null: false)
      add(:on, :boolean, null: false)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_push, [:household_id, :member_id, :kind]))
  end
end
