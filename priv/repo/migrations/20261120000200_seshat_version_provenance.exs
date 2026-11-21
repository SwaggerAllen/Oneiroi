defmodule Oneiroi.Repo.Migrations.SeshatVersionProvenance do
  use Ecto.Migration

  # Each written version's provenance (kumbukumbu#83, seshat#100): the
  # turn that wrote it, by session and ref, and that turn's input ledger,
  # each input's id, ref, turn and labels, never its words. A version
  # written before it carries none, and a delivery of its words is
  # unproven.
  def change do
    alter table(:seshat_document_version) do
      add(:session_key, :text)
      add(:turn_ref, :text)
      add(:ledger, {:array, :map})
    end
  end
end
