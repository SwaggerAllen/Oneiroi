defmodule Oneiroi.Repo.Migrations.XeniaReplySuperseded do
  use Ecto.Migration

  # A draft replaced by a newer one (xenia#17) names its replacement.
  def change do
    alter table(:xenia_reply) do
      add(:superseded_by, :integer)
    end
  end
end
