defmodule Oneiroi.Repo.Migrations.SeshatClassificationProposal do
  use Ecto.Migration

  # The witness's classification proposal waiting on her (seshat#103):
  # whose life, which domain (null for the common room), his note, when;
  # all null when none waits.
  def change do
    alter table(:seshat_document) do
      add(:proposed_person, :text)
      add(:proposed_domain, :text)
      add(:proposed_note, :text)
      add(:proposed_at, :utc_datetime_usec)
    end
  end
end
