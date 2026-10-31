defmodule Oneiroi.Seshat.Projectors.Journal do
  @moduledoc "Folds the journal streams into entry rows."
  use Oneiroi.Projection, name: "seshat_journal"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.JournalEntry

  fold(%Events.JournalEntryAdded{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :entry,
      %JournalEntry{
        resident_id: e.id,
        day: e.day,
        number: e.number,
        kind: e.kind,
        text: e.text,
        register: e.register,
        at: e.at,
        actor_kind: actor_kind(e.actor)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :day, :number]
    )
  end)

  fold(%Events.JournalTodoDone{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :done,
      from(j in JournalEntry,
        where: j.resident_id == ^e.id and j.day == ^e.day and j.number == ^e.number
      ),
      set: [done_at: e.at]
    )
  end)

  defp actor_kind(%{kind: kind}), do: Atom.to_string(kind)
  defp actor_kind(_other), do: nil
end
