defmodule Oneiroi.Repo.Migrations.RemoteCheck do
  use Ecto.Migration

  # What a backup remote's host last said it is (sima-qian#65): private,
  # public or unknown; whether the token may push; when it was asked.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:remote_visibility, :text)
      add(:remote_push, :text)
      add(:remote_checked_at, :utc_datetime_usec)
    end
  end
end
