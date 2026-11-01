defmodule Oneiroi.Repo.Migrations.SeshatDocumentProvenance do
  use Ecto.Migration

  # Where an original came from (seshat #28): the source repository's URL
  # without userinfo, the pinned commit, the path there and the git blob
  # sha the copy was verified against. Null for every document that is
  # not an original, which is every document before this.
  def change do
    alter table(:seshat_document) do
      add(:source_repo, :string)
      add(:source_commit, :string)
      add(:source_path, :string)
      add(:source_blob, :string)
    end
  end
end
