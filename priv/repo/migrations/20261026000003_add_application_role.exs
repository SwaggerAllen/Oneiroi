defmodule Oneiroi.Repo.Migrations.AddApplicationRole do
  use Ecto.Migration

  # The application role (conventions §12): owns nothing, cannot bypass
  # row-level security, cannot log in on its own. `Oneiroi.Repo` takes
  # it with SET ROLE on every connection, so the credential a deployment
  # supplies stays the migrator's and the application never acts as the
  # table owner. Created here, idempotently, because a role is
  # cluster-wide and a second database on one cluster (a preview) finds
  # it already present. The grants reach every table this migrator
  # creates from now on, and every table it already created.
  #
  # Unmeasured until the first deploy (plan: the second role on Render's
  # managed Postgres): if the credential lacks CREATEROLE, this migration
  # fails loudly and the deploy stops with the previous release serving,
  # which is the honest outcome; the alternative recorded in the plan is
  # a role the platform creates once by hand.
  @role "oneiroi_app"

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

    # The migrator has to be able to `SET ROLE` to it. Postgres 16 grants
    # a role's creator membership with the SET option, but the role may
    # already exist (a second database on the cluster) and have been
    # created by another credential, and a superuser needs no grant at
    # all, which is why the local suite could never notice its absence.
    execute(~s(GRANT #{@role} TO CURRENT_USER))
    execute(~s(GRANT USAGE ON SCHEMA public TO #{@role}))
    execute(~s(GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{@role}))
    execute(~s(GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{@role}))

    execute(
      ~s(ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{@role})
    )

    execute(~s(ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{@role}))
  end

  def down do
    execute(~s(REVOKE ALL ON ALL TABLES IN SCHEMA public FROM #{@role}))
    execute(~s(REVOKE ALL ON SCHEMA public FROM #{@role}))
  end
end
