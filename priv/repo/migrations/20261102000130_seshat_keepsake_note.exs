defmodule Oneiroi.Repo.Migrations.SeshatKeepsakeNote do
  use Ecto.Migration

  # Why a keepsake mattered, in the resident's words (seshat #32), and
  # when she last said so. Null on every other document.
  def change do
    alter table(:seshat_document) do
      add(:note, :text)
      add(:noted_at, :utc_datetime_usec)
    end
  end
end
