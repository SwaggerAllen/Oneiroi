defmodule Oneiroi.Repo.Migrations.AgathosDaimonFileRetired do
  use Ecto.Migration

  # An identity file she took out of her prefix (agathos-daimon#50): since
  # when, null while it is given every turn.
  def change do
    alter table(:agathos_daimon_file) do
      add(:retired_at, :utc_datetime_usec)
    end
  end
end
