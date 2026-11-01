defmodule Oneiroi.Repo.Migrations.WitnessNamesLeftBehind do
  use Ecto.Migration

  # The steward-to-witness rename (round 24) edited three migrations in
  # place, and a database that had already run them kept the old names:
  # production answered GET /v1/me with a 500, `relation
  # "gaia_witnessing" does not exist`, on 2026-11-01, and the import
  # would have failed on its first witnessing row. A fresh database has
  # the new names already, so each rename happens only where the old
  # name is still there. The data is untouched: a rename keeps the rows,
  # the grants, the row level security and the policy's expression.
  def up do
    execute("""
    DO $$
    BEGIN
      IF to_regclass('public.gaia_stewardship') IS NOT NULL THEN
        ALTER TABLE gaia_stewardship RENAME TO gaia_witnessing;
        ALTER INDEX gaia_stewardship_account_id_resident_id_index
          RENAME TO gaia_witnessing_account_id_resident_id_index;
        ALTER POLICY gaia_stewardship_scope ON gaia_witnessing RENAME TO gaia_witnessing_scope;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'glitnir_strike'
                   AND column_name = 'steward_account_id') THEN
        ALTER TABLE glitnir_strike RENAME COLUMN steward_account_id TO witness_account_id;
      END IF;

      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'nisaba_subscription'
                   AND column_name = 'policy_steward') THEN
        ALTER TABLE nisaba_subscription RENAME COLUMN policy_steward TO policy_witness;
      END IF;
    END
    $$;
    """)
  end

  # Nothing to undo: the old names are what the migrations once said, not
  # a state any code reads.
  def down, do: :ok
end
