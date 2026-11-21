defmodule Oneiroi.Repo.Migrations.ProposalsTold do
  use Ecto.Migration

  # The witness's proposals told her through this instant (brain#118):
  # null until the first is told, when every one waiting is told once.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:proposals_told_through, :utc_datetime_usec)
    end
  end
end
