defmodule Oneiroi.Repo.Migrations.KumbukumbuSessionLabel do
  use Ecto.Migration

  # What an adapter's conversation is called (kumbukumbu #40): the base
  # name of the folder its runtime ran in, never the path, and which
  # runtime it is; nil for the platform's own sessions. And when the open
  # turn started (#41), which orders the open turns newest first: a
  # session with no captured turn has no `last_turn_at`, and Postgres
  # sorts a null first in a descending order.
  def change do
    alter table(:kumbukumbu_session) do
      add(:label, :string)
      add(:runtime, :string)
      add(:open_turn_at, :utc_datetime_usec)
    end
  end
end
