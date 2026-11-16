defmodule Oneiroi.Repo.Migrations.GaiaHouseCheckins do
  use Ecto.Migration
  import Oneiroi.Migration

  # House check-ins (gaia#41): the workspace's own clock, and the
  # check-ins it keeps with the day each last fired and the thread it
  # opened.
  def change do
    alter table(:gaia_household) do
      add(:zone, :text, null: false, default: "Etc/UTC")
    end

    projection :gaia_house_checkin, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:key, :text, null: false)
      add(:label, :text, null: false)
      add(:time, :text, null: false)
      add(:last_day, :text)
      add(:last_thread, :text)
      add(:last_fired_at, :utc_datetime_usec)
    end

    create(unique_index(:gaia_house_checkin, [:household_id, :key]))
  end
end
