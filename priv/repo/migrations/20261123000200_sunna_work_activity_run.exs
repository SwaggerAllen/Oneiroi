defmodule Oneiroi.Repo.Migrations.SunnaWorkActivityRun do
  use Ecto.Migration

  # A house queue activity running on her work line (sunna#86): which
  # activity, of which task in which household, beside the old item's
  # `running` (one or the other runs, never both).
  def change do
    alter table(:sunna_work_queue) do
      add(:running_act, :text)
      add(:running_task, :integer)
      add(:running_household, :binary_id)
    end
  end
end
