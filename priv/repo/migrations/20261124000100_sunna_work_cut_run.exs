defmodule Oneiroi.Repo.Migrations.SunnaWorkCutRun do
  use Ecto.Migration

  # The run the check ended, left behind by a restart or a crash
  # (sunna#100): kept on her line so the next run of that activity is
  # told it was cut off, and where.
  def change do
    alter table(:sunna_work_queue) do
      add(:cut_act, :text)
      add(:cut_key, :string)
      add(:cut_since, :utc_datetime_usec)
      add(:cut_at, :utc_datetime_usec)
    end
  end
end
