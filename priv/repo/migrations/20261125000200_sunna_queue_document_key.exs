defmodule Oneiroi.Repo.Migrations.SunnaQueueDocumentKey do
  use Ecto.Migration

  # A document's key resolves as its citation does (sunna#108): a last
  # segment with no extension is its `.md`. Rows keyed before are keyed
  # again; where both forms were attached to one task, the newer key
  # stays and the older row goes.
  def up do
    execute("""
    DELETE FROM sunna_queue_document d
    WHERE d.key <> '' AND d.key !~ '\\.[^/]*$'
      AND EXISTS (
        SELECT 1 FROM sunna_queue_document o
        WHERE o.household_id = d.household_id AND o.task = d.task AND o.key = d.key || '.md'
      )
    """)

    execute("""
    UPDATE sunna_queue_document SET key = key || '.md'
    WHERE key <> '' AND key !~ '\\.[^/]*$'
    """)
  end

  def down, do: :ok
end
