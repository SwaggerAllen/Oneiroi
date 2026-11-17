defmodule Oneiroi.Repo.Migrations.GaiaHouseholdGiteaInstance do
  use Ecto.Migration

  # Which Gitea instance a household's repositories are on (sima-qian#60,
  # gaia#43; the witness, 2026-11-16: shard by household, with a routing
  # field): null is the primary, the only instance today. A household is
  # moved by an event of its own when there is a second instance to move
  # it to; until then nothing writes the column.
  def change do
    alter table(:gaia_household) do
      add(:gitea_instance, :text)
    end
  end
end
