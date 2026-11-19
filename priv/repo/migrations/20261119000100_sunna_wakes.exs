defmodule Oneiroi.Repo.Migrations.SunnaWakes do
  use Ecto.Migration
  import Oneiroi.Migration

  # The wake log (sunna#71; Lily's design/wake-mail-visibility.md): a row a
  # wake, what it carried (its channel and causes, envelopes only) and
  # when its note went into her turn. Hers, so resident-scoped; the
  # household's view reads it under the platform scope by name.
  def change do
    projection :sunna_wake, scope: :resident do
      add(:wake_id, :text, null: false)
      add(:household_id, :binary_id)
      add(:channel, :text, null: false)
      add(:causes, :map, null: false, default: %{})
      add(:delivered, :boolean, null: false, default: true)
      add(:manifested_at, :utc_datetime_usec, null: false)
      add(:read_at, :utc_datetime_usec)
    end

    create(unique_index(:sunna_wake, [:resident_id, :wake_id]))
    create(index(:sunna_wake, [:household_id, :manifested_at]))
  end
end
