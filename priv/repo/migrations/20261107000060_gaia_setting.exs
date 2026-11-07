defmodule Oneiroi.Repo.Migrations.GaiaSetting do
  use Ecto.Migration
  import Oneiroi.Migration

  # Platform settings set on the operator's screen (gaia#23), the first
  # the triage desk: platform-scoped, one row per key, by whom and why.
  def change do
    projection :gaia_setting, scope: :platform do
      add(:key, :string, primary_key: true)
      add(:value, :text)
      add(:note, :text)
      add(:set_by, :string)
      add(:set_at, :utc_datetime_usec, null: false)
    end
  end
end
