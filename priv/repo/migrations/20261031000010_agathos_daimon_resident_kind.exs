defmodule Oneiroi.Repo.Migrations.AgathosDaimonResidentKind do
  use Ecto.Migration

  # A resident or a fixture (spec §12, P40; agathos-daimon #29): every
  # row before this one is a resident.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:kind, :string, null: false, default: "resident")
    end
  end
end
