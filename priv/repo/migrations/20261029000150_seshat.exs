defmodule Oneiroi.Repo.Migrations.Seshat do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # pgvector (spec §2.1, conventions §1): CI's Postgres image carries
    # it and Render's does; a local Postgres needs the package
    # (postgresql-16-pgvector) before this migration runs.
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    projection :seshat_document, scope: :resident do
      add(:path, :string, null: false)
      add(:kind, :string, null: false)
      add(:origin, :string, null: false)
      add(:title, :string)
      add(:status, :string)
      add(:hash, :string)
      add(:bytes, :integer)
      add(:versions, :integer, null: false, default: 0)
      add(:embedded_with, :string)
      add(:chunks, :integer, null: false, default: 0)
      add(:indexed_at, :utc_datetime_usec)
      add(:missing_at, :utc_datetime_usec)
      add(:registered_at, :utc_datetime_usec, null: false)
      add(:written_at, :utc_datetime_usec)
      add(:written_by_kind, :string)
      add(:published_url, :string)
      add(:published_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_document, [:resident_id, :path]))

    # The width is SESHAT_EMBEDDING_WIDTH's default, spec §6.5's 1,536;
    # a run whose model answers another width fails before it reaches
    # this column (seshat #16).
    projection :seshat_chunk, scope: :resident do
      add(:path, :string, null: false)
      add(:ordinal, :integer, null: false)
      add(:text, :text, null: false)
      add(:embedding, :vector, size: 1536, null: false)
    end

    create(unique_index(:seshat_chunk, [:resident_id, :path, :ordinal]))

    projection :seshat_reference, scope: :resident do
      add(:from_path, :string, null: false)
      add(:ordinal, :integer, null: false)
      add(:from_kind, :string, null: false)
      add(:target, :string, null: false)
      add(:slug, :string, null: false)
      add(:kind, :string, null: false)
      add(:ref, :string, null: false)
      add(:resolved, :boolean)
      add(:reason, :text)
      add(:label, :text)
      add(:resolved_at, :utc_datetime_usec)
      add(:checked_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_reference, [:resident_id, :from_path, :ordinal]))
    create(index(:seshat_reference, [:resident_id, :target]))

    projection :seshat_index_run, scope: :resident do
      add(:id, :binary_id, null: false)
      # The order of runs, since two can share an instant (seshat #17).
      add(:sequence, :bigserial, null: false)
      add(:at, :utc_datetime_usec, null: false)
      add(:outcome, :string, null: false)
      add(:reason, :text)
      add(:model, :string)
      add(:scanned, :integer, null: false, default: 0)
      add(:embedded, :integer, null: false, default: 0)
      add(:chunks, :integer, null: false, default: 0)
      add(:missing, :integer, null: false, default: 0)
      add(:by_kind, :string)
    end

    create(unique_index(:seshat_index_run, [:resident_id, :id]))

    projection :seshat_discussion, scope: :resident do
      add(:path, :string, null: false)
      add(:session_key, :string, null: false)
      add(:opened_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_discussion, [:resident_id, :path, :session_key]))
  end
end
