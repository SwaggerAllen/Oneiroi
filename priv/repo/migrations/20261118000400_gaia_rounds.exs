defmodule Oneiroi.Repo.Migrations.GaiaRounds do
  use Ecto.Migration
  import Oneiroi.Migration

  # Round-robin threads (gaia#53): a row a thread (its round, whose turn,
  # stopped or not, who opted out) and a row a turn issued, the visible
  # queue of wakes (issued, until, spent how and when). The household's,
  # every member's, so platform-scoped as the household's tables are.
  def change do
    projection :gaia_round_thread, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:thread, :text, null: false)
      add(:round, :integer, null: false)
      add(:order, {:array, :binary_id}, null: false, default: [])
      add(:stopped, :boolean, null: false, default: false)
      add(:optout, {:array, :binary_id}, null: false, default: [])
      add(:live_turn, :text)
      add(:changed_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_round_thread, [:household_id, :thread]))

    projection :gaia_round_turn, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:turn_id, :text, null: false)
      add(:thread, :text, null: false)
      add(:round, :integer, null: false)
      add(:resident_id, :binary_id, null: false)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:outcome, :text)
      add(:spent_at, :utc_datetime_usec)
    end

    create(unique_index(:gaia_round_turn, [:household_id, :turn_id]))
    create(index(:gaia_round_turn, [:resident_id, :issued_at]))
  end
end
