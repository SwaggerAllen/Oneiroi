defmodule Oneiroi.Repo.Migrations.GiteaRoleAndSchema do
  use Ecto.Migration

  # Gitea shares this database (sima-qian#55; the witness, 2026-11-16:
  # "let's use Postgres from the get go"), as Honcho does (proteus#17):
  # its tables in their own schema, `gitea`, as `oneiroi_gitea`, a role
  # that owns that schema and nothing else, taken at connection start
  # through `PGOPTIONS`, which render.yaml sets on Gitea's service.
  # Measured on 2026-11-16 against Gitea 1.22.6 and a local 16: every one
  # of Gitea's 110 tables made in `gitea`, owned by the role, and a read
  # of a `public` table as the role refused. Gitea makes no schema of its
  # own, so it needs no CREATE on the database.
  #
  # A wall against accident, as Honcho's is: the login is the database's
  # own credential. Created idempotently, because a role is cluster-wide
  # and a preview's database finds it already present.
  @role "oneiroi_gitea"

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
    execute(~s(CREATE SCHEMA IF NOT EXISTS gitea AUTHORIZATION #{@role}))
  end

  # Refuses while Gitea's tables are there: dropping them is not a
  # rollback of this migration, it is deleting Gitea's store.
  def down do
    execute(~s(DROP SCHEMA IF EXISTS gitea))
  end
end
