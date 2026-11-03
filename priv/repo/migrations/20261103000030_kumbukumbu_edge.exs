defmodule Oneiroi.Repo.Migrations.KumbukumbuEdge do
  use Ecto.Migration
  import Oneiroi.Migration

  # Learned retrieval edges (kumbukumbu #46, design/memory-weighting.md):
  # `from → to` reads "when `from` is in play, `to` is worth bringing".
  # A deviation from neutral, decayed lazily from `touched_at`; only an
  # edge ever touched exists. Kept apart from the library's citations,
  # which are authored, never learned.
  def change do
    projection :kumbukumbu_edge, scope: :resident do
      add(:from_number, :bigint, null: false)
      add(:to_number, :bigint, null: false)
      add(:w, :float, null: false)
      add(:touched_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_edge, [:resident_id, :from_number, :to_number]))

    # What a turn returned and what was seen used, held until the turn's
    # feedback says what helped and the use rules are learned once.
    projection :kumbukumbu_edge_turn, scope: :resident do
      add(:turn_ref, :string, null: false)
      add(:returned, {:array, :bigint}, null: false, default: [])
      add(:used, {:array, :bigint}, null: false, default: [])
      # A platform turn records its tool calls (the feedback among them)
      # before its index; an adapter's records the index first. The use
      # rules are learned when both have arrived, in either order.
      add(:indexed, :boolean, null: false, default: false)
      add(:feedback, :boolean, null: false, default: false)
      add(:learned_at, :utc_datetime_usec)
    end

    create(unique_index(:kumbukumbu_edge_turn, [:resident_id, :turn_ref]))
  end
end
