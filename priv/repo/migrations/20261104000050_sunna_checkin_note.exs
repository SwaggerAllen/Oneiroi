defmodule Oneiroi.Repo.Migrations.SunnaCheckinNote do
  use Ecto.Migration

  # What a check-in's note carries (sunna#28): the parts checked from the
  # catalog and the witness's own words. Every check-in before this
  # carried the dates and nothing else, which the default keeps.
  def change do
    alter table(:sunna_checkin) do
      add(:parts, {:array, :string}, null: false, default: fragment("'{dates}'"))
      add(:prompt, :text)
    end
  end
end
