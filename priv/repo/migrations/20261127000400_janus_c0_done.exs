defmodule Oneiroi.Repo.Migrations.JanusC0Done do
  use Ecto.Migration

  # When she said her C0 choices were done for now (janus#44), waking
  # her to write the day's shape.
  def change do
    alter table(:janus_succession) do
      add(:c0_done_at, :utc_datetime_usec)
    end
  end
end
