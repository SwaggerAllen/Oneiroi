defmodule Oneiroi.Repo.Migrations.KumbukumbuEthos do
  use Ecto.Migration
  import Oneiroi.Migration

  # Behaviours are the resident's rows (spec §6.3, F55), read by the
  # steward as the steward under the resident's scope, as bookmarks are.
  def change do
    projection :kumbukumbu_behaviour, scope: :resident do
      add(:number, :bigint, null: false)
      add(:name, :string, null: false)
      add(:trigger, :map, null: false, default: %{})
      add(:stance, :string, null: false)
      add(:defined_by_kind, :string)
      add(:defined_by_id, :string)
      add(:defined_at, :utc_datetime_usec, null: false)
      add(:revised_at, :utc_datetime_usec)
      add(:revisions, :integer, null: false, default: 0)
    end

    create(unique_index(:kumbukumbu_behaviour, [:resident_id, :number]))

    projection :kumbukumbu_enactment, scope: :resident do
      add(:number, :bigint, null: false)
      add(:target_kind, :string, null: false)
      add(:target_id, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_enactment, [:resident_id, :number, :target_kind, :target_id]))

    projection :kumbukumbu_affirmation, scope: :resident do
      add(:number, :bigint, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:note, :text, null: false)
      add(:by_kind, :string)
      add(:by_id, :string)
    end

    create(index(:kumbukumbu_affirmation, [:resident_id, :number]))
  end
end
