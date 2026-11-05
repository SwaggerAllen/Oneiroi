defmodule Oneiroi.Repo.Migrations.SunnaRounds do
  use Ecto.Migration

  # The resident's own rounds (sunna#30): the cadence and waking window,
  # each null for the platform's default, and when the last one started,
  # so the witness can see they are on without seeing what they did.
  def change do
    alter table(:sunna_schedule) do
      add(:rounds_every_hours, :integer)
      add(:rounds_waking, :text)
      add(:last_round_at, :utc_datetime_usec)
    end
  end
end
