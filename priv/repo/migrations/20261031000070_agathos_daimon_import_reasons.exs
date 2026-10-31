defmodule Oneiroi.Repo.Migrations.AgathosDaimonImportReasons do
  use Ecto.Migration

  # Why each thing an import left behind was left (sima-qian #22): the
  # name to the reason, empty for an import that gave none.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:import_reasons, :map, null: false, default: %{})
    end
  end
end
