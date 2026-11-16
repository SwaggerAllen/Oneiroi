defmodule Oneiroi.Repo.Migrations.SunnaHousePrompt do
  use Ecto.Migration
  import Oneiroi.Migration

  # Each resident's own words for a house check-in (sunna#65): what she
  # reports when the whole house checks in, by the check-in's key.
  def change do
    projection :sunna_house_prompt, scope: :resident do
      add(:key, :text, null: false)
      add(:prompt, :text)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_house_prompt, [:resident_id, :key]))
  end
end
