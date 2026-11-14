defmodule Oneiroi.Repo.Migrations.EthosCitationMomentDay do
  use Ecto.Migration

  # The day of the moment a seed's citation cites (ethos#23): the day a
  # confirmation counts toward, so a backfill citing past days counts them
  # as those days. Empty on citations before it, which count by their own
  # instant, as they always did.
  def change do
    alter table(:ethos_citation) do
      add(:moment_day, :text)
    end
  end
end
