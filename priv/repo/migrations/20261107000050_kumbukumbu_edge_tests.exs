defmodule Oneiroi.Repo.Migrations.KumbukumbuEdgeTests do
  use Ecto.Migration
  import Oneiroi.Migration

  # kumbukumbu#53: learned edges decay by their source's seedings, not by
  # days, and citations add apart, by source, never decayed. The edges
  # projector is renamed so it folds every event again under these rules;
  # the tables the old name folded are emptied for it.
  def up do
    execute("DELETE FROM kumbukumbu_edge")
    execute("DELETE FROM kumbukumbu_edge_turn")

    alter table(:kumbukumbu_edge) do
      add(:touched_count, :bigint, null: false, default: 0)
    end

    projection :kumbukumbu_edge_source, scope: :resident do
      add(:number, :bigint, null: false)
      add(:seeded, :bigint, null: false, default: 0)
    end

    create(unique_index(:kumbukumbu_edge_source, [:resident_id, :number]))

    projection :kumbukumbu_citation_edge, scope: :resident do
      add(:source, :text, null: false)
      add(:from_number, :bigint, null: false)
      add(:to_number, :bigint, null: false)
      add(:w, :float, null: false)
    end

    create(
      unique_index(:kumbukumbu_citation_edge, [:resident_id, :source, :from_number, :to_number])
    )

    create(index(:kumbukumbu_citation_edge, [:resident_id, :from_number]))
  end

  def down do
    drop(table(:kumbukumbu_citation_edge))
    drop(table(:kumbukumbu_edge_source))

    alter table(:kumbukumbu_edge) do
      remove(:touched_count)
    end
  end
end
