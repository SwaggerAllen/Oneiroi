defmodule Oneiroi.Repo.Migrations.Register do
  use Ecto.Migration

  # The register a resident-authored record was written in (spec §6.13,
  # P8), on memory's bookmarks and the library's journal entries, tagged
  # at write time by the resident and counted nightly by the audits.
  def change do
    alter table(:kumbukumbu_bookmark) do
      add(:register, :string)
    end

    alter table(:seshat_journal_entry) do
      add(:register, :string)
    end
  end
end
