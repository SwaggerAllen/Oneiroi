defmodule Oneiroi.Repo.Migrations.KumbukumbuMessageDomain do
  use Ecto.Migration

  # Domains per message (P23-R1, kumbukumbu#72): a message's domain is a
  # (person, slug) pair, nil for the common room; `domain_tagged` when a
  # party named it, else carried forward. The session keeps its current
  # domain, the last named one, which every untagged message after it
  # takes. A message captured before this rule takes its session's
  # opening domain, as the capture fold now gives it, its person the
  # session's counterpart: so a session in the common room stays there,
  # and nothing is walled on deploy.
  def up do
    change_columns()
    # Under the platform scope, as every cross-tenant write is.
    execute("SET LOCAL oneiroi.scope = 'platform'")

    execute("""
    UPDATE kumbukumbu_message m
       SET domain = s.domain,
           domain_person = CASE WHEN s.kind IN ('main', 'adapter', 'imported') AND s.account_id IS NOT NULL
                                THEN 'account:' || s.account_id::text
                                ELSE 'resident:' || s.resident_id::text END
      FROM kumbukumbu_session s
     WHERE s.resident_id = m.resident_id AND s.key = m.session_key AND s.domain IS NOT NULL
    """)
  end

  def down do
    alter table(:kumbukumbu_session) do
      remove(:current_turn_ref)
      remove(:current_set)
      remove(:current_domain)
      remove(:current_person)
    end

    alter table(:kumbukumbu_message) do
      remove(:domain_tagged)
      remove(:domain)
      remove(:domain_person)
    end
  end

  defp change_columns do
    alter table(:kumbukumbu_message) do
      add(:domain_person, :text)
      add(:domain, :string)
      add(:domain_tagged, :boolean, null: false, default: false)
    end

    alter table(:kumbukumbu_session) do
      add(:current_person, :text)
      add(:current_domain, :text)
      add(:current_set, :boolean, null: false, default: false)
      add(:current_turn_ref, :string)
    end
  end
end
