defmodule Oneiroi.Repo.Migrations.JanusStepsFinished do
  use Ecto.Migration

  # When she said her picks and her questions were done for now
  # (janus#42), each waking her to the next part.
  def change do
    alter table(:janus_succession) do
      add(:pool_done_at, :utc_datetime_usec)
      add(:questions_done_at, :utc_datetime_usec)
    end
  end
end
