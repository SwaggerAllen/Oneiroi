defmodule Oneiroi.Repo.Migrations.SunnaPlanningCost do
  use Ecto.Migration

  # What the planning turn that closed a free-time slot cost (sunna#32),
  # shown on the slot's receipts as its own line.
  def change do
    alter table(:sunna_free_time_run) do
      add(:planning_nanos, :bigint)
    end
  end
end
