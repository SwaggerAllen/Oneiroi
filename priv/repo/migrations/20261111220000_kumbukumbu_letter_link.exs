defmodule Oneiroi.Repo.Migrations.KumbukumbuLetterLink do
  use Ecto.Migration

  # The other copy of a letter between two residents of a household
  # (kumbukumbu#66): where it came from or went, and the number there.
  def change do
    alter table(:kumbukumbu_house_letter) do
      add(:link, :map)
    end
  end
end
