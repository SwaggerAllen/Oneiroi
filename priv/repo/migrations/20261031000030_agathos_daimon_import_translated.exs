defmodule Oneiroi.Repo.Migrations.AgathosDaimonImportTranslated do
  use Ecto.Migration

  # What an import translated from the source platform's records
  # (agathos-daimon #30): `%{"source", "counts"}`, nil for an import
  # that translated nothing and for every resident before this one.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:import_translated, :map)
    end
  end
end
