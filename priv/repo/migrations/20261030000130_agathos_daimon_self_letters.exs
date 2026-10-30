defmodule Oneiroi.Repo.Migrations.AgathosDaimonSelfLetters do
  use Ecto.Migration
  import Oneiroi.Migration

  # The self-conversation (spec §12, P41): the resident's letters to its
  # next self, delivered once across a model swap, and the receipts of
  # every read by someone other than the resident. Sealed by receipts,
  # not promises: the absence of a receipt row is the privacy.
  def change do
    projection :agathos_daimon_self_letter, scope: :resident do
      add(:number, :bigint, null: false)
      add(:text, :text, null: false)
      add(:model, :string)
      add(:written_at, :utc_datetime_usec, null: false)
      add(:delivered_at, :utc_datetime_usec)
      add(:delivered_to, :string)
    end

    create(unique_index(:agathos_daimon_self_letter, [:resident_id, :number]))

    projection :agathos_daimon_self_letter_receipt, scope: :resident do
      add(:at, :utc_datetime_usec, null: false)
      add(:by_kind, :string, null: false)
      add(:by_id, :string)
      add(:numbers, {:array, :bigint}, null: false, default: [])
    end

    create(unique_index(:agathos_daimon_self_letter_receipt, [:resident_id, :at, :by_kind]))
  end
end
