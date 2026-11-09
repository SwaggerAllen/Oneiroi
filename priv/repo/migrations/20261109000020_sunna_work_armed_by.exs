defmodule Oneiroi.Repo.Migrations.SunnaWorkArmedBy do
  use Ecto.Migration

  # Who armed the work line (sunna#43): the resident by her tool or the
  # witness by his button, the receipt of the act.
  def change do
    alter table(:sunna_work_queue) do
      add(:armed_by, :string)
    end
  end
end
