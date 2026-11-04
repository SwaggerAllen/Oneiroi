defmodule Oneiroi.Repo.Migrations.SunnaFreeTimeSlots do
  use Ecto.Migration
  import Oneiroi.Migration

  # Free time is a list of slots (sunna#22): the settings row gains the
  # list, and each slot's run on a day is a row of its own. Nothing is
  # copied here: the rows are under forced row security, and the reads
  # take the one-slot columns as they stand (`Schedules.free_times_of/1`
  # and `free_time_ran/2`), so a deploy neither forgets the time set nor
  # runs today's free time a second time.
  def change do
    alter table(:sunna_schedule) do
      add(:free_times, {:array, :string})
    end

    projection :sunna_free_time_run, scope: :resident do
      add(:day, :string, null: false)
      add(:slot, :string)
      add(:outcome, :string, null: false)
      add(:session_key, :string)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_free_time_run, [:resident_id, :day, :slot]))
  end
end
