defmodule Oneiroi.Repo.Migrations.SeshatKeepsakesReleased do
  use Ecto.Migration

  # Nothing grandfathered (seshat#44, the witness's call of 2026-11-07):
  # every document recorded as a keepsake by its place at the root, before
  # registration existed, is a root file now; the projector reads those
  # events the same way, so a rebuild agrees. Under the platform scope,
  # since the row policy holds the migration's role too.
  def up do
    execute("SET LOCAL oneiroi.scope = 'platform'")
    execute("UPDATE seshat_document SET kind = 'root' WHERE kind = 'keepsake'")
  end

  def down, do: :ok
end
