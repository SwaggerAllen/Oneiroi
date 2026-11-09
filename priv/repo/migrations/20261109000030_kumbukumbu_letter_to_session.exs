defmodule Oneiroi.Repo.Migrations.KumbukumbuLetterToSession do
  use Ecto.Migration

  # The conversation a platform letter answers (sunna#44), so a free-time
  # answer wakes the session that asked rather than the newest one.
  def change do
    alter table(:kumbukumbu_house_letter) do
      add(:to_session, :text)
    end
  end
end
