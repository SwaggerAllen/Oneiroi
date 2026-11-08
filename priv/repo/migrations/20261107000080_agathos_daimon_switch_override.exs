defmodule Oneiroi.Repo.Migrations.AgathosDaimonSwitchOverride do
  use Ecto.Migration
  import Oneiroi.Migration

  # A contract switch moved to its safe value by one party
  # (agathos-daimon#38), standing over the version in force until a
  # version proposed after it is agreed.
  def change do
    projection :agathos_daimon_switch_override, scope: :resident do
      add(:key, :string, null: false)
      add(:value, :boolean, null: false)
      add(:set_by, :string)
      add(:note, :text)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_switch_override, [:resident_id, :key]))
  end
end
