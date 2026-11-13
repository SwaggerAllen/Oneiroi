defmodule Oneiroi.Repo.Migrations.SunnaWorkItemTime do
  use Ecto.Migration

  # How long an item has been in work (sunna#58): when its first run
  # started, and the seconds its ended runs took between them. Folded from
  # here on; an item that ran before has neither, and says so.
  def change do
    alter table(:sunna_work_item) do
      add(:first_started_at, :utc_datetime_usec)
      add(:worked_seconds, :integer, null: false, default: 0)
    end
  end
end
