defmodule Oneiroi.Repo.Migrations.SeshatJournalSummary do
  use Ecto.Migration

  # An entry's summary (seshat #30): the text is kept whole at any
  # length, and what the turn's journal section shows of a longer one is
  # this, at most 2,000 characters. Null for every entry before it.
  def change do
    alter table(:seshat_journal_entry) do
      add(:summary, :text)
    end
  end
end
