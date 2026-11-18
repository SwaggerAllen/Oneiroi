defmodule Oneiroi.Repo.Migrations.SunnaHousePromptParts do
  use Ecto.Migration

  # What a house check-in's note carries for this resident (sunna#68), as
  # her own check-in's does: the catalog's keys; null reads as none.
  def change do
    alter table(:sunna_house_prompt) do
      add(:parts, {:array, :text})
    end
  end
end
