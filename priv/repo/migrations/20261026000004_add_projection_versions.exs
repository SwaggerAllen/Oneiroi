defmodule Oneiroi.Repo.Migrations.AddProjectionVersions do
  use Ecto.Migration

  # The Ecto projectors' own bookkeeping (commanded_ecto_projections): one
  # row per projector naming the last event it applied, which is what
  # makes a projector resumable from the log rather than from a stored
  # cursor of its own (conventions §7). A library-reserved table, created
  # by its own statement rather than `create table` so the tables lint
  # reads it as the one reserved name it admits; no scope column, because
  # the row is the projector's, not a resident's.
  def up do
    execute("""
    CREATE TABLE projection_versions (
      projection_name text PRIMARY KEY,
      last_seen_event_number bigint NOT NULL,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """)
  end

  def down, do: execute("DROP TABLE projection_versions")
end
