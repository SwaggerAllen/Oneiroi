defmodule Oneiroi.Repo.Migrations.EunomiaMovement do
  use Ecto.Migration

  # The nightly pass carries movement (spec §6.4, P34): each judged
  # night keeps the threads that moved, string-keyed maps with the four
  # fields and the message numbers and turn the judge read them in.
  def change do
    alter table(:eunomia_night) do
      add(:movements, {:array, :map}, null: false, default: [])
    end
  end
end
