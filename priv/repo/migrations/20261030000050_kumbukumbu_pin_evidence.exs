defmodule Oneiroi.Repo.Migrations.KumbukumbuPinEvidence do
  use Ecto.Migration

  # A pin is leaf-evidence of a soul line, and which line it evidences
  # is the pin's tag (spec §6.17, P39); the line's own citation of the
  # bookmark is the character layer's row.
  def change do
    alter table(:kumbukumbu_bookmark) do
      add(:pin_evidences, :bigint)
    end
  end
end
