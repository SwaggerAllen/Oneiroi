defmodule Oneiroi.Repo.Migrations.KumbukumbuMemory do
  use Ecto.Migration
  import Oneiroi.Migration

  # Bookmarks, tags and taggings are the resident's rows (spec §6.3): the
  # witness reads them as the resident's witness, checked at the edge,
  # under the resident's scope. They are not a conversation and have no
  # party; what a custody transfer reveals of them is the export wall's
  # question (spec §6.12), left for the governance phase.
  def change do
    projection :kumbukumbu_bookmark, scope: :resident do
      add(:number, :bigint, null: false)
      add(:session_key, :string, null: false)
      add(:anchor_ref, :string, null: false)
      add(:anchor_at, :utc_datetime_usec, null: false)
      add(:turns_back, :integer, null: false, default: 1)
      add(:line, :string, null: false)
      add(:summary, :text)
      add(:added_by_kind, :string)
      add(:added_by_id, :string)
      add(:added_by_model, :string)
      add(:proposed_by_kind, :string)
      add(:proposed_by_id, :string)
      add(:pinned_by_kind, :string)
      add(:pinned_by_id, :string)
      add(:pinned_at, :utc_datetime_usec)
      # Weighting (F11) is a later measurement; every bookmark weighs the
      # same until it lands, and the column is here so the index's order
      # does not change shape when it does.
      add(:weight, :float, null: false, default: 1.0)
      add(:last_indexed_at, :utc_datetime_usec)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_bookmark, [:resident_id, :number]))
    create(index(:kumbukumbu_bookmark, [:resident_id, :session_key, :anchor_ref]))

    projection :kumbukumbu_bookmark_proposal, scope: :resident do
      add(:ref, :string, null: false)
      add(:session_key, :string, null: false)
      add(:anchor_ref, :string, null: false)
      add(:line, :string, null: false)
      add(:note, :text, null: false)
      add(:state, :string, null: false, default: "open")
      add(:proposed_by_kind, :string)
      add(:proposed_by_id, :string)
      add(:decided_note, :text)
      add(:bookmark_number, :bigint)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:kumbukumbu_bookmark_proposal, [:resident_id, :ref]))

    projection :kumbukumbu_tag, scope: :resident do
      add(:slug, :string, null: false)
      add(:state, :string, null: false)
      add(:proposed_by_kind, :string)
      add(:proposed_by_id, :string)
      add(:note, :text)
      add(:created_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:kumbukumbu_tag, [:resident_id, :slug]))

    projection :kumbukumbu_tagging, scope: :resident do
      add(:tag, :string, null: false)
      add(:target_kind, :string, null: false)
      add(:target_id, :string, null: false)
      add(:applied_by_kind, :string)
      add(:applied_by_id, :string)
      add(:applied_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_tagging, [:resident_id, :tag, :target_kind, :target_id]))
    create(index(:kumbukumbu_tagging, [:resident_id, :target_kind, :target_id]))

    # Compaction (spec §5): the summary that never deletes history, and
    # the store sequence it covers; the live transcript is what follows.
    alter table(:kumbukumbu_session) do
      add(:summary, :text)
      add(:compacted_through, :bigint, null: false, default: 0)
    end

    # The verbatim injected index is seen only in the turn's inspector
    # (spec §5), so the index injection carries its text and no other does.
    alter table(:kumbukumbu_context_injection) do
      add(:text, :text)
    end
  end
end
