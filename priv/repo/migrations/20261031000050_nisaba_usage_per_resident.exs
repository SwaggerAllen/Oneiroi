defmodule Oneiroi.Repo.Migrations.NisabaUsagePerResident do
  use Ecto.Migration

  # A call's ref is unique within its resident, not across the store
  # (sima-qian #21): a rebuilt copy replays the source's calls with the
  # source's refs, and with the ref alone as the key every one of them
  # was dropped as already projected, so the copy's ledger read empty
  # (measured by the whole-resident round trip of 10-31).
  def up do
    execute("ALTER TABLE nisaba_usage DROP CONSTRAINT nisaba_usage_pkey")
    execute("ALTER TABLE nisaba_usage ADD PRIMARY KEY (resident_id, ref)")
  end

  def down do
    execute("ALTER TABLE nisaba_usage DROP CONSTRAINT nisaba_usage_pkey")
    execute("ALTER TABLE nisaba_usage ADD PRIMARY KEY (ref)")
  end
end
