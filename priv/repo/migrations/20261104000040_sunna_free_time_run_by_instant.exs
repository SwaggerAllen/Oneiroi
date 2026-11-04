defmodule Oneiroi.Repo.Migrations.SunnaFreeTimeRunByInstant do
  use Ecto.Migration

  # A free-time run is one slot's by its instant, not its label (sunna#27):
  # two runs a change of zone gave the same day and slot are both kept.
  # A replayed event still lands on its own row (the same instant).
  def change do
    drop(unique_index(:sunna_free_time_run, [:resident_id, :day, :slot]))
    create(unique_index(:sunna_free_time_run, [:resident_id, :day, :slot, :at]))
  end
end
