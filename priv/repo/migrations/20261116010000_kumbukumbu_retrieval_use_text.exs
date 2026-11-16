defmodule Oneiroi.Repo.Migrations.KumbukumbuRetrievalUseText do
  use Ecto.Migration

  # A cited target can be longer than 255 characters (a long library
  # path, a transcript ref with its turn); on 2026-11-16 three
  # RetrievalRecorded events were parked for it, value too long for
  # character varying(255). Every text column of the table is text now.
  def change do
    alter table(:kumbukumbu_retrieval_use) do
      modify(:ref, :text, from: :string)
      modify(:session_key, :text, from: :string)
      modify(:turn_ref, :text, from: :string)
      modify(:target, :text, from: :string)
      modify(:stage, :text, from: :string)
      modify(:via, :text, from: :string)
    end
  end
end
