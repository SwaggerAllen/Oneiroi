defmodule Oneiroi.Repo.Migrations.XeniaRoutes do
  use Ecto.Migration
  import Oneiroi.Migration

  # Routes as data (xenia#19): her own routes, their runs, and the
  # profiles they read through as the witness made, named or revoked them.
  def change do
    projection :xenia_route, scope: :resident do
      add(:key, :text, null: false)
      add(:descriptor, :map, null: false)
      add(:created_by, :text)
      add(:updated_by, :text)
      add(:created_at, :utc_datetime_usec, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xenia_route, [:resident_id, :key]))

    projection :xenia_route_run, scope: :resident do
      add(:number, :integer, null: false)
      add(:key, :text, null: false)
      add(:state, :text, null: false)
      add(:note, :text)
      add(:asked_by, :text)
      add(:asked_at, :utc_datetime_usec, null: false)
      add(:path, :text)
      add(:reason, :text)
      add(:done_at, :utc_datetime_usec)
    end

    create(unique_index(:xenia_route_run, [:resident_id, :number]))

    projection :xenia_profile, scope: :resident do
      add(:key, :text, null: false)
      add(:label, :text)
      add(:origin, :text)
      add(:signed_in_as, :text)
      add(:revoked, :boolean, null: false, default: false)
      add(:note, :text)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xenia_profile, [:resident_id, :key]))
  end
end
