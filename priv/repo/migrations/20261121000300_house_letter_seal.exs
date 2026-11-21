defmodule Oneiroi.Repo.Migrations.HouseLetterSeal do
  use Ecto.Migration

  # Sealed to its parties (kumbukumbu#93): a letter between residents is
  # sealed to the two of them unless sent open. Every letter between
  # residents already written is sealed, per letter, as the event's
  # upcaster seals it on a replay: none inherits openness.
  def up do
    alter table(:kumbukumbu_house_letter) do
      add(:sealed, :boolean, null: false, default: false)
      add(:parties, {:array, :text})
    end

    execute("""
    UPDATE kumbukumbu_house_letter
       SET sealed = true,
           parties = ARRAY(SELECT unnest(ARRAY['resident:' || resident_id::text,
                                                'resident:' || (link->>'resident_id')]) ORDER BY 1)
     WHERE link ? 'resident_id'
    """)
  end

  def down do
    alter table(:kumbukumbu_house_letter) do
      remove(:sealed)
      remove(:parties)
    end
  end
end
