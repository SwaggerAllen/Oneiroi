defmodule Oneiroi.Repo.Migrations.ApsuOperatorQueue do
  use Ecto.Migration
  import Oneiroi.Migration

  # The operator's queue (apsu#31): what waits on the person running the
  # platform, raised by the agent that helps run it, the platform itself
  # or the operator, closed with a note. The platform's own record.
  def change do
    projection :apsu_operator_item, scope: :platform do
      add(:number, :bigserial, primary_key: true)
      add(:what, :text, null: false)
      add(:why, :text)
      add(:raised_by, :string, null: false)
      add(:links, {:array, :text}, null: false, default: [])
      add(:key, :string)
      add(:status, :string, null: false, default: "open")
      add(:note, :text)
      add(:raised_at, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec)
      add(:closed_by, :string)
    end

    create(index(:apsu_operator_item, [:status, :raised_at]))

    create(
      unique_index(:apsu_operator_item, [:key],
        where: "status = 'open' and key is not null",
        name: :apsu_operator_item_open_key
      )
    )
  end
end
