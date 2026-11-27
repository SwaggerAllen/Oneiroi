defmodule Oneiroi.Repo.Migrations.JanusC0Unfrozen do
  use Ecto.Migration

  # When she last reopened C0 before screening, and why (janus#46).
  def change do
    alter table(:janus_succession) do
      add(:c0_unfrozen_at, :utc_datetime_usec)
      add(:c0_unfrozen_note, :text)
    end
  end
end
