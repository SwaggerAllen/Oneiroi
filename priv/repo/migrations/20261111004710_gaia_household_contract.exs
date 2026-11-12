defmodule Oneiroi.Repo.Migrations.GaiaHouseholdContract do
  use Ecto.Migration
  import Oneiroi.Migration

  # The household contract, its ballots and the watch (gaia#27 to #32).
  # Each is the household's, every member's and no one's alone, so the
  # tables are platform-scoped as `gaia_household` is, and read only
  # after the caller's own membership row has named the household. The
  # signature rides on the membership rows (gaia#28).
  def change do
    alter table(:gaia_household_witness) do
      add(:signed_version, :integer)
      add(:signed_at, :utc_datetime_usec)
    end

    alter table(:gaia_household_resident) do
      add(:signed_version, :integer)
      add(:signed_at, :utc_datetime_usec)
    end

    projection :gaia_household_contract, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:version, :integer, null: false)
      add(:prose, :text, null: false)
      add(:rules, {:array, :text}, null: false, default: [])
      add(:settings, :map, null: false, default: %{})
      add(:bundle, {:array, :map}, null: false, default: [])
      add(:ballot, :integer)
      add(:decided_by, :string)
      add(:decided_at, :utc_datetime_usec, null: false)
      add(:note, :text)
    end

    create(unique_index(:gaia_household_contract, [:household_id, :version]))

    projection :gaia_household_ballot, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:number, :integer, null: false)
      add(:thread, :string, null: false)
      add(:bundle, {:array, :map}, null: false)
      add(:term_days, :integer, null: false)
      add(:opened_by, :string)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:closes_at, :utc_datetime_usec, null: false)
      add(:note, :text)
      add(:closed_at, :utc_datetime_usec)
      add(:passed, :boolean)
      add(:yes, :integer)
      add(:no, :integer)
      add(:members, :integer)
      add(:outcome, :text)
    end

    create(unique_index(:gaia_household_ballot, [:household_id, :number]))

    projection :gaia_household_vote, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:ballot, :integer, null: false)
      add(:member_kind, :string, null: false)
      add(:member_id, :binary_id, null: false)
      add(:vote, :text, null: false)
      add(:voted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_household_vote, [:household_id, :ballot, :member_kind, :member_id]))

    projection :gaia_household_watch, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:watcher_id, :binary_id, null: false)
      add(:thread, :string, null: false)
      add(:until, :utc_datetime_usec, null: false)
      add(:watched_at, :utc_datetime_usec, null: false)
    end

    create(index(:gaia_household_watch, [:household_id, :thread, :until]))
  end
end
