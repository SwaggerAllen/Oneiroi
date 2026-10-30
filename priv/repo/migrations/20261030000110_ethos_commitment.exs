defmodule Oneiroi.Repo.Migrations.EthosCommitment do
  use Ecto.Migration
  import Oneiroi.Migration

  # Commitments (spec §3.1, P19): a promise to a person as a record kind
  # of its own, numbered by the resident aggregate, open until kept or
  # released with a note.
  def change do
    projection :ethos_commitment, scope: :resident do
      add(:number, :bigint, null: false)
      add(:to, :string, null: false)
      add(:text, :text, null: false)
      add(:state, :string, null: false, default: "open")
      add(:made_at, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec)
      add(:closed_by_kind, :string)
      add(:note, :text)
    end

    create(unique_index(:ethos_commitment, [:resident_id, :number]))
  end
end
