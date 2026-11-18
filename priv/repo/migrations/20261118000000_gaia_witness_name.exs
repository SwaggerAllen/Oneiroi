defmodule Oneiroi.Repo.Migrations.GaiaWitnessName do
  use Ecto.Migration

  # The name a witness goes by in the records (gaia#46): a household
  # names its witness by it, and a witness's name-folder is named for it.
  def change do
    alter table(:gaia_account) do
      add(:name, :text)
    end
  end
end
