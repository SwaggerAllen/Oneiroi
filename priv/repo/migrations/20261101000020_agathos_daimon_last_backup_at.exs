defmodule Oneiroi.Repo.Migrations.AgathosDaimonLastBackupAt do
  use Ecto.Migration

  # When the last backup was committed, so the resident's response can say
  # whether last night's push landed without a read of the event store.
  # Null until the next backup: the instant was not projected before.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:last_backup_at, :utc_datetime_usec)
    end
  end
end
