defmodule Oneiroi.Repo.Migrations.GaiaBoot do
  use Ecto.Migration
  import Oneiroi.Migration

  # The platform's boots (gaia#21): each start with the commit it ran,
  # the one before and whether it changed; the platform's own, so
  # platform-scoped.
  def change do
    projection :gaia_boot, scope: :platform do
      add(:id, :string, primary_key: true)
      add(:stream_key, :string, null: false)
      add(:number, :integer, null: false)
      add(:commit, :text)
      add(:previous, :text)
      add(:changed, :boolean, null: false, default: false)
      add(:booted_at, :utc_datetime_usec, null: false)
    end

    create(index(:gaia_boot, [:booted_at]))
  end
end
