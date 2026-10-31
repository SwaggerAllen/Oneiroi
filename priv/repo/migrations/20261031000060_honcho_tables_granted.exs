defmodule Oneiroi.Repo.Migrations.HonchoTablesGranted do
  use Ecto.Migration

  # Honcho's migrations run as this login, not as oneiroi_honcho
  # (proteus #17): its Alembic connects with
  # `connect_args={"options": "-c statement_timeout=300000"}`, which
  # replaces the `options` on the URL that takes the role. So its tables
  # are the login's, and the running app, which does take the role, was
  # refused its own tables (measured on the first live deploy, 10-31:
  # "permission denied for table active_queue_sessions"). The same shape
  # as Oneiroi's own: the migrator owns, the application role is granted.
  # The role is granted every table, sequence and function in `honcho`,
  # and by default whatever this login makes there later; reproduced
  # locally before writing this, the denial first and then both the
  # existing table and one made after the grants usable, with Oneiroi's
  # tables still refused.
  @role "oneiroi_honcho"

  def up do
    for kind <- ~w(TABLES SEQUENCES FUNCTIONS) do
      execute(~s(GRANT ALL ON ALL #{kind} IN SCHEMA honcho TO #{@role}))
      execute(~s(ALTER DEFAULT PRIVILEGES IN SCHEMA honcho GRANT ALL ON #{kind} TO #{@role}))
    end
  end

  def down do
    for kind <- ~w(TABLES SEQUENCES FUNCTIONS) do
      execute(~s(ALTER DEFAULT PRIVILEGES IN SCHEMA honcho REVOKE ALL ON #{kind} FROM #{@role}))
      execute(~s(REVOKE ALL ON ALL #{kind} IN SCHEMA honcho FROM #{@role}))
    end
  end
end
