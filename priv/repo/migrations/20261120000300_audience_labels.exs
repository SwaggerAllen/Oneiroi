defmodule Oneiroi.Repo.Migrations.AudienceLabels do
  use Ecto.Migration

  # The labels a derived artifact keeps (kumbukumbu#84): the writing
  # turn's, by session and ref, and every distinct label its context
  # held, never its words. Null on every row written before, which a
  # read takes as unclassified.
  def change do
    alter table(:seshat_journal_entry) do
      add(:session_key, :text)
      add(:turn_ref, :text)
      add(:labels, {:array, :map})
    end

    alter table(:kumbukumbu_house_letter) do
      add(:turn_ref, :text)
      add(:labels, {:array, :map})
    end

    # The asking turn's ledger a research question's answers inherit.
    alter table(:seshat_research) do
      add(:ledger, {:array, :map})
    end

    # A soul line's annotation (agathos-daimon#55): the domains it is
    # about and whether it is private to the dyad; never cut.
    alter table(:agathos_daimon_soul_line) do
      add(:domains, {:array, :map})
      add(:private, :boolean, default: false, null: false)
      add(:annotated_at, :utc_datetime_usec)
    end

    alter table(:agathos_daimon_self_letter) do
      add(:session_key, :text)
      add(:turn_ref, :text)
      add(:labels, {:array, :map})
    end
  end
end
