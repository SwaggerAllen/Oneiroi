defmodule Oneiroi.Repo.Migrations.HonchoRoleAndSchema do
  use Ecto.Migration

  # Honcho shares this database (proteus #17): its tables live in their
  # own schema, `honcho`, and it acts as `oneiroi_honcho`, a role that
  # owns that schema and nothing else, taken at connection start through
  # the startup option render.yaml puts on Honcho's URL. Measured on a
  # local 16 with pgvector before anything relied on it: as that role,
  # Honcho's own startup statements pass and a vector column is created
  # in its schema, while reading an Oneiroi table and creating one in
  # `public` are both refused. CREATE on the database is granted because
  # Honcho runs `CREATE SCHEMA IF NOT EXISTS` on every start, which
  # Postgres refuses without it even when the schema exists (measured:
  # "permission denied for database"). It lets the role make a new
  # schema of its own, and read nothing it does not own.
  #
  # A wall against accident, not against Honcho: the login is this
  # credential, so `SET ROLE` back to it succeeds (also measured).
  # Created idempotently, like oneiroi_app, because a role is
  # cluster-wide and a preview's database finds it already present.
  @role "oneiroi_honcho"

  def up do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{@role}') THEN
        CREATE ROLE #{@role} NOLOGIN NOBYPASSRLS;
      END IF;
    END
    $$;
    """)

    execute(~s(GRANT #{@role} TO CURRENT_USER))
    execute(~s(CREATE SCHEMA IF NOT EXISTS honcho AUTHORIZATION #{@role}))

    execute("""
    DO $$
    BEGIN
      EXECUTE format('GRANT CREATE ON DATABASE %I TO #{@role}', current_database());
    END
    $$;
    """)
  end

  # Refuses while Honcho's tables are there: dropping them is not a
  # rollback of this migration, it is deleting Honcho's store.
  def down do
    execute(~s(DROP SCHEMA IF EXISTS honcho))

    execute("""
    DO $$
    BEGIN
      EXECUTE format('REVOKE CREATE ON DATABASE %I FROM #{@role}', current_database());
    END
    $$;
    """)
  end
end
