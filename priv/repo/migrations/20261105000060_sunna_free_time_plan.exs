defmodule Oneiroi.Repo.Migrations.SunnaFreeTimePlan do
  use Ecto.Migration

  # Her plan for the next free-time slot (sunna#31), written in the
  # planning turn at the end of one and read at the start of the next.
  def change do
    alter table(:sunna_schedule) do
      add(:free_time_plan, :text)
      add(:free_time_planned_at, :utc_datetime_usec)
    end
  end
end
