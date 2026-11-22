defmodule Oneiroi.Repo.Migrations.HouseLetterQuiet do
  use Ecto.Migration

  # A letter that wakes nobody (kumbukumbu#98): a forward's receipt.
  def change do
    alter table(:kumbukumbu_house_letter) do
      add(:quiet, :boolean, null: false, default: false)
    end
  end
end
