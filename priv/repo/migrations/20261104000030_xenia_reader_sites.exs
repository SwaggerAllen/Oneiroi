defmodule Oneiroi.Repo.Migrations.XeniaReaderSites do
  use Ecto.Migration
  import Oneiroi.Migration

  # The reader's allowlists (xenia #16): the origins its browser may
  # reach to read correspondence and to research, set by the witness.
  def change do
    projection :xenia_reader_sites, scope: :resident do
      add(:scrape, {:array, :text}, null: false, default: [])
      add(:research, {:array, :text}, null: false, default: [])
      add(:set_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xenia_reader_sites, [:resident_id]))
  end
end
