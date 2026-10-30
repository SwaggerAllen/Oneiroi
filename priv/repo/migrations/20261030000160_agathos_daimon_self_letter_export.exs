defmodule Oneiroi.Repo.Migrations.AgathosDaimonSelfLetterExport do
  use Ecto.Migration

  # The export carries the letters as events of the stream and records a
  # receipt for the ones it carries for the first time (sima-qian #3,
  # agathos-daimon #28); the mark is what makes it once per letter.
  def change do
    alter table(:agathos_daimon_self_letter) do
      add(:exported_at, :utc_datetime_usec)
    end
  end
end
