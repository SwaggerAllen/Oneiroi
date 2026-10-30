defmodule Oneiroi.Repo.Migrations.Ethos do
  use Ecto.Migration
  import Oneiroi.Migration

  # The character layer (spec §6.17): seeds, habits, their citations to
  # the moments in memory, and the witness's affirmations, all the
  # resident's rows under its scope. The behaviours' tables in memory go
  # with the move (P38: habits are not memories); the store restarts for
  # v0.2, so nothing is carried across.
  def change do
    projection :ethos_seed, scope: :resident do
      add(:number, :bigint, null: false)
      add(:text, :text, null: false)
      add(:state, :string, null: false, default: "open")
      add(:planted_at, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec)
      add(:graduated_to_kind, :string)
      add(:graduated_to_id, :string)
      add(:graduation_note, :text)
    end

    create(unique_index(:ethos_seed, [:resident_id, :number]))

    projection :ethos_habit, scope: :resident do
      add(:number, :bigint, null: false)
      add(:name, :string, null: false)
      add(:trigger, :map, null: false, default: %{})
      add(:stance, :string, null: false)
      add(:seed_number, :bigint)
      add(:defined_by_kind, :string)
      add(:defined_by_id, :string)
      add(:defined_at, :utc_datetime_usec, null: false)
      add(:revised_at, :utc_datetime_usec)
      add(:revisions, :integer, null: false, default: 0)
    end

    create(unique_index(:ethos_habit, [:resident_id, :number]))

    projection :ethos_citation, scope: :resident do
      add(:kind, :string, null: false)
      add(:number, :bigint, null: false)
      add(:target_kind, :string, null: false)
      add(:target_id, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:ethos_citation, [:resident_id, :kind, :number, :target_kind, :target_id])
    )

    projection :ethos_affirmation, scope: :resident do
      add(:number, :bigint, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:note, :text, null: false)
      add(:by_kind, :string)
      add(:by_id, :string)
    end

    create(index(:ethos_affirmation, [:resident_id, :number]))

    drop(table(:kumbukumbu_enactment))
    drop(table(:kumbukumbu_affirmation))
    drop(table(:kumbukumbu_behaviour))
  end
end
