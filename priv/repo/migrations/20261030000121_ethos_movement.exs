defmodule Oneiroi.Repo.Migrations.EthosMovement do
  use Ecto.Migration

  # The citation's annotation (spec §6.17, P34 under P38): what the
  # cited moment changed, as stance, intention and resume, or nothing.
  def change do
    alter table(:ethos_citation) do
      add(:movement, :map)
    end
  end
end
