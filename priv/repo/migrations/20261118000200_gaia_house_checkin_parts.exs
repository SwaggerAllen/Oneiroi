defmodule Oneiroi.Repo.Migrations.GaiaHouseCheckinParts do
  use Ecto.Migration

  # What a house check-in's note carries (gaia#48), as a resident's own
  # does: the witness's words for the whole house, and the catalog's
  # parts (null reads as the dates, sunna#28's default).
  def change do
    alter table(:gaia_house_checkin) do
      add(:prompt, :text)
      add(:parts, {:array, :text})
    end
  end
end
