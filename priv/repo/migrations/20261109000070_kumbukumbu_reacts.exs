defmodule Oneiroi.Repo.Migrations.KumbukumbuReacts do
  use Ecto.Migration
  import Oneiroi.Migration

  # The witness's reacts on her messages and letters (kumbukumbu#56).
  def change do
    projection :kumbukumbu_react, scope: :resident do
      add(:number, :integer, null: false)
      add(:target_kind, :text, null: false)
      add(:session_key, :text)
      add(:turn_ref, :text)
      add(:letter, :integer)
      add(:emoji, :text, null: false)
      add(:reacted_at, :utc_datetime_usec, null: false)
      add(:told_at, :utc_datetime_usec)
      add(:told_in, :text)
    end

    create(unique_index(:kumbukumbu_react, [:resident_id, :number]))
  end
end
