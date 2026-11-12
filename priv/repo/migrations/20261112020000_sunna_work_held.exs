defmodule Oneiroi.Repo.Migrations.SunnaWorkHeld do
  use Ecto.Migration

  # A held item (sunna#54): what it asks of the witness, who held it and
  # when; empty on every item that is not held (sunna#55).
  def change do
    alter table(:sunna_work_item) do
      add(:held_ask, :text)
      add(:held_by, :string)
      add(:held_at, :utc_datetime_usec)
    end
  end
end
