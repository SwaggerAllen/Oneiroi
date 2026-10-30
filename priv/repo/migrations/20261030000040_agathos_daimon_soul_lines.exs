defmodule Oneiroi.Repo.Migrations.AgathosDaimonSoulLines do
  use Ecto.Migration
  import Oneiroi.Migration

  # The soul file as rows (spec §6.17, P39): one per minted number, live
  # or retired, in the file's order, with the seeds it cites. The file
  # itself stays in `agathos_daimon_file` as its words; the markers are
  # rendered on read.
  def change do
    projection :agathos_daimon_soul_line, scope: :resident do
      add(:number, :bigint, null: false)
      add(:text, :text, null: false)
      add(:position, :integer, null: false, default: 0)
      add(:state, :string, null: false, default: "live")
      add(:cites, {:array, :bigint}, null: false, default: [])
      add(:version, :integer, null: false, default: 1)
      add(:written_at, :utc_datetime_usec, null: false)
      add(:reworded_at, :utc_datetime_usec)
      add(:retired_at, :utc_datetime_usec)
    end

    create(unique_index(:agathos_daimon_soul_line, [:resident_id, :number]))
  end
end
