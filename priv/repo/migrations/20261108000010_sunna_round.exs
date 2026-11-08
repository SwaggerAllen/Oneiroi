defmodule Oneiroi.Repo.Migrations.SunnaRound do
  use Ecto.Migration
  import Oneiroi.Migration

  # Each thinking round, remembered (sunna#39): claimed at its drawn slot,
  # then ran in a conversation or failed with its kind. Rounds claimed
  # before this table are not back-filled: the settings row's
  # `last_round_at` still says when the last one started.
  def change do
    projection :sunna_round, scope: :resident do
      add(:day, :text, null: false)
      add(:slot, :text, null: false)
      add(:outcome, :text, null: false)
      add(:session_key, :string)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_round, [:resident_id, :day, :slot]))
  end
end
