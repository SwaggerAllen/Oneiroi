defmodule Oneiroi.Repo.Migrations.JanusReadiness do
  use Ecto.Migration

  import Oneiroi.Migration

  # Readiness per act (janus#48): each judge's mark, ready or not yet, and
  # her waivers, for her set's close ("questions") or her freeze ("c0"),
  # each naming the version it readied against; both artifacts' versions
  # and her question window on the succession's row. The one-flag ready
  # table (janus#9) is read no more: its marks named no act and no
  # version; it is left in place, empty of new rows.
  def change do
    projection :janus_mark, scope: :resident do
      add(:episode, :integer, null: false)
      add(:action, :text, null: false)
      add(:party, :text, null: false)
      add(:kind, :text, null: false)
      add(:ready, :boolean)
      add(:version, :integer)
      add(:note, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:janus_mark, [:resident_id, :episode, :action, :party, :kind]))

    alter table(:janus_succession) do
      add(:questions_version, :integer, null: false, default: 0)
      add(:c0_version, :integer, null: false, default: 0)
      add(:questions_opened_at, :utc_datetime_usec)
      add(:questions_reopened_at, :utc_datetime_usec)
      add(:questions_reopened_note, :text)
    end
  end
end
