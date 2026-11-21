# The journal's events, under the library's `Events` namespace so the
# events census (`events/0` against the compiled modules) sees them;
# the file is theirs alone.

defmodule Oneiroi.Seshat.Events.JournalEntryAdded do
  @moduledoc """
  A journal row (spec §6.5, F29) on `journal-<resident_id>`: a day, the
  entry's number within the day, a kind (plan, note, todo, wrap) and
  its text; the narrative file is rendered from these.
  """
  # Version 2 adds `register` (`Oneiroi.Register`, spec §6.13, P8), the
  # register the resident wrote the entry in, or nil; the identity
  # upcaster is the shape the store's restart for v0.2 allows.
  # Version 3 adds `summary` (seshat#30): the text is whole at any
  # length, and a summary of at most 2,000 characters is what the turn's
  # journal section shows of a longer one; nil on every earlier entry,
  # which the identity upcaster leaves as the struct's default.
  # Version 4 adds the writing turn (kumbukumbu#84): `session_key`,
  # `turn_ref` and `labels`, every distinct label its context held,
  # never words; nil on every earlier entry, read as unclassified.
  use Oneiroi.Event,
    version: 4,
    fields: [
      :id,
      :day,
      :number,
      :kind,
      :text,
      :register,
      :summary,
      :session_key,
      :turn_ref,
      :labels
    ]
end

defimpl Commanded.Event.Upcaster, for: Oneiroi.Seshat.Events.JournalEntryAdded do
  def upcast(event, _metadata), do: event
end

defmodule Oneiroi.Seshat.Events.JournalTodoDone do
  @moduledoc "A to-do row marked done."
  use Oneiroi.Event, version: 1, fields: [:id, :day, :number]
end
