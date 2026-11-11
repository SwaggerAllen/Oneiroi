defmodule Oneiroi.Repo.Migrations.SeshatScenePeople do
  use Ecto.Migration

  # Who a scene involves (seshat#57): the names of the persons in it, as
  # she names them; empty on every row written before, and on a
  # correction row. The table's row policy is unchanged.
  def change do
    alter table(:seshat_scene) do
      add(:people, {:array, :text}, null: false, default: [])
    end
  end
end
