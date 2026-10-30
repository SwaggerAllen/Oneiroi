defmodule Oneiroi.Repo.Migrations.SunnaHour do
  use Ecto.Migration
  import Oneiroi.Migration

  # The hour marker (spec §6.7, P20 as amended): one row per local hour
  # the tick reached, no model call and no wake, so absence is auditable.
  def change do
    projection :sunna_hour, scope: :resident do
      add(:hour, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_hour, [:resident_id, :hour]))
  end
end
