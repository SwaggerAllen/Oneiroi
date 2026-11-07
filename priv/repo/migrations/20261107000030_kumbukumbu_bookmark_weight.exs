defmodule Oneiroi.Repo.Migrations.KumbukumbuBookmarkWeight do
  use Ecto.Migration

  # The timeline's weight on a bookmark (kumbukumbu#51): importance 0 to
  # 3, a status line, and when she last set them.
  def change do
    alter table(:kumbukumbu_bookmark) do
      add(:importance, :integer, null: false, default: 0)
      add(:status, :text)
      add(:weighed_at, :utc_datetime_usec)
    end
  end
end
