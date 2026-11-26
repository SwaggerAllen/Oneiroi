defmodule Oneiroi.Repo.Migrations.SunnaWorkStoppedRun do
  use Ecto.Migration

  # The run a stop ended (sunna#109), kept on her line while it rests
  # it: the activity, its task, household and conversation, and who
  # stopped it, so the witness's bell can say so and offer to resume.
  def change do
    alter table(:sunna_work_queue) do
      add(:stopped_act, :text)
      add(:stopped_task, :integer)
      add(:stopped_household, :binary_id)
      add(:stopped_key, :string)
      add(:stopped_by, :string)
    end
  end
end
