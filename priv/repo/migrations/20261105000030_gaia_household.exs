defmodule Oneiroi.Repo.Migrations.GaiaHousehold do
  use Ecto.Migration
  import Oneiroi.Migration

  # The household (gaia#17), the billing owner: the household itself is
  # every member's and no one's alone, so it is platform-scoped and read
  # through a membership; each membership row is its member's own, a
  # witness's under the account scope and a resident's under the
  # resident's.
  def change do
    projection :gaia_household, scope: :platform do
      add(:id, :binary_id, primary_key: true)
      add(:founded_by, :binary_id, null: false)
      add(:founded_at, :utc_datetime_usec, null: false)
      add(:plan, :text)
      add(:price_nanos, :bigint)
      add(:terms_until, :utc_datetime_usec)
      add(:terms_source, :text)
      add(:terms_note, :text)
    end

    projection :gaia_household_witness, scope: :account do
      add(:household_id, :binary_id, null: false)
      add(:joined_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_witness, [:household_id, :account_id]))
    create(index(:gaia_household_witness, [:account_id]))

    projection :gaia_household_resident, scope: :resident do
      add(:household_id, :binary_id, null: false)
      add(:joined_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_resident, [:household_id, :resident_id]))
    create(index(:gaia_household_resident, [:resident_id]))
  end
end
