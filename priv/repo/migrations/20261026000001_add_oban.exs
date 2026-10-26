defmodule Oneiroi.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Infrastructure persistence (conventions §6): Oban owns its tables
  # under its reserved prefix, reached only through the Oban API. The
  # version is the pinned library's current one; no database outside
  # throwaway CI has run this yet, and append-only discipline starts at
  # the first deploy.
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
