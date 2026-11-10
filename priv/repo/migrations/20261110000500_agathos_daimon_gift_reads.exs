defmodule Oneiroi.Repo.Migrations.AgathosDaimonGiftReads do
  use Ecto.Migration
  import Oneiroi.Migration

  # The gifts' reads (agathos-daimon#40): one row per read of a gift's
  # draft, with its notes as given. The record is the resident's stream
  # (`GiftReadGiven`, beside the seeds) and the export's reading copy;
  # this table is what the creation flow lists.
  def change do
    projection :agathos_daimon_gift_read, scope: :resident do
      add(:ref, :text, null: false)
      add(:gift, :text, null: false)
      add(:file, :text, null: false)
      add(:draft_sha, :text, null: false)
      add(:notes, {:array, :map}, null: false, default: [])
      add(:model, :text)
      add(:by_kind, :string, null: false)
      add(:by_id, :string)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_gift_read, [:resident_id, :ref]))
    create(index(:agathos_daimon_gift_read, [:resident_id, :file, :at]))
  end
end
