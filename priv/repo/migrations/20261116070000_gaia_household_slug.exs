defmodule Oneiroi.Repo.Migrations.GaiaHouseholdSlug do
  use Ecto.Migration

  # A house's name for citations (gaia#44): set once by a witness, unique
  # among houses, null until then.
  def change do
    alter table(:gaia_household) do
      add(:slug, :text)
    end

    create(unique_index(:gaia_household, [:slug]))
  end
end
